SPEN_NATIVE()
{
    "${BASH_SOURCE[0]%/*}/../../../scripts/run_xml_perl.sh" - "$@" <<'PERL'
use strict;
use warnings;
use JSON::PP;
use Digest::SHA qw(sha256_hex);
use File::Find;
use File::Path qw(make_path);
use File::Basename qw(dirname basename);
use File::Glob qw(bsd_glob);
use File::Temp qw(tempfile tempdir);
use File::Spec;
use Cwd qw(abs_path);
use XML::Parser;
sub need($$) { die "UN1CA: $_[1]\n" unless $_[0] }
sub raw { open my $f,'<:raw',$_[0] or die "$_[0]: $!\n"; local $/; return <$f>//'' }
sub sha { sha256_hex(raw($_[0])) }
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
sub u32 { unpack('V',substr($_[0],$_[1],4)) }
sub u64 { unpack('Q<',substr($_[0],$_[1],8)) }
sub cstr { my($d,$o)=@_; my $end=index($d,"\0",$o); need($o>=0 && $end>=$o,'Invalid string offset'); return substr($d,$o,$end-$o) }
sub elf64 {
    my($data)=@_; need(substr($data,0,6) eq "\x7fELF\x02\x01" && u16($data,18)==183,'Expected little-endian ARM64 ELF');
    my($po,$so,$pe,$pn,$se,$sn,$names)=(u64($data,32),u64($data,40),u16($data,54),u16($data,56),u16($data,58),u16($data,60),u16($data,62));
    need((!$pn||$pe==56) && $se==64 && $names<$sn && $so+$sn*$se<=length($data) && $po+$pn*$pe<=length($data),'Invalid ELF layout');
    my @s=map {[unpack('VVQ<Q<Q<Q<VVQ<Q<',substr($data,$so+$_*$se,$se))]} 0..$sn-1;
    my @p=map {[unpack('VVQ<Q<Q<Q<Q<Q<',substr($data,$po+$_*$pe,$pe))]} 0..$pn-1;
    my $strings=substr($data,$s[$names][4],$s[$names][5]); my %by;
    for my $s(@s) { my $name=cstr($strings,$s->[0]); need(!exists $by{$name},'Duplicate ELF section'); $by{$name}=$s }
    return {data=>$data,sections=>\@s,segments=>\@p,by=>\%by};
}
sub section { my($e,$name)=@_; my $s=$e->{by}{$name}; need($s,"Missing ELF section $name"); return substr($e->{data},$s->[4],$s->[5]) }
sub elf_abi {
    my $e=elf64($_[0]); my(@symbols,%imports,%exports,@needed);
    for my $s(@{$e->{sections}}) {next unless $s->[1]==11; need($s->[9]==24 && $s->[6]<@{$e->{sections}},'Invalid dynamic symbol table'); my $strings=$e->{sections}[$s->[6]]; my $data=substr($e->{data},$strings->[4],$strings->[5]);
        for(my $o=$s->[4];$o<$s->[4]+$s->[5];$o+=24) {my($n,$info,$vis,$ndx,$value,$size)=unpack('VCCvQ<Q<',substr($e->{data},$o,24)); my $name=cstr($data,$n); my $binding=$info>>4; my $visibility=$vis&3;
            push @symbols,{name=>$name,binding=>$binding,visibility=>$visibility,ndx=>$ndx,value=>$value,size=>$size}; $exports{$name}=1 if $ndx && ($binding==1||$binding==2) && ($visibility==0||$visibility==3); $imports{$name}=1 if !$ndx && $binding==1;
        }
    }
    if(my $s=$e->{by}{'.dynamic'}) {my $strings=$e->{sections}[$s->[6]]; my $data=substr($e->{data},$strings->[4],$strings->[5]); for(my $o=$s->[4];$o<$s->[4]+$s->[5];$o+=16) {my($tag,$v)=unpack('q<Q<',substr($e->{data},$o,16)); push @needed,cstr($data,$v) if $tag==1}}
    $e->{symbols}=\@symbols; $e->{exports}=\%exports; $e->{imports}=\%imports; $e->{needed}=\@needed; return $e;
}
sub hardened {
    my($e)=@_; need(!scalar(grep {$_->[0]==1 && ($_->[1]&3)==3} @{$e->{segments}}),'Writable executable PT_LOAD');
    need(scalar(grep {$_->[0]==0x6474e552} @{$e->{segments}}),'Missing GNU_RELRO'); need(scalar(grep {$_->[0]==0x6474e551 && !($_->[1]&1)} @{$e->{segments}}),'Missing non-executable stack');
}
sub va_offset { my($e,$addr,$size)=@_; $size//=1; for my $p(@{$e->{segments}}) {return $p->[2]+$addr-$p->[3] if $p->[0]==1 && $addr>=$p->[3] && $addr+$size<=$p->[3]+$p->[5]} die "No file-backed address $addr" }
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
sub edit_xml { my($doc,$edits)=@_; my $data=$doc->{data}; for my $e(sort {$b->[0]<=>$a->[0]} @$edits) {substr($data,$e->[0],$e->[1]-$e->[0])=$e->[2]} xml($data,0); return $data }
sub append_xml {
    my($doc,$parent,$content)=@_; my $tag=$parent->{tag}; utf8::encode($tag) if utf8::is_utf8($tag);
    return edit_xml($doc,[[substr($doc->{data},$parent->{open}-2,2) eq '/>' ?
        ($parent->{open}-2,$parent->{open},">\n$content\n</$tag>") : ($parent->{close},$parent->{close},"$content\n")]]);
}
sub methods { my($text)=@_; my %m; while($text =~ /^(\.method [^\n]+\n.*?^\.end method)/msg) {my $raw=$1; my($first)=split /\n/,$raw; my($name)=$first =~ /(\S+)$/; need(!exists $m{$name},"Duplicate method $name"); $m{$name}=$raw} return \%m }
sub once { my($text,$old,$new)=@_; my $count=()=$text =~ /\Q$old\E/g; need($count==1,"Expected one exact anchor, found $count: $old"); $text =~ s/\Q$old\E/$new/; return $text }
my $action=shift(@ARGV)//''; my %args; while(@ARGV) {my $key=shift @ARGV; need($key =~ /^--/ && @ARGV,'Expected named S Pen arguments'); $args{$key}=shift @ARGV}
my $here="$ENV{SRC_DIR}/unica/patches/spen";
if($action eq 'native') {
    my($platform,$donor,$output)=@args{qw(--platform --donor --output)}; need(defined($output)&&defined($donor)&&defined($platform),'Missing SMPS paths');
    $platform=abs_path($platform); $donor=abs_path($donor); my $output_abs=abs_path(dirname($output)).'/'.basename($output); need(index($output_abs,"$platform/system/")!=0 && index($output_abs,"$donor/")!=0 && $output_abs ne $donor,'Output must not be inside input trees');
    my $lib="$platform/system/system/lib64"; my %cohort=('libaudioclient.so'=>'7ce4927daf08ff26b34b9d55d49425052dac06bbdd753e7cad2c2b464235008c','libmedia.so'=>'6f765d9dcb46dd6f4ab5623089284bdd72ae55bef316bf24f488609be0453b43','libutils.so'=>'e1eb96ad194e2b2191c3a2a11d7f2d876fd57b30583d9fdaee1da001ba5b5e23','libc++.so'=>'cb118e98c74d3454858921123b9b51ba13df9cad7dfa141dd892c453661a4d78');
    my %providers; for my $name(keys %cohort) {need(sha("$lib/$name") eq $cohort{$name},"Unmeasured One UI 9 C++ cohort: $name"); $providers{$name}=elf_abi(raw("$lib/$name"))}
    my $provider='libsmpsft.smps.samsung.so'; my $adapter='libspen_audiotrack37.so'; my $input_sha='89fc59766d247464eb174b6889b7e266b2dcb48d4336fc24ae0c93e857fc09c3'; my $raw=raw("$donor/system/lib64/$provider"); need(sha256_hex($raw) eq $input_sha,'Unmeasured Samsung SMPS provider'); my $original=elf_abi($raw);
    my $old='_ZN7android10AudioTrack3setE19audio_stream_type_tj14audio_format_t20audio_channel_mask_tm20audio_output_flags_tRKNS_2wpINS0_19IAudioTrackCallbackEEEiRKNS_2spINS_7IMemoryEEEb15audio_session_tNS0_13transfer_typeEPK20audio_offload_info_tRKNS_7content22AttributionSourceStateEPK18audio_attributes_tbfi'; my $new=$old.'RKNSt3__112basic_stringIcNSR_11char_traitsIcEENSR_9allocatorIcEEEE';
    need(exists($original->{imports}{$old}) && exists($providers{'libaudioclient.so'}{exports}{$new}),'AudioTrack::set ABI differs from measured profile');
    my %available=map {map {$_=>1} keys %{$_->{exports}}} values %providers;
    for my $name(@{$original->{needed}}) {if(-f "$lib/$name") {my $e=elf_abi(raw("$lib/$name")); $available{$_}=1 for keys %{$e->{exports}}}}
    my %bionic=map {$_->{name}=>1} grep {!$_->{ndx} && $_->{name} !~ /^_Z/} @{$original->{symbols}}; my @missing=sort grep {!$available{$_} && !$bionic{$_}} keys %{$original->{imports}}; need(same(\@missing,[$old]),"Additional unresolved C++ ABI: @missing");
    my $server=elf64(raw("$lib/libandroid_servers.so")); my %registrations;
    for my $row(['setPenHovering','(Z)V'],['setShowHovering','(Z)V'],['setPenModeOnDex','(I)V'],['setStylusPointerIconEnabled','(Z)V']) {my($name,$sig)=@$row; my $off=index($server->{data},"$name\0"); need($off>=0,"Missing native method name $name"); my @matches;
        for my $p(grep {$_->[0]==1 && $off>=$_->[2] && $off<$_->[2]+$_->[5]} @{$server->{segments}}) {my $address=$p->[3]+$off-$p->[2];
            for my $s(grep {$_->[1]==1 && ($_->[2]&2)} @{$server->{sections}}) {my $data=substr($server->{data},$s->[4],$s->[5]); for(my $i=0;$i+24<=length($data);$i+=8) {next unless u64($data,$i)==$address; my($signature,$function)=unpack('Q<Q<',substr($data,$i+8,16)); my($actual,$code);
                my $valid=eval {$actual=cstr($server->{data},va_offset($server,$signature,1)); $code=substr($server->{data},va_offset($server,$function,16),16); 1}; next unless $valid && $actual eq $sig;
                need(substr($code,0,4) ne "\xc0\x03\x5f\xd6" && substr($code,0,4) ne "\x00\x00\x80\x52","Unexpected trivial native implementation: $name"); push @matches,{table=>sprintf('0x%x',$s->[3]+$i),function=>sprintf('0x%x',$function),signature=>$actual};
            }}
        } need(@matches==1,"Expected exactly one native registration: $name"); $registrations{$name}=$matches[0];
    }
    my $hwr=elf_abi(raw("$lib/libSDKRecognitionText.spensdk.samsung.so")); my $prefix='Java_com_samsung_android_sdk_handwriting_text_impl_TextRecognizerLib_'; my @hwr=map {$prefix.$_} qw(VIHW_1Init VIHW_1Release VIHW_1Recognize VIHW_1SetAsyncMode VIHW_1SetListener VIHW_1AddStroke__J_3F_3FI VIHW_1SetLanguage__JLjava_lang_String_2Ljava_lang_String_2Ljava_lang_String_2);
    need(!scalar(grep {!$hwr->{exports}{$_}} @hwr),'One UI 9 handwriting provider lacks measured SmartEye JNI'); need(scalar(grep {$_ eq 'libSDKRecognitionText.spensdk.samsung.so'} split /\n/,raw("$platform/system/system/etc/public.libraries-spensdk.samsung.txt")),'Handwriting engine is not public');
    my $dir="$output/system/lib64"; make_path($dir); need(!-e "$dir/$provider" && !-e "$dir/$adapter",'Refusing existing native outputs');
    my @patches=([0x6cb4,0x5280aa00,0x5280af00,'AudioTrack allocation: 0x550 -> 0x578'],[0x700c,0xb9422106,0xb9423906,'initCheck/mStatus: 0x220 -> 0x238']); my $patched=$raw;
    for my $p(@patches) {my $o=va_offset($original,$p->[0],4); need(u32($patched,$o)==$p->[1],'Unexpected SMPS opcode'); substr($patched,$o,4)=pack('V',$p->[2])}
    run('clang','--target=aarch64-linux-android37','-fuse-ld=lld','-nostdlib','-shared',"-Wl,-soname,$adapter",'-Wl,-z,defs,-z,relro,-z,now,-z,noexecstack','-Wl,-z,max-page-size=16384,--build-id=sha1','-Wl,--no-as-needed',"$here/audiotrack_set.S","$lib/libaudioclient.so",'-o',"$dir/$adapter");
    put("$dir/$provider",$patched); run('patchelf','--add-needed',$adapter,"$dir/$provider"); my $final=elf_abi(raw("$dir/$provider")); my $bridge=elf_abi(raw("$dir/$adapter"));
    need(same($final->{imports},$original->{imports}) && same($final->{exports},$original->{exports}),'SMPS JNI/synthesis ABI changed'); need(same([sort @{$final->{needed}}],[sort @{$original->{needed}},$adapter]),'Unexpected SMPS dependencies');
    need(same([sort keys %{$bridge->{exports}}],[$old]) && same([sort keys %{$bridge->{imports}}],[$new]) && same($bridge->{needed},['libaudioclient.so']),'Unexpected adapter ABI/dependency'); need(!scalar(grep {!$available{$_} && !$bridge->{exports}{$_} && !$bionic{$_}} keys %{$final->{imports}}),'Unresolved C++ symbol after adaptation');
    my $text=$original->{by}{'.text'}; need(section($final,'.text') eq substr($patched,$text->[4],$text->[5]),'ELF editing changed native implementation');
    need(section($final,$_) eq section($original,$_),"ELF editing changed $_") for qw(.rodata .data .data.rel.ro .rela.dyn .relr.dyn .rela.plt); hardened($final); hardened($bridge);
    save("$output/native-report.json",{profile=>'p3s / SM-S942B_INS One UI 9 arm64 / b0sxxx SMPS SDK36',cohort_sha256=>\%cohort,provider_input_sha256=>$input_sha,patches=>[map {{address=>sprintf('0x%x',$_->[0]),before=>sprintf('0x%x',$_->[1]),after=>sprintf('0x%x',$_->[2]),purpose=>$_->[3]}} @patches],native_registrations=>\%registrations,jni_exports=>[sort grep {/^Java_/} keys %{$final->{exports}}],handwriting_jni_exports=>[sort @hwr],adapter_export=>$old,adapter_import=>$new,provider_output_sha256=>sha256_hex($final->{data}),adapter_output_sha256=>sha256_hex($bridge->{data}),scope=>'Static ABI/linkage validation; no Android audio or pen hardware executed'}); exit 0;
}
if($action eq 'clients') {
    my($source,$original,$platform,$decoded,$scratch,$jar,$report)=@args{qw(--source --original --platform --decoded --scratch --jar --report)};
    need(defined($report)&&defined($jar)&&defined($scratch)&&defined($decoded)&&defined($platform)&&defined($original)&&defined($source),'Missing SmartEye client paths');
    # Stock SM-S942B_INS BZJA APK; all 91 SDK classes and five isolated R8 helpers
    # match the previously measured client contract. Keep the APK pin fail-closed.
    my $source_sha='22e02765030fe995712f4edb7a5e93d5895677e199f011507184263412cc467c'; my $original_sha='952c0629fe00aa161026ea3221aeb1fa1ef0cc15efd8f2ae72e0afc17ae3ad52';
    my $stride_sha='e49b999011f24279afb42d7c5fc115a69c193f634d1e9ec967bee49ce388990c'; my $hwr_sha='16e8e712dd7686b7457f8a0de98d84e27a956cdd30760a7e417f727af060b305';
    need(sha($source) eq $source_sha,'Unmeasured One UI 9 SmartCapture clients'); need(sha($original) eq $original_sha,'Unmeasured SmartEye application facade');
    need(sha("$platform/system/system/lib64/libStride.camera.samsung.so") eq $stride_sha,'Unmeasured One UI 9 Stride provider'); need(sha("$platform/system/system/lib64/libSDKRecognitionText.spensdk.samsung.so") eq $hwr_sha,'Unmeasured One UI 9 handwriting provider');
    for my $row(['libStride.camera.samsung.so','camera'],['libSDKRecognitionText.spensdk.samsung.so','spensdk']) {need(scalar(grep {$_ eq $row->[0]} split /\n/,raw("$platform/system/system/etc/public.libraries-$row->[1].samsung.txt")),"Native provider is not public: $row->[0]")}
    need(!-e $scratch && !-l $scratch && -d $decoded,'Client scratch must be new; SmartEye must be normally decoded'); make_path($scratch);
    my @prefixes=('Lcom/samsung/android/sdk/handwriting/','Lcom/samsung/android/ocr/');
    my %helpers=('La0/j1;'=>['Lunica/spen/r8/Strings;',[qw(B(Ljava/lang/StringBuilder;ILjava/lang/String;)V C(ILjava/lang/String;Ljava/lang/String;)V D(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V p(ILjava/lang/String;Ljava/lang/String;)Ljava/lang/StringBuilder; r(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)Ljava/lang/StringBuilder;)]],
        'Lcom/google/android/material/appbar/b;'=>['Lunica/spen/r8/Maps;',[qw(m(IILjava/lang/String;Ljava/lang/String;Ljava/lang/String;)V o(ILcom/samsung/android/ocr/MOCRLang$1;Ljava/lang/String;ILjava/lang/String;)V p(ILcom/samsung/android/sdk/handwriting/LanguageID$1;Ljava/lang/String;ILjava/lang/String;)V w(Ljava/lang/String;Ljava/lang/String;Z)V)]],
        'Lcom/samsung/android/sdk/scs/ai/core/b;'=>['Lunica/spen/r8/Messages;',[qw(j(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String; p(IILjava/lang/String;Ljava/lang/String;Ljava/lang/String;)Ljava/lang/StringBuilder;)]],
        'Lne/b;'=>['Lunica/spen/r8/ErrorText;',['i(ILjava/lang/String;)Ljava/lang/String;']], 'Lbg/a;'=>['Lunica/spen/r8/UrlPredicate;',undef]);
    my $is_sdk=sub {my($name)=@_; return scalar grep {index($name,$_)==0} @prefixes};
    sub descriptor {my($text)=@_; my @c=$text =~ /^\.class [^\n]*?(L\S+;)$/mg; need(@c==1,'Missing/ambiguous smali class declaration'); return $c[0]}
    sub relative_class {my $name=$_[0]; need($name =~ /^L[^\s]+;$/,'Invalid class descriptor'); return substr($name,1,-1).'.smali'}
    my $extract=sub {my($apk,$dest,$select)=@_; need(!-e $dest,'Existing selective disassembly destination'); make_path($dest); my %selected;
        for my $member(grep {/^classes\d*\.dex$/} split /\n/,run('unzip','-Z1',$apk)) {my $data=run('unzip','-p',$apk,$member); need(substr($data,0,4) eq "dex\n",'Expected ordinary DEX'); my @strings;
            for my $i(0..u32($data,56)-1) {my $o=u32($data,u32($data,60)+$i*4); my $count=0; while(ord(substr($data,$o,1))&128) {need(++$count<=4,'Invalid DEX string length'); $o++} push @strings,cstr($data,$o+1)}
            my @types=map {$strings[u32($data,u32($data,68)+$_*4)]} 0..u32($data,64)-1; my @names=sort grep {$select->($_)} map {$types[u32($data,u32($data,100)+$_*32)]} 0..u32($data,96)-1;
            next unless @names; need(!scalar(grep {$selected{$_}} @names),'Duplicate source class definitions'); $selected{$_}=1 for @names;
            run('java','-Xmx512m','-cp',$jar,'com.android.tools.smali.baksmali.Main','d','--debug-info','false','--accessor-comments','false','--use-locals','--sequential-labels','-j','1','--classes',join(',',@names),'-o',$dest,abs_path($apk)."/$member");
        }
        my @actual=sort map {descriptor(raw($_))} grep {/\.smali$/} walk($dest); need(same(\@actual,[sort keys %selected]),'Incomplete selective disassembly'); return \%selected;
    };
    my $source_dir="$scratch/source"; my $old_dir="$scratch/original"; my $cohort=$extract->($source,$source_dir,sub {$is_sdk->($_[0])||exists $helpers{$_[0]}}); my %sdk=map {$_=>1} grep {$is_sdk->($_)} keys %$cohort;
    need(grep(index($_,$prefixes[0])==0,keys %sdk)==47 && grep(index($_,$prefixes[1])==0,keys %sdk)==44,'Incomplete One UI 9 client cohorts'); need(!scalar(grep {!$cohort->{$_}} keys %helpers),'Missing R8 outline/predicate dependencies');
    my %facade=map {my $text=raw($_); descriptor($text)=>$text} grep {/\.smali$/} walk("$here/smarteye"); my $originals=$extract->($original,$old_dir,sub {$is_sdk->($_[0])||exists $facade{$_[0]}}); my %existing;
    for my $dir(grep {-d $_} bsd_glob("$decoded/smali*")) {for my $path(grep {/\.smali$/} walk($dir)) {my $name=descriptor(raw($path)); need(!exists $existing{$name},"Duplicate decoded class $name"); $existing{$name}=$path}}
    my @expected=sort grep {$is_sdk->($_)||exists $facade{$_}} keys %existing; need(same(\@expected,[sort keys %$originals]),'Unexpected existing SmartEye client classes');
    need(raw($existing{$_}) eq raw("$old_dir/".relative_class($_)),"Modified SmartEye class $_; refusing overwrite") for keys %$originals;
    my $remap=sub {my $text=$_[0]; for my $old(sort keys %helpers) {my $new=$helpers{$old}[0]; $text =~ s/\Q$old\E/$new/g} return $text}; my(%transformed,%provenance);
    for my $name(sort keys %sdk) {my $raw=raw("$source_dir/".relative_class($name)); my $text=$raw;
        if($name eq 'Lcom/samsung/android/sdk/handwriting/Recognizer;') {my $create="    invoke-static {p0}, Lcom/samsung/android/spen/libwrapper/SystemPropertiesWrapper;->create(Landroid/content/Context;)Lcom/samsung/android/spen/libwrapper/SystemPropertiesWrapper;\n\n    move-result-object p0\n"; $text=once($text,$create,'');
            my $old='invoke-virtual {p0, v1}, Lcom/samsung/android/spen/libwrapper/SystemPropertiesWrapper;->get(Ljava/lang/String;)Ljava/lang/String;'; my $new='invoke-static {v1}, Landroid/os/SystemProperties;->get(Ljava/lang/String;)Ljava/lang/String;'; $text =~ s/\Q$old\E/$new/g; $text =~ s{Lcom/samsung/android/spen/libwrapper/utils/PlatformException;}{Ljava/lang/IllegalArgumentException;}g;
        } elsif($name eq 'Lcom/samsung/android/sdk/handwriting/text/impl/SepUseWrapper;') {my $direct='Lcom/samsung/android/sdk/handwriting/text/impl/SepUseDirect;'; $text=raw("$source_dir/".relative_class($direct)); $text =~ s/\Q$direct\E/$name/g}
        elsif($name eq 'Lcom/samsung/android/sdk/handwriting/common/HwrLibraryLoader;') {my $old='    const-class v6, Lcom/samsung/android/sdk/pen/Spen;' . "\n\n" . '    sget-object v7, Lcom/samsung/android/sdk/pen/Spen;->Companion:Lcom/samsung/android/sdk/pen/Spen$Companion;'; my $new="    const-string v6, \"com.samsung.android.sdk.pen.Spen\"\n\n    invoke-static {v6}, Ljava/lang/Class;->forName(Ljava/lang/String;)Ljava/lang/Class;\n\n    move-result-object v6"; $text=once($text,$old,$new)}
        $text=$remap->($text); $transformed{$name}=$text; $provenance{$name}={source_smali_sha256=>sha256_hex($raw),installed_smali_sha256=>sha256_hex($text)};
    }
    for my $old(sort keys %helpers) {my($new,$keep)=@{$helpers{$old}}; my $raw=raw("$source_dir/".relative_class($old)); my $text;
        if(!defined $keep) {$text=$remap->($raw)} else {my $m=methods($raw); need(!scalar(grep {!exists $m->{$_}} @$keep),"R8 helper methods changed in $old"); $text=".class public final $new\n.super Ljava/lang/Object;\n\n".join("\n\n",map {$remap->($m->{$_})} sort @$keep)."\n"}
        $transformed{$new}=$text; $provenance{$new}={source_class=>$old,methods=>$keep?[sort @$keep]:'complete class',installed_smali_sha256=>sha256_hex($text)};
    }
    @transformed{keys %facade}=values %facade; my %texts=(map {$_=>raw($existing{$_})} grep {!exists $originals->{$_}} keys %existing); @texts{keys %transformed}=values %transformed;
    my %affected=(%sdk,map {$_=>1} (keys(%facade),map {$_->[0]} values %helpers)); my(%parents,%mdefs,%fdefs);
    for my $name(keys %texts) {my $text=$texts{$name}; $parents{$name}=[$text =~ /^\.(?:super|implements) (L\S+;)/mg]; $mdefs{$name}=methods($text); my %fields;
        for my $line($text =~ /^(\.field .+)$/mg) {$line =~ s/ = .*//; my($field)=$line =~ /(\S+)$/; $fields{$field}=1} $fdefs{$name}=\%fields;
    }
    my $has; $has=sub {my($owner,$member,$defs,$seen)=@_; return 0 if $seen->{$owner}++; return 1 if exists $defs->{$owner}{$member}; return scalar grep {$has->($_,$member,$defs,$seen)} @{$parents{$owner}//[]}}; my $checked=0;
    for my $caller(keys %texts) {while($texts{$caller} =~ /(\[*L[^\s,{}\[]+;)->([^\s,}]+)/g) {my($owner,$member)=($1,$2); next if $owner =~ /^\[/ && $member eq 'clone()Ljava/lang/Object;'; next unless $affected{$owner}||$is_sdk->($owner);
        need(exists $texts{$owner},"Missing client class $owner from $caller"); next if $member eq 'getClass()Ljava/lang/Class;'; need($has->($owner,$member,index($member,'(')>=0?\%mdefs:\%fdefs,{}),"Missing client member $owner->$member from $caller"); $checked++}}
    for my $name(keys %transformed) {need(!exists($existing{$name})||exists($originals->{$name}),"Existing unrelated destination class $name"); while($transformed{$name} =~ /(L[\w\/\$-]+;)/g) {my $ref=$1; need(exists($texts{$ref}) || $ref =~ m{^(?:Ljava/|Ljavax/|Landroid/|Ldalvik/|Lcom/samsung/android/feature/)},"Unresolved source type $ref in $name")}}
    my $manifest="$decoded/AndroidManifest.xml"; my $data=raw($manifest); my $doc=xml($data,1); my @app=grep {$_->{tag} eq 'application'} @{$doc->{root}{children}}; need(@app==1,'Expected one text manifest application from normal APK decode'); my %libs;
    for my $node(grep {$_->{tag} eq 'uses-native-library'} @{$app[0]{children}}) {my $name=$node->{attrs}{'android:name'}; need(defined($name)&&!exists($libs{$name}),'Duplicate/missing native-library manifest identity'); $libs{$name}=$node->{attrs}{'android:required'}//'true'}
    my $library='libSDKRecognitionText.spensdk.samsung.so'; need(exists($libs{'libStride.camera.samsung.so'})&&!exists($libs{$library}),'Unexpected SmartEye native-library declarations'); my $updated=append_xml($doc,$app[0],qq{<uses-native-library android:name="$library" android:required="true" />}); xml($updated,1); $libs{$library}='true';
    for my $name(keys %$originals) {unlink($existing{$name}) or die $! unless exists $transformed{$name}}
    for my $name(keys %transformed) {my $dest=$existing{$name}//"$decoded/smali/".relative_class($name); need(exists($originals->{$name})||!-e $dest,"Unexpected destination $dest"); put($dest,$transformed{$name})} put($manifest,$updated);
    save($report,{source_apk_sha256=>$source_sha,stride_sha256=>$stride_sha,handwriting_sha256=>$hwr_sha,original_apk_sha256=>$original_sha,handwriting_classes=>47,ocr_classes=>44,isolated_helper_classes=>scalar(keys %helpers),facade_classes=>[sort keys %facade],client_member_references_checked=>$checked,manifest_native_libraries=>\%libs,provenance=>\%provenance,limits=>'Client installation/static resolution only; native Android execution is not implied'}); exit 0;
}
die "Expected native or clients S Pen action\n";
PERL
}
SPEN_ENABLE_NATIVE()
(
    "${BASH_SOURCE[0]%/*}/../../../scripts/run_xml_perl.sh" --check || exit 1
    [ "$TARGET_CODENAME" = "p3s" ] || { ABORT "One UI 9 S Pen native profile only measured for p3s"; return 1; }
    if grep -q '^ro.system.product.cpu.abilist32=.' "$WORK_DIR/system/system/build.prop"; then
        ABORT "One UI 9 p3s S Pen requires the source arm64-only platform"
        return 1
    fi
    SPEN_BUILD_DIR="$(mktemp -d "$WORK_DIR/configs/spen.XXXXXX")" || return 1
    trap 'rm -rf "$SPEN_BUILD_DIR"' EXIT
    SPEN_NATIVE native --platform "$WORK_DIR" --donor "$SRC_DIR/prebuilts/samsung/b0sxxx" \
        --output "$SPEN_BUILD_DIR" || return 1
    ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" "system" "system/framework/SmpsManager.jar" 0 0 644 "u:object_r:system_file:s0" || return 1
    ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" "system" "system/etc/permissions/smps_library.xml" 0 0 644 "u:object_r:system_file:s0" || return 1
    ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" "system" "system/app/HandwritingService/HandwritingService.apk" 0 0 644 "u:object_r:system_file:s0" || return 1
    for SPEN_FILE in libsmpsft.smps.samsung.so libspen_audiotrack37.so; do
        ADD_TO_WORK_DIR "$SPEN_BUILD_DIR" "system" "system/lib64/$SPEN_FILE" 0 0 644 "u:object_r:system_lib_file:s0" || return 1
    done
    cp "$SPEN_BUILD_DIR/native-report.json" "$WORK_DIR/configs/spen-native.json" || return 1
    for SPEN_FILE in \
        "system/app/AirGlance/AirGlance.apk" "system/app/LiveDrawing/LiveDrawing.apk" \
        "system/etc/default-permissions/default-permissions-com.samsung.android.service.aircommand.xml" \
        "system/etc/permissions/privapp-permissions-com.samsung.android.app.readingglass.xml" \
        "system/etc/permissions/privapp-permissions-com.samsung.android.service.aircommand.xml" \
        "system/etc/permissions/privapp-permissions-com.samsung.android.service.airviewdictionary.xml" \
        "system/etc/sysconfig/airviewdictionaryservice.xml" "system/etc/public.libraries-smps.samsung.txt" \
        "system/priv-app/AirCommand/AirCommand.apk" "system/priv-app/AirReadingGlass/AirReadingGlass.apk" \
        "system/priv-app/SmartEye/SmartEye.apk"; do
        ADD_TO_WORK_DIR "b0qxxx" "system" "$SPEN_FILE" 0 0 644 "u:object_r:system_file:s0" || return 1
    done
    ADD_TO_WORK_DIR "b0qxxx" "system" "system/media/audio/pensounds" 0 0 755 "u:object_r:system_file:s0" || return 1
    DECODE_APK "system" "system/priv-app/SmartEye/SmartEye.apk" || return 1
    SPEN_NATIVE clients \
        --source "$FW_DIR/$SOURCE_FIRMWARE_PATH/system/system/app/SmartCapture/SmartCapture.apk" \
        --original "$SRC_DIR/prebuilts/samsung/b0qxxx/system/priv-app/SmartEye/SmartEye.apk" \
        --platform "$WORK_DIR" --decoded "$APKTOOL_DIR/system/priv-app/SmartEye/SmartEye.apk" \
        --scratch "$SPEN_BUILD_DIR/clients" --jar "$TOOLS_DIR/bin/apktool.jar" \
        --report "$WORK_DIR/configs/spen-clients.json" || return 1
    ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/etc/permissions/com.sec.feature.spen_usp_level75.xml" \
        0 0 644 "u:object_r:system_file:s0" || return 1
    for SPEN_FEATURE in SEC_FLOATING_FEATURE_FRAMEWORK_CONFIG_SPEN_VERSION SEC_FLOATING_FEATURE_FRAMEWORK_CONFIG_SPEN_GARAGE_SPEC; do
        SPEN_VALUE="$(GET_FLOATING_FEATURE_CONFIG "$FW_DIR/$TARGET_FIRMWARE_PATH/system/system/etc/floating_feature.xml" "$SPEN_FEATURE")"
        [ -n "$SPEN_VALUE" ] || { ABORT "Missing target S Pen feature: $SPEN_FEATURE"; return 1; }
        SET_FLOATING_FEATURE_CONFIG "$SPEN_FEATURE" "$SPEN_VALUE" || return 1
    done
    LOG "- Enabled p3s S Pen using One UI 9 input JNI and adapted Samsung SMPS"
)

SOURCE_FIRMWARE_PATH="$(cut -d "/" -f 1 -s <<< "$SOURCE_FIRMWARE")_$(cut -d "/" -f 2 -s <<< "$SOURCE_FIRMWARE")"
TARGET_FIRMWARE_PATH="$(cut -d "/" -f 1 -s <<< "$TARGET_FIRMWARE")_$(cut -d "/" -f 2 -s <<< "$TARGET_FIRMWARE")"

SOURCE_HAS_SPEN="$(test -n "$(find "$FW_DIR/$SOURCE_FIRMWARE_PATH/system/system/etc/permissions" -type f -name "com.sec.feature.spen_usp*.xml")" && echo "true" || echo "false")"
TARGET_HAS_SPEN="$(test -n "$(find "$FW_DIR/$TARGET_FIRMWARE_PATH/system/system/etc/permissions" -type f -name "com.sec.feature.spen_usp*.xml")" && echo "true" || echo "false")"

if ! $SOURCE_HAS_SPEN; then
    if $TARGET_HAS_SPEN; then
        if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ]; then
            SPEN_ENABLE_NATIVE || return 1
            unset SOURCE_FIRMWARE_PATH TARGET_FIRMWARE_PATH SOURCE_HAS_SPEN TARGET_HAS_SPEN
            return 0
        fi
        ADD_TO_WORK_DIR "b0qxxx" "system" "system/app/AirGlance/AirGlance.apk" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system" "system/app/LiveDrawing/LiveDrawing.apk" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system" "system/etc/default-permissions/default-permissions-com.samsung.android.service.aircommand.xml" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system" "system/etc/permissions/privapp-permissions-com.samsung.android.app.readingglass.xml" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system" "system/etc/permissions/privapp-permissions-com.samsung.android.service.aircommand.xml" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system" "system/etc/permissions/privapp-permissions-com.samsung.android.service.airviewdictionary.xml" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system" "system/etc/sysconfig/airviewdictionaryservice.xml" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system" "system/etc/public.libraries-smps.samsung.txt" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "$([[ "$TARGET_OS_SINGLE_SYSTEM_IMAGE" == "qssi" ]] && echo "b0qxxx" || echo "b0sxxx")" \
            "system" "system/lib/libandroid_runtime.so" 0 0 644 "u:object_r:system_lib_file:s0"
        ADD_TO_WORK_DIR "$([[ "$TARGET_OS_SINGLE_SYSTEM_IMAGE" == "qssi" ]] && echo "b0qxxx" || echo "b0sxxx")" \
            "system" "system/lib/libsmpsft.smps.samsung.so" 0 0 644 "u:object_r:system_lib_file:s0"
        ADD_TO_WORK_DIR "$([[ "$TARGET_OS_SINGLE_SYSTEM_IMAGE" == "qssi" ]] && echo "b0qxxx" || echo "b0sxxx")" \
            "system" "system/lib64/libandroid_runtime.so" 0 0 644 "u:object_r:system_lib_file:s0"
        ADD_TO_WORK_DIR "$([[ "$TARGET_OS_SINGLE_SYSTEM_IMAGE" == "qssi" ]] && echo "b0qxxx" || echo "b0sxxx")" \
            "system" "system/lib64/libsmpsft.smps.samsung.so" 0 0 644 "u:object_r:system_lib_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system" "system/media/audio/pensounds" 0 0 755 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system" "system/priv-app/AirCommand/AirCommand.apk" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system" "system/priv-app/AirReadingGlass/AirReadingGlass.apk" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system" "system/priv-app/SmartEye/SmartEye.apk" 0 0 644 "u:object_r:system_file:s0"
    else
        LOG "\033[0;33m! Nothing to do\033[0m"
    fi
else
    if ! $TARGET_HAS_SPEN; then
        ABORT "Missing patch for condition (SOURCE_HAS_SPEN: [$SOURCE_HAS_SPEN], TARGET_HAS_SPEN: [$TARGET_HAS_SPEN]). Aborting"
    fi
fi

unset SOURCE_FIRMWARE_PATH TARGET_FIRMWARE_PATH SOURCE_HAS_SPEN TARGET_HAS_SPEN
