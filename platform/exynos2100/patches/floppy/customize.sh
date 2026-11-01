#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Shell entry point; Perl's core JSON/binary primitives only parse build artifacts.
FLOPPY_PREPARE_SOURCE()
(
    # Explicit source-only provisioning, never an implicit cache/build fallback.
    # Refuse even empty directories or broken symlinks; preserve existing work.
    if [ "$#" -ne 1 ] || [[ "$1" != /* ]]; then
        echo "Usage: customize.sh prepare-source <new-absolute-directory>" >&2
        exit 1
    fi
    if [ -e "$1" ] || [ -L "$1" ]; then
        echo "[floppy] Refusing existing source destination: $1" >&2
        exit 1
    fi
    local module source commit patch
    module="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" || exit 1
    commit=113ce9d986f74e1526981324ec164e4d90930071
    mkdir -- "$1" || exit 1
    source="$(readlink -f "$1")" || exit 1
    git init -q --object-format=sha1 "$source" || exit 1
    git -C "$source" remote add origin https://github.com/FlopKernel-Series/flop_exynos2100_kernel.git || exit 1
    git -C "$source" fetch --depth=1 --no-tags origin "$commit" || exit 1
    [ "$(git -C "$source" rev-parse FETCH_HEAD)" = "$commit" ] || exit 1
    git -C "$source" -c advice.detachedHead=false checkout --detach FETCH_HEAD || exit 1
    # Only mkbootimg is needed; do not fetch unrelated firmware/AnyKernel trees.
    git -C "$source" submodule update --init --depth=1 -- build/mkbootimg || exit 1
    [ "$(git -C "$source/build/mkbootimg" rev-parse HEAD)" = d2bb0af5ba6d3198a3e99529c97eda1be0b5a093 ] || exit 1
    for patch in \
        source/0001-Retain-the-UN1CA-source-overlay.patch \
        source/0002-Pin-the-retained-configuration.patch \
        source/0003-Pin-vendor-load-policy-and-reproducible-ramdisk.patch \
        uname/0001-Report-5.15.206-for-the-selected-uname-spoof.patch \
        uname/0002-Respect-the-explicit-BPF-spoof-boot-option.patch \
        uname/0003-Select-full-BPF-uname-mode.patch \
        bpf/0001-Backport-cgroup-bind-permission-flags.patch; do
        git -C "$source" apply --check "$module/$patch" || exit 1
        git -C "$source" apply "$module/$patch" || exit 1
    done
    FLOPPY_RUNTIME source-inputs > "$source/floppy-source-inputs.json" || exit 1
    echo "[floppy] Prepared pinned source/config inputs only: $source"
    echo "[floppy] No toolchain downloaded, kernel built, ABI checked or cache published; see $module/README.md"
)

FLOPPY_RUNTIME()
{
    local FLOPPY_MODULE
    FLOPPY_MODULE="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
    export FLOPPY_MODULE
    perl - "$@" <<'PERL'
use strict;
use warnings;
use JSON::PP;
use Digest::SHA qw(sha256_hex);
use Cwd qw(abs_path);
use File::Basename qw(basename dirname);
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Find;
use File::Spec;
use File::Temp qw(tempfile tempdir);
use Fcntl qw(:flock);

sub need($$) { die "[floppy] $_[1]\n" unless $_[0] }
sub raw { open my $f,'<:raw',$_[0] or die "$_[0]: $!\n"; local $/; return <$f>//'' }
sub write_raw { my($p,$v)=@_; open my $f,'>:raw',$p or die "$p: $!\n"; print $f $v; close $f or die "$p: $!\n" }
sub json { decode_json(raw($_[0])) }
sub save_json { write_raw($_[0],JSON::PP->new->canonical->pretty->encode($_[1])) }
sub sha { open my $f,'<:raw',$_[0] or die "$_[0]: $!\n"; return Digest::SHA->new(256)->addfile($f)->hexdigest }
sub align { int(($_[0]+$_[1]-1)/$_[1])*$_[1] }
sub u32 { unpack('V',substr($_[0],$_[1],4)) }
sub temporary_root { return $ENV{UNICA_TEST_TMPDIR}//(-d '/tmp/opencode'?'/tmp/opencode':File::Spec->tmpdir) }
sub files { my($root)=@_; my @p; find({no_chdir=>1,wanted=>sub {push @p,$File::Find::name if -f $_ || -l $_}},$root) if -d $root; return @p }
sub relative { my($p,$root)=@_; $p =~ s/^\Q$root\E\/// or die "Outside $root: $p\n"; return $p }
sub crypto { $_[0] =~ /encrypt|keydirectory|wrappedkey/ || $_[0] =~ /^forcefdeorfbe(?:=|$)/ }
sub rows {
    my($text)=@_; my %r;
    for(split /\n/,$text) { next if /^\s*#/; my @f=split; next unless @f>=5 && ($f[1] eq '/data'||$f[1] eq '/metadata');
        need(!exists $r{$f[1]},"Duplicate userdata mount: $f[1]"); $r{$f[1]}=\@f }
    need(keys(%r)==2 && $r{'/data'} && $r{'/metadata'},'Missing userdata/metadata mount'); return \%r;
}
sub policy { my($r)=@_; return 'target-fbe' unless exists $r->{userdata_encryption_policy};
    need($r->{userdata_encryption_policy} eq 'unencrypted','Unsupported userdata encryption policy'); return 'unencrypted' }
sub unencrypted { my($text,$role)=@_; my $r=rows($text);
    for my $m(keys %$r) { my @bad=grep {crypto($_)} split /,/,$r->{$m}[4]; need(!@bad,"$role still requests userdata encryption: $m @bad") } return $r }
sub contract { my($text)=@_; my $r=rows($text); return {map {$_=>[$r->{$_}[2],[sort grep {crypto($_)} split /,/,$r->{$_}[4]]]} keys %$r} }
sub rewrite {
    my($text,$baseline)=@_; rows($text); my @out;
    for(split /(?<=\n)/,$text) { my $line=$_; my @f=split;
        if($line !~ /^\s*#/ && @f>=5 && ($f[1] eq '/data'||$f[1] eq '/metadata')) {
            need(!$baseline || $f[2] eq $baseline->{$f[1]}[2],'Userdata filesystem differs from target vendor');
            my @flags=grep {!crypto($_)} split /,/,$f[4];
            push @flags,grep {crypto($_)} split /,/,$baseline->{$f[1]}[4] if $baseline;
            need(scalar(@flags),"Missing non-crypto fs_mgr flags for $f[1]"); $f[4]=join(',',@flags); $line=join("\t",@f)."\n";
        } push @out,$line;
    } return join('',@out);
}
sub source_hashes { my($fixed,$full,$bind)=@_; my @files=('uname/0001-Report-5.15.206-for-the-selected-uname-spoof.patch','uname/uname.config');
    push @files,'uname/0002-Respect-the-explicit-BPF-spoof-boot-option.patch' if $fixed;
    push @files,'uname/0003-Select-full-BPF-uname-mode.patch' if $full;
    push @files,'bpf/0001-Backport-cgroup-bind-permission-flags.patch' if $bind; return {map {$_=>sha("$ENV{FLOPPY_MODULE}/$_")} @files} }
sub same { JSON::PP->new->canonical->encode($_[0]) eq JSON::PP->new->canonical->encode($_[1]) }
sub uname_check { my($r,$config)=@_;
    need(($r->{uname_spoof_version}//'') eq '5.15.206','Missing/mismatched uname spoof provenance');
    need(same($r->{uname_source_inputs},source_hashes($r->{bpf_boot_option_order_fixed},$r->{bpf_compiled_full_default},$r->{bpf_bind_flags_backport})),'Unreviewed uname source patch/configuration');
    my @selected=$config =~ /^(CONFIG_FAKE_UNAME_\w+=y)$/mg;
    need(@selected==1 && $selected[0] eq 'CONFIG_FAKE_UNAME_5_15=y','Wrong uname spoof configuration');
}
sub target { need(($ENV{TARGET_CODENAME}//'') =~ /^(?:t2s|o1s|p3s|r9s)$/,'Unsupported target'); return $ENV{TARGET_CODENAME} }
sub cohort_root { return "$ENV{OUT_DIR}/kernel/floppy/cohorts/uname-5.15.206-bpf-bind" }
sub selected_publication { my $p=cohort_root(); return (-e $p || -l $p)?'uname-5.15.206-bpf-bind':'' }
sub install_root { return ($_[0]?cohort_root().'/install/':"$ENV{OUT_DIR}/kernel/floppy/install/uname-5.15.206-bpf-bind/").target() }
sub publication_check {
    my $p=cohort_root(); need(-d $p && !-l $p && -f "$p/cohort.json" && !-l "$p/cohort.json",'Incomplete/unsafe published cohort');
    my $r=json("$p/cohort.json"); need($r->{profile} eq 'uname-5.15.206-bpf-bind' && same($r->{source_inputs},source_inputs()),'Published source inputs differ from the module');
    need(sha("$p/module-abi-proof.json") eq $r->{module_abi_proof_sha256},'Published ABI proof checksum mismatch');
    need(sha("$p/cache/$_/floppy-build-info.json") eq $r->{target_manifests}{$_},'Published target manifest checksum mismatch') for qw(t2s o1s p3s r9s);
}
sub cache { my($version,$fixed,$full,$bind,$published)=@_; my $t=target(); need(!defined($version)||$version eq '5.15.206','Unreviewed uname spoof version');
    if($published) { need($bind && $full && $published eq 'uname-5.15.206-bpf-bind','Invalid published receipt profile'); publication_check(); return cohort_root()."/cache/$t" }
    return "$ENV{OUT_DIR}/floppy-images/".(defined($version)?($bind?'uname-5.15.206-bpf-bind/':($full?'uname-5.15.206-bpf-full/':($fixed?'uname-5.15.206-bpf-option/':'uname-5.15.206/'))):'').$t }
sub payload {
    my($d,$name)=@_;
    if($name eq 'boot.img') { need(substr($d,0,8) eq 'ANDROID!' && u32($d,40)==3,'Invalid boot v3');
        my($k,$r)=unpack('VV',substr($d,8,8)); my $o=4096+align($k,4096);
        need($k>0 && $o+$r<=length($d),'Truncated boot payload'); return {kernel=>sha256_hex(substr($d,4096,$k)),ramdisk=>sha256_hex(substr($d,$o,$r))}; }
    if($name eq 'dtbo.img') { my($magic,$size)=unpack('NN',substr($d,0,8)); need($magic==0xd7b7ab1e && $size>=32 && $size<=length($d),'Invalid DTBO'); return {logical_image=>sha256_hex(substr($d,0,$size))} }
    need(substr($d,0,8) eq 'VNDRBOOT','Invalid vendor boot'); my($v,$p)=unpack('VV',substr($d,8,8));
    my($h,$ds)=unpack('VV',substr($d,2096,8)); my $rs=u32($d,24); my $o=align($h,$p); my $dt=$o+align($rs,$p);
    need($v==3 && ($p==2048||$p==4096) && $h==2112 && $ds>0 && $dt+$ds<=length($d),'Unsupported/truncated vendor boot');
    return {dtb=>sha256_hex(substr($d,$dt,$ds)),ramdisk=>sha256_hex(substr($d,$o,$rs))};
}
sub members {
    my($d)=@_; payload($d,'vendor_boot.img'); my $p=u32($d,12); my $packed=substr($d,align(u32($d,2096),$p),u32($d,24));
    my($tmp,$name)=tempfile('unica-ramdisk-XXXXXX',DIR=>temporary_root(),UNLINK=>1);
    binmode $tmp; print $tmp $packed; close $tmp;
    my @cmd=substr($packed,0,2) eq "\x1f\x8b" ? ('gzip','-dc',$name):('lz4','-d','-c',$name);
    open my $pipe,'-|',@cmd or die "decompress: $!"; binmode $pipe; local $/; my $data=<$pipe>; close $pipe or die 'Ramdisk decompression failed';
    my($off,%out)=(0);
    while($off+110<=length $data) { my $h=substr($data,$off,110); need(substr($h,0,6)=~/^07070[12]$/,'Invalid ramdisk cpio');
        my @f=map {hex(substr($h,6+$_*8,8))} 0..12; my $start=align($off+110+$f[11],4);
        need($f[11]>0 && $start+$f[6]<=length($data),'Truncated cpio member'); my $n=substr($data,$off+110,$f[11]-1); $n =~ s/^\.\///;
        return \%out if $n eq 'TRAILER!!!'; need(!exists $out{$n},"Duplicate cpio member: $n");
        $out{$n}=substr($data,$start,$f[6]); $off=align($start+$f[6],4);
    } die "[floppy] Missing cpio trailer\n";
}
sub module_set { return {map {$_=>1} grep {/\.ko$/ || m{(?:^|/)modules\.[^/]*$}} @_} }
sub require_set { my($expected,$actual,$role)=@_; need(same($expected,$actual),"Mismatched $role module set") }
sub cmdline { my($d,$vendor)=@_; return (split /\0/,substr($d,$vendor?28:44,$vendor?2048:1536),2)[0] }
sub bpf_mode {
    my($boot,$vendor,$mode)=@_; $mode//=1;
    my @boot=grep {/^uname_bpf_spoof=/} split /\s+/,cmdline($boot,0);
    my @vendor=grep {/^uname_bpf_spoof=/} split /\s+/,cmdline($vendor,1);
    need(!@boot && @vendor==1 && $vendor[0] eq 'uname_bpf_spoof='.$mode,'Missing/conflicting selected BPF uname compatibility mode');
}

# Artifact verification, not a compiler/build engine. Read ELF sections lazily:
# vmlinux has hundreds of MiB of debugging data which is not needed here.
sub run {
    open my $p,'-|',@_ or die "Cannot run $_[0]: $!\n"; binmode $p; local $/; my $out=<$p>//'';
    my $ok=close $p; need($ok,"Command failed ($_[0]): ".substr($out,-4000)); return $out;
}
sub take { my($f,$o,$n)=@_; seek($f,$o,0) or die "seek: $!\n"; my $v='';
    while(length($v)<$n) { my $r=read($f,my $b,$n-length($v)); need(defined($r)&&$r>0,'Truncated ELF'); $v.=$b } return $v }
sub cstr { my($s,$o)=@_; my $end=index($s,"\0",$o); need($o>=0 && $end>=$o,'Invalid ELF string'); return substr($s,$o,$end-$o) }
sub elf {
    my($path,$type)=@_; open my $f,'<:raw',$path or die "$path: $!\n"; my $h=take($f,0,64);
    need(substr($h,0,6) eq "\x7fELF\x02\x01" && unpack('v',substr($h,16,2))==$type && unpack('v',substr($h,18,2))==183,"Not the required ARM64 ELF: $path");
    my($size,$count,$strings)=unpack('vvv',substr($h,58,6)); my $off=unpack('Q<',substr($h,40,8));
    need($size==64 && $strings<$count && $off+$size*$count<=-s $f,'Invalid ELF section headers');
    my @rows=map {[unpack('VVQ<Q<Q<Q<VVQ<Q<',take($f,$off+$_*64,64))]} 0..$count-1;
    my $names=take($f,$rows[$strings][4],$rows[$strings][5]); my %by;
    for my $r(@rows) { need($r->[1]==8 || $r->[4]+$r->[5]<=-s $f,'ELF section out of bounds'); my $n=cstr($names,$r->[0]); need(!exists $by{$n},'Duplicate ELF section'); $by{$n}=$r }
    return {fh=>$f,rows=>\@rows,by=>\%by};
}
sub section { my($e,$n)=@_; my $r=$e->{by}{$n}; need(defined($r),"Missing ELF section: $n"); return take($e->{fh},$r->[4],$r->[5]) }
sub symbols {
    my($e)=@_; my $r=$e->{by}{'.symtab'}; need($r && $r->[9]==24 && $r->[5]%24==0 && $r->[6]<@{$e->{rows}},'Invalid ELF symbol table');
    my $s=$e->{rows}[$r->[6]]; my $names=take($e->{fh},$s->[4],$s->[5]); my $data=section($e,'.symtab'); my @out;
    for(my $i=0;$i<length($data);$i+=24) { my @v=unpack('VCCvQ<Q<',substr($data,$i,24)); push @out,[cstr($names,$v[0]),@v[1..5]] if $v[0] } return @out;
}
sub module_owner { my $n=basename($_[0]); $n.='.ko' unless $n =~ /\.ko$/; return $n }
sub address_hex { no warnings 'portable'; return hex($_[0]) }
sub verify_build {
    my($source,$pin,$tc)=@_; my $out="$source/out"; my $release=raw("$out/include/config/kernel.release"); chomp $release;
    need($release eq '5.4.304-Floppy-v1.1.2-KN-g113ce9d986f7-dirty','Unexpected real kernel release');
    need(sha("$out/.config") eq source_inputs()->{expected_resolved_config_sha256},'Unreviewed resolved kernel configuration');
    my $image="$out/arch/arm64/boot/Image"; my %inputs=map {$_=>sha("$out/$_")} qw(.config Module.symvers System.map vmlinux arch/arm64/boot/Image);
    # Upstream kernel/Makefile intentionally embeds the stock config, not .config.
    need(run('bash',"$pin/scripts/extract-ikconfig",$image) eq raw("$pin/arch/arm64/configs/exynos2100-r9sxxx-stock_defconfig"),'Image embedded stock-config template differs from pinned upstream');
    run("$tc/bin/llvm-objcopy",'-O','binary','-R','.note','-R','.note.gnu.build-id','-R','.comment','-S',"$out/vmlinux","$pin/Image");
    need(sha("$pin/Image") eq $inputs{'arch/arm64/boot/Image'},'Image does not match this vmlinux');
    my $data=raw("$pin/Image"); need(index($data,"5.15.206\0")>=0 && index($data,"5.10.200\0")==-1 && index($data,"uname_bpf_spoof=2\0")>=0,'Compiled uname/mode-2 defaults are missing');
    need(index($data,"Linux version $release ")>=0 && index($data,"$release\0")>=0,'Kernel native release differs from module vermagic');
    my @dtb=('arch/arm64/boot/dts/exynos/exynos2100.dtb');
    for my $t(qw(t2s o1s p3s r9s)) { push @dtb,map {"arch/arm64/boot/dts/exynos/samsung/$t/$_"} grep {/^[A-Za-z0-9_-]+\.dtbo$/} split /\n/,raw("$pin/build/dtconfigs/$t.cfg") }
    for my $p(@dtb) { my $d=raw("$out/$p"); need(length($d)>=40 && unpack('N',substr($d,0,4))==0xd00dfeed && unpack('N',substr($d,4,4))<=length($d),"Invalid compiled device tree: $p"); $inputs{$p}=sha256_hex($d) }
    my(%providers,%checked,%map);
    for(split /\n/,raw("$out/Module.symvers")) { my($crc,$name,$owner)=split; need(defined($owner) && $crc =~ /^0x[0-9a-fA-F]{8}$/ && !exists($providers{$name}),'Invalid/duplicate Module.symvers export'); $providers{$name}=[hex($crc),$owner] }
    for(split /\n/,raw("$out/System.map")) { my($addr,$type,$name)=split; $map{$name}{address_hex($addr)}=1 if defined $name }
    my $kernel=elf("$out/vmlinux",3); my $strings=section($kernel,'__ksymtab_strings'); my $base=$kernel->{by}{'__ksymtab_strings'}[3];
    # This pinned config uses absolute 64-bit kernel_symbol entries and u32 CRCs.
    for my $suffix('',qw(_gpl _unused _unused_gpl _gpl_future)) {
        my $table=section($kernel,'__ksymtab'.$suffix); my $crc=section($kernel,'__kcrctab'.$suffix);
        need(length($table)%24==0 && length($table)/24==length($crc)/4,'Kernel export/CRC table length mismatch');
        for(my $o=0;$o<length($table);$o+=24) { my($value,$ptr)=unpack('Q<Q<',substr($table,$o,16)); my $name=cstr($strings,$ptr-$base); my $p=$providers{$name};
            need($p && $p->[1] eq 'vmlinux' && $p->[0]==u32($crc,$o/6) && !$checked{$name}++,"vmlinux export CRC/provider mismatch: $name");
            need(exists($map{$name}) && $map{$name}{$value},"System.map differs from vmlinux: $name"); }
    }
    need(exists($checked{'__cgroup_bpf_run_filter_sock_addr_flags'}),'Compiled bind-flags export is missing');
    my $installed="$source/modules_out/lib/modules/$release"; my @paths=sort grep {/\.ko$/} files($installed);
    need(@paths==284,'Expected all 284 installed modules'); my(%modules,@proof); my($strong,$versions,$magic)=(0,0,'');
    for my $path(@paths) {
        need(-f $path && !-l $path,'Installed module must be a regular file'); my $name=basename($path); need(!exists($modules{$name}),'Duplicate installed module basename');
        my $e=elf($path,1); my @info=split /\0/,section($e,'.modinfo'); my @m=grep {/^vermagic=/} @info;
        need(@m==1 && index($m[0],"vermagic=$release ")==0 && (!$magic || $magic eq $m[0]),"Mismatched module vermagic: $name"); $magic=$m[0];
        need(grep($_ eq 'version=r54p3-01eac0 (UK version 11.46)',@info)==1,'Wrong Mali r54 version') if $name eq 'mali_kbase_r54p3.ko';
        my $v=section($e,'__versions'); need(length($v)>0 && length($v)%64==0,'Invalid module version records'); my(%import,%deps,%defined); my $count=0;
        for(my $o=0;$o<length($v);$o+=64) { my $n=cstr(substr($v,$o,64),8); my $crc=unpack('Q<',substr($v,$o,8));
            need(!exists($import{$n}) && exists($providers{$n}) && $providers{$n}[0]==$crc,"Unresolved/CRC-mismatched import $n in $name"); $import{$n}=$crc; }
        need(exists($import{module_layout}),'Missing module_layout CRC'); my @symbols=symbols($e);
        $defined{$_->[0]}=$_->[3] for grep {$_->[3]} @symbols;
        for my $s(@symbols) { my($n,$info,$other,$ndx,$value)=@$s;
            if(!$ndx && ($info>>4)==1) { need(exists($import{$n}) && exists($providers{$n}),"Unresolved strong import $n in $name"); $count++;
                $deps{module_owner($providers{$n}[1])}=1 unless $providers{$n}[1] eq 'vmlinux'; }
            if($n =~ /^__crc_(.+)$/ && $ndx==0xfff1) { my $export=$1; my $p=$providers{$export};
                need($p && module_owner($p->[1]) eq $name && $p->[0]==$value && $defined{'__ksymtab_'.$export} && !$checked{$export}++,"Module export CRC/provider mismatch: $export"); }
        }
        my $row={module=>relative($path,$installed),name=>$name,sha256=>sha($path),strong_imports=>$count,versioned_imports=>scalar(keys %import),dependencies=>[sort keys %deps],vermagic=>substr($magic,9)};
        $modules{$name}={%$row,path=>$path}; push @proof,$row; $strong+=$count; $versions+=keys %import;
    }
    need(exists($modules{'mali_kbase_r54p3.ko'}),'Missing Mali r54 module');
    need(keys(%checked)==keys(%providers),'Module.symvers contains exports absent from the actual kernel/modules');
    for my $r(values %modules) { need(exists($modules{$_}),"Missing module provider: $_") for @{$r->{dependencies}} }
    my @order=map {basename($_)} grep {length} split /\n/,raw("$installed/modules.order");
    my @built=map {basename($_)} grep {length} split /\n/,raw("$out/modules.order");
    need(@order==284 && same(\@order,\@built) && same({map {$_=>1} @order},{map {$_=>1} keys %modules}),'Installed/built modules.order differs from the verified module set');
    return ({kernel_release=>$release,module_count=>284,strong_imports_checked=>$strong,versioned_imports_checked=>$versions,exports_checked=>scalar(keys %checked),
        method=>'Actual ELF64 ARM64 imports, export CRCs/providers, vermagic, vmlinux/Image and pinned stock IKCONFIG template; no module loading',
        inputs=>\%inputs,modules=>\@proof,all_passed=>JSON::PP::true,Image_matches_vmlinux=>JSON::PP::true,embedded_stock_config_checked=>JSON::PP::true,
        embedded_config_is_actual_build_config=>JSON::PP::false,native_release_strings_checked=>JSON::PP::true,physical_boot_qualified=>JSON::PP::false},\%modules);
}

sub publish_build {
    my($source)=@_; need(defined($source) && $source =~ m{^/} && -d $source,'publish-build requires an absolute full-build source directory');
    need(($ENV{OUT_DIR}//'') =~ m{^/} && -d $ENV{OUT_DIR},'OUT_DIR must be an existing absolute directory');
    my $tc=$ENV{FLOPPY_CLANG_DIR}//''; need($tc =~ m{^/} && -d $tc,'Set FLOPPY_CLANG_DIR to the pinned r596125 directory');
    my %compiler=(clang=>'b50deb7c48633d03c02b15b6508d79768027e80422265d7a4a7f2f13d2f01d97','clang-22'=>'96473352cecb545fd039e3291771f7ae78f8a7a48d16703cb19d60b5379999b6',
        'llvm-objcopy'=>'969a5b001021d521b204d5c963d3347fc0dc5032a3870525de86f964caafeabe');
    need(sha("$tc/bin/$_") eq $compiler{$_},"Unreviewed compiler component: $_") for sort keys %compiler;
    my $input=source_inputs(); my $profile=$input->{profile}; my $parent="$ENV{OUT_DIR}/kernel/floppy/cohorts"; my $dest="$parent/$profile";
    make_path($parent); open my $lock,'>>',"$parent/.publication.lock" or die "publication lock: $!\n"; flock($lock,LOCK_EX) or die "flock: $!\n";
    need(!-e $dest && !-l $dest,'Refusing existing published cohort'); require 'syscall.ph'; need(defined(&SYS_renameat2),'Atomic no-replace publication needs Linux renameat2');
    local $ENV{GIT_OPTIONAL_LOCKS}=0; local $ENV{PYTHONDONTWRITEBYTECODE}=1; local $ENV{TZ}='UTC'; local $ENV{LC_ALL}='C';
    need(run('git','-C',$source,'rev-parse','HEAD') eq "$input->{commit}\n",'Wrong source base commit');
    my $tmp=tempdir('.publication-XXXXXXXX',DIR=>$parent,CLEANUP=>1); my $pin="$tmp/source"; my $cohort="$tmp/cohort"; make_path($pin,$cohort);
    local $ENV{TMPDIR}=$tmp; local $ENV{UNICA_TEST_TMPDIR}=$tmp;
    my %tracked=map {$_=>1} split /\n/,run('git','-C',$source,'ls-tree','-r','--name-only',$input->{commit}); my %touched;
    for my $p(keys %{$input->{patches}}) { my $text=raw("$ENV{FLOPPY_MODULE}/$p"); $touched{$1}=1 while $text =~ /^diff --git a\/(.*?) b\//mg }
    my @targets=grep {$tracked{$_}} keys %touched;
    write_raw("$tmp/source.tar",run('git','-C',$source,'archive',$input->{commit},'--','build','scripts/extract-ikconfig','arch/arm64/configs/exynos2100-r9sxxx-stock_defconfig',@targets));
    run('tar','-xf',"$tmp/source.tar",'-C',$pin); run('git','-C',$pin,'init','-q');
    for my $p(sort keys %{$input->{patches}}) { run('git','-C',$pin,'apply','--check',"$ENV{FLOPPY_MODULE}/$p"); run('git','-C',$pin,'apply',"$ENV{FLOPPY_MODULE}/$p") }
    # Packaging always uses Git-exported/patched templates, not source build/tmp
    # or cached images. Only the publication-only images.sh change may be absent
    # from an older full build; the compiler/build script changes must match.
    for(split /\n/,run('git','-C',$source,'diff','--no-ext-diff','--name-only','HEAD')) { need($touched{$_},"Unreviewed source change: $_") }
    for(split /\n/,run('git','-C',$source,'ls-files','--others','--exclude-standard')) { need($touched{$_} || $_ eq 'floppy-source-inputs.json',"Unreviewed untracked source input: $_") }
    for my $p(keys %touched) { next unless $tracked{$p}; my $actual=sha("$source/$p");
        next if $p eq 'build/scripts/images.sh' && $actual eq sha256_hex(run('git','-C',$source,'show',"$input->{commit}:$p"));
        need($actual eq sha("$pin/$p"),"Source patch mismatch: $p"); }
    # Historical warm worktrees accidentally nested this copied submodule. Both
    # accepted locations must contain the exact two Python blobs at the gitlink.
    my $mk="$source/build/mkbootimg"; $mk.='/mkbootimg' unless -f "$mk/mkbootimg.py";
    my %mkblobs=('mkbootimg.py'=>'ec2958179691a434df917cd1b6f196edaa80e31d','gki/generate_gki_certificate.py'=>'739c61b04a9dbd95cafa5196533e3a472c31f2d9');
    for my $p(sort keys %mkblobs) { my $d=raw("$mk/$p"); need(Digest::SHA::sha1_hex('blob '.length($d)."\0".$d) eq $mkblobs{$p},"Wrong pinned mkbootimg source: $p"); make_path(dirname("$pin/build/mkbootimg/$p")); write_raw("$pin/build/mkbootimg/$p",$d) }
    my($proof,$modules)=verify_build($source,$pin,$tc); my $release=$proof->{kernel_release};
    $proof->{publisher_sha256}=sha("$ENV{FLOPPY_MODULE}/customize.sh"); $proof->{compiler_components}=\%compiler;
    $proof->{complete_toolchain_tree_verified}=JSON::PP::false;
    my %vendor; my @load=grep {length} split /\n/,raw("$pin/build/unica/vendor.modules.load"); my @pending=@load;
    while(@pending) { my $n=shift @pending; need(exists($modules->{$n}),"Missing vendor load/provider: $n"); next if $vendor{$n}++; push @pending,@{$modules->{$n}{dependencies}} }
    my $full="$pin/modules_out/lib/modules/$release"; my $subset="$pin/vendor/lib/modules/$release"; make_path($full,$subset);
    for my $n(sort keys %$modules) { my $r=$modules->{$n}; my $p="$full/$r->{module}"; make_path(dirname($p)); copy($r->{path},$p) or die "copy module: $!\n";
        need(sha($p) eq $r->{sha256},'Module changed during snapshot'); copy($p,"$subset/$n") or die "copy vendor module: $!\n" if $vendor{$n}; }
    copy("$source/modules_out/lib/modules/$release/modules.order","$full/modules.order") or die "copy modules.order: $!\n";
    write_raw("$subset/modules.order",join('',map {"$_\n"} sort keys %vendor)); write_raw("$subset/modules.load",join('',map {"$_\n"} @load));
    my $repo=abs_path("$ENV{FLOPPY_MODULE}/../../../.."); my $tools=$ENV{TOOLS_DIR}//"$repo/out/tools";
    # Only existing upstream post/image/DTBO functions and original UN1CA AVB
    # signing are executed. All of their writable paths are private snapshots.
    my $script=<<'SHELL';
set -e -o pipefail
KDIR="$1"; OUTDIR="$2/out"; release="$3"; export SRC_DIR="$4"; export PATH="$5/bin:$PATH"
cd "$KDIR"
source build/lib/log.sh
SCRIPTS_DIR="$KDIR/build/scripts"; MOD_OUTDIR="$KDIR/modules_out"; TMPDIR="$KDIR/build/tmp"
RAMDISK_DIR="$TMPDIR/vendor_ramdisk"; MODULES_DIR="$RAMDISK_DIR/lib/modules"; IN_VBOOT="$KDIR/build/vboot"
IMAGES_DIR="$KDIR/build/images"; mkdir -p "$IMAGES_DIR"
OUT_BOOTIMG_ONEUI="$IMAGES_DIR/boot_oneui.img"; OUT_BOOTIMG_AOSP="$IMAGES_DIR/boot_aosp.img"; OUT_VENDORBOOTIMG="$IMAGES_DIR/vendor_boot.img"
OUT_KERNEL="$KDIR/Image"; PREBUILT_RAMDISK="$KDIR/build/boot/ramdisk"
MKBOOTIMG="$KDIR/build/mkbootimg/mkbootimg.py"; MKDTBOIMG="$KDIR/build/dtb/mkdtboimg.py"
IN_DTB="$OUTDIR/arch/arm64/boot/dts/exynos/exynos2100.dtb"; OUT_DTBIMAGE="$TMPDIR/dtb.img"
BOOT_OS_VERSION=16.0.0; BOOT_OS_PATCH_LEVEL=2026-10; BOOT_HEADER_VERSION=3; VENDOR_CMDLINE=loop.max_part=7; DO_NHMOD=0
source build/scripts/post.sh
source build/scripts/images.sh
source build/scripts/dtbo.sh
kernel_modules
find "$RAMDISK_DIR" -exec touch -h -t 197001010000.00 {} +
build_images
build_dtbo_images
depmod -e -F "$OUTDIR/System.map" -b "$KDIR/vendor" "$release"
SHELL
    write_raw("$cohort/assembly.log",run('bash','-c',$script,'floppy-upstream-packaging',$pin,$source,$release,$repo,$tools));
    my $boot=raw("$pin/build/images/boot_oneui.img"); my $vendor_image=raw("$pin/build/images/vendor_boot.img"); my $ramdisk=members($vendor_image);
    require_set({map {("lib/modules/$_",1)} keys %$modules}, {map {$_=>1} grep {/\.ko$/} keys %$ramdisk},'new upstream ramdisk');
    for my $n(keys %$modules) { need(sha256_hex($ramdisk->{"lib/modules/$n"}) eq $modules->{$n}{sha256},"Ramdisk module differs: $n") }
    my @ramload=grep {length} split /\n/,$ramdisk->{'lib/modules/modules.load'}//'';
    need(@ramload==284 && same({map {$_=>1} @ramload},{map {$_=>1} keys %$modules}),'Incomplete/duplicate upstream modules.load');
    my %ramdep; for(split /\n/,$ramdisk->{'lib/modules/modules.dep'}//'') { my @n=split /[:\s]+/; need(@n>0 && !$ramdep{$n[0]}++,'Duplicate upstream module dependency');
        need(m{^/lib/modules/([A-Za-z0-9_.-]+\.ko)$} && exists($modules->{$1}),'Unsafe/missing upstream module dependency') for @n; }
    need(keys(%ramdep)==284,'Incomplete upstream module dependency metadata');
    need(payload($boot,'boot.img')->{kernel} eq $proof->{inputs}{'arch/arm64/boot/Image'},'Packaged Image differs from verified build');
    need(payload($boot,'boot.img')->{ramdisk} eq sha("$pin/build/boot/ramdisk"),'Wrong repository boot ramdisk');
    my @dependencies;
    for(split /\n/,raw("$subset/modules.dep")) { my($name,$deps)=split /:/,$_,2; need(defined($deps) && $vendor{$name},'Unexpected vendor dependency record');
        my @d=split /\s+/,$deps; @d=grep {length} @d; need(!(grep {!$vendor{$_}} @d),'Vendor dependency escaped verified closure'); push @dependencies,"/vendor/lib/modules/$name:".join('',map {" /vendor/lib/modules/$_"} @d)."\n"; }
    need(@dependencies==keys(%vendor),'Incomplete vendor dependency metadata');
    $proof->{vendor_modules}=[sort keys %vendor]; $proof->{source_inputs}=$input; save_json("$cohort/module-abi-proof.json",$proof);
    for my $t(qw(t2s o1s p3s r9s)) { my $c="$cohort/cache/$t"; my $v="$cohort/install/$t/vendor/lib/modules"; make_path($c,$v);
        copy("$pin/build/images/boot_oneui.img","$c/boot.img") or die $!; copy("$pin/build/images/vendor_boot.img","$c/vendor_boot.img") or die $!;
        copy("$pin/build/images/dtbo_$t.img","$c/dtbo.img") or die $!; copy("$source/out/.config","$c/kernel.config") or die $!;
        copy("$subset/$_","$v/$_") or die $! for sort keys %vendor; write_raw("$v/modules.dep",join('',@dependencies));
        copy("$subset/$_","$v/$_") or die $! for qw(modules.alias modules.softdep modules.load);
    }
    my $sign=<<'SHELL';
set -e -o pipefail
export SRC_DIR="$1"; export PATH="$2/bin:$PATH"
export TARGET_BOOT_PARTITION_SIZE=67108864 TARGET_VENDOR_BOOT_PARTITION_SIZE=67108864 TARGET_DTBO_PARTITION_SIZE=8388608
source "$SRC_DIR/scripts/utils/install_utils.sh"
for t in t2s o1s p3s r9s; do
    for n in boot.img vendor_boot.img dtbo.img; do
        SIGN_IMAGE_WITH_AVB "$3/cache/$t/$n"
        avbtool verify_image --image "$3/cache/$t/$n" --key "$SRC_DIR/security/avb/testkey_rsa4096.pem"
    done
done
SHELL
    save_json("$cohort/source-inputs.json",$input); write_raw("$cohort/signing.log",run('bash','-c',$sign,'floppy-original-avb',$repo,$tools,$cohort));
    for my $t(qw(t2s o1s p3s r9s)) { my $c="$cohort/cache/$t"; my $v="$cohort/install/$t/vendor/lib/modules";
        my $r={schema=>1,target=>$t,commit=>$input->{commit},published_cohort=>$profile,source_inputs=>$input,
            uname_spoof_version=>'5.15.206',uname_source_inputs=>source_hashes(1,1,1),bpf_boot_option_order_fixed=>JSON::PP::true,bpf_compiled_full_default=>JSON::PP::true,bpf_bind_flags_backport=>JSON::PP::true,
            config_sha256=>sha("$c/kernel.config"),images=>{map {$_=>{sha256=>sha("$c/$_"),payload=>payload(raw("$c/$_"),$_)}} qw(boot.img vendor_boot.img dtbo.img)},
            vendor_modules=>{map {basename($_)=>sha($_)} files($v)},compiled=>{release=>$release,commit=>$input->{commit},Image_sha256=>$proof->{inputs}{'arch/arm64/boot/Image'},'Module.symvers_sha256'=>$proof->{inputs}{'Module.symvers'},
                mali_version=>'r54p3-01eac0 (UK version 11.46)',module_symbol_abi_checked=>JSON::PP::true,module_abi_proof_sha256=>sha("$cohort/module-abi-proof.json")},
            boot_validated=>JSON::PP::false,stock_fallback=>JSON::PP::false,public_test_signing_only=>JSON::PP::true};
        uname_check($r,raw("$c/kernel.config")); save_json("$c/floppy-build-info.json",$r);
    }
    need(sha("$source/out/$_") eq $proof->{inputs}{$_},"Build input changed during publication: $_") for keys %{$proof->{inputs}};
    save_json("$cohort/cohort.json",{profile=>$profile,source_inputs=>$input,module_abi_proof_sha256=>sha("$cohort/module-abi-proof.json"),
        target_manifests=>{map {$_=>sha("$cohort/cache/$_/floppy-build-info.json")} qw(t2s o1s p3s r9s)},clean_host_build_qualified=>JSON::PP::false,physical_boot_qualified=>JSON::PP::false});
    # One directory contains both cache and install trees. No two-rename window
    # and no replacement of a user-created destination, even outside this lock.
    my $old=$cohort; my $new=$dest; need(syscall(&SYS_renameat2,-100,$old,-100,$new,1)==0,"Atomic cohort publication failed: $!");
    print "[floppy] Published verified 284-module bind cohort atomically: $dest\n";
}

sub source_inputs {
    return {repository=>'https://github.com/FlopKernel-Series/flop_exynos2100_kernel.git',
        commit=>'113ce9d986f74e1526981324ec164e4d90930071',profile=>'uname-5.15.206-bpf-bind',
        mkbootimg_repository=>'https://android.googlesource.com/platform/system/tools/mkbootimg/',
        mkbootimg_commit=>'d2bb0af5ba6d3198a3e99529c97eda1be0b5a093',
        patches=>{map {$_=>sha("$ENV{FLOPPY_MODULE}/$_")} qw(
            source/0001-Retain-the-UN1CA-source-overlay.patch
            source/0002-Pin-the-retained-configuration.patch
            source/0003-Pin-vendor-load-policy-and-reproducible-ramdisk.patch
            uname/0001-Report-5.15.206-for-the-selected-uname-spoof.patch
            uname/0002-Respect-the-explicit-BPF-spoof-boot-option.patch
            uname/0003-Select-full-BPF-uname-mode.patch
            bpf/0001-Backport-cgroup-bind-permission-flags.patch)},
        uname_config_sha256=>sha("$ENV{FLOPPY_MODULE}/uname/uname.config"),
        expected_resolved_config_sha256=>'40971838c329afaa1c25af65392dfd99ea326595d909e2e6f110c8e94a85268f',
        toolchain_repository=>'https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86',
        toolchain_repository_commit=>'95ecb5c85cd772cae7b67dabf0a1c34c103b6351',
        toolchain_subdirectory=>'clang-r596125',toolchain_build_id=>'15682573',
        toolchain_subtree_git_tree=>'44e59376d6231e87e4ba5545c6baa619b6d4ad54',
        phase=>'source-inputs-only',kernel_built=>JSON::PP::false,module_abi_checked=>JSON::PP::false,
        cache_published=>JSON::PP::false,clean_host_provisioning_qualified=>JSON::PP::false};
}

my $action=shift(@ARGV)//'';
if($action eq 'publish-build') { need(@ARGV==1,'publish-build requires one source directory'); publish_build($ARGV[0]); exit 0 }
if($action eq 'source-inputs') { need(!@ARGV,'source-inputs takes no arguments'); print JSON::PP->new->canonical->pretty->encode(source_inputs()); exit 0 }
if($action eq 'install-root') { my $p=selected_publication(); publication_check() if $p; print install_root($p)."\n"; exit 0 }
if($action eq 'stage') {
    my $t=target(); my $published=selected_publication(); my $c=cache('5.15.206',1,1,1,$published);
    my $install=install_root($published).'/vendor/lib/modules';
    need(-d $install && !(grep { !-f "$c/$_" } qw(floppy-build-info.json kernel.config boot.img dtbo.img vendor_boot.img)),
        "One UI 9 selected kernel cache/install cohort is missing or incomplete for $t. Clean-host ROM provisioning is not qualified. " .
        'prepare-source provisions inputs only; publish-build verifies/packages an existing full build. See the module README. No stock/older-cache fallback.');
    my $r=json("$c/floppy-build-info.json"); my $config=raw("$c/kernel.config");
    if($published) { need(($r->{published_cohort}//'') eq $published && same($r->{source_inputs},source_inputs()),'Wrong published build provenance') }
    need($r->{bpf_boot_option_order_fixed},'Cached kernel does not respect the explicit BPF boot option');
    need($r->{bpf_compiled_full_default},'Cached One UI 9 kernel does not select requested BPF mode 2');
    need($r->{bpf_bind_flags_backport},'Cached kernel lacks the One UI 9 cgroup bind return flags');
    need($r->{target} eq $t,'Cached DTBO/device mismatch'); need($r->{commit} eq '113ce9d986f74e1526981324ec164e4d90930071','Unexpected kernel revision');
    need($r->{compiled}{mali_version} eq 'r54p3-01eac0 (UK version 11.46)','Not the retained Mali r54 build');
    need($r->{compiled}{module_symbol_abi_checked},'Kernel/module ABI was not verified');
    need(sha("$c/kernel.config") eq $r->{config_sha256},'Configuration checksum mismatch'); uname_check($r,$config);
    need($config =~ /^CONFIG_SECURITY_SELINUX=y$/m && $config =~ /^CONFIG_SECURITY_SELINUX_ALWAYS_PERMISSIVE=y$/m,'The existing SELinux mode/configuration differs');
    for my $n(qw(boot.img dtbo.img vendor_boot.img)) { need(sha("$c/$n") eq $r->{images}{$n}{sha256},"Image checksum mismatch: $n");
        my $key='TARGET_'.uc(substr($n,0,-4)).'_PARTITION_SIZE'; need((-s "$c/$n")<=$ENV{$key},"Image exceeds target partition: $n") }
    for my $n(keys %{$r->{vendor_modules}}) { need($n !~ m{/|^\.\.?$},'Unsafe module path in provenance'); need(sha("$install/$n") eq $r->{vendor_modules}{$n},"Module checksum mismatch: $n") }
    my $boot=raw("$c/boot.img"); my $vendor=raw("$c/vendor_boot.img");
    need(cmdline($boot,0) !~ /(?:^|\s)uname_bpf_spoof=/,'Unexpected boot uname compatibility argument');
    my $line=cmdline($vendor,1); need($line !~ /(?:^|\s)uname_bpf_spoof=/,'Unexpected cached vendor uname compatibility argument');
    $line.=' uname_bpf_spoof=2'; need(length($line)<2048,'Vendor boot command line too long'); substr($vendor,28,2048)=$line."\0" x (2048-length($line)); bpf_mode($boot,$vendor,2);
    my $k="$ENV{WORK_DIR}/kernel"; need(-d $k,'Normal target kernel work directory is missing');
    for my $n(qw(boot.img dtbo.img vendor_boot.img kernel.config)) { copy("$c/$n","$k/$n") or die "copy $n: $!" }
    write_raw("$k/vendor_boot.img",$vendor);
    write_raw("$k/floppy-vendor-files.txt",join("\n",sort keys %{$r->{vendor_modules}})."\n");
    save_json("$k/floppy-preserved.json",{source_commit=>$r->{commit},target=>$t,compiled_release=>$r->{compiled}{release},mali=>$r->{compiled}{mali_version},
        ($published?(published_cohort=>$published,source_inputs=>$r->{source_inputs}):()),
        input_images=>$r->{images},uname_spoof_version=>'5.15.206',uname_source_inputs=>source_hashes(1,1,1),userdata_encryption_policy=>'unencrypted',bpf_uname_spoof_mode=>2,bpf_boot_option_order_fixed=>JSON::PP::true,bpf_compiled_full_default=>JSON::PP::true,bpf_bind_flags_backport=>JSON::PP::true,
        vendor_modules=>$r->{vendor_modules},reused_existing_source_build=>JSON::PP::true,stock_fallback=>JSON::PP::false,physical_boot_validated=>JSON::PP::false,
        note=>'Normal fs adaptation/repacking/signing follows; mode 2 keeps the existing root BPF-loader caller gates.'});
    print "[floppy] Staged retained kernel/r54, uname target 5.15.206; root BPF-loader mode 2 with cgroup bind flags; userdata unencrypted\n"; exit 0;
}
if($action eq 'userdata') {
    my($path,$receipt)=@ARGV; my $p=policy(json($receipt));
    if($p eq 'unencrypted') { my $updated=rewrite(raw($path),undef); unencrypted($updated,'Target vendor'); write_raw($path,$updated) }
    print "[floppy] Applied vendor userdata policy $p; no device data changes\n"; exit 0;
}
if($action eq 'fstab') {
    my($root,$vendor,$receipt)=@ARGV; my $p=defined($receipt)?policy(json($receipt)):'target-fbe'; my $v=raw($vendor); my $baseline=rows($v);
    if($p eq 'unencrypted') { unencrypted($v,'Target vendor') } else { need(scalar(grep(/^fileencryption=/,split /,/,$baseline->{'/data'}[4])),'Target vendor has no reviewed FBE configuration') }
    my %pending; for my $file(grep {m{(?:^|/)fstab\.exynos2100$}} files($root)) { $pending{$file}=rewrite(raw($file),$baseline) }
    need(scalar(keys %pending),'Ramdisk fstab is missing'); write_raw($_,$pending{$_}) for sort keys %pending;
    print "[floppy] Applied userdata policy $p to both ramdisk fstabs; no device data changes\n"; exit 0;
}
if($action eq 'verify') {
    my $work=$ENV{WORK_DIR}; my $r=json("$work/kernel/floppy-preserved.json"); my $p=policy($r); my $version=$r->{uname_spoof_version};
    my $c=cache($version,$r->{bpf_boot_option_order_fixed},$r->{bpf_compiled_full_default},$r->{bpf_bind_flags_backport},$r->{published_cohort}); uname_check($r,raw("$work/kernel/kernel.config")) if defined $version;
    my(%image,$destination); my @names=qw(boot.img dtbo.img vendor_boot.img);
    if(@ARGV==2 && $ARGV[0] eq '--zip') {
        open my $list,'-|','unzip','-Z1',$ARGV[1] or die "unzip: $!"; my @entries=<$list>; close $list or die 'Invalid ZIP'; chomp @entries;
        for my $n(@names) { need(grep($_ eq $n,@entries)==1,"Missing/duplicate ZIP image: $n"); open my $z,'-|','unzip','-p',$ARGV[1],$n or die "unzip $n: $!"; binmode $z; local $/; $image{$n}=<$z>; close $z or die "ZIP read $n failed" }
    } else { $destination=$ARGV[0] if @ARGV; my $dir=$destination//"$work/kernel"; $image{$_}=raw("$dir/$_") for @names }
    my %actual=map {$_=>payload($image{$_},$_)} @names;
    for my $n(qw(boot.img dtbo.img)) { for my $k(keys %{$actual{$n}}) { need($actual{$n}{$k} eq $r->{input_images}{$n}{payload}{$k},"Stock/changed Floppy payload: $n/$k") } }
    need($actual{'vendor_boot.img'}{dtb} eq $r->{input_images}{'vendor_boot.img'}{payload}{dtb},'Wrong Floppy DTB');
    if(exists $r->{bpf_uname_spoof_mode}) { need($r->{bpf_uname_spoof_mode}==1 || $r->{bpf_uname_spoof_mode}==2,'Unreviewed uname compatibility mode'); bpf_mode($image{'boot.img'},$image{'vendor_boot.img'},$r->{bpf_uname_spoof_mode}) }
    my $base=members(raw("$c/vendor_boot.img")); my $m=members($image{'vendor_boot.img'});
    require_set(module_set(keys %$base),module_set(keys %$m),'ramdisk');
    for my $n(keys %$base) { need($m->{$n} eq $base->{$n},"Mismatched ramdisk module/dependency: $n") if $n =~ /\.ko$/ || $n =~ m{(?:^|/)modules\.} }
    my @fstabs=grep {m{(?:^|/)fstab\.exynos2100$}} keys %$m; need(scalar(@fstabs),'Missing vendor boot fstab');
    my $v=raw("$work/vendor/etc/fstab.exynos2100"); unencrypted($v,'Target vendor') if $p eq 'unencrypted';
    for my $n(@fstabs) { unencrypted($m->{$n},'Vendor ramdisk') if $p eq 'unencrypted'; need(same(contract($v),contract($m->{$n})),'Vendor ramdisk/userdata encryption differs from the ROM fstab') }
    my $vm="$work/vendor/lib/modules"; my @actual_vendor=map {relative($_,$vm)} files($vm);
    require_set({map {$_=>1} keys %{$r->{vendor_modules}}},module_set(@actual_vendor),'vendor partition');
    for my $n(keys %{$r->{vendor_modules}}) { my $file="$vm/$n"; need(-f $file && !-l $file,"Vendor partition module is not a regular file: $n"); need(sha($file) eq $r->{vendor_modules}{$n},"Mismatched vendor partition module: $n") }
    $r->{final_payloads}=\%actual; $r->{final_kernel_checks_passed}=JSON::PP::true; $r->{userdata_encryption_matches_vendor}=JSON::PP::true;
    $r->{final_images_sha256}={map {$_=>sha256_hex($image{$_})} @names}; $r->{userdata_unencrypted}=JSON::PP::true if $p eq 'unencrypted';
    if(defined $destination) { need(-d $destination,'Missing target-files staging directory'); save_json("$destination/floppy-preserved.json",$r); copy("$work/kernel/kernel.config","$destination/kernel.config") or die "copy config: $!" }
    print "[floppy] Verified kernel/r54 cohort, DTBO/DTB, exact module sets, uname mode and userdata policy $p; no stock fallback\n"; exit 0;
}
die "Usage: customize.sh prepare-source <new-absolute-directory>|publish-build <full-build-source>|source-inputs|stage|install-root|userdata|fstab|verify [arguments]\n";
PERL
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    if [ "${1:-}" = prepare-source ]; then
        shift
        FLOPPY_PREPARE_SOURCE "$@"
    else
        FLOPPY_RUNTIME "$@"
    fi
    exit $?
fi
if [ "$SOURCE_PLATFORM_SDK_VERSION" -ne 37 ]; then
    return 0
fi
FLOPPY_RUNTIME stage || return 1
FLOPPY_INSTALL_ROOT="$(FLOPPY_RUNTIME install-root)" || return 1
while IFS= read -r FLOPPY_VENDOR_FILE; do
    [ -n "$FLOPPY_VENDOR_FILE" ] || continue
    ADD_TO_WORK_DIR "$FLOPPY_INSTALL_ROOT" "vendor" "lib/modules/$FLOPPY_VENDOR_FILE" \
        0 0 644 "u:object_r:vendor_file:s0" || return 1
done < "$WORK_DIR/kernel/floppy-vendor-files.txt"
unset FLOPPY_INSTALL_ROOT FLOPPY_VENDOR_FILE
