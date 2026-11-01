PRODUCT_OPTICAL()
{
    perl - "$@" <<'PERL'
use strict;
use warnings;
use JSON::PP;
use Digest::SHA qw(sha256_hex);
use File::Path qw(make_path);
use File::Basename qw(dirname basename);
use File::Glob qw(bsd_glob);
use File::Temp qw(tempfile tempdir);
use File::Spec;
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
sub methods { my($text)=@_; my %m; while($text =~ /^(\.method [^\n]+\n.*?^\.end method)/msg) {my $raw=$1; my($first)=split /\n/,$raw; my($name)=$first =~ /(\S+)$/; need(!exists $m{$name},"Duplicate method $name"); $m{$name}=$raw} return \%m }
my $action=shift(@ARGV)//''; my $module="$ENV{SRC_DIR}/unica/patches/product_feature/fingerprint/optical_fod";
if($action eq 'check-patches') {
    my($root)=@ARGV; my $contract=json("$module/contract.json");
    for my $row(@{$contract->{files}}) {my $relative=$row->{path}; $relative =~ s{^smali[^/]*/}{}; my $artifact="$root/$contract->{artifacts}{$row->{artifact}}"; my @paths=grep {-f $_} bsd_glob("$artifact/smali*/$relative");
        need(@paths==1 && rel($paths[0],$artifact) eq $row->{path},"Missing/ambiguous One UI 9 optical class: $relative"); my $text=raw($paths[0]); my $descriptor='L'.substr($relative,0,-6).';'; my @decl=$text =~ /^\.class [^\n]* (L[^\s]+;)$/mg; need(same(\@decl,[$descriptor]),'Optical class descriptor does not match path');
        my $m=methods($text); for my $sig(keys %{$row->{methods}}) {my $hash=$row->{methods}{$sig}; need(defined($hash)?(exists($m->{$sig})&&sha256_hex($m->{$sig}) eq $hash):!exists($m->{$sig}),"Unmeasured/existing optical method: $relative->$sig")}
    }
    for my $artifact(sort keys %{$contract->{artifacts}}) {my $patch="$module/$artifact/0001-Port-optical-FOD-to.patch"; need(sha($patch) eq $contract->{patches}{$artifact},'Optical patch differs from reviewed method plan'); run('git','apply','--check','--unsafe-paths',"--directory=$root/$contract->{artifacts}{$artifact}",$patch)}
    print "One UI 9 optical: all 18 owners and five ordinary patches validated before mutation\n"; exit 0;
}
need($action eq 'native','Expected native or check-patches optical action'); my %args; while(@ARGV) {my $key=shift @ARGV; need($key =~ /^--/ && @ARGV,'Expected optical argument'); $args{$key}=shift @ARGV}
my $platform=$args{'--platform'}; need(defined($platform),'Missing optical platform'); my $output=$args{'--output'}; my $libui='system/system/lib64/libui.so';
# The second runtime identity differs only in GNU build-id/debug metadata.
# All code/data/linkage and the other seven reviewed cohort inputs are unchanged.
my %cohort=('system/system/lib64/libgui.so'=>'aff919fec79a2636533d8026a07ccaa31b3c92673142f68f64e0b60570329b04',$libui=>'466dffbd2087a5a0c18b84717437e7204128af9343a9ec42657ba9839a309d0f','system/system/lib64/libandroid_runtime.so'=>['4a21077a466d05232d8fc521455a3b9e1b036793e3a91bb32ac51252f6beb6b9','7e7d3c0ecb6adc789e02d8d76e8defa0fc003651f514ec22b15efdb446c3f755'],'vendor/lib64/hw/android.hardware.graphics.allocator@4.0-impl.so'=>'789d49fbcf3620160855e89b17323adf4366f0dff65cf8d1258153e0a6fe01d0','vendor/lib64/hw/android.hardware.graphics.mapper@4.0-impl.so'=>'7859d7e6596127a32b178650a37219146615e5c324cd508b2ac5fb05c72bbcb4','vendor/lib64/libexynosgraphicbuffer.so'=>'177570fe889185ea8834a2f4c55b513a4941e660328a43d452ad81fce1e58e54','vendor/lib64/libexynosdisplay.so'=>'21ec8cf91ba79c838b04f2dedaf7af9192c194757a462549d8c9caa1dc7d1955','vendor/etc/vintf/manifest.xml'=>'e292660d39a886d2a83b7f7e63b1c43b854760a3e1c9dd356c3acb3a7134f875');
my %measured;
for my $path(sort keys %cohort) {
    need(-f "$platform/$path" && !-l "$platform/$path","Missing/unsafe One UI 9/r9s optical native input: $path");
    my $actual=sha("$platform/$path"); my @accepted=ref($cohort{$path}) eq 'ARRAY'?@{$cohort{$path}}:($cohort{$path});
    need((grep {$_ eq $actual} @accepted),"Unmeasured One UI 9/r9s optical native cohort: $path"); $measured{$path}=$actual;
}
exit 0 unless defined $output; need(!-e $output && !-l $output,'Refusing existing optical native outputs'); my $raw=raw("$platform/$libui"); my $elf=elf64($raw); my $va=0x446a8; my @offsets=map {$_->[2]+$va-$_->[3]} grep {$_->[0]==1 && $va>=$_->[3] && $va+4<=$_->[3]+$_->[5]} @{$elf->{segments}}; need(@offsets==1,'Ambiguous/unmapped One UI 9 instruction'); my $offset=$offsets[0]; need(u32($raw,$offset)==0xf2dfffe8,'Unexpected libui validation instruction'); substr($raw,$offset,4)=pack('V',0xf2dfff68);
need(sha256_hex($raw) eq '979a5ed04506a6be231ebbe6c5546670739f8dcc89c571c759ad8d600e42c461','Unexpected libui edit scope'); make_path($output); my $library='libunica_optical37.so'; my $target="$output/$library";
run('clang','--target=aarch64-linux-android37','-fuse-ld=lld','-nostdlib','-shared','-O2','-Wall','-Wextra','-Werror','-fPIC','-fvisibility=hidden','-fstack-protector-strong','-mbranch-protection=standard',"-Wl,-soname,$library",'-Wl,-z,defs,-z,relro,-z,now,-z,noexecstack','-Wl,-z,max-page-size=16384,--build-id=sha1','-Wl,--no-as-needed',"$module/consumer_usage.c","$platform/system/system/lib64/libgui.so",'-o',$target);
my $jni='Java_android_view_ViewRootImpl_nativeSetOpticalMaskBufferUsage'; my $consumer='_ZN7android12ConsumerBase20setConsumerUsageBitsEm'; my $abi=elf_abi(raw($target)); need(same([sort keys %{$abi->{imports}}],[$consumer]) && same([sort keys %{$abi->{exports}}],[$jni]) && same($abi->{needed},['libgui.so']),'Unexpected optical JNI/linkage ABI'); my $dynamic=run('readelf','-dW',$target); need(index($dynamic,'BIND_NOW')>=0 && index($dynamic,'TEXTREL')<0,'Optical bridge lacks hardening'); put("$output/libui.so",$raw);
save("$output/native-report.json",{profile=>'r9s HIDL4 / SM-S942B One UI 9 arm64 optical usage',input_sha256=>\%measured,bridge_sha256=>sha($target),libui_output_sha256=>sha256_hex($raw),libui_patch=>{virtual_address=>'0x446a8',file_offset=>sprintf('0x%x',$offset),before=>'0xf2dfffe8',after=>'0xf2dfff68',effect=>'HIDL reserved-usage rejection mask 0xffff00280000 -> 0xfffb00280000; AIDL unchanged'},jni_export=>$jni,import=>$consumer,runtime_verified=>JSON::PP::false,panel_hbm_verified=>JSON::PP::false});
PERL
}
PRODUCT_ENABLE_OPTICAL()
{
    if [ "$SOURCE_PLATFORM_SDK_VERSION" != "37" ] || [ "$TARGET_CODENAME" != "r9s" ] || \
            [ "$TARGET_PLATFORM_SDK_VERSION" != "36" ] || [ "$TARGET_OS_SINGLE_SYSTEM_IMAGE" != "essi" ] || \
            [ "$TARGET_FINGERPRINT_CONFIG_SENSOR" != "google_touch_display_optical,settings=3" ] || \
            [ "$SOURCE_FINGERPRINT_CONFIG_SENSOR" != "google_touch_display_ultrasonic" ]; then
        ABORT "One UI 9 optical FOD only supports the reviewed r9s/ESSI cohort"
        return 1
    fi
    local OPTICAL_PATH="$MODPATH/fingerprint/optical_fod"
    PRODUCT_OPTICAL native --platform "$WORK_DIR" --output "$APKTOOL_DIR/.optical-fod/native" || return 1
    DECODE_APK "system" "system/framework/framework.jar" || return 1
    DECODE_APK "system" "system/framework/services.jar" || return 1
    DECODE_APK "system" "system/priv-app/BiometricSetting/BiometricSetting.apk" || return 1
    DECODE_APK "system" "system/priv-app/SecSettings/SecSettings.apk" || return 1
    DECODE_APK "system_ext" "priv-app/SystemUI/SystemUI.apk" || return 1
    PRODUCT_OPTICAL check-patches "$APKTOOL_DIR" || return 1
    APPLY_PATCH "system" "system/framework/framework.jar" "$OPTICAL_PATH/framework.jar/0001-Port-optical-FOD-to.patch" || return 1
    APPLY_PATCH "system" "system/framework/services.jar" "$OPTICAL_PATH/services.jar/0001-Port-optical-FOD-to.patch" || return 1
    APPLY_PATCH "system" "system/priv-app/BiometricSetting/BiometricSetting.apk" "$OPTICAL_PATH/BiometricSetting.apk/0001-Port-optical-FOD-to.patch" || return 1
    APPLY_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" "$OPTICAL_PATH/SecSettings.apk/0001-Port-optical-FOD-to.patch" || return 1
    APPLY_PATCH "system_ext" "priv-app/SystemUI/SystemUI.apk" "$OPTICAL_PATH/SystemUI.apk/0001-Port-optical-FOD-to.patch" || return 1
    SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_BIOAUTH_CONFIG_FINGERPRINT_FEATURES" "optical_display_phone" || return 1
    SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_LCD_CONFIG_LOCAL_HBM" "0" || return 1
    SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_LCD_CONFIG_SELFMASK_VERSION" "0" || return 1
    install -m 644 "$APKTOOL_DIR/.optical-fod/native/libui.so" "$WORK_DIR/system/system/lib64/libui.so" || return 1
    install -m 644 "$APKTOOL_DIR/.optical-fod/native/libunica_optical37.so" "$WORK_DIR/system/system/lib64/libunica_optical37.so" || return 1
    SET_METADATA "system" "system/lib64/libunica_optical37.so" 0 0 644 "u:object_r:system_lib_file:s0" || return 1
}

PRODUCT_DISPLAY_SMALI_DIR="smali_classes4"
PRODUCT_TELEPHONY_SMALI_DIR="smali_classes4"
PRODUCT_REFRESH_DUMP_METHOD="dump(Ljava/io/PrintWriter;Ljava/lang/String;Z)V"
PRODUCT_RESOLUTION_PROFILE=false
PRODUCT_OPTICAL_PROFILE=false
if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ]; then
    PRODUCT_DISPLAY_SMALI_DIR="smali_classes3"
    PRODUCT_TELEPHONY_SMALI_DIR="smali_classes6"
    PRODUCT_REFRESH_DUMP_METHOD="dumpProductFeature(Ljava/io/PrintWriter;Ljava/lang/String;Z)V"
fi

# [
GET_FINGERPRINT_SENSOR_TYPE()
{
    if [[ "$1" == *"ultrasonic"* ]]; then
        echo "ultrasonic"
    elif [[ "$1" == *"optical"* ]]; then
        echo "optical"
    elif [[ "$1" == *"side"* ]]; then
        echo "side"
    else
        ABORT "Unknown fingerprint sensor type: \"$1\". Aborting"
    fi
}

LOG_MISSING_PATCHES()
{
    local MESSAGE="Missing SPF patches for condition ($1: [${!1}], $2: [${!2}])"

    if $DEBUG; then
        LOGW "$MESSAGE"
    else
        ABORT "${MESSAGE}. Aborting"
    fi
}
# ]

# Admit only the reviewed One UI 9 profiles and dispatch around the ENTIRE legacy
# branches. Never import their SDK36 compositor or R8-generated UI replacements.
# Reject unsupported transitions before any product-feature mutations.
if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ]; then
    if [[ "$SOURCE_COMMON_SUPPORT_DYN_RESOLUTION_CONTROL" != "$TARGET_COMMON_SUPPORT_DYN_RESOLUTION_CONTROL" ]]; then
        if [ "$TARGET_CODENAME" = "p3s" ] && [ "$TARGET_PLATFORM_SDK_VERSION" -eq 35 ] && \
                [ "$TARGET_OS_SINGLE_SYSTEM_IMAGE" = "essi" ] && \
                [ "$SOURCE_COMMON_SUPPORT_DYN_RESOLUTION_CONTROL" = false ] && \
                [ "$TARGET_COMMON_SUPPORT_DYN_RESOLUTION_CONTROL" = true ] && \
                [ "$(GET_FINGERPRINT_SENSOR_TYPE "$TARGET_FINGERPRINT_CONFIG_SENSOR")" = ultrasonic ]; then
            PRODUCT_RESOLUTION_PROFILE=true
        else
            ABORT "Unreviewed One UI 9 dynamic-resolution capability transition"
            return 1
        fi
    fi
    if [[ "$(GET_FINGERPRINT_SENSOR_TYPE "$SOURCE_FINGERPRINT_CONFIG_SENSOR")" != \
            "$(GET_FINGERPRINT_SENSOR_TYPE "$TARGET_FINGERPRINT_CONFIG_SENSOR")" ]]; then
        if [ "$TARGET_CODENAME" = "r9s" ] && [ "$TARGET_PLATFORM_SDK_VERSION" -eq 36 ] && \
                [ "$TARGET_OS_SINGLE_SYSTEM_IMAGE" = "essi" ] && \
                [ "$SOURCE_FINGERPRINT_CONFIG_SENSOR" = "google_touch_display_ultrasonic" ] && \
                [ "$TARGET_FINGERPRINT_CONFIG_SENSOR" = "google_touch_display_optical,settings=3" ]; then
            # Layout and legacy allocator compatibility are cohort-dependent.
            # Fail BEFORE unrelated product-feature mutations on new inputs.
            PRODUCT_OPTICAL native --platform "$WORK_DIR" || return 1
            PRODUCT_OPTICAL_PROFILE=true
        else
            ABORT "Unreviewed One UI 9 fingerprint sensor-type transition"
            return 1
        fi
    fi
fi

# SEC_PRODUCT_FEATURE_BUILD_MAINLINE_API_LEVEL
if [[ "$SOURCE_PRODUCT_SHIPPING_API_LEVEL" != "$TARGET_PRODUCT_SHIPPING_API_LEVEL" ]]; then
    SMALI_PATCH "system" "system/framework/esecomm.jar" \
        "smali/com/sec/esecomm/EsecommAdapter.smali" "replace" \
        "<clinit>()V" \
        "$SOURCE_PRODUCT_SHIPPING_API_LEVEL" \
        "$TARGET_PRODUCT_SHIPPING_API_LEVEL"
    SMALI_PATCH "system" "system/framework/services.jar" \
        "smali/com/android/server/enterprise/hdm/HdmSakManager.smali" "replace" \
        "isSupported(Landroid/content/Context;)Z" \
        "$SOURCE_PRODUCT_SHIPPING_API_LEVEL" \
        "$TARGET_PRODUCT_SHIPPING_API_LEVEL"
    PRODUCT_HDM_VENDOR_SMALI="smali/com/android/server/enterprise/hdm/HdmVendorController.smali"
    PRODUCT_HDM_VENDOR_METHOD="<init>()V"
    if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ]; then
        # R8 inlined this initialization; the vendor capability decision and
        # real service lookup remain intact in the owning constructor.
        PRODUCT_HDM_VENDOR_SMALI="smali/com/android/server/enterprise/EnterpriseDeviceManagerServiceImpl.smali"
        PRODUCT_HDM_VENDOR_METHOD="<init>(Landroid/content/Context;)V"
    fi
    SMALI_PATCH "system" "system/framework/services.jar" \
        "$PRODUCT_HDM_VENDOR_SMALI" "replace" \
        "$PRODUCT_HDM_VENDOR_METHOD" \
        "$SOURCE_PRODUCT_SHIPPING_API_LEVEL" \
        "$TARGET_PRODUCT_SHIPPING_API_LEVEL"
    unset PRODUCT_HDM_VENDOR_SMALI PRODUCT_HDM_VENDOR_METHOD
    SMALI_PATCH "system" "system/framework/services.jar" \
        "smali/com/android/server/knox/dar/ddar/ta/TAProxy.smali" "replace" \
        "updateServiceHolder(Z)V" \
        "$SOURCE_PRODUCT_SHIPPING_API_LEVEL" \
        "$TARGET_PRODUCT_SHIPPING_API_LEVEL"
    SMALI_PATCH "system" "system/framework/services.jar" \
        "smali/com/android/server/SystemServer.smali" "replace" \
        "startOtherServices(Lcom/android/server/utils/TimingsTraceAndSlog;)V" \
        "MAINLINE_API_LEVEL: $SOURCE_PRODUCT_SHIPPING_API_LEVEL" \
        "MAINLINE_API_LEVEL: $TARGET_PRODUCT_SHIPPING_API_LEVEL"
    SMALI_PATCH "system" "system/framework/services.jar" \
        "smali/com/android/server/SystemServer.smali" "replace" \
        "startOtherServices(Lcom/android/server/utils/TimingsTraceAndSlog;)V" \
        "$SOURCE_PRODUCT_SHIPPING_API_LEVEL" \
        "$TARGET_PRODUCT_SHIPPING_API_LEVEL"
    SMALI_PATCH "system" "system/framework/services.jar" \
        "smali_classes2/com/android/server/power/PowerManagerUtil.smali" "replace" \
        "<clinit>()V" \
        "$SOURCE_PRODUCT_SHIPPING_API_LEVEL" \
        "$TARGET_PRODUCT_SHIPPING_API_LEVEL"
    SMALI_PATCH "system" "system/framework/services.jar" \
        "smali_classes2/com/android/server/sepunion/EngmodeService\$EngmodeTimeThread.smali" "replace" \
        "<clinit>()V" \
        "$SOURCE_PRODUCT_SHIPPING_API_LEVEL" \
        "$TARGET_PRODUCT_SHIPPING_API_LEVEL"
fi

# SEC_PRODUCT_FEATURE_AUDIO_CONFIG_RECORDALIVE_LIB_VERSION
if [[ "$SOURCE_AUDIO_CONFIG_RECORDALIVE_LIB_VERSION" != "$TARGET_AUDIO_CONFIG_RECORDALIVE_LIB_VERSION" ]]; then
    if [[ "$SOURCE_AUDIO_CONFIG_RECORDALIVE_LIB_VERSION" != "none" ]]; then
        SMALI_PATCH "system" "system/framework/framework.jar" \
            "smali_classes6/com/samsung/android/camera/mic/SemMultiMicManager.smali" "replace" \
            "isSupported()Z" \
            "$SOURCE_AUDIO_CONFIG_RECORDALIVE_LIB_VERSION" \
            "${TARGET_AUDIO_CONFIG_RECORDALIVE_LIB_VERSION//none/}"
        SMALI_PATCH "system" "system/framework/framework.jar" \
            "smali_classes6/com/samsung/android/camera/mic/SemMultiMicManager.smali" "replace" \
            "isSupported(I)Z" \
            "$SOURCE_AUDIO_CONFIG_RECORDALIVE_LIB_VERSION" \
            "${TARGET_AUDIO_CONFIG_RECORDALIVE_LIB_VERSION//none/}"
    else
        # TODO handle this condition
        LOG_MISSING_PATCHES "SOURCE_AUDIO_CONFIG_RECORDALIVE_LIB_VERSION" "TARGET_AUDIO_CONFIG_RECORDALIVE_LIB_VERSION"
    fi
fi

# SEC_PRODUCT_FEATURE_AUDIO_CONFIG_HAPTIC
if $SOURCE_AUDIO_SUPPORT_ACH_RINGTONE; then
    if ! $TARGET_AUDIO_SUPPORT_ACH_RINGTONE; then
        APPLY_PATCH "system" "system/framework/framework.jar" \
            "$MODPATH/audio/ach/framework.jar/0001-Disable-ACH-ringtone-support.patch"
    fi
else
    if $TARGET_AUDIO_SUPPORT_ACH_RINGTONE; then
        # TODO handle this condition
        LOG_MISSING_PATCHES "SOURCE_AUDIO_SUPPORT_ACH_RINGTONE" "TARGET_AUDIO_SUPPORT_ACH_RINGTONE"
    fi
fi

# SEC_PRODUCT_FEATURE_AUDIO_SUPPORT_DUAL_SPEAKER
if $SOURCE_AUDIO_SUPPORT_DUAL_SPEAKER; then
    if ! $TARGET_AUDIO_SUPPORT_DUAL_SPEAKER; then
        SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_AUDIO_SUPPORT_DUAL_SPEAKER" --delete

        APPLY_PATCH "system" "system/framework/framework.jar" \
            "$MODPATH/audio/dual_speaker/framework.jar/0001-Disable-dual-speaker-support.patch"
        APPLY_PATCH "system" "system/framework/services.jar" \
            "$MODPATH/audio/dual_speaker/services.jar/0001-Disable-dual-speaker-support.patch"
    fi
else
    if $TARGET_AUDIO_SUPPORT_DUAL_SPEAKER; then
        # TODO handle this condition
        LOG_MISSING_PATCHES "SOURCE_AUDIO_SUPPORT_DUAL_SPEAKER" "TARGET_AUDIO_SUPPORT_DUAL_SPEAKER"
    fi
fi

# SEC_PRODUCT_FEATURE_AUDIO_SUPPORT_VIRTUAL_VIBRATION_SOUND
if $SOURCE_AUDIO_SUPPORT_VIRTUAL_VIBRATION_SOUND; then
    if ! $TARGET_AUDIO_SUPPORT_VIRTUAL_VIBRATION_SOUND; then
        APPLY_PATCH "system" "system/framework/framework.jar" \
            "$MODPATH/audio/virtual_vib/framework.jar/0001-Disable-virtual-vibration-support.patch"
        APPLY_PATCH "system" "system/framework/services.jar" \
            "$MODPATH/audio/virtual_vib/services.jar/0001-Disable-virtual-vibration-support.patch"
        if [ "$SOURCE_PLATFORM_SDK_VERSION" -lt 37 ]; then
        SMALI_PATCH "system" "system/framework/services.jar" \
            "smali/com/android/server/audio/BtHelper\$\$ExternalSyntheticLambda0.smali" "remove"
        EVAL "sed -i \"/.source/q\" \"$APKTOOL_DIR/system/framework/services.jar/smali_classes2/com/android/server/vibrator/VibratorManagerInternal.smali\""
        SMALI_PATCH "system" "system/framework/services.jar" \
            "smali_classes2/com/android/server/vibrator/VibratorManagerService\$SamsungBroadcastReceiver\$\$ExternalSyntheticLambda1.smali" "remove"
        SMALI_PATCH "system" "system/framework/services.jar" \
            "smali_classes2/com/android/server/vibrator/VirtualVibSoundHelper.smali" "remove"
        fi
        APPLY_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
            "$MODPATH/audio/virtual_vib/SecSettings.apk/0001-Disable-virtual-vibration-support.patch"
        APPLY_PATCH "system" "system/priv-app/SettingsProvider/SettingsProvider.apk" \
            "$MODPATH/audio/virtual_vib/SettingsProvider.apk/0001-Disable-virtual-vibration-support.patch"
    fi
else
    if $TARGET_AUDIO_SUPPORT_VIRTUAL_VIBRATION_SOUND; then
        # TODO handle this condition
        LOG_MISSING_PATCHES "SOURCE_AUDIO_SUPPORT_VIRTUAL_VIBRATION_SOUND" "TARGET_AUDIO_SUPPORT_VIRTUAL_VIBRATION_SOUND"
    fi
fi

# SEC_PRODUCT_FEATURE_COMMON_CONFIG_MDNIE_MODE
if [[ "$SOURCE_COMMON_CONFIG_MDNIE_MODE" != "$TARGET_COMMON_CONFIG_MDNIE_MODE" ]]; then
    SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_COMMON_CONFIG_MDNIE_MODE" "$TARGET_COMMON_CONFIG_MDNIE_MODE"

    SMALI_PATCH "system" "system/framework/services.jar" \
        "smali_classes2/com/samsung/android/hardware/display/SemMdnieManagerService.smali" "replace" \
        "<init>(Landroid/content/Context;)V" \
        "$SOURCE_COMMON_CONFIG_MDNIE_MODE" \
        "$TARGET_COMMON_CONFIG_MDNIE_MODE"
fi

# SEC_PRODUCT_FEATURE_COMMON_CONFIG_DYN_RESOLUTION_CONTROL
if $PRODUCT_RESOLUTION_PROFILE; then
    # Keep the One UI 9 compositor and bootanimation; only enable the reviewed
    # forced-size resolution policy, never the legacy native/R8 replacements.
    SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_COMMON_CONFIG_DYN_RESOLUTION_CONTROL" "WQHD,FHD,HD" || return 1

    # LPM blits SPI images at their stored size, unlike bootanimation's QMG
    # scaling. Restore the original QHD media without replacing either binary
    # or overwriting newer source-only media with a whole-directory import.
    for PRODUCT_RESOLUTION_MEDIA in battery_error.spi battery_low.spi battery_protection.spi \
            battery_temperature_error.spi battery_temperature_limit.spi battery_water_usb.spi \
            incomplete_connect.spi lcd_density.txt new_vi_0_100.spi new_vi_1_100.spi new_vi_2_100.spi \
            new_vi_level_0_1.spi new_vi_level_0_2.spi new_vi_level_0_3.spi new_vi_level_0_4.spi \
            new_vi_level_1_1.spi new_vi_level_1_2.spi new_vi_level_1_3.spi new_vi_level_1_4.spi \
            new_vi_level_2_1.spi new_vi_level_2_2.spi new_vi_level_2_3.spi new_vi_level_2_4.spi \
            slow_charging_usb.spi temperature_limit_usb.spi water_protection_usb.spi; do
        ADD_TO_WORK_DIR "b0qxxx" "system" "system/media/$PRODUCT_RESOLUTION_MEDIA" \
            0 0 644 "u:object_r:system_file:s0" || return 1
    done
    unset PRODUCT_RESOLUTION_MEDIA

    APPLY_PATCH "system" "system/framework/framework.jar" \
        "$MODPATH/resolution/framework.jar/0001-Enable-legacy-resolution-voting.patch" || return 1
    APPLY_PATCH "system" "system/framework/gamemanager.jar" \
        "$MODPATH/resolution/gamemanager.jar/0001-Enable-resolution-notifications.patch" || return 1

    # Both One UI 9 confirmation listeners retain the source entry point's ABI.
    SMALI_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
        "smali_classes3/com/samsung/android/settings/display/SecDisplayUtils.smali" "null" \
        "setDisplayMode(Ljava/lang/String;Landroid/view/Display;)V" || return 1
    APPLY_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
        "$MODPATH/resolution/SecSettings.apk/0001-Enable-resolution-controls.patch" || return 1
    APPLY_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
        "$MODPATH/resolution/SecSettings.apk/0002-Connect-reset-routines-and-backup.patch" || return 1
    APPLY_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
        "$MODPATH/resolution/SecSettings.apk/0003-Add-resolution-policy.patch" || return 1

    APPLY_PATCH "system_ext" "priv-app/SystemUI/SystemUI.apk" \
        "$MODPATH/resolution/SystemUI.apk/0001-Scale-edge-mask-for-resolution.patch" || return 1
elif ! $SOURCE_COMMON_SUPPORT_DYN_RESOLUTION_CONTROL; then
    if $TARGET_COMMON_SUPPORT_DYN_RESOLUTION_CONTROL; then
        if [[ "$(GET_FINGERPRINT_SENSOR_TYPE "$TARGET_FINGERPRINT_CONFIG_SENSOR")" == "optical" ]]; then
            ABORT "TARGET_COMMON_SUPPORT_DYN_RESOLUTION_CONTROL is not supported on targets with an optical fingerprint sensor"
        fi

        SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_COMMON_CONFIG_DYN_RESOLUTION_CONTROL" "WQHD,FHD,HD"

        ADD_TO_WORK_DIR "$([[ "$TARGET_OS_SINGLE_SYSTEM_IMAGE" == "qssi" ]] && echo "b0qxxx" || echo "b0sxxx")" \
            "system" "system/bin/bootanimation" 0 2000 755 "u:object_r:bootanim_exec:s0"
        ADD_TO_WORK_DIR "$([[ "$TARGET_OS_SINGLE_SYSTEM_IMAGE" == "qssi" ]] && echo "b0qxxx" || echo "b0sxxx")" \
            "system" "system/bin/surfaceflinger" 0 2000 755 "u:object_r:surfaceflinger_exec:s0"
        # Ensure IQtiComposer support (pre-API 36)
        # Check unica/patches/legacy/customize.sh for more info.
        if [ "$TARGET_PLATFORM_SDK_VERSION" -lt "36" ]; then
            if [[ "$TARGET_OS_SINGLE_SYSTEM_IMAGE" == "qssi" ]] && \
                    ! grep -q -r "IQtiComposer" "$WORK_DIR/vendor/etc/vintf"; then
                # [b.lt #0x72b2b0] -> [nop]
                HEX_PATCH "$WORK_DIR/system/system/bin/surfaceflinger" "9f8a00712b03005400068052" "9f8a00711f2003d500068052"
            fi
        fi
        ADD_TO_WORK_DIR "b0qxxx" "system" "system/media/battery_error.spi" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system" "system/media/battery_low.spi" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system" "system/media/battery_protection.spi" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system" "system/media/battery_temperature_error.spi" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system" "system/media/battery_temperature_limit.spi" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system" "system/media/battery_water_usb.spi" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system" "system/media/incomplete_connect.spi" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system" "system/media/lcd_density.txt" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system" "system/media/new_vi_0_100.spi" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system" "system/media/new_vi_1_100.spi" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system" "system/media/new_vi_2_100.spi" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system" "system/media/new_vi_level_0_1.spi" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system" "system/media/new_vi_level_0_2.spi" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system" "system/media/new_vi_level_0_3.spi" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system" "system/media/new_vi_level_0_4.spi" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system" "system/media/new_vi_level_1_1.spi" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system" "system/media/new_vi_level_1_2.spi" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system" "system/media/new_vi_level_1_3.spi" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system" "system/media/new_vi_level_1_4.spi" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system" "system/media/new_vi_level_2_1.spi" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system" "system/media/new_vi_level_2_2.spi" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system" "system/media/new_vi_level_2_3.spi" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system" "system/media/new_vi_level_2_4.spi" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system" "system/media/slow_charging_usb.spi" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system" "system/media/temperature_limit_usb.spi" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "b0qxxx" "system" "system/media/water_protection_usb.spi" 0 0 644 "u:object_r:system_file:s0"

        if [ "$TARGET_PLATFORM_SDK_VERSION" -ge "36" ]; then
            APPLY_PATCH "system" "system/framework/framework.jar" \
                "$MODPATH/resolution/framework.jar/0001-Enable-FW_SUPPORT_MULTI_RESOLUTION.patch"
        else
            APPLY_PATCH "system" "system/framework/framework.jar" \
                "$MODPATH/resolution/framework.jar/0001-Enable-FW_DYNAMIC_RESOLUTION_CONTROL.patch"
        fi
        APPLY_PATCH "system" "system/framework/gamemanager.jar" \
            "$MODPATH/resolution/gamemanager.jar/0001-Enable-dynamic-resolution-control.patch"
        APPLY_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
            "$MODPATH/resolution/SecSettings.apk/0001-Enable-dynamic-resolution-control.patch"
        SMALI_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
            "smali_classes2/com/android/settings/Utils\$\$ExternalSyntheticLambda2.smali" "remove"
        EVAL "sed -i \"s/^\.implements.*/.implements Landroidx\/core\/view\/OnApplyWindowInsetsListener;/g\" \"$APKTOOL_DIR/system/priv-app/SecSettings/SecSettings.apk/smali_classes2/com/android/settings/Utils\\\$\\\$ExternalSyntheticLambda3.smali\""
        SMALI_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
            "smali_classes2/com/android/settings/applications/manageapplications/ManageApplications\$ApplicationsAdapter\$\$ExternalSyntheticLambda3.smali" "remove"
        SMALI_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
            "smali_classes2/com/android/settings/applications/manageapplications/ManageApplications\$ApplicationsAdapter\$\$ExternalSyntheticLambda7.smali" "remove"
        SMALI_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
            "smali_classes2/com/android/settings/applications/manageapplications/ManageApplications\$ApplicationsAdapter\$\$ExternalSyntheticLambda9.smali" "remove"
        SMALI_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
            "smali_classes2/com/android/settings/applications/manageapplications/ManageApplications\$ApplicationsAdapter\$\$ExternalSyntheticOutline0.smali" "remove"
        if [ "$TARGET_PLATFORM_SDK_VERSION" -lt "36" ]; then
            APPLY_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
                "$MODPATH/resolution/SecSettings.apk/0002-Backport-legacy-DYN_RESOLUTION_CONTROL-code.patch"
            EVAL "sed -i \"/static fields/,+3d\" \"$APKTOOL_DIR/system/priv-app/SecSettings/SecSettings.apk/smali_classes4/com/samsung/android/settings/display/ScreenResolutionFragment.smali\""
            SMALI_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
                "smali_classes4/com/samsung/android/settings/display/controller/ScreenResolutionPreferenceController\$2.smali" "remove"
        fi
        APPLY_PATCH "system_ext" "priv-app/SystemUI/SystemUI.apk" \
            "$MODPATH/resolution/SystemUI.apk/0001-Enable-dynamic-resolution-control.patch"
    fi
else
    if ! $TARGET_COMMON_SUPPORT_DYN_RESOLUTION_CONTROL; then
        # TODO handle this condition
        LOG_MISSING_PATCHES "SOURCE_COMMON_SUPPORT_DYN_RESOLUTION_CONTROL" "TARGET_COMMON_SUPPORT_DYN_RESOLUTION_CONTROL"
    fi
fi

# SEC_PRODUCT_FEATURE_COMMON_SUPPORT_EMBEDDED_SIM
if $SOURCE_COMMON_SUPPORT_EMBEDDED_SIM; then
    if ! $TARGET_COMMON_SUPPORT_EMBEDDED_SIM; then
        SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_COMMON_CONFIG_EMBEDDED_SIM_SLOTSWITCH" --delete
    fi
else
    if $TARGET_COMMON_SUPPORT_EMBEDDED_SIM; then
        # TODO handle this condition
        LOG_MISSING_PATCHES "SOURCE_COMMON_SUPPORT_EMBEDDED_SIM" "TARGET_COMMON_SUPPORT_EMBEDDED_SIM"
    fi
fi

# SEC_PRODUCT_FEATURE_COMMON_SUPPORT_HDR_EFFECT
if $SOURCE_COMMON_SUPPORT_HDR_EFFECT; then
    if ! $TARGET_COMMON_SUPPORT_HDR_EFFECT; then
        SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_COMMON_SUPPORT_HDR_EFFECT" --delete || return 1

        APPLY_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
            "$MODPATH/mdnie/hdr/SecSettings.apk/0001-Disable-HDR-Settings.patch" || return 1
        APPLY_PATCH "system" "system/priv-app/SettingsProvider/SettingsProvider.apk" \
            "$MODPATH/mdnie/hdr/SettingsProvider.apk/0001-Disable-HDR-Settings.patch" || return 1
    else
        if [ ! "$(GET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_COMMON_SUPPORT_HDR_EFFECT")" ]; then
            SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_COMMON_SUPPORT_HDR_EFFECT" "TRUE"
        fi
    fi
else
    if $TARGET_COMMON_SUPPORT_HDR_EFFECT; then
        # TODO handle this condition
        LOG_MISSING_PATCHES "SOURCE_COMMON_SUPPORT_HDR_EFFECT" "TARGET_COMMON_SUPPORT_HDR_EFFECT"
    fi
fi

# SEC_PRODUCT_FEATURE_FINGERPRINT_CONFIG_SENSOR
if $PRODUCT_OPTICAL_PROFILE; then
    # The renderer must see the source strings/owners, not pre-edited legacy
    # replacements. It patches all five One UI 9 artifacts as one validated plan.
    # shellcheck source=/dev/null
    PRODUCT_ENABLE_OPTICAL || return 1
elif [[ "$SOURCE_FINGERPRINT_CONFIG_SENSOR" != "$TARGET_FINGERPRINT_CONFIG_SENSOR" ]]; then
    SMALI_PATCH "system" "system/framework/framework.jar" \
        "smali_classes6/com/samsung/android/bio/fingerprint/SemFingerprintManager.smali" "replace" \
        "getMaxTemplateNumberFromSPF()I" \
        "$SOURCE_FINGERPRINT_CONFIG_SENSOR" \
        "$TARGET_FINGERPRINT_CONFIG_SENSOR"
    SMALI_PATCH "system" "system/framework/framework.jar" \
        "smali_classes6/com/samsung/android/bio/fingerprint/SemFingerprintManager.smali" "replace" \
        "getProductFeatureValue(Landroid/content/Context;)Ljava/lang/String;" \
        "$SOURCE_FINGERPRINT_CONFIG_SENSOR" \
        "$TARGET_FINGERPRINT_CONFIG_SENSOR"
    SMALI_PATCH "system" "system/framework/framework.jar" \
        "smali_classes6/com/samsung/android/bio/fingerprint/SemFingerprintManager\$Characteristics.smali" "replaceall" \
        "$SOURCE_FINGERPRINT_CONFIG_SENSOR" \
        "$TARGET_FINGERPRINT_CONFIG_SENSOR"
    SMALI_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
        "$PRODUCT_DISPLAY_SMALI_DIR/com/samsung/android/settings/biometrics/fingerprint/FingerprintSettingsUtils.smali" "replaceall" \
        "$SOURCE_FINGERPRINT_CONFIG_SENSOR" \
        "$TARGET_FINGERPRINT_CONFIG_SENSOR"

    if [[ "$(GET_FINGERPRINT_SENSOR_TYPE "$SOURCE_FINGERPRINT_CONFIG_SENSOR")" != "$(GET_FINGERPRINT_SENSOR_TYPE "$TARGET_FINGERPRINT_CONFIG_SENSOR")" ]]; then
        if [[ "$(GET_FINGERPRINT_SENSOR_TYPE "$SOURCE_FINGERPRINT_CONFIG_SENSOR")" == "ultrasonic" ]]; then
            if [[ "$(GET_FINGERPRINT_SENSOR_TYPE "$TARGET_FINGERPRINT_CONFIG_SENSOR")" == "optical" ]]; then
                SOURCE_FINGERPRINT_CONFIG_SENSOR="google_touch_display_optical,settings=3"

                if [[ "$TARGET_OS_SINGLE_SYSTEM_IMAGE" == "qssi" ]]; then
                    ADD_TO_WORK_DIR "r9qxxx" "system" "system/bin/surfaceflinger" 0 2000 755 "u:object_r:surfaceflinger_exec:s0"
                    # Ensure IQtiComposer support (pre-API 36)
                    # Check unica/patches/legacy/customize.sh for more info.
                    if [ "$TARGET_PLATFORM_SDK_VERSION" -lt "36" ]; then
                        if ! grep -q -r "IQtiComposer" "$WORK_DIR/vendor/etc/vintf"; then
                            # [b.lt #0x72914c] -> [nop]
                            HEX_PATCH "$WORK_DIR/system/system/bin/surfaceflinger" "9f8a00712b03005400068052" "9f8a00711f2003d500068052"
                        fi
                    fi
                    ADD_TO_WORK_DIR "r9qxxx" "system" "system/lib/libgui.so" 0 0 644 "u:object_r:system_lib_file:s0"
                    ADD_TO_WORK_DIR "r9qxxx" "system" "system/lib/libui.so" 0 0 644 "u:object_r:system_lib_file:s0"
                    ADD_TO_WORK_DIR "r9qxxx" "system" "system/lib64/libgui.so" 0 0 644 "u:object_r:system_lib_file:s0"
                    ADD_TO_WORK_DIR "r9qxxx" "system" "system/lib64/libui.so" 0 0 644 "u:object_r:system_lib_file:s0"
                elif [[ "$TARGET_OS_SINGLE_SYSTEM_IMAGE" == "essi" ]]; then
                    ADD_TO_WORK_DIR "r9sxxx" "system" "system/bin/surfaceflinger" 0 2000 755 "u:object_r:surfaceflinger_exec:s0"
                    ADD_TO_WORK_DIR "r9sxxx" "system" "system/lib/libgui.so" 0 0 644 "u:object_r:system_lib_file:s0"
                    ADD_TO_WORK_DIR "r9sxxx" "system" "system/lib/libui.so" 0 0 644 "u:object_r:system_lib_file:s0"
                    ADD_TO_WORK_DIR "r9sxxx" "system" "system/lib64/libgui.so" 0 0 644 "u:object_r:system_lib_file:s0"
                    ADD_TO_WORK_DIR "r9sxxx" "system" "system/lib64/libui.so" 0 0 644 "u:object_r:system_lib_file:s0"
                else
                    ABORT "Unknown SSI: $TARGET_OS_SINGLE_SYSTEM_IMAGE"
                fi

                ADD_TO_WORK_DIR "r9qxxx" "system" "system/priv-app/BiometricSetting/BiometricSetting.apk" 0 0 644 "u:object_r:system_file:s0"

                APPLY_PATCH "system" "system/framework/framework.jar" \
                    "$MODPATH/fingerprint/optical_fod/framework.jar/0001-Add-optical-FOD-support.patch"
                APPLY_PATCH "system" "system/framework/services.jar" \
                    "$MODPATH/fingerprint/optical_fod/services.jar/0001-Add-optical-FOD-support.patch"
                APPLY_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
                    "$MODPATH/fingerprint/optical_fod/SecSettings.apk/0001-Add-optical-FOD-support.patch"
                APPLY_PATCH "system_ext" "priv-app/SystemUI/SystemUI.apk" \
                    "$MODPATH/fingerprint/optical_fod/SystemUI.apk/0001-Add-optical-FOD-support.patch"

                if [[ "$TARGET_FINGERPRINT_CONFIG_SENSOR" == *"no_delay_in_screen_off"* ]]; then
                    APPLY_PATCH "system" "system/priv-app/BiometricSetting/BiometricSetting.apk" \
                        "$MODPATH/fingerprint/optical_fod/BiometricSetting.apk/0001-Enable-FP_FEATURE_NO_DELAY_IN_SCREEN_OFF.patch"
                fi

                if [[ "$TARGET_FINGERPRINT_CONFIG_SENSOR" == *"transition_effect_on"* ]]; then
                    SMALI_PATCH "system" "system/framework/framework.jar" \
                        "smali_classes2/android/hardware/fingerprint/FingerprintManager.smali" "return" \
                        "semGetTransitionEffectValue()I" \
                        "1"
                elif [[ "$TARGET_FINGERPRINT_CONFIG_SENSOR" == *"transition_effect_off"* ]]; then
                    SMALI_PATCH "system" "system/framework/framework.jar" \
                        "smali_classes2/android/hardware/fingerprint/FingerprintManager.smali" "return" \
                        "semGetTransitionEffectValue()I" \
                        "0"
                fi
            elif [[ "$(GET_FINGERPRINT_SENSOR_TYPE "$TARGET_FINGERPRINT_CONFIG_SENSOR")" == "side" ]]; then
                SOURCE_FINGERPRINT_CONFIG_SENSOR="google_touch_side,navi=1"

                ADD_TO_WORK_DIR "b4qxxx" "system" "system/priv-app/BiometricSetting/BiometricSetting.apk" 0 0 644 "u:object_r:system_file:s0"
                APPLY_PATCH "system" "system/priv-app/BiometricSetting/BiometricSetting.apk" \
                    "$MODPATH/fingerprint/side_fp/BiometricSetting.apk/0001-Add-FEATURE_FINGERPRINT_JDM_HAL-support.patch"

                APPLY_PATCH "system" "system/framework/framework.jar" \
                    "$MODPATH/fingerprint/side_fp/framework.jar/0001-Add-side-fingerprint-sensor-support.patch"
                APPLY_PATCH "system" "system/framework/services.jar" \
                    "$MODPATH/fingerprint/side_fp/services.jar/0001-Add-side-fingerprint-sensor-support.patch"
                EVAL "sed -i \"/implements/i .implements Lcom\/android\/server\/biometrics\/sensors\/fingerprint\/SemFpHalLifecycleListener;\" \"$APKTOOL_DIR/system/framework/services.jar/smali/com/android/server/biometrics/sensors/fingerprint/SemFingerprintServiceExtImpl.smali\""
                APPLY_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
                    "$MODPATH/fingerprint/side_fp/SecSettings.apk/0001-Add-side-fingerprint-sensor-support.patch"
                EVAL "sed -i \"s/^\.implements.*/.implements Landroid\/widget\/CompoundButton\$OnCheckedChangeListener;/g\" \"$APKTOOL_DIR/system/priv-app/SecSettings/SecSettings.apk/smali_classes4/com/samsung/android/settings/biometrics/fingerprint/SuwFingerprintUsefulFeature\\\$\\\$ExternalSyntheticLambda1.smali\""
                SMALI_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
                    "smali_classes4/com/samsung/android/settings/biometrics/fingerprint/SuwFingerprintUsefulFeature\$\$ExternalSyntheticLambda4.smali" "remove"
                SMALI_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
                    "smali_classes4/com/samsung/android/settings/biometrics/fingerprint/SuwFingerprintUsefulFeature\$\$ExternalSyntheticLambda9.smali" "remove"
                SMALI_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
                    "smali_classes4/com/samsung/android/settings/biometrics/fingerprint/SuwFingerprintUsefulFeature\$1.smali" "remove"
                APPLY_PATCH "system_ext" "priv-app/SystemUI/SystemUI.apk" \
                    "$MODPATH/fingerprint/side_fp/SystemUI.apk/0001-Add-side-fingerprint-sensor-support.patch"
                EVAL "sed -i \"s/^\.implements.*/.implements Ljava\/util\/function\/Consumer;/g\" \"$APKTOOL_DIR/system_ext/priv-app/SystemUI/SystemUI.apk/smali/com/android/keyguard/KeyguardSecUpdateMonitorImpl\\\$\\\$ExternalSyntheticLambda28.smali\""
                SMALI_PATCH "system_ext" "priv-app/SystemUI/SystemUI.apk" \
                    "smali/com/android/keyguard/KeyguardSecUpdateMonitorImpl\$\$ExternalSyntheticLambda24.smali" "remove"
                SMALI_PATCH "system_ext" "priv-app/SystemUI/SystemUI.apk" \
                    "smali/com/android/keyguard/KeyguardSecUpdateMonitorImpl\$\$ExternalSyntheticLambda29.smali" "remove"
                SMALI_PATCH "system_ext" "priv-app/SystemUI/SystemUI.apk" \
                    "smali/com/android/keyguard/KeyguardSecUpdateMonitorImpl\$\$ExternalSyntheticLambda33.smali" "remove"
                SMALI_PATCH "system_ext" "priv-app/SystemUI/SystemUI.apk" \
                    "smali/com/android/keyguard/KeyguardSecUpdateMonitorImpl\$\$ExternalSyntheticLambda40.smali" "remove"
                SMALI_PATCH "system_ext" "priv-app/SystemUI/SystemUI.apk" \
                    "smali/com/android/keyguard/KeyguardSecUpdateMonitorImpl\$\$ExternalSyntheticLambda42.smali" "remove"

                if [[ "$TARGET_FINGERPRINT_CONFIG_SENSOR" == *"navi=1"* ]]; then
                    LOG "- Enabling FP_FEATURE_GESTURE_MODE:Z in /system/system/framework/services.jar/smali/com/android/server/biometrics/SemBiometricFeature.smali"
                    SMALI_PATCH "system" "system/framework/services.jar" \
                        "smali/com/android/server/biometrics/SemBiometricFeature.smali" "replace" \
                        "<clinit>()V" \
                        "sput-boolean v3, Lcom/android/server/biometrics/SemBiometricFeature;->FP_FEATURE_GESTURE_MODE:Z" \
                        "sput-boolean v2, Lcom/android/server/biometrics/SemBiometricFeature;->FP_FEATURE_GESTURE_MODE:Z" \
                        > /dev/null
                fi
                if [[ "$TARGET_FINGERPRINT_CONFIG_SENSOR" == *"swipe_enroll"* ]]; then
                    LOG "- Enabling FP_FEATURE_SWIPE_ENROLL:Z in /system/system/framework/services.jar/smali/com/android/server/biometrics/SemBiometricFeature.smali"
                    SMALI_PATCH "system" "system/framework/services.jar" \
                        "smali/com/android/server/biometrics/SemBiometricFeature.smali" "replace" \
                        "<clinit>()V" \
                        "sput-boolean v3, Lcom/android/server/biometrics/SemBiometricFeature;->FP_FEATURE_SWIPE_ENROLL:Z" \
                        "sput-boolean v2, Lcom/android/server/biometrics/SemBiometricFeature;->FP_FEATURE_SWIPE_ENROLL:Z" \
                        > /dev/null
                fi
                if [[ "$TARGET_FINGERPRINT_CONFIG_SENSOR" == *"wof_off"* ]]; then
                    LOG "- Enabling FP_FEATURE_WOF_OPTION_DEFAULT_OFF:Z in /system/system/framework/services.jar/smali/com/android/server/biometrics/SemBiometricFeature.smali"
                    SMALI_PATCH "system" "system/framework/services.jar" \
                        "smali/com/android/server/biometrics/SemBiometricFeature.smali" "replace" \
                        "<clinit>()V" \
                        "sput-boolean v3, Lcom/android/server/biometrics/SemBiometricFeature;->FP_FEATURE_WOF_OPTION_DEFAULT_OFF:Z" \
                        "sput-boolean v2, Lcom/android/server/biometrics/SemBiometricFeature;->FP_FEATURE_WOF_OPTION_DEFAULT_OFF:Z" \
                        > /dev/null
                fi
            elif [[ "$(GET_FINGERPRINT_SENSOR_TYPE "$TARGET_FINGERPRINT_CONFIG_SENSOR")" != "ultrasonic" ]]; then
                # TODO handle this condition
                LOG_MISSING_PATCHES "SOURCE_FINGERPRINT_CONFIG_SENSOR" "TARGET_FINGERPRINT_CONFIG_SENSOR"
            fi
        else
            # TODO handle this condition
            LOG_MISSING_PATCHES "SOURCE_FINGERPRINT_CONFIG_SENSOR" "TARGET_FINGERPRINT_CONFIG_SENSOR"
        fi
    fi

    if [[ "$SOURCE_FINGERPRINT_CONFIG_SENSOR" != "$TARGET_FINGERPRINT_CONFIG_SENSOR" ]]; then
        SMALI_PATCH "system" "system/priv-app/BiometricSetting/BiometricSetting.apk" \
            "smali/com/samsung/android/biometrics/app/setting/DisplayStateManager.smali" "replace" \
            "<init>(Lcom/samsung/android/biometrics/app/setting/BiometricsUIService;)V" \
            "$SOURCE_FINGERPRINT_CONFIG_SENSOR" \
            "$TARGET_FINGERPRINT_CONFIG_SENSOR"
    fi
fi

# SEC_PRODUCT_FEATURE_LCD_CONFIG_CONTROL_AUTO_BRIGHTNESS
if [[ "$SOURCE_LCD_CONFIG_CONTROL_AUTO_BRIGHTNESS" != "$TARGET_LCD_CONFIG_CONTROL_AUTO_BRIGHTNESS" ]]; then
    SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_LCD_CONFIG_CONTROL_AUTO_BRIGHTNESS" "$TARGET_LCD_CONFIG_CONTROL_AUTO_BRIGHTNESS"

    SMALI_PATCH "system" "system/framework/services.jar" \
        "smali_classes2/com/android/server/power/PowerManagerUtil.smali" "replace" \
        "<clinit>()V" \
        "$SOURCE_LCD_CONFIG_CONTROL_AUTO_BRIGHTNESS" \
        "$TARGET_LCD_CONFIG_CONTROL_AUTO_BRIGHTNESS"
    SMALI_PATCH "system" "system/framework/ssrm.jar" \
        "smali/com/android/server/ssrm/PreMonitor.smali" "replace" \
        "getBrightness()Ljava/lang/String;" \
        "$SOURCE_LCD_CONFIG_CONTROL_AUTO_BRIGHTNESS" \
        "$TARGET_LCD_CONFIG_CONTROL_AUTO_BRIGHTNESS"
    SMALI_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
        "$PRODUCT_DISPLAY_SMALI_DIR/com/samsung/android/settings/Rune.smali" "replace" \
        "<clinit>()V" \
        "$SOURCE_LCD_CONFIG_CONTROL_AUTO_BRIGHTNESS" \
        "$TARGET_LCD_CONFIG_CONTROL_AUTO_BRIGHTNESS"
fi

# SEC_PRODUCT_FEATURE_LCD_CONFIG_SEAMLESS_BRT
# SEC_PRODUCT_FEATURE_LCD_CONFIG_SEAMLESS_LUX
#
# Apply before SEC_PRODUCT_FEATURE_LCD_CONFIG_HFR_* to avoid conflicts
if [ "$SOURCE_PLATFORM_SDK_VERSION" = "37" ]; then
    APPLY_PATCH "system" "system/framework/framework.jar" \
        "$MODPATH/hfr/framework.jar/0001-Allow-custom-refresh-rate-thresholds.patch"
    SMALI_PATCH "system" "system/framework/framework.jar" \
        "smali_classes6/com/samsung/android/hardware/display/RefreshRateConfig.smali" "replaceall" \
        "CONFIG_SEAMLESS_BRT" "${TARGET_LCD_CONFIG_SEAMLESS_BRT//none/}"
    SMALI_PATCH "system" "system/framework/framework.jar" \
        "smali_classes6/com/samsung/android/hardware/display/RefreshRateConfig.smali" "replaceall" \
        "CONFIG_SEAMLESS_LUX" "${TARGET_LCD_CONFIG_SEAMLESS_LUX//none/}"
    SMALI_PATCH "system" "system/framework/framework.jar" \
        "smali_classes6/com/samsung/android/hardware/display/RefreshRateConfig.smali" "replaceall" \
        "CONFIG_HFR_NS" "${TARGET_LCD_CONFIG_HFR_SUPPORTED_REFRESH_RATE_NS//none/}"
else
    if [[ "$SOURCE_LCD_CONFIG_SEAMLESS_BRT" != "$TARGET_LCD_CONFIG_SEAMLESS_BRT" ]] || \
            [[ "$SOURCE_LCD_CONFIG_SEAMLESS_LUX" != "$TARGET_LCD_CONFIG_SEAMLESS_LUX" ]]; then
        if [[ "$SOURCE_LCD_CONFIG_SEAMLESS_BRT" != "none" ]] && [[ "$SOURCE_LCD_CONFIG_SEAMLESS_LUX" != "none" ]] && \
                [[ "$TARGET_LCD_CONFIG_SEAMLESS_BRT" == "none" ]] && [[ "$TARGET_LCD_CONFIG_SEAMLESS_LUX" == "none" ]]; then
            APPLY_PATCH "system" "system/framework/framework.jar" \
                "$MODPATH/hfr/framework.jar/0001-Remove-brightness-threshold-values.patch"
        elif [[ "$SOURCE_LCD_CONFIG_SEAMLESS_BRT" != "none" ]] && [[ "$SOURCE_LCD_CONFIG_SEAMLESS_LUX" != "none" ]] && \
                [[ "$TARGET_LCD_CONFIG_SEAMLESS_BRT" != "none" ]] && [[ "$TARGET_LCD_CONFIG_SEAMLESS_LUX" != "none" ]]; then
            SMALI_PATCH "system" "system/framework/framework.jar" \
                "smali_classes6/com/samsung/android/hardware/display/RefreshRateConfig.smali" "replace" \
                "dump(Ljava/io/PrintWriter;Ljava/lang/String;Z)V" \
                "SEAMLESS_BRT: $SOURCE_LCD_CONFIG_SEAMLESS_BRT" \
                "SEAMLESS_BRT: $TARGET_LCD_CONFIG_SEAMLESS_BRT"
            SMALI_PATCH "system" "system/framework/framework.jar" \
                "smali_classes6/com/samsung/android/hardware/display/RefreshRateConfig.smali" "replace" \
                "dump(Ljava/io/PrintWriter;Ljava/lang/String;Z)V" \
                "SEAMLESS_LUX: $SOURCE_LCD_CONFIG_SEAMLESS_LUX" \
                "SEAMLESS_LUX: $TARGET_LCD_CONFIG_SEAMLESS_LUX"
            SMALI_PATCH "system" "system/framework/framework.jar" \
                "smali_classes6/com/samsung/android/hardware/display/RefreshRateConfig.smali" "replace" \
                "getMainInstance()Lcom/samsung/android/hardware/display/RefreshRateConfig;" \
                "$SOURCE_LCD_CONFIG_SEAMLESS_BRT" \
                "$TARGET_LCD_CONFIG_SEAMLESS_BRT"
            SMALI_PATCH "system" "system/framework/framework.jar" \
                "smali_classes6/com/samsung/android/hardware/display/RefreshRateConfig.smali" "replace" \
                "getMainInstance()Lcom/samsung/android/hardware/display/RefreshRateConfig;" \
                "$SOURCE_LCD_CONFIG_SEAMLESS_LUX" \
                "$TARGET_LCD_CONFIG_SEAMLESS_LUX"
        else
            # TODO handle these conditions
            LOG_MISSING_PATCHES "SOURCE_LCD_CONFIG_SEAMLESS_BRT" "TARGET_LCD_CONFIG_SEAMLESS_BRT" || true
            LOG_MISSING_PATCHES "SOURCE_LCD_CONFIG_SEAMLESS_LUX" "TARGET_LCD_CONFIG_SEAMLESS_LUX"
        fi
    fi

fi

# SEC_PRODUCT_FEATURE_LCD_CONFIG_HFR_DEFAULT_REFRESH_RATE
if [[ "$SOURCE_LCD_CONFIG_HFR_DEFAULT_REFRESH_RATE" != "$TARGET_LCD_CONFIG_HFR_DEFAULT_REFRESH_RATE" ]]; then
    SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_LCD_CONFIG_HFR_DEFAULT_REFRESH_RATE" "$TARGET_LCD_CONFIG_HFR_DEFAULT_REFRESH_RATE"

    SMALI_PATCH "system" "system/framework/framework.jar" \
        "smali_classes6/com/samsung/android/hardware/display/RefreshRateConfig.smali" "replace" \
        "$PRODUCT_REFRESH_DUMP_METHOD" \
        "HFR_DEFAULT_REFRESH_RATE: $SOURCE_LCD_CONFIG_HFR_DEFAULT_REFRESH_RATE" \
        "HFR_DEFAULT_REFRESH_RATE: $TARGET_LCD_CONFIG_HFR_DEFAULT_REFRESH_RATE"
    SMALI_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
        "$PRODUCT_DISPLAY_SMALI_DIR/com/samsung/android/settings/display/SecDisplayUtils.smali" "replace" \
        "getHighRefreshRateDefaultValue(Landroid/content/Context;I)I" \
        "$SOURCE_LCD_CONFIG_HFR_DEFAULT_REFRESH_RATE" \
        "$TARGET_LCD_CONFIG_HFR_DEFAULT_REFRESH_RATE"
    SMALI_PATCH "system" "system/priv-app/SettingsProvider/SettingsProvider.apk" \
        "smali/com/android/providers/settings/DatabaseHelper.smali" "replace" \
        "loadRefreshRateMode(Landroid/database/sqlite/SQLiteStatement;Ljava/lang/String;)V" \
        "$SOURCE_LCD_CONFIG_HFR_DEFAULT_REFRESH_RATE" \
        "$TARGET_LCD_CONFIG_HFR_DEFAULT_REFRESH_RATE"
fi

# SEC_PRODUCT_FEATURE_LCD_CONFIG_HFR_MODE
if [[ "$SOURCE_LCD_CONFIG_HFR_MODE" != "$TARGET_LCD_CONFIG_HFR_MODE" ]]; then
    SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_LCD_CONFIG_HFR_MODE" "$TARGET_LCD_CONFIG_HFR_MODE"

    SMALI_PATCH "system" "system/framework/framework.jar" \
        "smali_classes2/android/inputmethodservice/SemImsRune.smali" "replace" \
        "<clinit>()V" \
        "$SOURCE_LCD_CONFIG_HFR_MODE" \
        "$TARGET_LCD_CONFIG_HFR_MODE"
    if [ "$SOURCE_PLATFORM_SDK_VERSION" = "37" ]; then
        SMALI_PATCH "system" "system/framework/framework.jar" \
            "smali_classes6/com/samsung/android/hardware/display/RefreshRateConfig.smali" "replace" \
            "$PRODUCT_REFRESH_DUMP_METHOD" \
            "$SOURCE_LCD_CONFIG_HFR_MODE" "${TARGET_LCD_CONFIG_HFR_MODE//none/}"
    else
        SMALI_PATCH "system" "system/framework/framework.jar" \
            "smali_classes6/com/samsung/android/hardware/display/RefreshRateConfig.smali" "replace" \
            "$PRODUCT_REFRESH_DUMP_METHOD" \
            "HFR_MODE: $SOURCE_LCD_CONFIG_HFR_MODE" \
            "HFR_MODE: $TARGET_LCD_CONFIG_HFR_MODE"
    fi
    SMALI_PATCH "system" "system/framework/framework.jar" \
        "smali_classes6/com/samsung/android/hardware/display/RefreshRateConfig.smali" "replace" \
        "getMainInstance()Lcom/samsung/android/hardware/display/RefreshRateConfig;" \
        "$SOURCE_LCD_CONFIG_HFR_MODE" \
        "$TARGET_LCD_CONFIG_HFR_MODE"
    SMALI_PATCH "system" "system/framework/framework.jar" \
        "smali_classes6/com/samsung/android/rune/CoreRune.smali" "replace" \
        "<clinit>()V" \
        "$SOURCE_LCD_CONFIG_HFR_MODE" \
        "$TARGET_LCD_CONFIG_HFR_MODE"
    if [ "$SOURCE_PLATFORM_SDK_VERSION" = "37" ]; then
        SMALI_PATCH "system" "system/framework/gamemanager.jar" \
            "smali/com/samsung/android/game/VrrManager.smali" "replace" \
            "<init>(Landroid/hardware/display/DisplayManager;Lcom/samsung/android/game/ActionLogger;Ljava/util/Map;Ljava/util/List;)V" \
            "$SOURCE_LCD_CONFIG_HFR_MODE" \
            "$TARGET_LCD_CONFIG_HFR_MODE"
    else
        SMALI_PATCH "system" "system/framework/gamemanager.jar" \
            "smali/com/samsung/android/game/GameManagerService.smali" "replace" \
            "isVariableRefreshRateSupported()Ljava/lang/String;" \
            "$SOURCE_LCD_CONFIG_HFR_MODE" \
            "$TARGET_LCD_CONFIG_HFR_MODE"
    fi
    SMALI_PATCH "system" "system/framework/secinputdev-service.jar" \
        "smali/com/samsung/android/hardware/secinputdev/utils/SemInputFeatures.smali" "replaceall" \
        "\\\"$SOURCE_LCD_CONFIG_HFR_MODE\\\"" \
        "\\\"$TARGET_LCD_CONFIG_HFR_MODE\\\""
    SMALI_PATCH "system" "system/framework/secinputdev-service.jar" \
        "smali/com/samsung/android/hardware/secinputdev/utils/SemInputFeaturesExtra.smali" "replaceall" \
        "\\\"$SOURCE_LCD_CONFIG_HFR_MODE\\\"" \
        "\\\"$TARGET_LCD_CONFIG_HFR_MODE\\\""
    SMALI_PATCH "system" "system/framework/services.jar" \
        "smali_classes2/com/android/server/power/PowerManagerUtil.smali" "replace" \
        "<clinit>()V" \
        "$SOURCE_LCD_CONFIG_HFR_MODE" \
        "$TARGET_LCD_CONFIG_HFR_MODE"
    SMALI_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
        "$PRODUCT_DISPLAY_SMALI_DIR/com/samsung/android/settings/display/SecDisplayUtils.smali" "replace" \
        "getHighRefreshRateSeamlessType(I)I" \
        "$SOURCE_LCD_CONFIG_HFR_MODE" \
        "$TARGET_LCD_CONFIG_HFR_MODE"
    SMALI_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
        "$PRODUCT_DISPLAY_SMALI_DIR/com/samsung/android/settings/display/SecDisplayUtils.smali" "replace" \
        "isSupportMaxHS60RefreshRate(I)Z" \
        "$SOURCE_LCD_CONFIG_HFR_MODE" \
        "$TARGET_LCD_CONFIG_HFR_MODE"
    SMALI_PATCH "system" "system/priv-app/SettingsProvider/SettingsProvider.apk" \
        "smali/com/android/providers/settings/DatabaseHelper.smali" "replace" \
        "loadRefreshRateMode(Landroid/database/sqlite/SQLiteStatement;Ljava/lang/String;)V" \
        "$SOURCE_LCD_CONFIG_HFR_MODE" \
        "$TARGET_LCD_CONFIG_HFR_MODE"
    SMALI_PATCH "system_ext" "priv-app/SystemUI/SystemUI.apk" \
        "smali/com/android/systemui/BasicRune.smali" "replace" \
        "<clinit>()V" \
        "$SOURCE_LCD_CONFIG_HFR_MODE" \
        "$TARGET_LCD_CONFIG_HFR_MODE"
    SMALI_PATCH "system_ext" "priv-app/SystemUI/SystemUI.apk" \
        "smali/com/android/systemui/LsRune.smali" "replace" \
        "<clinit>()V" \
        "$SOURCE_LCD_CONFIG_HFR_MODE" \
        "$TARGET_LCD_CONFIG_HFR_MODE"
fi

# SEC_PRODUCT_FEATURE_LCD_CONFIG_HFR_SUPPORTED_REFRESH_RATE
if [[ "$SOURCE_LCD_CONFIG_HFR_SUPPORTED_REFRESH_RATE" != "$TARGET_LCD_CONFIG_HFR_SUPPORTED_REFRESH_RATE" ]]; then
    if [[ "$TARGET_LCD_CONFIG_HFR_SUPPORTED_REFRESH_RATE" != "none" ]]; then
        SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_LCD_CONFIG_HFR_SUPPORTED_REFRESH_RATE" "$TARGET_LCD_CONFIG_HFR_SUPPORTED_REFRESH_RATE"
    else
        SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_LCD_CONFIG_HFR_SUPPORTED_REFRESH_RATE" "0"
    fi

    if [[ "$SOURCE_LCD_CONFIG_HFR_SUPPORTED_REFRESH_RATE" != "none" ]]; then
        if [ "$SOURCE_PLATFORM_SDK_VERSION" = "37" ]; then
            SMALI_PATCH "system" "system/framework/framework.jar" \
                "smali_classes6/com/samsung/android/hardware/display/RefreshRateConfig.smali" "replace" \
                "$PRODUCT_REFRESH_DUMP_METHOD" \
                "$SOURCE_LCD_CONFIG_HFR_SUPPORTED_REFRESH_RATE" "${TARGET_LCD_CONFIG_HFR_SUPPORTED_REFRESH_RATE//none/}"
        else
            SMALI_PATCH "system" "system/framework/framework.jar" \
                "smali_classes6/com/samsung/android/hardware/display/RefreshRateConfig.smali" "replace" \
                "$PRODUCT_REFRESH_DUMP_METHOD" \
                "HFR_SUPPORTED_REFRESH_RATE: $SOURCE_LCD_CONFIG_HFR_SUPPORTED_REFRESH_RATE" \
                "HFR_SUPPORTED_REFRESH_RATE: ${TARGET_LCD_CONFIG_HFR_SUPPORTED_REFRESH_RATE//none/}"
        fi
        SMALI_PATCH "system" "system/framework/framework.jar" \
            "smali_classes6/com/samsung/android/hardware/display/RefreshRateConfig.smali" "replace" \
            "getMainInstance()Lcom/samsung/android/hardware/display/RefreshRateConfig;" \
            "$SOURCE_LCD_CONFIG_HFR_SUPPORTED_REFRESH_RATE" \
            "${TARGET_LCD_CONFIG_HFR_SUPPORTED_REFRESH_RATE//none/}"
        SMALI_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
            "$PRODUCT_DISPLAY_SMALI_DIR/com/samsung/android/settings/display/SecDisplayUtils.smali" "replace" \
            "getHighRefreshRateSupportedValues(I)[Ljava/lang/String;" \
            "$SOURCE_LCD_CONFIG_HFR_SUPPORTED_REFRESH_RATE" \
            "${TARGET_LCD_CONFIG_HFR_SUPPORTED_REFRESH_RATE//none/}"
        SMALI_PATCH "system_ext" "priv-app/SystemUI/SystemUI.apk" \
            "smali_classes2/com/android/systemui/keyguard/KeyguardViewMediatorHelperImpl\$\$ExternalSyntheticLambda0.smali" "replace" \
            "invoke()Ljava/lang/Object;" \
            "$SOURCE_LCD_CONFIG_HFR_SUPPORTED_REFRESH_RATE" \
            "${TARGET_LCD_CONFIG_HFR_SUPPORTED_REFRESH_RATE//none/}"
    else
        # TODO handle this condition
        LOG_MISSING_PATCHES "SOURCE_LCD_CONFIG_HFR_SUPPORTED_REFRESH_RATE" "TARGET_LCD_CONFIG_HFR_SUPPORTED_REFRESH_RATE"
    fi
fi

# SEC_PRODUCT_FEATURE_LCD_CONFIG_HFR_SUPPORTED_REFRESH_RATE_NS
if [ "$SOURCE_PLATFORM_SDK_VERSION" = "37" ]; then
    if [[ "$TARGET_LCD_CONFIG_HFR_SUPPORTED_REFRESH_RATE_NS" != "none" ]]; then
        SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_LCD_CONFIG_HFR_SUPPORTED_REFRESH_RATE_NS" "$TARGET_LCD_CONFIG_HFR_SUPPORTED_REFRESH_RATE_NS"
    else
        SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_LCD_CONFIG_HFR_SUPPORTED_REFRESH_RATE_NS" --delete
    fi
else
    if [[ "$SOURCE_LCD_CONFIG_HFR_SUPPORTED_REFRESH_RATE_NS" != "$TARGET_LCD_CONFIG_HFR_SUPPORTED_REFRESH_RATE_NS" ]]; then
        if [[ "$SOURCE_LCD_CONFIG_HFR_SUPPORTED_REFRESH_RATE_NS" != "none" ]]; then
            if [[ "$TARGET_LCD_CONFIG_HFR_SUPPORTED_REFRESH_RATE_NS" != "none" ]]; then
                SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_LCD_CONFIG_HFR_SUPPORTED_REFRESH_RATE_NS" "$TARGET_LCD_CONFIG_HFR_SUPPORTED_REFRESH_RATE_NS"
            else
                SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_LCD_CONFIG_HFR_SUPPORTED_REFRESH_RATE_NS" --delete
            fi

            SMALI_PATCH "system" "system/framework/framework.jar" \
                "smali_classes6/com/samsung/android/hardware/display/RefreshRateConfig.smali" "replace" \
                "$PRODUCT_REFRESH_DUMP_METHOD" \
                "HFR_SUPPORTED_REFRESH_RATE_NS: $SOURCE_LCD_CONFIG_HFR_SUPPORTED_REFRESH_RATE_NS" \
                "HFR_SUPPORTED_REFRESH_RATE_NS: ${TARGET_LCD_CONFIG_HFR_SUPPORTED_REFRESH_RATE_NS//none/}"
            SMALI_PATCH "system" "system/framework/framework.jar" \
                "smali_classes6/com/samsung/android/hardware/display/RefreshRateConfig.smali" "replace" \
                "getMainInstance()Lcom/samsung/android/hardware/display/RefreshRateConfig;" \
                "$SOURCE_LCD_CONFIG_HFR_SUPPORTED_REFRESH_RATE_NS" \
                "${TARGET_LCD_CONFIG_HFR_SUPPORTED_REFRESH_RATE_NS//none/}"
        else
            # TODO handle this condition
            LOG_MISSING_PATCHES "SOURCE_LCD_CONFIG_HFR_SUPPORTED_REFRESH_RATE_NS" "TARGET_LCD_CONFIG_HFR_SUPPORTED_REFRESH_RATE_NS"
        fi
    fi

fi

# SEC_PRODUCT_FEATURE_LCD_SUPPORT_MDNIE_HW
# SEC_PRODUCT_FEATURE_LCD_CONFIG_COLOR_WEAKNESS_SOLUTION
if $SOURCE_LCD_SUPPORT_MDNIE_HW && [[ "$SOURCE_LCD_CONFIG_COLOR_WEAKNESS_SOLUTION" != "0" ]]; then
    if ! $TARGET_LCD_SUPPORT_MDNIE_HW; then
        SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_LCD_SUPPORT_MDNIE_HW" --delete || return 1

        APPLY_PATCH "system" "system/framework/framework.jar" \
            "$MODPATH/mdnie/hw/framework.jar/0001-Disable-HW-mDNIe.patch" || return 1
        if [[ "$TARGET_LCD_CONFIG_COLOR_WEAKNESS_SOLUTION" == "0" ]]; then
            APPLY_PATCH "system" "system/framework/framework.jar" \
                "$MODPATH/mdnie/hw/framework.jar/0002-Disable-A11Y_COLOR_BOOL_SUPPORT_DMC_COLORWEAKNESS.patch" || return 1
        fi
        APPLY_PATCH "system" "system/framework/services.jar" \
            "$MODPATH/mdnie/hw/services.jar/0001-Disable-HW-mDNIe.patch" || return 1
    fi
elif $SOURCE_LCD_SUPPORT_MDNIE_HW && [[ "$SOURCE_LCD_CONFIG_COLOR_WEAKNESS_SOLUTION" == "0" ]]; then
    # TODO handle these conditions
    LOG_MISSING_PATCHES "SOURCE_LCD_SUPPORT_MDNIE_HW" "TARGET_LCD_SUPPORT_MDNIE_HW" || true
    LOG_MISSING_PATCHES "SOURCE_LCD_CONFIG_COLOR_WEAKNESS_SOLUTION" "TARGET_LCD_CONFIG_COLOR_WEAKNESS_SOLUTION"
else
    if $TARGET_LCD_SUPPORT_MDNIE_HW || \
            [[ "$SOURCE_LCD_CONFIG_COLOR_WEAKNESS_SOLUTION" != "$TARGET_LCD_CONFIG_COLOR_WEAKNESS_SOLUTION" ]]; then
        # TODO handle these conditions
        LOG_MISSING_PATCHES "SOURCE_LCD_SUPPORT_MDNIE_HW" "TARGET_LCD_SUPPORT_MDNIE_HW" || true
        LOG_MISSING_PATCHES "SOURCE_LCD_CONFIG_COLOR_WEAKNESS_SOLUTION" "TARGET_LCD_CONFIG_COLOR_WEAKNESS_SOLUTION"
    fi
fi

# SEC_PRODUCT_FEATURE_RIL_FEATURES
if [[ "$SOURCE_RIL_FEATURES" != "$TARGET_RIL_FEATURES" ]]; then
    if [[ "$SOURCE_RIL_FEATURES" != "none" ]]; then
        SMALI_PATCH "system" "system/framework/framework.jar" \
            "$PRODUCT_TELEPHONY_SMALI_DIR/com/android/internal/telephony/TelephonyFeatures.smali" "replaceall" \
            "$SOURCE_RIL_FEATURES" \
            "${TARGET_RIL_FEATURES//none/}"
        if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ]; then
            # R8 folded the feature string into the dump message.
            SMALI_PATCH "system" "system/framework/telephony-common.jar" \
                "smali/com/android/internal/telephony/TelephonyLogger.smali" "replaceall" \
                "$SOURCE_RIL_FEATURES" \
                "${TARGET_RIL_FEATURES//none/}"
        else
            SMALI_PATCH "system" "system/framework/telephony-common.jar" \
                "smali/com/android/internal/telephony/TelephonyLogger.smali" "replace" \
                "dump(Ljava/io/FileDescriptor;Ljava/io/PrintWriter;[Ljava/lang/String;)V" \
                "$SOURCE_RIL_FEATURES" \
                "${TARGET_RIL_FEATURES//none/}"
            SMALI_PATCH "system" "system/priv-app/TeleService/TeleService.apk" \
                "smali/com/samsung/telephony/model/feature/tag/SamsungProductFeatureTag.smali" "replaceall" \
                "$SOURCE_RIL_FEATURES" \
                "${TARGET_RIL_FEATURES//none/}"
        fi
        SMALI_PATCH "system" "system/priv-app/TeleService/TeleService.apk" \
            "smali/com/samsung/telephony/model/feature/SamsungFeatureSatellite.smali" "replaceall" \
            "$SOURCE_RIL_FEATURES" \
            "${TARGET_RIL_FEATURES//none/}"
    else
        # TODO handle this condition
        LOG_MISSING_PATCHES "SOURCE_RIL_FEATURES" "TARGET_RIL_FEATURES"
    fi
fi

# SEC_PRODUCT_FEATURE_RIL_SIM_CONFIG_MULTISIM_TRAYCOUNT
if [[ "$SOURCE_RIL_SIM_CONFIG_MULTISIM_TRAYCOUNT" != "$TARGET_RIL_SIM_CONFIG_MULTISIM_TRAYCOUNT" ]]; then
    if [[ "$SOURCE_RIL_SIM_CONFIG_MULTISIM_TRAYCOUNT" == "1" ]] && \
            [[ "$TARGET_RIL_SIM_CONFIG_MULTISIM_TRAYCOUNT" != "1" ]]; then
        SMALI_PATCH "system" "system/framework/framework.jar" \
            "$PRODUCT_TELEPHONY_SMALI_DIR/com/android/internal/telephony/TelephonyFeatures.smali" "return" \
            "isOneTray()Z" \
            "false"
    elif [[ "$SOURCE_RIL_SIM_CONFIG_MULTISIM_TRAYCOUNT" != "1" ]] && \
            [[ "$TARGET_RIL_SIM_CONFIG_MULTISIM_TRAYCOUNT" == "1" ]]; then
        # TODO handle this condition
        LOG_MISSING_PATCHES "SOURCE_RIL_SIM_CONFIG_MULTISIM_TRAYCOUNT" "TARGET_RIL_SIM_CONFIG_MULTISIM_TRAYCOUNT"
    fi
fi

# SEC_PRODUCT_FEATURE_RIL_SUPPORT_WATERPROOF_SIM_TRAY_MSG
if $SOURCE_RIL_SUPPORT_WATERPROOF_SIM_TRAY_MSG; then
    if ! $TARGET_RIL_SUPPORT_WATERPROOF_SIM_TRAY_MSG; then
        APPLY_PATCH "system" "system/framework/telephony-common.jar" \
            "$MODPATH/ril/telephony-common.jar/0001-Disable-RIL_SUPPORT_WATERPROOF_SIM_TRAY_MSG.patch"
    fi
else
    if $TARGET_RIL_SUPPORT_WATERPROOF_SIM_TRAY_MSG; then
        # TODO handle this condition
        LOG_MISSING_PATCHES "SOURCE_RIL_SUPPORT_WATERPROOF_SIM_TRAY_MSG" "TARGET_RIL_SUPPORT_WATERPROOF_SIM_TRAY_MSG"
    fi
fi

# SEC_PRODUCT_FEATURE_SECURITY_SUPPORT_STRONGBOX
TARGET_FIRMWARE_PATH="$(cut -d "/" -f 1 -s <<< "$TARGET_FIRMWARE")_$(cut -d "/" -f 2 -s <<< "$TARGET_FIRMWARE")"

if [ ! -f "$FW_DIR/$TARGET_FIRMWARE_PATH/vendor/etc/permissions/android.hardware.strongbox_keystore.xml" ]; then
    SMALI_PATCH "system" "system/framework/framework.jar" \
        "smali_classes6/com/samsung/android/service/DeviceIDProvisionService/DeviceIDProvisionManager\$DeviceIDProvisionWorker.smali" "return" \
        "isSupportStrongboxDeviceID()Z" \
        "false"
fi

# SEC_PRODUCT_FEATURE_WLAN_CONFIG_CPU_CSTATE_DISABLE_THRESHOLD
# SEC_PRODUCT_FEATURE_WLAN_CONFIG_DATA_ACTIVITY_AFFINITY_BOOSTER_THRESHOLD
# SEC_PRODUCT_FEATURE_WLAN_CONFIG_L1SS_DISABLE_THRESHOLD
if [[ "$SOURCE_WLAN_CONFIG_CPU_CSTATE_DISABLE_THRESHOLD" != "$TARGET_WLAN_CONFIG_CPU_CSTATE_DISABLE_THRESHOLD" ]] || \
        [[ "$SOURCE_WLAN_CONFIG_DATA_ACTIVITY_AFFINITY_BOOSTER_THRESHOLD" != "$TARGET_WLAN_CONFIG_DATA_ACTIVITY_AFFINITY_BOOSTER_THRESHOLD" ]] || \
        [[ "$SOURCE_WLAN_CONFIG_L1SS_DISABLE_THRESHOLD" != "$TARGET_WLAN_CONFIG_L1SS_DISABLE_THRESHOLD" ]]; then
    if { [[ "$SOURCE_WLAN_CONFIG_CPU_CSTATE_DISABLE_THRESHOLD" == "100" ]] || \
            { [[ "$SOURCE_PLATFORM_SDK_VERSION" -ge "37" ]] && [[ "$SOURCE_WLAN_CONFIG_CPU_CSTATE_DISABLE_THRESHOLD" == "0" ]]; }; } && \
            [[ "$SOURCE_WLAN_CONFIG_DATA_ACTIVITY_AFFINITY_BOOSTER_THRESHOLD" == "0" ]] && \
            [[ "$SOURCE_WLAN_CONFIG_L1SS_DISABLE_THRESHOLD" == "0" ]]; then
        APPLY_PATCH "system" "system/framework/semwifi-service.jar" \
            "$MODPATH/wifi/thresholds/semwifi-service.jar/0001-Allow-custom-booster-thresholds-values.patch"
        SMALI_PATCH "system" "system/framework/semwifi-service.jar" \
            "smali/com/samsung/android/server/wifi/SemFrameworkFacade.smali" "replace" \
            "getBoosterThresholds()[I" \
            "CONFIG_DATA_ACTIVITY_AFFINITY_BOOSTER_THRESHOLD" \
            "$TARGET_WLAN_CONFIG_DATA_ACTIVITY_AFFINITY_BOOSTER_THRESHOLD" | \
            sed "s/CONFIG_DATA_ACTIVITY_AFFINITY_BOOSTER_THRESHOLD/$SOURCE_WLAN_CONFIG_DATA_ACTIVITY_AFFINITY_BOOSTER_THRESHOLD/g"
        [ "${PIPESTATUS[0]}" -eq 0 ] || return 1
        SMALI_PATCH "system" "system/framework/semwifi-service.jar" \
            "smali/com/samsung/android/server/wifi/SemFrameworkFacade.smali" "replace" \
            "getBoosterThresholds()[I" \
            "CONFIG_CPU_CSTATE_DISABLE_THRESHOLD" \
            "$TARGET_WLAN_CONFIG_CPU_CSTATE_DISABLE_THRESHOLD" | \
            sed "s/CONFIG_CPU_CSTATE_DISABLE_THRESHOLD/$SOURCE_WLAN_CONFIG_CPU_CSTATE_DISABLE_THRESHOLD/g"
        [ "${PIPESTATUS[0]}" -eq 0 ] || return 1
        SMALI_PATCH "system" "system/framework/semwifi-service.jar" \
            "smali/com/samsung/android/server/wifi/SemFrameworkFacade.smali" "replace" \
            "getBoosterThresholds()[I" \
            "CONFIG_L1SS_DISABLE_THRESHOLD" \
            "$TARGET_WLAN_CONFIG_L1SS_DISABLE_THRESHOLD" | \
            sed "s/CONFIG_L1SS_DISABLE_THRESHOLD/$SOURCE_WLAN_CONFIG_L1SS_DISABLE_THRESHOLD/g"
        [ "${PIPESTATUS[0]}" -eq 0 ] || return 1
    else
        # TODO handle these conditions
        LOG_MISSING_PATCHES "SOURCE_WLAN_CONFIG_CPU_CSTATE_DISABLE_THRESHOLD" "TARGET_WLAN_CONFIG_CPU_CSTATE_DISABLE_THRESHOLD" || true
        LOG_MISSING_PATCHES "SOURCE_WLAN_CONFIG_DATA_ACTIVITY_AFFINITY_BOOSTER_THRESHOLD" "TARGET_WLAN_CONFIG_DATA_ACTIVITY_AFFINITY_BOOSTER_THRESHOLD" || true
        LOG_MISSING_PATCHES "SOURCE_WLAN_CONFIG_L1SS_DISABLE_THRESHOLD" "TARGET_WLAN_CONFIG_L1SS_DISABLE_THRESHOLD"
    fi
fi

# SEC_PRODUCT_FEATURE_WLAN_CONFIG_CUSTOM_BACKOFF
if [[ "$SOURCE_WLAN_CONFIG_CUSTOM_BACKOFF" != "$TARGET_WLAN_CONFIG_CUSTOM_BACKOFF" ]]; then
    if [[ "$SOURCE_WLAN_CONFIG_CUSTOM_BACKOFF" != "none" ]] && [[ "$TARGET_WLAN_CONFIG_CUSTOM_BACKOFF" != "none" ]]; then
        SMALI_PATCH "system" "system/framework/semwifi-service.jar" \
            "smali/com/samsung/android/server/wifi/SemWifiCoexManager.smali" "replaceall" \
            "$SOURCE_WLAN_CONFIG_CUSTOM_BACKOFF" \
            "$TARGET_WLAN_CONFIG_CUSTOM_BACKOFF"
    elif [[ "$SOURCE_WLAN_CONFIG_CUSTOM_BACKOFF" == "none" ]] && [[ "$TARGET_WLAN_CONFIG_CUSTOM_BACKOFF" != "none" ]]; then
        APPLY_PATCH "system" "system/framework/semwifi-service.jar" \
            "$MODPATH/wifi/custom_backoff/semwifi-service.jar/0001-Allow-custom-CUSTOM_BACKOFF-value.patch"
        SMALI_PATCH "system" "system/framework/semwifi-service.jar" \
            "smali/com/samsung/android/server/wifi/SemWifiCoexManager.smali" "replaceall" \
            "CONFIG_CUSTOM_BACKOFF" \
            "$TARGET_WLAN_CONFIG_CUSTOM_BACKOFF" | \
            sed "s/CONFIG_CUSTOM_BACKOFF/$SOURCE_WLAN_CONFIG_CUSTOM_BACKOFF/g"
        [ "${PIPESTATUS[0]}" -eq 0 ] || return 1
    elif [[ "$SOURCE_WLAN_CONFIG_CUSTOM_BACKOFF" != "none" ]] && [[ "$TARGET_WLAN_CONFIG_CUSTOM_BACKOFF" == "none" ]]; then
        if [[ "$SOURCE_PLATFORM_SDK_VERSION" -ge "37" ]]; then
            SMALI_PATCH "system" "system/framework/semwifi-service.jar" \
                "smali/com/samsung/android/server/wifi/SemWifiCoexManager.smali" "replaceall" \
                "$SOURCE_WLAN_CONFIG_CUSTOM_BACKOFF" ""
        else
            SMALI_PATCH "system" "system/framework/semwifi-service.jar" \
                "smali/com/samsung/android/server/wifi/SemWifiCoexManager.smali" "replaceall" \
                "$SOURCE_WLAN_CONFIG_CUSTOM_BACKOFF" \
                "CONFIG_CUSTOM_BACKOFF" > /dev/null
            APPLY_PATCH "system" "system/framework/semwifi-service.jar" \
                "$MODPATH/wifi/custom_backoff/semwifi-service.jar/0001-Remove-CUSTOM_BACKOFF-value.patch"
        fi
    fi
fi

# SEC_PRODUCT_FEATURE_WLAN_CONFIG_SEPARATE_ANT_BACKOFF
if [[ "$SOURCE_WLAN_CONFIG_SEPARATE_ANT_BACKOFF" != "$TARGET_WLAN_CONFIG_SEPARATE_ANT_BACKOFF" ]]; then
    SMALI_PATCH "system" "system/framework/semwifi-service.jar" \
        "smali/com/samsung/android/server/wifi/backoff/BackOffFeatureUtil.smali" "return" \
        "getSeparateAntennaType()Ljava/lang/String;" \
        "${TARGET_WLAN_CONFIG_SEPARATE_ANT_BACKOFF//none/}"
fi

# SEC_PRODUCT_FEATURE_WLAN_CONFIG_SINGLE_ANT_BACKOFF
if [[ "$SOURCE_WLAN_CONFIG_SINGLE_ANT_BACKOFF" != "$TARGET_WLAN_CONFIG_SINGLE_ANT_BACKOFF" ]]; then
    SMALI_PATCH "system" "system/framework/semwifi-service.jar" \
        "smali/com/samsung/android/server/wifi/backoff/BackOffFeatureUtil.smali" "return" \
        "getSingleAntennaType()Ljava/lang/String;" \
        "${TARGET_WLAN_CONFIG_SINGLE_ANT_BACKOFF//none/}"
fi

# SEC_PRODUCT_FEATURE_WLAN_SUPPORT_80211AX
# SEC_PRODUCT_FEATURE_WLAN_SUPPORT_80211AX_6GHZ
if $SOURCE_WLAN_SUPPORT_80211AX; then
    if $TARGET_WLAN_SUPPORT_80211AX; then
        if ! $SOURCE_WLAN_SUPPORT_80211AX_6GHZ; then
            if $TARGET_WLAN_SUPPORT_80211AX_6GHZ; then
                APPLY_PATCH "system" "system/framework/semwifi-service.jar" \
                    "$MODPATH/wifi/80211ax_6ghz/semwifi-service.jar/0001-Enable-80211AX_6GHZ-support.patch"
                APPLY_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
                    "$MODPATH/wifi/80211ax_6ghz/SecSettings.apk/0001-Enable-80211AX_6GHZ-support.patch"
                APPLY_PATCH "system_ext" "priv-app/SystemUI/SystemUI.apk" \
                    "$MODPATH/wifi/80211ax_6ghz/SystemUI.apk/0001-Enable-80211AX_6GHZ-support.patch"
            fi
        else
            if ! $TARGET_WLAN_SUPPORT_80211AX_6GHZ; then
                if [[ "$SOURCE_PLATFORM_SDK_VERSION" -ge "37" ]]; then
                    APPLY_PATCH "system" "system/framework/semwifi-service.jar" \
                        "$MODPATH/wifi/80211ax_6ghz/semwifi-service.jar/0001-Disable-80211AX_6GHZ-support.patch"
                    APPLY_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
                        "$MODPATH/wifi/80211ax_6ghz/SecSettings.apk/0001-Disable-80211AX_6GHZ-support.patch"
                    APPLY_PATCH "system_ext" "priv-app/SystemUI/SystemUI.apk" \
                        "$MODPATH/wifi/80211ax_6ghz/SystemUI.apk/0001-Disable-80211AX_6GHZ-support.patch"
                    if [ -f "$WORK_DIR/product/overlay/SoftapOverlay/SoftapOverlay.apk" ]; then
                        DECODE_APK "product" "overlay/SoftapOverlay/SoftapOverlay.apk"
                        EVAL "sed -i '/name=\"config_wifi6ghzSupport\"/s/>true</>false</' \"$APKTOOL_DIR/product/overlay/SoftapOverlay/SoftapOverlay.apk/res/values/bools.xml\""
                    fi
                else
                    # TODO handle this condition
                    LOG_MISSING_PATCHES "SOURCE_WLAN_SUPPORT_80211AX_6GHZ" "TARGET_WLAN_SUPPORT_80211AX_6GHZ"
                fi
            fi
        fi
    else
        if $TARGET_WLAN_SUPPORT_80211AX_6GHZ; then
            ABORT "TARGET_WLAN_SUPPORT_80211AX is required by TARGET_WLAN_SUPPORT_80211AX_6GHZ"
        fi
        if ! $SOURCE_WLAN_SUPPORT_80211AX_6GHZ; then
            APPLY_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
                "$MODPATH/wifi/80211ax/SecSettings.apk/0001-Disable-80211AX-support.patch"
            APPLY_PATCH "system_ext" "priv-app/SystemUI/SystemUI.apk" \
                "$MODPATH/wifi/80211ax/SystemUI.apk/0001-Disable-80211AX-support.patch"
        else
            # TODO handle these conditions
            LOG_MISSING_PATCHES "SOURCE_WLAN_SUPPORT_80211AX" "TARGET_WLAN_SUPPORT_80211AX" || true
            LOG_MISSING_PATCHES "SOURCE_WLAN_SUPPORT_80211AX_6GHZ" "TARGET_WLAN_SUPPORT_80211AX_6GHZ"
        fi
    fi
else
    if $SOURCE_WLAN_SUPPORT_80211AX_6GHZ; then
        ABORT "SOURCE_WLAN_SUPPORT_80211AX is required by SOURCE_WLAN_SUPPORT_80211AX_6GHZ"
    fi
    if $TARGET_WLAN_SUPPORT_80211AX; then
        # TODO handle this condition
        LOG_MISSING_PATCHES "SOURCE_WLAN_SUPPORT_80211AX" "TARGET_WLAN_SUPPORT_80211AX"
    fi
    if $TARGET_WLAN_SUPPORT_80211AX_6GHZ; then
        ABORT "TARGET_WLAN_SUPPORT_80211AX is required by TARGET_WLAN_SUPPORT_80211AX_6GHZ"
    fi
fi

# SEC_PRODUCT_FEATURE_WLAN_SUPPORT_APE_SERVICE
# SEC_PRODUCT_FEATURE_WLAN_CONFIG_CONNECTION_PERSONALIZATION
# SEC_PRODUCT_FEATURE_WLAN_CONFIG_DYNAMIC_SWITCH
if [[ "$SOURCE_WLAN_CONFIG_CONNECTION_PERSONALIZATION" != "$TARGET_WLAN_CONFIG_CONNECTION_PERSONALIZATION" ]] || \
        [[ "$SOURCE_WLAN_CONFIG_DYNAMIC_SWITCH" != "$TARGET_WLAN_CONFIG_DYNAMIC_SWITCH" ]] || \
        [[ "$SOURCE_WLAN_SUPPORT_APE_SERVICE" != "$TARGET_WLAN_SUPPORT_APE_SERVICE" ]]; then
    if { [[ "$SOURCE_WLAN_CONFIG_CONNECTION_PERSONALIZATION" == "1" ]] || \
            { [[ "$SOURCE_PLATFORM_SDK_VERSION" -ge "37" ]] && [[ "$SOURCE_WLAN_CONFIG_CONNECTION_PERSONALIZATION" == "3" ]]; }; } && $SOURCE_WLAN_SUPPORT_APE_SERVICE; then
        if [[ "$SOURCE_PLATFORM_SDK_VERSION" -lt "37" ]] && [[ "$SOURCE_WLAN_CONFIG_DYNAMIC_SWITCH" != "0" ]]; then
            SMALI_PATCH "system" "system/framework/semwifi-service.jar" \
                "smali/com/samsung/android/server/wifi/SemWifiInjector.smali" "replace" \
                "<init>(Landroid/content/Context;)V" \
                "$SOURCE_WLAN_CONFIG_DYNAMIC_SWITCH" \
                "0" > /dev/null
        fi
        APPLY_PATCH "system" "system/framework/semwifi-service.jar" \
            "$MODPATH/wifi/connection_personalization/semwifi-service.jar/0001-Allow-custom-CONNECTION_PERSONALIZATION-value.patch"
        if [[ "$SOURCE_PLATFORM_SDK_VERSION" -lt "37" ]] && [[ "$SOURCE_WLAN_CONFIG_DYNAMIC_SWITCH" != "0" ]]; then
            SMALI_PATCH "system" "system/framework/semwifi-service.jar" \
                "smali/com/samsung/android/server/wifi/SemWifiInjector.smali" "replace" \
                "<init>(Landroid/content/Context;)V" \
                "0" \
                "$SOURCE_WLAN_CONFIG_DYNAMIC_SWITCH" > /dev/null
        fi
        SMALI_PATCH "system" "system/framework/semwifi-service.jar" \
            "smali/com/samsung/android/server/wifi/SemWifiInjector.smali" "replace" \
            "<init>(Landroid/content/Context;)V" \
            "CONFIG_CONNECTION_PERSONALIZATION" \
            "$TARGET_WLAN_CONFIG_CONNECTION_PERSONALIZATION" | \
            sed "s/CONFIG_CONNECTION_PERSONALIZATION/$SOURCE_WLAN_CONFIG_CONNECTION_PERSONALIZATION/g"
        [ "${PIPESTATUS[0]}" -eq 0 ] || return 1
        if [[ "$SOURCE_PLATFORM_SDK_VERSION" -ge "37" ]]; then
            SMALI_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
                "smali_classes4/com/samsung/android/settings/wifi/develop/compatibility/btm/BtmController.smali" "replace" \
                "getAvailabilityStatus()I" \
                "$SOURCE_WLAN_CONFIG_CONNECTION_PERSONALIZATION" \
                "$TARGET_WLAN_CONFIG_CONNECTION_PERSONALIZATION"
        else
            APPLY_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
                "$MODPATH/wifi/connection_personalization/SecSettings.apk/0001-Allow-custom-CONNECTION_PERSONALIZATION-value.patch"
            SMALI_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
                "smali_classes3/com/samsung/android/settings/wifi/develop/btm/BtmController.smali" "replace" \
                "getAvailabilityStatus()I" \
                "CONFIG_CONNECTION_PERSONALIZATION" \
                "$TARGET_WLAN_CONFIG_CONNECTION_PERSONALIZATION" | \
                sed "s/CONFIG_CONNECTION_PERSONALIZATION/$SOURCE_WLAN_CONFIG_CONNECTION_PERSONALIZATION/g"
            [ "${PIPESTATUS[0]}" -eq 0 ] || return 1
        fi

        if [[ "$SOURCE_WLAN_CONFIG_DYNAMIC_SWITCH" != "$TARGET_WLAN_CONFIG_DYNAMIC_SWITCH" ]]; then
            SMALI_PATCH "system" "system/framework/semwifi-service.jar" \
                "smali/com/samsung/android/server/wifi/SemWifiInjector.smali" "replace" \
                "<init>(Landroid/content/Context;)V" \
                "$SOURCE_WLAN_CONFIG_DYNAMIC_SWITCH" \
                "$TARGET_WLAN_CONFIG_DYNAMIC_SWITCH"
            SMALI_PATCH "system" "system/framework/semwifi-service.jar" \
                "smali/com/samsung/android/server/wifi/SemWifiResourceManager.smali" "replace" \
                "<init>(Landroid/content/Context;Lcom/samsung/android/server/wifi/halclient/SemWifiNative;Lcom/samsung/android/server/wifi/SemWifiInjector;)V" \
                "$SOURCE_WLAN_CONFIG_DYNAMIC_SWITCH" \
                "$TARGET_WLAN_CONFIG_DYNAMIC_SWITCH"
            if [[ "$SOURCE_PLATFORM_SDK_VERSION" -ge "37" ]]; then
                SMALI_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
                    "smali_classes3/com/samsung/android/settings/development/SecDevelopmentSettingsDashboardFragment.smali" "replace" \
                    "buildPreferenceControllers\$1(Landroid/content/Context;Lcom/android/settingslib/core/lifecycle/Lifecycle;)Ljava/util/List;" \
                    "$SOURCE_WLAN_CONFIG_DYNAMIC_SWITCH" \
                    "$TARGET_WLAN_CONFIG_DYNAMIC_SWITCH"
            else
                SMALI_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
                    "smali_classes2/com/android/settings/development/WifiSafePreferenceController.smali" "replace" \
                    "<init>(Landroid/content/Context;)V" \
                    "$SOURCE_WLAN_CONFIG_DYNAMIC_SWITCH" \
                    "$TARGET_WLAN_CONFIG_DYNAMIC_SWITCH"
            fi
        fi

        if ! $TARGET_WLAN_SUPPORT_APE_SERVICE; then
            APPLY_PATCH "system" "system/framework/semwifi-service.jar" \
                "$MODPATH/wifi/ape_service/semwifi-service.jar/0001-Disable-APE_SERVICE-support.patch"
            if [[ "$SOURCE_PLATFORM_SDK_VERSION" -lt "37" ]]; then
                SMALI_PATCH "system" "system/framework/semwifi-service.jar" \
                    "smali/com/samsung/android/server/wifi/SemQboxController\$1.smali" "remove"
            fi
            APPLY_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
                "$MODPATH/wifi/ape_service/SecSettings.apk/0001-Disable-APE_SERVICE-support.patch"
        fi
    else
        # TODO handle these conditions
        LOG_MISSING_PATCHES "SOURCE_WLAN_CONFIG_CONNECTION_PERSONALIZATION" "TARGET_WLAN_CONFIG_CONNECTION_PERSONALIZATION" || true
        LOG_MISSING_PATCHES "SOURCE_WLAN_SUPPORT_APE_SERVICE" "TARGET_WLAN_SUPPORT_APE_SERVICE"
    fi
fi

# SEC_PRODUCT_FEATURE_WLAN_SUPPORT_MBO
if ! $SOURCE_WLAN_SUPPORT_MBO && $TARGET_WLAN_SUPPORT_MBO; then
    SMALI_PATCH "system" "system/framework/semwifi-service.jar" \
        "smali/com/samsung/android/server/wifi/SemFrameworkFacade.smali" "return" \
        "isMBOSupported()Z" \
        "true"
elif $SOURCE_WLAN_SUPPORT_MBO && ! $TARGET_WLAN_SUPPORT_MBO; then
    SMALI_PATCH "system" "system/framework/semwifi-service.jar" \
        "smali/com/samsung/android/server/wifi/SemFrameworkFacade.smali" "return" \
        "isMBOSupported()Z" \
        "false"
fi

# SEC_PRODUCT_FEATURE_WLAN_SUPPORT_MIMO
if ! $SOURCE_WLAN_SUPPORT_MIMO && $TARGET_WLAN_SUPPORT_MIMO; then
    SMALI_PATCH "system" "system/framework/semwifi-service.jar" \
        "smali/com/samsung/android/server/wifi/SemWifiServiceImpl.smali" "return" \
        "getNumOfWifiAnt()I" \
        "2"
elif $SOURCE_WLAN_SUPPORT_MIMO && ! $TARGET_WLAN_SUPPORT_MIMO; then
    SMALI_PATCH "system" "system/framework/semwifi-service.jar" \
        "smali/com/samsung/android/server/wifi/SemWifiServiceImpl.smali" "return" \
        "getNumOfWifiAnt()I" \
        "1"
fi

# SEC_PRODUCT_FEATURE_WLAN_SUPPORT_MOBILEAP_11AX
if $SOURCE_WLAN_SUPPORT_MOBILEAP_11AX; then
    if ! $TARGET_WLAN_SUPPORT_MOBILEAP_11AX; then
        APPLY_PATCH "system" "system/framework/semwifi-service.jar" \
            "$MODPATH/wifi/80211ax/semwifi-service.jar/0001-Disable-MOBILEAP_11AX-support.patch"
    fi
else
    if $TARGET_WLAN_SUPPORT_MOBILEAP_11AX; then
        # TODO handle this condition
        LOG_MISSING_PATCHES "SOURCE_WLAN_SUPPORT_MOBILEAP_11AX" "TARGET_WLAN_SUPPORT_MOBILEAP_11AX"
    fi
fi

# SEC_PRODUCT_FEATURE_WLAN_SUPPORT_MOBILEAP_5G_BASEDON_COUNTRY
if ! $SOURCE_WLAN_SUPPORT_MOBILEAP_5G_BASEDON_COUNTRY; then
    if $TARGET_WLAN_SUPPORT_MOBILEAP_5G_BASEDON_COUNTRY; then
        APPLY_PATCH "system" "system/framework/semwifi-service.jar" \
            "$MODPATH/wifi/5g_basedon_country/semwifi-service.jar/0001-Enable-MOBILEAP_5G_BASEDON_COUNTRY-support.patch"
        SMALI_PATCH "system" "system/framework/semwifi-service.jar" \
            "smali/com/samsung/android/server/wifi/ap/SemSoftApConfiguration.smali" "replaceall" \
            "SPF_5G_BASEDON_COUNTRY=false" \
            "SPF_5G_BASEDON_COUNTRY=true"
    fi
else
    if ! $TARGET_WLAN_SUPPORT_MOBILEAP_5G_BASEDON_COUNTRY; then
        if [[ "$SOURCE_PLATFORM_SDK_VERSION" -ge 37 ]]; then
            APPLY_PATCH "system" "system/framework/semwifi-service.jar" \
                "$MODPATH/wifi/5g_basedon_country/semwifi-service.jar/0001-Disable-unsupported-capabilities.patch"
            SMALI_PATCH "system" "system/framework/semwifi-service.jar" \
                "smali/com/samsung/android/server/wifi/ap/SemSoftApConfiguration.smali" "replaceall" \
                "SPF_5G_BASEDON_COUNTRY=true" \
                "SPF_5G_BASEDON_COUNTRY=false"
        else
            # TODO handle this condition
            LOG_MISSING_PATCHES "SOURCE_WLAN_SUPPORT_MOBILEAP_5G_BASEDON_COUNTRY" "TARGET_WLAN_SUPPORT_MOBILEAP_5G_BASEDON_COUNTRY"
        fi
    fi
fi

# SEC_PRODUCT_FEATURE_WLAN_SUPPORT_MOBILEAP_6G
if ! $SOURCE_WLAN_SUPPORT_MOBILEAP_6G && $TARGET_WLAN_SUPPORT_MOBILEAP_6G; then
    ADD_TO_WORK_DIR "b0qxxx" "product" "overlay/SoftapOverlay6GHz/SoftapOverlay6GHz.apk" 0 0 644 "u:object_r:system_file:s0"

    SMALI_PATCH "system" "system/framework/semwifi-service.jar" \
        "smali/com/samsung/android/server/wifi/ap/SemSoftApConfiguration.smali" "replaceall" \
        "SPF_6G=false" \
        "SPF_6G=true"
    SMALI_PATCH "system" "system/framework/semwifi-service.jar" \
        "smali/com/samsung/android/server/wifi/SemFrameworkFacade.smali" "return" \
        "isSupportMobileAp6G()Z" \
        "true"
elif $SOURCE_WLAN_SUPPORT_MOBILEAP_6G && ! $TARGET_WLAN_SUPPORT_MOBILEAP_6G; then
    if [ -f "$WORK_DIR/product/overlay/SoftapOverlay/SoftapOverlay.apk" ]; then
        DECODE_APK "product" "overlay/SoftapOverlay/SoftapOverlay.apk"
        EVAL "sed -i '/name=\"config_wifiSoftap6ghzSupported\"/s/>true</>false</' \"$APKTOOL_DIR/product/overlay/SoftapOverlay/SoftapOverlay.apk/res/values/bools.xml\""
        EVAL "sed -i '/name=\"config_wifiLocalOnlyHotspot6ghz\"/s/>true</>false</' \"$APKTOOL_DIR/product/overlay/SoftapOverlay/SoftapOverlay.apk/res/values/bools.xml\""
    fi
    if [ -d "$WORK_DIR/product/overlay/SoftapOverlay6GHz" ]; then
        DELETE_FROM_WORK_DIR "product" "overlay/SoftapOverlay6GHz"
    fi

    SMALI_PATCH "system" "system/framework/semwifi-service.jar" \
        "smali/com/samsung/android/server/wifi/ap/SemSoftApConfiguration.smali" "replaceall" \
        "SPF_6G=true" \
        "SPF_6G=false"
    SMALI_PATCH "system" "system/framework/semwifi-service.jar" \
        "smali/com/samsung/android/server/wifi/SemFrameworkFacade.smali" "return" \
        "isSupportMobileAp6G()Z" \
        "false"
fi

# SEC_PRODUCT_FEATURE_WLAN_SUPPORT_MOBILEAP_DUALAP
if ! $SOURCE_WLAN_SUPPORT_MOBILEAP_DUALAP; then
    if $TARGET_WLAN_SUPPORT_MOBILEAP_DUALAP; then
        ADD_TO_WORK_DIR "dm1qxxx" "product" "overlay/SoftapOverlayDualAp/SoftapOverlayDualAp.apk" 0 0 644 "u:object_r:system_file:s0"

        APPLY_PATCH "system" "system/framework/semwifi-service.jar" \
            "$MODPATH/wifi/dualap/semwifi-service.jar/0001-Enable-MOBILEAP_DUALAP-support.patch"
        SMALI_PATCH "system" "system/framework/semwifi-service.jar" \
            "smali/com/samsung/android/server/wifi/ap/SemSoftApConfiguration.smali" "replaceall" \
            "SPF_DualAp=false" \
            "SPF_DualAp=true"
        SMALI_PATCH "system" "system/framework/semwifi-service.jar" \
            "smali/com/samsung/android/server/wifi/ap/SemSoftApConfiguration\$6.smali" "remove"
        SMALI_PATCH "system" "system/framework/semwifi-service.jar" \
            "smali/com/samsung/android/server/wifi/ap/SemSoftApConfiguration\$12.smali" "remove"
        SMALI_PATCH "system" "system/framework/semwifi-service.jar" \
            "smali/com/samsung/android/server/wifi/ap/SemSoftApConfiguration\$16.smali" "remove"
        if $TARGET_COMMON_SUPPORT_DYN_RESOLUTION_CONTROL; then
            APPLY_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
                "$MODPATH/wifi/dualap_resolution/SecSettings.apk/0001-Enable-MOBILEAP_DUALAP-support.patch"
        else
            APPLY_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
                "$MODPATH/wifi/dualap/SecSettings.apk/0001-Enable-MOBILEAP_DUALAP-support.patch"
        fi
        SMALI_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
            "smali_classes3/com/samsung/android/settings/wifi/mobileap/WifiApSmartSwitchBackupRestore\$5.smali" "remove"
    fi
else
    if ! $TARGET_WLAN_SUPPORT_MOBILEAP_DUALAP; then
        if [[ "$SOURCE_PLATFORM_SDK_VERSION" -ge 37 ]]; then
            APPLY_PATCH "system" "system/framework/semwifi-service.jar" \
                "$MODPATH/wifi/dualap/semwifi-service.jar/0001-Disable-unsupported-capabilities.patch"
            APPLY_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
                "$MODPATH/wifi/dualap/SecSettings.apk/0001-Disable-unsupported-capabilities.patch"
            if [ -f "$WORK_DIR/product/overlay/SoftapOverlay/SoftapOverlay.apk" ]; then
                DECODE_APK "product" "overlay/SoftapOverlay/SoftapOverlay.apk"
                EVAL "sed -i '/name=\"config_wifiBridgedSoftApSupported\"/s/>true</>false</' \"$APKTOOL_DIR/product/overlay/SoftapOverlay/SoftapOverlay.apk/res/values/bools.xml\""
            fi
            SMALI_PATCH "system" "system/framework/semwifi-service.jar" \
                "smali/com/samsung/android/server/wifi/ap/SemSoftApConfiguration.smali" "replaceall" \
                "SPF_DualAp=true" \
                "SPF_DualAp=false"
        else
            # TODO handle this condition
            LOG_MISSING_PATCHES "SOURCE_WLAN_SUPPORT_MOBILEAP_DUALAP" "TARGET_WLAN_SUPPORT_MOBILEAP_DUALAP"
        fi
    fi
fi

# SEC_PRODUCT_FEATURE_WLAN_SUPPORT_MOBILEAP_OWE
if ! $SOURCE_WLAN_SUPPORT_MOBILEAP_OWE; then
    if $TARGET_WLAN_SUPPORT_MOBILEAP_OWE; then
        ADD_TO_WORK_DIR "dm1qxxx" "product" "overlay/SoftapOverlayOWE/SoftapOverlayOWE.apk" 0 0 644 "u:object_r:system_file:s0"

        APPLY_PATCH "system" "system/framework/semwifi-service.jar" \
            "$MODPATH/wifi/owe/semwifi-service.jar/0001-Enable-MOBILEAP_OWE-support.patch"
        SMALI_PATCH "system" "system/framework/semwifi-service.jar" \
            "smali/com/samsung/android/server/wifi/ap/SemSoftApConfiguration.smali" "replaceall" \
            "SPF_OWE=false" \
            "SPF_OWE=true"
        APPLY_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
            "$MODPATH/wifi/owe/SecSettings.apk/0001-Enable-MOBILEAP_OWE-support.patch"
    fi
else
    if ! $TARGET_WLAN_SUPPORT_MOBILEAP_OWE; then
        if [[ "$SOURCE_PLATFORM_SDK_VERSION" -ge 37 ]]; then
            APPLY_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
                "$MODPATH/wifi/owe/SecSettings.apk/0001-Disable-unsupported-capabilities.patch"
            if [ -f "$WORK_DIR/product/overlay/SoftapOverlay/SoftapOverlay.apk" ]; then
                DECODE_APK "product" "overlay/SoftapOverlay/SoftapOverlay.apk"
                EVAL "sed -i '/name=\"config_wifiSoftapOweSupported\"/s/>true</>false</' \"$APKTOOL_DIR/product/overlay/SoftapOverlay/SoftapOverlay.apk/res/values/bools.xml\""
            fi
            SMALI_PATCH "system" "system/framework/semwifi-service.jar" \
                "smali/com/samsung/android/server/wifi/ap/SemSoftApConfiguration.smali" "replaceall" \
                "SPF_OWE=true" \
                "SPF_OWE=false"
        else
            # TODO handle this condition
            LOG_MISSING_PATCHES "SOURCE_WLAN_SUPPORT_MOBILEAP_OWE" "TARGET_WLAN_SUPPORT_MOBILEAP_OWE"
        fi
    fi
fi

# SEC_PRODUCT_FEATURE_WLAN_SUPPORT_MOBILEAP_POWER_SAVEMODE
if $SOURCE_WLAN_SUPPORT_MOBILEAP_POWER_SAVEMODE; then
    if ! $TARGET_WLAN_SUPPORT_MOBILEAP_POWER_SAVEMODE; then
        APPLY_PATCH "system" "system/framework/semwifi-service.jar" \
            "$MODPATH/wifi/power_savemode/semwifi-service.jar/0001-Disable-MOBILEAP_POWER_SAVEMODE-support.patch"
        SMALI_PATCH "system" "system/framework/semwifi-service.jar" \
            "smali/com/samsung/android/server/wifi/ap/SemSoftApConfiguration.smali" "replaceall" \
            "SPF_POWER_SAVEMODE=true" \
            "SPF_POWER_SAVEMODE=false"
        SMALI_PATCH "system" "system/framework/semwifi-service.jar" \
            "smali/com/samsung/android/server/wifi/ap/SemWifiApPowerSaveImpl\$\$ExternalSyntheticLambda0.smali" "remove"
        SMALI_PATCH "system" "system/framework/semwifi-service.jar" \
            "smali/com/samsung/android/server/wifi/ap/SemWifiApPowerSaveImpl\$\$ExternalSyntheticLambda1.smali" "remove"
    fi
else
    if $TARGET_WLAN_SUPPORT_MOBILEAP_POWER_SAVEMODE; then
        # TODO handle this condition
        LOG_MISSING_PATCHES "SOURCE_WLAN_SUPPORT_MOBILEAP_POWER_SAVEMODE" "TARGET_WLAN_SUPPORT_MOBILEAP_POWER_SAVEMODE"
    fi
fi

# SEC_PRODUCT_FEATURE_WLAN_SUPPORT_MOBILEAP_PRIORITIZE_TRAFFIC
if $SOURCE_WLAN_SUPPORT_MOBILEAP_PRIORITIZE_TRAFFIC; then
    if ! $TARGET_WLAN_SUPPORT_MOBILEAP_PRIORITIZE_TRAFFIC; then
        DELETE_FROM_WORK_DIR "system" "system/app/MhsAiService"
        DELETE_FROM_WORK_DIR "system" "system/etc/xgb_mhs_l1.model"

        APPLY_PATCH "system" "system/framework/semwifi-service.jar" \
            "$MODPATH/wifi/prioritize_traffic/semwifi-service.jar/0001-Disable-MOBILEAP_PRIORITIZE_TRAFFIC-support.patch"
        SMALI_PATCH "system" "system/framework/semwifi-service.jar" \
            "smali/com/samsung/android/server/wifi/ap/SemSoftApConfiguration.smali" "replaceall" \
            "SPF_Prio_Traffic=true" \
            "SPF_Prio_Traffic=false"
        APPLY_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
            "$MODPATH/wifi/prioritize_traffic/SecSettings.apk/0001-Disable-MOBILEAP_PRIORITIZE_TRAFFIC-support.patch"
    fi
else
    if $TARGET_WLAN_SUPPORT_MOBILEAP_PRIORITIZE_TRAFFIC; then
        # TODO handle this condition
        LOG_MISSING_PATCHES "SOURCE_WLAN_SUPPORT_MOBILEAP_PRIORITIZE_TRAFFIC" "TARGET_WLAN_SUPPORT_MOBILEAP_PRIORITIZE_TRAFFIC"
    fi
fi

# SEC_PRODUCT_FEATURE_WLAN_SEC_SUPPORT_MOBILEAP_WIFI_CONCURRENCY
if ! $SOURCE_WLAN_SUPPORT_MOBILEAP_WIFI_CONCURRENCY; then
    if $TARGET_WLAN_SUPPORT_MOBILEAP_WIFI_CONCURRENCY; then
        # Check for target flag instead as we've already took care of this SPF above
        if ! $TARGET_WLAN_SUPPORT_MOBILEAP_POWER_SAVEMODE; then
            APPLY_PATCH "system" "system/framework/semwifi-service.jar" \
                "$MODPATH/wifi/power_savemode/semwifi-service.jar/0002-Enable-MOBILEAP_WIFI_CONCURRENCY-support.patch"
        else
            APPLY_PATCH "system" "system/framework/semwifi-service.jar" \
                "$MODPATH/wifi/wifisharing/semwifi-service.jar/0001-Enable-MOBILEAP_WIFI_CONCURRENCY-support.patch"
        fi
        SMALI_PATCH "system" "system/framework/semwifi-service.jar" \
            "smali/com/samsung/android/server/wifi/ap/SemSoftApConfiguration.smali" "replaceall" \
            "SPF_Concurrency=false" \
            "SPF_Concurrency=true"
    fi
else
    if ! $TARGET_WLAN_SUPPORT_MOBILEAP_WIFI_CONCURRENCY; then
        if [ "$SOURCE_PLATFORM_SDK_VERSION" = "37" ]; then
            APPLY_PATCH "system" "system/framework/semwifi-service.jar" \
                "$MODPATH/wifi/wifisharing/semwifi-service.jar/0001-Disable-MOBILEAP_WIFI_CONCURRENCY-support.patch"
            SMALI_PATCH "system" "system/framework/semwifi-service.jar" \
                "smali/com/samsung/android/server/wifi/ap/SemSoftApConfiguration.smali" "replaceall" \
                "SPF_Concurrency=true" \
                "SPF_Concurrency=false"
        else
            # TODO handle this condition
            LOG_MISSING_PATCHES "SOURCE_WLAN_SUPPORT_MOBILEAP_WIFI_CONCURRENCY" "TARGET_WLAN_SUPPORT_MOBILEAP_WIFI_CONCURRENCY"
        fi
    fi
fi

# SEC_PRODUCT_FEATURE_WLAN_SUPPORT_MOBILEAP_WIFISHARING_LITE
if ! $SOURCE_WLAN_SUPPORT_MOBILEAP_WIFISHARING_LITE; then
    if $TARGET_WLAN_SUPPORT_MOBILEAP_WIFISHARING_LITE; then
        # Check for target flag instead as we've already took care of this SPF above
        if ! $TARGET_WLAN_SUPPORT_MOBILEAP_POWER_SAVEMODE; then
            APPLY_PATCH "system" "system/framework/semwifi-service.jar" \
                "$MODPATH/wifi/power_savemode/semwifi-service.jar/0003-Enable-MOBILEAP_WIFISHARING_LITE-support.patch"
        else
            APPLY_PATCH "system" "system/framework/semwifi-service.jar" \
                "$MODPATH/wifi/wifisharing/semwifi-service.jar/0002-Enable-MOBILEAP_WIFISHARING_LITE-support.patch"
        fi
        SMALI_PATCH "system" "system/framework/semwifi-service.jar" \
            "smali/com/samsung/android/server/wifi/ap/SemSoftApConfiguration.smali" "replaceall" \
            "SPF_WS_Lite=false" \
            "SPF_WS_Lite=true"
    fi
else
    if ! $TARGET_WLAN_SUPPORT_MOBILEAP_WIFISHARING_LITE; then
        # TODO handle this condition
        LOG_MISSING_PATCHES "SOURCE_WLAN_SUPPORT_MOBILEAP_WIFISHARING_LITE" "TARGET_WLAN_SUPPORT_MOBILEAP_WIFISHARING_LITE"
    fi
fi

# SEC_PRODUCT_FEATURE_WLAN_SUPPORT_TWT_CONTROL
# SEC_PRODUCT_FEATURE_WLAN_SUPPORT_LOWLATENCY
if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ]; then
    if $SOURCE_WLAN_SUPPORT_TWT_CONTROL && ! $TARGET_WLAN_SUPPORT_TWT_CONTROL; then
        # One UI 9 obtains TWT feature bits from the vendor, not the old default
        # map. Treat TWT and LOWLATENCY as independent target capabilities.
        SMALI_PATCH "system" "system/framework/semwifi-service.jar" \
            "smali/com/samsung/android/server/wifi/driver/WifiDriverFeatureProvider.smali" "return" \
            "isTwtSupported()Z" "false"
    elif ! $SOURCE_WLAN_SUPPORT_TWT_CONTROL && $TARGET_WLAN_SUPPORT_TWT_CONTROL; then
        LOG_MISSING_PATCHES "SOURCE_WLAN_SUPPORT_TWT_CONTROL" "TARGET_WLAN_SUPPORT_TWT_CONTROL"
    fi
    if ! $SOURCE_WLAN_SUPPORT_LOWLATENCY && $TARGET_WLAN_SUPPORT_LOWLATENCY; then
        LOG_MISSING_PATCHES "SOURCE_WLAN_SUPPORT_LOWLATENCY" "TARGET_WLAN_SUPPORT_LOWLATENCY"
    fi
elif $SOURCE_WLAN_SUPPORT_TWT_CONTROL && $SOURCE_WLAN_SUPPORT_LOWLATENCY; then
    if ! $TARGET_WLAN_SUPPORT_TWT_CONTROL; then
        APPLY_PATCH "system" "system/framework/semwifi-service.jar" \
            "$MODPATH/wifi/twt_control/semwifi-service.jar/0001-Disable-TWT_CONTROL-support.patch"

        if ! $TARGET_WLAN_SUPPORT_LOWLATENCY; then
            APPLY_PATCH "system" "system/framework/semwifi-service.jar" \
                "$MODPATH/wifi/twt_control/semwifi-service.jar/0002-Disable-LOWLATENCY-support.patch"
        fi
    elif ! $TARGET_WLAN_SUPPORT_LOWLATENCY; then
        APPLY_PATCH "system" "system/framework/semwifi-service.jar" \
            "$MODPATH/wifi/lowlatency/semwifi-service.jar/0001-Disable-LOWLATENCY-support.patch"
    fi
else
    if ! $SOURCE_WLAN_SUPPORT_TWT_CONTROL && $TARGET_WLAN_SUPPORT_TWT_CONTROL; then
        # TODO handle this condition
        LOG_MISSING_PATCHES "SOURCE_WLAN_SUPPORT_TWT_CONTROL" "TARGET_WLAN_SUPPORT_TWT_CONTROL"
    elif ! $SOURCE_WLAN_SUPPORT_LOWLATENCY && $TARGET_WLAN_SUPPORT_LOWLATENCY; then
        # TODO handle this condition
        LOG_MISSING_PATCHES "SOURCE_WLAN_SUPPORT_LOWLATENCY" "TARGET_WLAN_SUPPORT_LOWLATENCY"
    fi
fi

if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ] && \
        $SOURCE_WLAN_SUPPORT_LOWLATENCY && ! $TARGET_WLAN_SUPPORT_LOWLATENCY; then
    # One UI 9 reads the vendor optimizer bitmask instead of an API36 default
    # map. Clear bit 0 only: dynamic/enhanced scan capability bits are distinct.
    SMALI_PATCH "system" "system/framework/semwifi-service.jar" \
        "smali/com/samsung/android/server/wifi/driver/WifiDriverFeatureProvider.smali" "replace" \
        "getOptimizerFeature()I" "return p0" \
        $'    and-int/lit8 p0, p0, -0x2\n\n    return p0'
fi

# SEC_PRODUCT_FEATURE_WLAN_SUPPORT_SWITCH_FOR_INDIVIDUAL_APPS
if $SOURCE_WLAN_SUPPORT_SWITCH_FOR_INDIVIDUAL_APPS; then
    if ! $TARGET_WLAN_SUPPORT_SWITCH_FOR_INDIVIDUAL_APPS; then
        APPLY_PATCH "system" "system/framework/semwifi-service.jar" \
            "$MODPATH/wifi/individual_apps/semwifi-service.jar/0001-Disable-SWITCH_FOR_INDIVIDUAL_APPS-support.patch"
    fi
else
    if $TARGET_WLAN_SUPPORT_SWITCH_FOR_INDIVIDUAL_APPS; then
        # TODO handle this condition
        LOG_MISSING_PATCHES "SOURCE_WLAN_SUPPORT_SWITCH_FOR_INDIVIDUAL_APPS" "TARGET_WLAN_SUPPORT_SWITCH_FOR_INDIVIDUAL_APPS"
    fi
fi

# SEC_PRODUCT_FEATURE_WLAN_SUPPORT_WIFI_TO_CELLULAR
if ! $SOURCE_WLAN_SUPPORT_WIFI_TO_CELLULAR && $TARGET_WLAN_SUPPORT_WIFI_TO_CELLULAR; then
    SMALI_PATCH "system" "system/framework/semwifi-service.jar" \
        "smali/com/samsung/android/server/wifi/SemFrameworkFacade.smali" "return" \
        "isWifiToCellularSupported()Z" \
        "true"
elif $SOURCE_WLAN_SUPPORT_WIFI_TO_CELLULAR && ! $TARGET_WLAN_SUPPORT_WIFI_TO_CELLULAR; then
    SMALI_PATCH "system" "system/framework/semwifi-service.jar" \
        "smali/com/samsung/android/server/wifi/SemFrameworkFacade.smali" "return" \
        "isWifiToCellularSupported()Z" \
        "false"
fi

unset TARGET_FIRMWARE_PATH
unset PRODUCT_DISPLAY_SMALI_DIR PRODUCT_TELEPHONY_SMALI_DIR PRODUCT_REFRESH_DUMP_METHOD \
    PRODUCT_RESOLUTION_PROFILE PRODUCT_OPTICAL_PROFILE
unset -f GET_FINGERPRINT_SENSOR_TYPE LOG_MISSING_PATCHES
