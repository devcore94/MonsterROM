# shellcheck shell=bash
BLUETOOTH_RUNTIME()
{
    TOOLS_DIR="${BLUETOOTH_TOOLS:-$TOOLS_DIR}" "${BASH_SOURCE[0]%/*}/../../../scripts/run_xml_perl.sh" - "$@" <<'PERL'
use strict;
use warnings;
use JSON::PP;
use Digest::SHA qw(sha256_hex);
use File::Find;
use File::Path qw(make_path);
use File::Basename qw(dirname basename);
use File::Copy qw(copy);
use File::Temp qw(tempfile tempdir);
use File::Spec;
use XML::Parser;
sub need($$) { die "UN1CA: $_[1]\n" unless $_[0] }
sub raw { open my $f,'<:raw',$_[0] or die "$_[0]: $!\n"; local $/; return <$f>//'' }
sub sha { sha256_hex(raw($_[0])) }
sub json { decode_json(raw($_[0])) }
sub encoded { JSON::PP->new->canonical->pretty->encode($_[0]) }
sub same { JSON::PP->new->canonical->encode($_[0]) eq JSON::PP->new->canonical->encode($_[1]) }
sub put {
    my($path,$data)=@_; return if -f $path && raw($path) eq $data;
    make_path(dirname($path)); my($f,$name)=tempfile('.unica-native-XXXXXX',DIR=>dirname($path),UNLINK=>0);
    binmode $f; print $f $data or die "write $path: $!"; close $f or die "close $path: $!";
    chmod((-e $path ? (stat($path))[2]&0777 : 0644),$name) or die "chmod $name: $!";
    rename($name,$path) or die "rename $path: $!";
}
sub save { put($_[0],encoded($_[1])) }
sub walk { my($root)=@_; my @paths; find({no_chdir=>1,wanted=>sub {push @paths,$File::Find::name if -f $_||-l $_}},$root) if -d $root; return sort @paths }
sub rel { my($path,$root)=@_; $path =~ s/^\Q$root\E\/// or die "Outside $root: $path"; return $path }
sub capture {
    my @cmd=@_; my($err,$name)=tempfile('unica-stderr-XXXXXX',DIR=>scratch_root(),UNLINK=>1); close $err;
    my $pid=open my $p,'-|'; defined $pid or die "fork: $!";
    if(!$pid) { open STDERR,'>:raw',$name or die "stderr: $!"; exec {$cmd[0]} @cmd; exit 127 }
    binmode $p; local $/; my $out=<$p>//''; close $p; my $status=$?; my $error=raw($name);
    return ($out,$error,$status);
}
sub run { my @cmd=@_; my($out,$err,$status)=capture(@cmd); die "Command failed (@cmd): $err$out" if $status; return $out }
sub scratch_root {return $ENV{UNICA_TEST_TMPDIR}//$ENV{TMPDIR}//(-d '/tmp/opencode'?'/tmp/opencode':File::Spec->tmpdir())}
sub u16 { unpack('v',substr($_[0],$_[1],2)) }
sub elf_symbols {
    my($path)=@_; my $data=raw($path); need(substr($data,0,6) eq "\x7fELF\x02\x01" && u16($data,18)==183,"Not ARM64 ELF: $path");
    my(%imports,%exports); my $text=run('readelf','--dyn-syms','-W',$path);
    while($text =~ /^\s*\d+:\s+[0-9a-f]+\s+\d+\s+.+?\s+(GLOBAL|WEAK)\s+(DEFAULT|PROTECTED)\s+(\S+)\s+(\S+)/mg) {
        my($bind,$index,$name)=($1,$3,$4); if($index eq 'UND') {$imports{$name}=1 if $bind eq 'GLOBAL'} else {$exports{$name}=1; if($name =~ /@@/) {my $base=$name; $base =~ s/@@.*//; $exports{$base}=1; $name =~ s/@@/\@/; $exports{$name}=1}} }
    need(scalar(keys %exports),"Unreadable ELF symbols: $path"); my $dynamic=run('readelf','-dW',$path); my @needed=$dynamic =~ /\(NEEDED\).*?\[([^\]]+)\]/g; my @soname=$dynamic =~ /\(SONAME\).*?\[([^\]]+)\]/g;
    need(@soname==1,"Missing/duplicate SONAME: $path"); return {imports=>\%imports,exports=>\%exports,needed=>\@needed,soname=>$soname[0]};
}
sub tag_end {
    my($data,$start)=@_; my $quote=''; for(my $i=$start;$i<length($data);$i++) {my $c=substr($data,$i,1);
        if(length $quote) {$quote='' if $c eq $quote} elsif($c eq chr(34)||$c eq chr(39)) {$quote=$c} elsif($c eq '>') {return $i+1} }
    die "Unterminated XML tag at byte $start of ".length($data).": ".substr($data,$start,80);
}
sub xml {
    my($data,$namespaces)=@_; my($root,@stack);
    if($namespaces) {XML::Parser->new(Namespaces=>1,Handlers=>{Doctype=>sub {die 'DOCTYPE is not allowed'},ExternEnt=>sub {die 'External entities are not allowed'}})->parse($data)}
    XML::Parser->new(Handlers=>{
        Doctype=>sub {die 'DOCTYPE is not allowed'},ExternEnt=>sub {die 'External entities are not allowed'},
        Start=>sub {my($p,$tag,%attrs)=@_; my $n={tag=>$tag,attrs=>\%attrs,start=>$p->current_byte,open=>tag_end($data,$p->current_byte),children=>[],text=>''};
            if(@stack) {push @{$stack[-1]{children}},$n} else {$root=$n} push @stack,$n},
        End=>sub {my($p)=@_; my $n=pop @stack; my $empty=substr($data,$n->{open}-2,2) eq '/>';
            $n->{close}=$empty?$n->{open}:$p->current_byte; $n->{end}=$empty?$n->{open}:tag_end($data,$p->current_byte)},
        Char=>sub {my($p,$text)=@_; $stack[-1]{text}.=$text if @stack},
    })->parse($data); need($root,'Missing XML root'); return {data=>$data,root=>$root};
}
sub escaped {my $s=$_[0]; $s =~ s/([.\^\$*+?{}\[\]\\|()\#\s-])/\\$1/g; return $s}
my $action=shift(@ARGV)//'';
if($action eq 'state') {
    my($mode,$state,$artifact,$source,$module,$cert)=@ARGV; my @names=qw(SOURCE_PLATFORM_SDK_VERSION ROM_IS_OFFICIAL TARGET_FIRMWARE);
    for my $feature(qw(A2DPSINK_PROFILE A2DP_SBM HEAD_SAR_BACKOFF XLNA_CONTROL)) {push @names,map {$_.'_BLUETOOTH_SUPPORT_'.$feature} qw(SOURCE TARGET)}
    need(defined $ENV{$_},"Missing Bluetooth input $_") for @names;
    my @files=("$module/customize.sh","$module/BluetoothSignature.java",grep {/\.patch$/} walk($module));
    my $root=$source; $root=dirname($root) for 1..4; my @id=split m{/},$ENV{TARGET_FIRMWARE}; my $target="$ENV{FW_DIR}/$id[0]_$id[1]";
    my @native=((map {"$root/system/system/lib64/$_"} qw(libvkmanager.so libhidlbase.so)),(map {"$target/system/system/lib64/$_"} ('libvkmanager.so','vendor.samsung.hardware.security.vaultkeeper@2.0.so')),"$target/vendor/etc/vintf/manifest/vaultkeeper_manifest.xml");
    my $digest=sha($artifact); my $expected={output_sha256=>$digest,inputs=>{source_sha256=>sha($source),certificate_sha256=>sha($cert),config=>{map {$_=>$ENV{$_}} @names},native_inputs=>{map {$_=>(-f $_?sha($_):undef)} @native},implementation=>{map {rel($_,$module)=>sha($_)} @files}}};
    if($mode eq 'check') {need(same(json("$state/$digest.json"),$expected),'Bluetooth receipt does not match exact inputs')} else {need($mode eq 'record','Invalid Bluetooth receipt action'); save("$state/$digest.json",$expected)} exit 0;
}
if($action eq 'payload') {
    my($mode,$image,$tree,$fs,$contexts)=@ARGV; need($mode eq 'extract'||$mode eq 'verify','Invalid payload action');
    local $ENV{LC_ALL}='C'; my $scratch=tempdir('bt-native-XXXXXX',DIR=>scratch_root(),CLEANUP=>1);
    sub quote {my $v=$_[0]; need($v !~ /[\n\r\0]/,'Unsupported debugfs argument'); $v =~ s/([\\"])/\\$1/g; return '"'.$v.'"'}
    my $debug=sub {my($command)=@_; my($out,$err,$status)=capture('debugfs','-R',$command,$image); my @err=grep {!/^debugfs [\d.]+ \(.+\)$/} split /\n/,$err; need(!$status&&!@err,"debugfs $command: $err$out"); return $out};
    my $dump=sub {my($inode,$dest,$size)=@_; $debug->("dump <$inode> ".quote($dest)); need(-f $dest && (-s $dest)==$size,"Incomplete dump of inode $inode")};
    my(@entries,%dirs,%paths); my @pending=(['',2]);
    while(@pending) {my($path,$inode)=@{shift @pending}; my $stat=$debug->("stat <$inode>");
        my($number,$kind,$mode)=$stat =~ /Inode: (\d+)\s+Type: (\w+)\s+Mode:\s+([0-7]+)/; my($uid,$gid,$size)=$stat =~ /User:\s+(\d+)\s+Group:\s+(\d+).*?Size:\s+(\d+)/;
        need(defined($size)&&defined($number)&&$number==$inode,"Invalid inode metadata: $path"); need($kind =~ /^(directory|regular|symlink)$/,"Unsupported inode type: $kind");
        my $attrs=$debug->("ea_list <$inode>"); my @names=$attrs =~ /^  (\S+) \(\d+\)/mg;
        need(!scalar(grep {$_ ne 'security.selinux' && $_ ne 'security.capability'} @names),"Unsupported extended attributes: $path"); my($label)=$attrs =~ /  security\.selinux \(\d+\) = "([^"]+)"/;
        need(defined($label),"Missing SELinux label: $path"); $label =~ s/\\000$//; need($label =~ /^[A-Za-z0-9_:,.\-]+$/,"Unsupported SELinux label: $path"); my $caps=0;
        if(grep {$_ eq 'security.capability'} @names) {my $dest="$scratch/cap"; $debug->('ea_get -f '.quote($dest)." <$inode> security.capability"); my $raw=raw($dest); my @words=unpack('V*',$raw); my $revision=$words[0]>>24; my %sizes=(1=>12,2=>20,3=>24);
            need(exists($sizes{$revision}) && length($raw)==$sizes{$revision} && ($words[0]&0xffffff)==1,'Capability flags cannot be represented by fs_config'); need(!$words[2] && ($revision<2||!$words[4]) && ($revision!=3||!$words[5]),'Inheritable/namespaced capabilities cannot be represented'); $caps=$words[1]|($revision>=2?$words[3]<<32:0)}
        my $entry={path=>$path,inode=>$inode,kind=>$kind,mode=>oct($mode),uid=>0+$uid,gid=>0+$gid,size=>0+$size,context=>$label,caps=>$caps};
        if($kind eq 'symlink') {my($target)=$stat =~ /^Fast link dest: "(.*)"$/m; if(!defined $target) {$dump->($inode,"$scratch/link",$size); $target=raw("$scratch/link")}
            need(length($target)==$size && length($target) && index($target,"\0")<0,"Invalid symlink: $path"); $entry->{target}=$target}
        need(!$paths{$path}++,'Duplicate payload path'); push @entries,$entry;
        if($kind eq 'directory') {need(!$dirs{$inode}++,"Repeated directory inode: $path"); for my $line(split /\n/,$debug->("ls -p <$inode>")) {next unless length $line;
            my($child,$name)=$line =~ m{^/(\d+)/[0-7]+/\d+/\d+/([^/]*)/[^/]*/$}; need(defined($name),"Invalid directory entry: $line"); next if !$child||$name eq '.'||$name eq '..';
            need(length($name)&&$name !~ /[\s\\\0"]/,"Unsupported entry name: $name"); my $relative=length($path)?"$path/$name":$name; push @pending,[$relative,0+$child] unless $relative eq 'lost+found';
        }}
    }
    @entries=sort {$a->{path} cmp $b->{path}} @entries; my $config=join('',map {sprintf("%s %d %d %o capabilities=0x%x\n",@{$_}{qw(path uid gid mode caps)})} @entries); my $labels=join('',map {escaped('/'.$_->{path}).' '.$_->{context}."\n"} @entries);
    if($mode eq 'extract') {need(!-e $tree && !-l $tree && !-e $fs && !-e $contexts,'Extraction destinations must not already exist'); make_path($tree,{mode=>0700});
        for my $e(@entries) {my $dest="$tree/$e->{path}"; if($e->{kind} eq 'directory' && length($e->{path})) {mkdir($dest,0700) or die $!} elsif($e->{kind} eq 'regular') {$dump->($e->{inode},$dest,$e->{size}); chmod(0644,$dest) or die $!}}
        for my $e(grep {$_->{kind} eq 'symlink'} @entries) {symlink($e->{target},"$tree/$e->{path}") or die $!} put($fs,$config); put($contexts,$labels);
    } else {
        my @config=grep {!/^lost\+found /} split /\n/,raw($fs); my @contexts=grep {!m{^/lost\\\+found }} split /\n/,raw($contexts);
        need(same([sort split /\n/,$config],[sort @config]),'Rebuilt payload changed fs_config metadata'); need(same([sort split /\n/,$labels],[sort @contexts]),'Rebuilt payload changed file_contexts metadata');
        my @actual=(''); find({no_chdir=>1,wanted=>sub {push @actual,rel($File::Find::name,$tree) unless $File::Find::name eq $tree}},$tree); need(same([sort @actual],[map {$_->{path}} @entries]),'Rebuilt payload changed its file set');
        for my $e(@entries) {my $p="$tree/$e->{path}"; if($e->{kind} eq 'symlink') {need(-l $p && readlink($p) eq $e->{target},"Changed symlink: $p")} elsif($e->{kind} eq 'directory') {need(-d $p && !-l $p,"Changed directory: $p")} else {need(-f $p && !-l $p,"Changed file type: $p"); $dump->($e->{inode},"$scratch/file",$e->{size}); need(sha("$scratch/file") eq sha($p),"Changed file content: $p"); unlink("$scratch/file") or die $!}}
    } exit 0;
}
if($action eq 'vaultkeeper') {
    my($source,$target,$payload,$fs,$contexts,$report)=@ARGV; my $hidl='vendor.samsung.hardware.security.vaultkeeper@2.0.so'; my $manifest=xml(raw("$target/vendor/etc/vintf/manifest/vaultkeeper_manifest.xml"),1);
    sub children {my($n,$tag)=@_; return grep {$_->{tag} eq $tag} @{$n->{children}}}
    sub value {my($n,$tag)=@_; my @c=children($n,$tag); return @c?$c[0]{text}:''}
    my @hal=grep {value($_,'name') eq 'vendor.samsung.hardware.security.vaultkeeper'} children($manifest->{root},'hal'); need(@hal==1,'Ambiguous target VaultKeeper service'); my $hal=$hal[0];
    if(($hal->{attrs}{format}//'') eq 'aidl') {save($report,{backend=>'source AIDL',modified=>JSON::PP::false}); exit 0}
    my @interfaces=map {[value($_,'name'),value($_,'instance')]} children($hal,'interface');
    need(($hal->{attrs}{format}//'') eq 'hidl' && value($hal,'version') eq '2.0' && value($hal,'transport') eq 'hwbinder' && same(\@interfaces,[['ISehVaultKeeper','default']]),'Unreviewed target VaultKeeper HAL');
    my $src="$source/system/system/lib64"; my $tgt="$target/system/system/lib64"; my $jni="$payload/lib64/libbluetooth_jni.so";
    need(sha($jni) eq 'fa1a7be4125866a162864166b20d6ec27ca198bfecdae48afcfee8fdd9f92752','Unreviewed VaultKeeper JNI'); need(sha("$src/libvkmanager.so") eq '0fdf61d254ff10c50f9f5e9027e3d2f5e0ac1fb938637c086540f85ffb1596e4','Unreviewed AIDL manager');
    my %cohorts=('s21-sdk35'=>['4d84d6674aa779b3460ddcf94f69459ba828ed30ffe2d00feccc500245a81aa5','adb95777c6db31a45ea88cb2b554e897c6e13c5802f4c4766e4fda89b35f1602'],'r9s-sdk36'=>['63610e52c7f110c68eff36c3fa1d870968ee5822ca78d94f91989bd579c2a778','d13537814b4d0a8ff4088bcd518031932981b968aea4e6f7d3540178e38551bd']);
    my @observed=(sha("$tgt/libvkmanager.so"),sha("$tgt/$hidl")); my @cohort=grep {same($cohorts{$_},\@observed)} keys %cohorts; need(@cohort==1,'Unreviewed VaultKeeper HIDL client cohort');
    need(sha("$src/libhidlbase.so") eq '24f21e2f0873c80a32b9ae9d951edc803d9dd2ea16df89ad4d2c48ff7d3c4501','Unreviewed One UI 9 libhidlbase');
    my %files=('libvkmanager.so'=>"$tgt/libvkmanager.so",$hidl=>"$tgt/$hidl",'libhidlbase.so'=>"$src/libhidlbase.so"); my $jni_info=elf_symbols($jni); my @imports=sort grep {/VaultKeeperManager/} keys %{$jni_info->{imports}};
    need(same(\@imports,[sort qw(_ZN18VaultKeeperManager11getInstanceEv _ZN18VaultKeeperManager12freeInstanceEv _ZN18VaultKeeperManager4readEiPcPi _ZN18VaultKeeperManager5writeEiPci)]),'Bluetooth no longer uses the reviewed opaque VaultKeeper API');
    my $bridge=elf_symbols($files{'libvkmanager.so'}); need(!scalar(grep {!exists $bridge->{exports}{$_}} @imports),'Target bridge lacks VaultKeeper methods');
    my(%providers,%paths); my @pending=sort keys %files;
    while(@pending) {my $name=shift @pending; next if exists $providers{$name}; my $path=$files{$name}//"$src/$name";
        $path="$src/bootstrap/$name" if !-f $path && $name =~ /^(libc\.so|libm\.so|libdl\.so|libdl_android\.so)$/; $path="$source/system/system/bin/bootstrap/linker64" if !-f $path && $name eq 'ld-android.so';
        my $info=elf_symbols($path); need($info->{soname} eq $name,"Native SONAME mismatch: $path"); $providers{$name}=$info; $paths{$name}=$path; push @pending,@{$info->{needed}};
    }
    my %exports=map {map {$_=>1} keys %{$_->{exports}}} values %providers;
    for my $name(keys %providers) {my @missing=grep {!exists $exports{$_}} keys %{$providers{$name}{imports}}; need(!@missing,"Unresolved One UI 9 imports for $name: @missing")}
    opendir(my $d,"$payload/lib64") or die $!; my %allowed=map {$_=>1} (readdir($d),keys(%files),@{$jni_info->{needed}},'libandroidicu.so'); closedir $d;
    for my $name(keys %files) {need(!scalar(grep {!$allowed{$_}} @{$providers{$name}{needed}}),"New APEX namespace dependencies: $name")}
    my $manager="$payload/lib64/libvkmanager.so"; need(-l $manager && readlink($manager) eq '/system/lib64/libvkmanager.so','VaultKeeper is not the reviewed source symlink');
    for my $name(grep {$_ ne 'libvkmanager.so'} keys %files) {need(!-e "$payload/lib64/$name" && !-l "$payload/lib64/$name","Conflicting APEX native member: $name")}
    my @config=split /(?<=\n)/,raw($fs); my @labels=split /(?<=\n)/,raw($contexts); my @model=grep {/^lib64\/libvkmanager\.so /} @config; my $prefix=escaped('/lib64/libvkmanager.so'); my @label=grep {/^\Q$prefix\E /} @labels;
    need(@model==1 && @label==1,'Missing source VaultKeeper inode metadata'); my(undef,$permissions)=split / /,$model[0],2; my(undef,$context)=split / /,$label[0],2;
    for my $name(sort grep {$_ ne 'libvkmanager.so'} keys %files) {push @config,"lib64/$name $permissions"; push @labels,escaped("/lib64/$name")." $context"}
    unlink($manager) or die $!; for my $name(keys %files) {copy($files{$name},"$payload/lib64/$name") or die $!} put($fs,join('',sort @config)); put($contexts,join('',sort @labels));
    save($report,{backend=>'genuine target HIDL 2.0',modified=>JSON::PP::true,jni_sha256=>sha($jni),target_hidl_cohort=>$cohort[0],opaque_api=>\@imports,installed=>{map {$_=>{source=>$files{$_},sha256=>sha($files{$_})}} keys %files},providers=>{map {$_=>{source=>$paths{$_},sha256=>sha($paths{$_}),strong_imports=>scalar(keys %{$providers{$_}{imports}}),needed=>$providers{$_}{needed}}} keys %providers},unresolved_strong_imports=>[],scope=>'Static ARM64 symbol/version/dependency and reviewed opaque-object ABI; not device execution'}); exit 0;
}
die "Expected state, payload or vaultkeeper action\n";
PERL
}
# Keep helper functions, environment overrides and traps out of the module runner.
(
set -o pipefail

BLUETOOTH_FAIL()
{
    ABORT "$1"
    return 1
}

# Invoked only by the private subshell's EXIT trap, including all failure paths.
# shellcheck disable=SC2329
BLUETOOTH_CLEANUP()
{
    [ ! "$BLUETOOTH_CANDIDATE" ] || rm -f -- "$BLUETOOTH_CANDIDATE"
    [ ! "$BLUETOOTH_STAGE" ] || rm -rf -- "$BLUETOOTH_STAGE"
}

BLUETOOTH_SIGNATURE()
{
    java -cp "$BLUETOOTH_TOOLS/bin/signapk.jar" "$MODPATH/BluetoothSignature.java" \
        "$1" "$BLUETOOTH_CERT" "$SOURCE_PLATFORM_SDK_VERSION" || return 1
}

BLUETOOTH_PATCH()
{
    local MEMBER="$1" PATCH="$2" FILE CACHE
    case "$MEMBER" in
        javalib/*) FILE="system/framework/$(basename "$MEMBER")" ;;
        app/*) FILE="system/$MEMBER" ;;
        *) BLUETOOTH_FAIL "Unsupported Bluetooth APEX member: $MEMBER"; return 1 ;;
    esac
    CACHE="$APKTOOL_DIR/system/${FILE//system\//}"
    if [ ! "${BLUETOOTH_MEMBERS[$MEMBER]:-}" ]; then
        mkdir -p "$(dirname "$WORK_DIR/system/$FILE")" || return 1
        cp --reflink=auto "$BLUETOOTH_PAYLOAD/$MEMBER" "$WORK_DIR/system/$FILE" || return 1
        DECODE_APK system "$FILE" || return 1
        BLUETOOTH_MEMBERS["$MEMBER"]="$FILE"
    fi
    [ -d "$CACHE" ] || return 1
    APPLY_PATCH system "$FILE" "$PATCH" || return 1
}

BLUETOOTH_MAIN()
{
    "${BASH_SOURCE[0]%/*}/../../../scripts/run_xml_perl.sh" --check || return 1
    local SOURCE_FIRMWARE_PATH TARGET_FIRMWARE_PATH SOURCE_APEX SOURCE_HASH WORK_HASH CERT_PREFIX=aosp
    local REAL_WORK_DIR="$WORK_DIR" REAL_APKTOOL_DIR="$APKTOOL_DIR"
    # UN1CA's caller-provided scratch root is distinct from POSIX TMPDIR below.
    local TMP_DIR="${TMP_DIR:?The build runner must provide TMP_DIR}"
    local MEMBER FILE SALT APP APKS
    local -A BLUETOOTH_MEMBERS=()

    # Configuration strings must not be executed as arbitrary shell commands.
    for FILE in SOURCE_BLUETOOTH_SUPPORT_A2DPSINK_PROFILE TARGET_BLUETOOTH_SUPPORT_A2DPSINK_PROFILE \
            SOURCE_BLUETOOTH_SUPPORT_A2DP_SBM TARGET_BLUETOOTH_SUPPORT_A2DP_SBM \
            SOURCE_BLUETOOTH_SUPPORT_HEAD_SAR_BACKOFF TARGET_BLUETOOTH_SUPPORT_HEAD_SAR_BACKOFF \
            SOURCE_BLUETOOTH_SUPPORT_XLNA_CONTROL TARGET_BLUETOOTH_SUPPORT_XLNA_CONTROL ROM_IS_OFFICIAL; do
        if [[ "${!FILE}" != true && "${!FILE}" != false ]]; then
            BLUETOOTH_FAIL "Invalid Bluetooth boolean $FILE: ${!FILE}"
            return 1
        fi
        export "${FILE?}"
    done
    if ! [[ "$SOURCE_PLATFORM_SDK_VERSION" =~ ^[0-9]+$ ]]; then
        BLUETOOTH_FAIL "Invalid Bluetooth source SDK"
        return 1
    fi
    export SOURCE_PLATFORM_SDK_VERSION
    SOURCE_FIRMWARE_PATH="${SOURCE_FIRMWARE%%/*}_${SOURCE_FIRMWARE#*/}"
    SOURCE_FIRMWARE_PATH="${SOURCE_FIRMWARE_PATH%%/*}"
    TARGET_FIRMWARE_PATH="${TARGET_FIRMWARE%%/*}_${TARGET_FIRMWARE#*/}"
    TARGET_FIRMWARE_PATH="${TARGET_FIRMWARE_PATH%%/*}"
    SOURCE_APEX="$FW_DIR/$SOURCE_FIRMWARE_PATH/system/system/apex/com.android.bt.apex"
    BLUETOOTH_DEST="$REAL_WORK_DIR/system/system/apex/com.android.bt.apex"
    BLUETOOTH_TOOLS="$TOOLS_DIR"
    $ROM_IS_OFFICIAL && CERT_PREFIX=unica
    BLUETOOTH_CERT="$SRC_DIR/security/${CERT_PREFIX}_platform.x509.pem"
    SOURCE_HASH="$(sha256sum "$SOURCE_APEX")" || return 1
    SOURCE_HASH="${SOURCE_HASH%% *}"
    WORK_HASH="$(sha256sum "$BLUETOOTH_DEST")" || return 1
    WORK_HASH="${WORK_HASH%% *}"
    if [[ "$SOURCE_HASH" != "$WORK_HASH" ]]; then
        if BLUETOOTH_RUNTIME state check "$REAL_APKTOOL_DIR/.bluetooth" "$BLUETOOTH_DEST" \
                "$SOURCE_APEX" "$MODPATH" "$BLUETOOTH_CERT"; then
            LOG "- Bluetooth APEX already built and verified for these exact inputs"
            return 0
        fi
        BLUETOOTH_FAIL "Modified Bluetooth APEX has no matching verified receipt; restore the source APEX before rebuilding"
        return 1
    fi

    # These legacy patches do not describe the Android 17 ABI. Keep the guards;
    # the current t2s path needs only the reviewed SBM-enable/XLNA-disable pair.
    if [ "$SOURCE_PLATFORM_SDK_VERSION" -gt 37 ]; then
        BLUETOOTH_FAIL "Bluetooth APEX port is not reviewed above One UI 9"
        return 1
    elif [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ]; then
        if [[ "$SOURCE_BLUETOOTH_SUPPORT_A2DPSINK_PROFILE" != "$TARGET_BLUETOOTH_SUPPORT_A2DPSINK_PROFILE" ]] || \
                [[ "$SOURCE_BLUETOOTH_SUPPORT_HEAD_SAR_BACKOFF" != "$TARGET_BLUETOOTH_SUPPORT_HEAD_SAR_BACKOFF" ]] || \
                { ! $SOURCE_BLUETOOTH_SUPPORT_XLNA_CONTROL && $TARGET_BLUETOOTH_SUPPORT_XLNA_CONTROL; }; then
            BLUETOOTH_FAIL "One UI 9 Bluetooth A2DP sink/HEAD SAR/XLNA enable transitions require reviewed One UI 9 patches"
            return 1
        fi
    fi
    if { ! $SOURCE_BLUETOOTH_SUPPORT_A2DPSINK_PROFILE && $TARGET_BLUETOOTH_SUPPORT_A2DPSINK_PROFILE; } || \
            { $SOURCE_BLUETOOTH_SUPPORT_A2DP_SBM && ! $TARGET_BLUETOOTH_SUPPORT_A2DP_SBM; } || \
            { $SOURCE_BLUETOOTH_SUPPORT_HEAD_SAR_BACKOFF && ! $TARGET_BLUETOOTH_SUPPORT_HEAD_SAR_BACKOFF; }; then
        BLUETOOTH_FAIL "Missing Bluetooth capability transition patches"
        return 1
    fi

    command -v debugfs > /dev/null || { BLUETOOTH_FAIL "Rootless Bluetooth APEX extraction requires debugfs (e2fsprogs)"; return 1; }
    mkdir -p "$TMP_DIR" || return 1
    BLUETOOTH_STAGE="$(mktemp -d "$TMP_DIR/bluetooth.XXXXXXXX")" || return 1
    trap 'BLUETOOTH_CLEANUP' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    export WORK_DIR="$BLUETOOTH_STAGE/work" APKTOOL_DIR="$BLUETOOTH_STAGE/apktool"
    export TOOLS_DIR="$BLUETOOTH_STAGE/tools" TMPDIR="$BLUETOOTH_STAGE"
    mkdir -p "$WORK_DIR/system/system/framework" "$TOOLS_DIR/apktool/framework" || return 1
    # Use the donor resource cohort and a private framework cache, not any of the
    # user's standalone Bluetooth/framework files or partially patched decodes.
    cp --reflink=auto "$FW_DIR/$SOURCE_FIRMWARE_PATH/system/system/framework/framework-res.apk" \
        "$WORK_DIR/system/system/framework/framework-res.apk" || return 1
    cp "$FW_DIR/$SOURCE_FIRMWARE_PATH/system/system/build.prop" "$WORK_DIR/system/system/build.prop" || return 1

    LOG "- Decoding Bluetooth APEX (private rootless staging)"
    apktool d -j 1 -s -r -p "$TOOLS_DIR/apktool/framework" -o "$BLUETOOTH_STAGE/apex" "$SOURCE_APEX" || return 1
    BLUETOOTH_PAYLOAD="$BLUETOOTH_STAGE/apex/unknown/apex_payload"
    local IMAGE="$BLUETOOTH_STAGE/apex/unknown/apex_payload.img"
    local FS_CONFIG="$BLUETOOTH_STAGE/fs_config" CONTEXTS="$BLUETOOTH_STAGE/file_contexts"
    BLUETOOTH_RUNTIME payload extract "$IMAGE" "$BLUETOOTH_PAYLOAD" "$FS_CONFIG" "$CONTEXTS" || return 1
    rm -f "$IMAGE" || return 1
    APKS="$(find "$BLUETOOTH_PAYLOAD/app" -mindepth 2 -maxdepth 2 -type f -name Bluetooth.apk)" || return 1
    mapfile -t APKS <<< "$APKS"
    if [ "${#APKS[@]}" -ne 1 ] || [ ! -f "${APKS[0]}" ]; then
        BLUETOOTH_FAIL "Expected exactly one Bluetooth APK in the source APEX"
        return 1
    fi
    APP="app/$(basename "$(dirname "${APKS[0]}")")/Bluetooth.apk"
    if $SOURCE_BLUETOOTH_SUPPORT_A2DPSINK_PROFILE && ! $TARGET_BLUETOOTH_SUPPORT_A2DPSINK_PROFILE; then
        BLUETOOTH_PATCH "$APP" "$MODPATH/a2dp_sink/Bluetooth.apk/0001-Disable-SUPPORT_A2DPSINK_PROFILE-support.patch" || return 1
        BLUETOOTH_PATCH javalib/framework-bluetooth.jar "$MODPATH/a2dp_sink/framework-bluetooth.jar/0001-Disable-SUPPORT_A2DPSINK_PROFILE-support.patch" || return 1
    fi
    if ! $SOURCE_BLUETOOTH_SUPPORT_A2DP_SBM && $TARGET_BLUETOOTH_SUPPORT_A2DP_SBM; then
        BLUETOOTH_PATCH "$APP" "$MODPATH/sbm/Bluetooth.apk/0001-Enable-SUPPORT_A2DP_SBM-support.patch" || return 1
    fi
    if ! $SOURCE_BLUETOOTH_SUPPORT_HEAD_SAR_BACKOFF && $TARGET_BLUETOOTH_SUPPORT_HEAD_SAR_BACKOFF; then
        BLUETOOTH_PATCH "$APP" "$MODPATH/head_sar/Bluetooth.apk/0001-Enable-SUPPORT_HEAD_SAR_BACKOFF-support.patch" || return 1
    fi
    if [[ "$SOURCE_BLUETOOTH_SUPPORT_XLNA_CONTROL" != "$TARGET_BLUETOOTH_SUPPORT_XLNA_CONTROL" ]]; then
        local ACTION=Disable
        $TARGET_BLUETOOTH_SUPPORT_XLNA_CONTROL && ACTION=Enable
        BLUETOOTH_PATCH "$APP" "$MODPATH/xlna/Bluetooth.apk/0001-$ACTION-SUPPORT_XLNA_CONTROL-support.patch" || return 1
    fi
    if [ "$SOURCE_PLATFORM_SDK_VERSION" -lt 37 ]; then
        HEX_PATCH "$BLUETOOTH_PAYLOAD/lib64/libbluetooth_jni.so" 28f7773948050037 28f777392a000014 || return 1
    else
        LOG "- Selecting the genuine target VaultKeeper backend (One UI 9 JNI unchanged)"
        BLUETOOTH_RUNTIME vaultkeeper "$FW_DIR/$SOURCE_FIRMWARE_PATH" "$FW_DIR/$TARGET_FIRMWARE_PATH" \
            "$BLUETOOTH_PAYLOAD" "$FS_CONFIG" "$CONTEXTS" "$BLUETOOTH_STAGE/vaultkeeper-contract.json" || return 1
    fi
    for MEMBER in "${!BLUETOOTH_MEMBERS[@]}"; do
        FILE="${BLUETOOTH_MEMBERS[$MEMBER]}"
        "$SRC_DIR/scripts/apktool.sh" b system "$FILE" || return 1
        if [[ "$MEMBER" == *.apk ]]; then
            BLUETOOTH_SIGNATURE "$WORK_DIR/system/$FILE" || return 1
        fi
        cp "$WORK_DIR/system/$FILE" "$BLUETOOTH_PAYLOAD/$MEMBER" || return 1
    done

    LOG "- Rebuilding and verifying Bluetooth APEX payload"
    "$SRC_DIR/scripts/build_fs_image.sh" ext4 --no-avb -o "$IMAGE" -p system \
        "$BLUETOOTH_PAYLOAD" "$CONTEXTS" "$FS_CONFIG" || return 1
    SALT="$(sha256sum "$BLUETOOTH_STAGE/apex/unknown/apex_manifest.pb")" || return 1
    SALT="${SALT%% *}"
    avbtool add_hashtree_footer --do_not_generate_fec --algorithm SHA256_RSA4096 --hash_algorithm sha256 \
        --key "$SRC_DIR/security/avb/testkey_rsa4096.pem" --prop apex.key:com.android.bt --salt "$SALT" --image "$IMAGE" || return 1
    avbtool extract_public_key --key "$SRC_DIR/security/avb/testkey_rsa4096.pem" \
        --output "$BLUETOOTH_STAGE/apex/unknown/apex_pubkey" || return 1
    avbtool verify_image --image "$IMAGE" --key "$SRC_DIR/security/avb/testkey_rsa4096.pem" || return 1
    BLUETOOTH_RUNTIME payload verify "$IMAGE" "$BLUETOOTH_PAYLOAD" "$FS_CONFIG" "$CONTEXTS" || return 1
    # The extracted tree is not an outer ZIP member.
    rm -rf -- "$BLUETOOTH_PAYLOAD" || return 1
    mkdir -p "$BLUETOOTH_STAGE/apex/build/apk" || return 1
    cp -a "$BLUETOOTH_STAGE/apex/original/META-INF" "$BLUETOOTH_STAGE/apex/build/apk/META-INF" || return 1
    apktool b -j 1 -p "$TOOLS_DIR/apktool/framework" "$BLUETOOTH_STAGE/apex" || return 1
    local UNSIGNED="$BLUETOOTH_STAGE/apex/dist/com.android.bt.apex"
    local SIGNED="$BLUETOOTH_STAGE/com.android.bt.apex"
    signapk -a 4096 --align-file-size "$BLUETOOTH_CERT" "$SRC_DIR/security/${CERT_PREFIX}_platform.pk8" "$UNSIGNED" "$SIGNED" || return 1
    BLUETOOTH_SIGNATURE "$SIGNED" || return 1
    zipalign -c 4096 "$SIGNED" || return 1
    # Refuse a lost update, then publish only fully signed/verified bytes using
    # a same-filesystem rename. A failed decode/patch/build/sign leaves work intact.
    local CURRENT_HASH
    CURRENT_HASH="$(sha256sum "$BLUETOOTH_DEST")" || return 1
    if [[ "${CURRENT_HASH%% *}" != "$WORK_HASH" ]]; then
        BLUETOOTH_FAIL "Bluetooth APEX changed concurrently; refusing to overwrite it"
        return 1
    fi
    BLUETOOTH_CANDIDATE="$(mktemp "$BLUETOOTH_DEST.bluetooth.XXXXXXXX")" || return 1
    cp "$SIGNED" "$BLUETOOTH_CANDIDATE" || return 1
    chmod --reference="$BLUETOOTH_DEST" "$BLUETOOTH_CANDIDATE" || return 1
    BLUETOOTH_RUNTIME state record "$REAL_APKTOOL_DIR/.bluetooth" "$BLUETOOTH_CANDIDATE" \
        "$SOURCE_APEX" "$MODPATH" "$BLUETOOTH_CERT" || return 1
    mv -fT "$BLUETOOTH_CANDIDATE" "$BLUETOOTH_DEST" || return 1
    BLUETOOTH_CANDIDATE=""
    LOG "- Bluetooth APEX built, signed and verified"
}

BLUETOOTH_STAGE="" BLUETOOTH_CANDIDATE=""
BLUETOOTH_MAIN
)
