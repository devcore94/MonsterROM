NFC_ANTENNA()
{
    perl - "$@" <<'PERL'
use strict;
use warnings;
use JSON::PP;
use File::Find;
use File::Path qw(make_path);
use File::Basename qw(dirname basename);
use File::Temp qw(tempfile tempdir);
use File::Spec;
sub need($$) { die "UN1CA: $_[1]\n" unless $_[0] }
sub raw { open my $f,'<:raw',$_[0] or die "$_[0]: $!\n"; local $/; return <$f>//'' }
sub same { JSON::PP->new->canonical->encode($_[0]) eq JSON::PP->new->canonical->encode($_[1]) }
sub put {
    my($path,$data)=@_; return if -f $path && raw($path) eq $data;
    make_path(dirname($path)); my($f,$name)=tempfile('.unica-native-XXXXXX',DIR=>dirname($path),UNLINK=>0);
    binmode $f; print $f $data or die "write $path: $!"; close $f or die "close $path: $!";
    chmod((-e $path ? (stat($path))[2]&0777 : 0644),$name) or die "chmod $name: $!";
    rename($name,$path) or die "rename $path: $!";
}
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
sub methods { my($text)=@_; my %m; while($text =~ /^(\.method [^\n]+\n.*?^\.end method)/msg) {my $raw=$1; my($first)=split /\n/,$raw; my($name)=$first =~ /(\S+)$/; need(!exists $m{$name},"Duplicate method $name"); $m{$name}=$raw} return \%m }
sub once { my($text,$old,$new)=@_; my $count=()=$text =~ /\Q$old\E/g; need($count==1,"Expected one exact anchor, found $count: $old"); $text =~ s/\Q$old\E/$new/; return $text }
my($decoded,$apk,$position)=@ARGV;
my %resources=(0=>"center",1=>"center",2=>"above",3=>"bottom",4=>"above_mid",5=>"right_top",6=>"left",7=>"right",8=>"above",9=>"above_mid",10=>"flex",11=>"right_center",12=>"bottom",13=>"flip",14=>"right_top_port_tab",15=>"left_dcm",16=>"right_top_port",17=>"right_center_delta",18=>"center_tab",19=>"flip_b5",20=>"flip_b6",21=>"flex_q6",22=>"active5pro",27=>"antenna_animation");
need($position =~ /^(?:0|[1-9][0-9]*)$/ && exists $resources{$position},"Unreviewed target NFC antenna position");
my $base="$decoded/smali_classes3/com/samsung/android/settings/nfc"; my $enum=raw("$base/NfcAntennaInfo.smali");
my $count=()=$enum =~ /new-instance v0, Lcom\/samsung\/android\/settings\/nfc\/NfcAntennaInfo;/g;
need($count==1 && index($enum,"0x7f140087")>=0,"Unexpected One UI 9 NFC DEFAULT animation contract");
my %owners=(NfcSettings=>"populateViewForOrientation(Lcom/android/settingslib/widget/LayoutPreference;)V",NfcAntennaGuideDialog=>"onCreate(Landroid/os/Bundle;)V"); my %writes;
for my $owner(sort keys %owners) {
    my $path="$base/$owner.smali"; my $text=raw($path); my $m=methods($text); my $signature=$owners{$owner}; need(exists $m->{$signature},"Missing NFC method $signature"); my $body=$m->{$signature};
    for my $anchor("ro.vendor.nfc.info.antpos","SEC_PRODUCT_FEATURE_NFC_CONFIG_ANTENNA_POSITION Value="," must be equal to value of ro.vendor.nfc.info.antpos=") {need(index($body,$anchor)>=0,"Missing original NFC antenna validation")}
    my $n=($body =~ s/^    const-string v1, "(?:27|\Q$position\E)"$/    const-string v1, "$position"/mg);
    need($n==1,"Unexpected inlined NFC antenna position"); $writes{$path}=once($text,$m->{$signature},$body);
}
my $animation="sec_nfc_antenna_animation.json"; my @actual=grep {m{/raw[^/]*/\Q$animation\E$}} walk("$decoded/res");
need(same(\@actual,[sort "$decoded/res/raw/$animation","$decoded/res/raw-night/$animation"]),"Unexpected One UI 9 day/night animation layout");
my @members=split /\n/,run("unzip","-Z1",$apk); my $name=$position==27?"sec_nfc_antenna_animation.json":"sec_nfc_ant_$resources{$position}.json";
for my $q(qw(raw raw-night)) {
    my @names=("res/$q/$name"); push @names,"res/raw-night-v8/$name" if $q eq "raw-night"; my @matches=grep {my $n=$_; scalar grep {$_ eq $n} @members} @names;
    need(@matches==1,"Missing/ambiguous target NFC animation for $q"); my $data=run("unzip","-p",$apk,$matches[0]); my $j=decode_json($data);
    need(ref($j) eq "HASH" && !scalar(grep {!exists $j->{$_}} qw(v fr w h layers)),"Target NFC resource is not a Lottie composition");
    for my $asset(@{$j->{assets}//[]}) {need(!($asset->{p}//"") || $asset->{p}=~/^data:/,"Target NFC animation needs external assets")}
    $writes{"$decoded/res/$q/$animation"}=$data;
}
put($_,$writes{$_}) for sort keys %writes;
PERL
}
# [
_LOG() { if $DEBUG; then LOGW "$1"; else ABORT "$1"; fi }
# ]

NFC_PREFLIGHT()
{
    local NFC_APEX_SHA256
    NFC_APEX_SHA256="$(sha256sum "$WORK_DIR/system/system/apex/com.android.nfcservices.capex" | cut -d ' ' -f 1)"
    # Keep the complete signed APK/framework/JNI cohort. Admit only reviewed
    # package hashes; see NFC-APEX.md before adding another one.
    case "$NFC_APEX_SHA256" in
        408f490bf488a6ef364ed0d1d1c249a7546fe6cec1efecfce6552c9192dab597|\
        00a29b4a9f83cf07746400613e0fa0910c50836e17ab92928a2c9651ed921ae0) ;;
        *)
            ABORT "Unreviewed One UI 9 NFC APEX (SHA-256: ${NFC_APEX_SHA256:-unreadable}); review the modular NFC/target HIDL contract"
            return 1
            ;;
    esac
    if [ ! -s "$WORK_DIR/vendor/bin/hw/nxp.android.hardware.nfc@1.2-service" ] || \
            [ ! -s "$WORK_DIR/vendor/lib64/nfc_nci_nxpsn.so" ]; then
        ABORT "One UI 9 NFC requires the target NXP HIDL 1.2 service and 64-bit NFC library"
        return 1
    fi
    if ! python3 - "$WORK_DIR/vendor/etc/vintf/manifest/nxp.android.hardware.nfc@1.2-service.xml" <<'PY'
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

try:
    xml = Path(sys.argv[1]).read_text()
    if "<!DOCTYPE" in xml or "<!ENTITY" in xml:
        raise ValueError("Unsupported VINTF declarations")
    root = ET.fromstring(xml)
    hals = [hal for hal in root.findall("hal")
            if (hal.findtext("name") or "").strip() == "android.hardware.nfc"]
    valid = root.tag == "manifest" and root.get("type") == "device" and len(hals) == 1
    if valid:
        hal = hals[0]
        versions = [(value.text or "").strip() for value in hal.findall("version")]
        fqnames = [(value.text or "").strip() for value in hal.findall("fqname")]
        interfaces = [((item.findtext("name") or "").strip(),
                       [(value.text or "").strip() for value in item.findall("instance")])
                      for item in hal.findall("interface")]
        legacy = versions == ["1.2"] and interfaces == [("INfc", ["default"])] and not fqnames
        qualified = fqnames == ["@1.2::INfc/default"] and not versions and not interfaces
        valid = (hal.get("format") == "hidl"
                 and (hal.findtext("transport") or "").strip() == "hwbinder"
                 and (legacy or qualified))
    if not valid:
        raise ValueError("Expected android.hardware.nfc@1.2::INfc/default over hwbinder")
except (OSError, ValueError, ET.ParseError) as error:
    sys.exit(f"One UI 9 NFC VINTF: {error}")
PY
    then
        ABORT "Review the modular One UI 9 NFC/target HIDL contract: incompatible target VINTF manifest"
        return 1
    fi
}

TARGET_FIRMWARE_PATH="$(cut -d "/" -f 1 -s <<< "$TARGET_FIRMWARE")_$(cut -d "/" -f 2 -s <<< "$TARGET_FIRMWARE")"

# Fail before copying target configuration or decoding Settings, including when
# this module is sourced from a conditional that suppresses Bash errexit.
if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ]; then
    NFC_PREFLIGHT || return 1
fi
unset -f NFC_PREFLIGHT

if [ -f "$FW_DIR/$TARGET_FIRMWARE_PATH/system/system/etc/libnfc-nci.conf" ]; then
    ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/etc/libnfc-nci.conf" 0 0 644 "u:object_r:system_file:s0"
else
    DELETE_FROM_WORK_DIR "system" "system/etc/libnfc-nci.conf"
fi
if [ -f "$FW_DIR/$TARGET_FIRMWARE_PATH/system/system/etc/libnfc-nci_temp.conf" ]; then
    ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/etc/libnfc-nci_temp.conf" 0 0 644 "u:object_r:system_file:s0"
else
    DELETE_FROM_WORK_DIR "system" "system/etc/libnfc-nci_temp.conf"
fi

# Android 17 ships a complete, matched NFC APK/framework/JNI cohort in an
# APEX. Its inspected adaptation still implements HIDL 1.0/1.1/1.2. The S21
# already has the matching NXP 1.2 service and vendor driver; do not request
# obsolete global 32-bit JNI prebuilts or mix an older app into that APEX.
if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ]; then
    LOG "- Retaining the complete One UI 9 NFC APEX with the target NXP HIDL 1.2 service"
    # Settings is outside the NFC APEX. Its inlined donor antenna position and
    # animation must describe the target, while its mismatch checks stay intact.
    NFC_ANTENNA_POSITION="$(GET_PROP "vendor" "ro.vendor.nfc.info.antpos")"
    if ! [[ "$NFC_ANTENNA_POSITION" =~ ^[0-9]+$ ]]; then
        ABORT "One UI 9 NFC Settings requires a numeric target vendor antenna position"
        return 1
    fi
    DECODE_APK "system" "system/priv-app/SecSettings/SecSettings.apk" || return 1
    NFC_ANTENNA "$APKTOOL_DIR/system/priv-app/SecSettings/SecSettings.apk" \
        "$FW_DIR/$TARGET_FIRMWARE_PATH/system/system/priv-app/SecSettings/SecSettings.apk" "$NFC_ANTENNA_POSITION" || return 1
    unset NFC_ANTENNA_POSITION
    unset TARGET_FIRMWARE_PATH
    unset -f _LOG
    return 0
fi

if [ "$(GET_PROP "vendor" "ro.vendor.nfc.feature.chipname")" ]; then
    if [[ "$(GET_PROP "vendor" "ro.vendor.nfc.feature.chipname")" == "NXP_PN553" ]]; then
        SET_PROP "vendor" "ro.vendor.nfc.feature.chipname" "NXP_SN100U"
    fi
    if ! [[ "$(GET_PROP "vendor" "ro.vendor.nfc.feature.chipname")" =~ NXP_SN100U|SLSI|STM_ST21 ]]; then
        _LOG "Unknown NFC chip name: $(GET_PROP "vendor" "ro.vendor.nfc.feature.chipname")"
        return 0
    fi
fi

# SEC_PRODUCT_FEATURE_NFC_CHIP_NAME:=NXP_SN100U/NXP_PN553
# - API 35 and below: libnfc_nxpsn_jni.so/libnfc_nxppn_jni.so
# - API 36: libnfc_nci_jni.so
#
# Use NXP_SN100U blobs for devices with legacy NXP_PN553 impl.
if [ -f "$WORK_DIR/system/system/lib/libnfc_nci_jni.so" ]; then
    if [ ! -f "$FW_DIR/$TARGET_FIRMWARE_PATH/system/system/lib/libnfc_nci_jni.so" ] && \
            [ ! -f "$FW_DIR/$TARGET_FIRMWARE_PATH/system/system/lib64/libnfc_nxppn_jni.so" ] && \
            [ ! -f "$FW_DIR/$TARGET_FIRMWARE_PATH/system/system/lib64/libnfc_nxpsn_jni.so" ] && \
            [ ! -f "$WORK_DIR/vendor/lib/nfc_nci_nxpsn.so" ] && \
            [ ! -f "$WORK_DIR/vendor/lib/nfc_nci_nxp.so" ] && \
            [ ! -f "$WORK_DIR/vendor/lib64/nfc_nci_nxpsn.so" ] && \
            [ ! -f "$WORK_DIR/vendor/lib64/nfc_nci_nxp.so" ]; then
        DELETE_FROM_WORK_DIR "system" "system/lib/libnfc_nci_jni.so"
        DELETE_FROM_WORK_DIR "system" "system/lib/libnfc_prop_extn.so"
        DELETE_FROM_WORK_DIR "system" "system/lib/libnfc_vendor_extn.so"
    fi
elif [ -f "$FW_DIR/$TARGET_FIRMWARE_PATH/system/system/lib/libnfc_nci_jni.so" ]; then
    ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/lib/libnfc_nci_jni.so" 0 0 644 "u:object_r:system_lib_file:s0"
    ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/lib/libnfc_prop_extn.so" 0 0 644 "u:object_r:system_lib_file:s0"
    ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/lib/libnfc_vendor_extn.so" 0 0 644 "u:object_r:system_lib_file:s0"
elif [ -f "$FW_DIR/$TARGET_FIRMWARE_PATH/system/system/lib64/libnfc_nxpsn_jni.so" ]; then
    # TODO
    _LOG "Missing prebuilt blobs for NXP_SN100U NFC chip"
    return 0
fi
if [ -f "$WORK_DIR/system/system/lib64/libnfc_nci_jni.so" ]; then
    if [ ! -f "$FW_DIR/$TARGET_FIRMWARE_PATH/system/system/lib64/libnfc_nci_jni.so" ] && \
            [ ! -f "$FW_DIR/$TARGET_FIRMWARE_PATH/system/system/lib64/libnfc_nxppn_jni.so" ] && \
            [ ! -f "$FW_DIR/$TARGET_FIRMWARE_PATH/system/system/lib64/libnfc_nxpsn_jni.so" ] && \
            [ ! -f "$WORK_DIR/vendor/lib64/nfc_nci_nxpsn.so" ] && \
            [ ! -f "$WORK_DIR/vendor/lib64/nfc_nci_nxp.so" ]; then
        DELETE_FROM_WORK_DIR "system" "system/lib64/libnfc_nci_jni.so"
        DELETE_FROM_WORK_DIR "system" "system/lib64/libnfc_prop_extn.so"
        DELETE_FROM_WORK_DIR "system" "system/lib64/libnfc_vendor_extn.so"
    fi
elif [ -f "$FW_DIR/$TARGET_FIRMWARE_PATH/system/system/lib64/libnfc_nci_jni.so" ]; then
    ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/lib64/libnfc_nci_jni.so" 0 0 644 "u:object_r:system_lib_file:s0"
    ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/lib64/libnfc_prop_extn.so" 0 0 644 "u:object_r:system_lib_file:s0"
    ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/lib64/libnfc_vendor_extn.so" 0 0 644 "u:object_r:system_lib_file:s0"
elif [ -f "$FW_DIR/$TARGET_FIRMWARE_PATH/system/system/lib64/libnfc_nxpsn_jni.so" ]; then
    # TODO
    _LOG "Missing prebuilt blobs for NXP_SN100U NFC chip"
    return 0
fi

# SEC_PRODUCT_FEATURE_NFC_CHIP_NAME:=STM_ST21
# - API 35 and below: libnfc_st_jni.so
# - API 36: libstnfc_nci_jni.so
if [ -f "$WORK_DIR/system/system/lib/libstnfc_nci_jni.so" ]; then
    if [ ! -f "$FW_DIR/$TARGET_FIRMWARE_PATH/system/system/lib/libstnfc_nci_jni.so" ] && \
            [ ! -f "$FW_DIR/$TARGET_FIRMWARE_PATH/system/system/lib64/libnfc_st_jni.so" ]; then
        DELETE_FROM_WORK_DIR "system" "system/lib/libnfc_vendor_extn_st.so"
        DELETE_FROM_WORK_DIR "system" "system/lib/libstnfc_nci_jni.so"
    fi
elif [ -f "$FW_DIR/$TARGET_FIRMWARE_PATH/system/system/lib/libstnfc_nci_jni.so" ]; then
    ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/lib/libnfc_vendor_extn_st.so" 0 0 644 "u:object_r:system_lib_file:s0"
    ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/lib/libstnfc_nci_jni.so" 0 0 644 "u:object_r:system_lib_file:s0"
elif [ -f "$FW_DIR/$TARGET_FIRMWARE_PATH/system/system/lib64/libnfc_st_jni.so" ]; then
    ADD_TO_WORK_DIR "a17xxx" "system" "system/lib/libnfc_vendor_extn_st.so" 0 0 644 "u:object_r:system_lib_file:s0"
    ADD_TO_WORK_DIR "a17xxx" "system" "system/lib/libstnfc_nci_jni.so" 0 0 644 "u:object_r:system_lib_file:s0"
fi
if [ -f "$WORK_DIR/system/system/lib64/libstnfc_nci_jni.so" ]; then
    if [ ! -f "$FW_DIR/$TARGET_FIRMWARE_PATH/system/system/lib64/libstnfc_nci_jni.so" ] && \
            [ ! -f "$FW_DIR/$TARGET_FIRMWARE_PATH/system/system/lib64/libnfc_st_jni.so" ]; then
        DELETE_FROM_WORK_DIR "system" "system/lib64/libnfc_vendor_extn_st.so"
        DELETE_FROM_WORK_DIR "system" "system/lib64/libstnfc_nci_jni.so"
    fi
elif [ -f "$FW_DIR/$TARGET_FIRMWARE_PATH/system/system/lib64/libstnfc_nci_jni.so" ]; then
    ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/lib64/libnfc_vendor_extn_st.so" 0 0 644 "u:object_r:system_lib_file:s0"
    ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/lib64/libstnfc_nci_jni.so" 0 0 644 "u:object_r:system_lib_file:s0"
elif [ -f "$FW_DIR/$TARGET_FIRMWARE_PATH/system/system/lib64/libnfc_st_jni.so" ]; then
    ADD_TO_WORK_DIR "a17xxx" "system" "system/lib64/libnfc_vendor_extn_st.so" 0 0 644 "u:object_r:system_lib_file:s0"
    ADD_TO_WORK_DIR "a17xxx" "system" "system/lib64/libstnfc_nci_jni.so" 0 0 644 "u:object_r:system_lib_file:s0"
fi

# SEC_PRODUCT_FEATURE_NFC_CHIP_NAME:=SLSI
# - Same lib name as before, check for TARGET_PLATFORM_SDK_VERSION instead
if [ -f "$WORK_DIR/system/system/lib/libnfc_sec_jni.so" ]; then
    if [ ! -f "$FW_DIR/$TARGET_FIRMWARE_PATH/system/system/lib/libnfc_sec_jni.so" ] && \
            [ ! -f "$FW_DIR/$TARGET_FIRMWARE_PATH/system/system/lib64/libnfc_sec_jni.so" ] && \
            [ ! -f "$WORK_DIR/vendor/lib/nfc_nci_sec.so" ] && \
            [ ! -f "$WORK_DIR/vendor/lib64/nfc_nci_sec.so" ]; then
        DELETE_FROM_WORK_DIR "system" "system/lib/libnfc_sec_jni.so"
    fi
elif [ -f "$FW_DIR/$TARGET_FIRMWARE_PATH/system/system/lib/libnfc_sec_jni.so" ] || \
        [ -f "$FW_DIR/$TARGET_FIRMWARE_PATH/system/system/lib64/libnfc_sec_jni.so" ]; then
    if [ "$TARGET_PLATFORM_SDK_VERSION" -ge "36" ]; then
        ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/lib/libnfc_sec_jni.so" 0 0 644 "u:object_r:system_lib_file:s0"
    else
        ADD_TO_WORK_DIR "r11sxxx" "system" "system/lib/libnfc_sec_jni.so" 0 0 644 "u:object_r:system_lib_file:s0"
    fi
fi
if [ -f "$WORK_DIR/system/system/lib64/libnfc_sec_jni.so" ]; then
    if [ ! -f "$FW_DIR/$TARGET_FIRMWARE_PATH/system/system/lib64/libnfc_sec_jni.so" ] && \
            [ ! -f "$WORK_DIR/vendor/lib64/nfc_nci_sec.so" ]; then
        DELETE_FROM_WORK_DIR "system" "system/lib64/libnfc_sec_jni.so"
    fi
elif [ -f "$FW_DIR/$TARGET_FIRMWARE_PATH/system/system/lib64/libnfc_sec_jni.so" ]; then
    if [ "$TARGET_PLATFORM_SDK_VERSION" -ge "36" ]; then
        ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/lib64/libnfc_sec_jni.so" 0 0 644 "u:object_r:system_lib_file:s0"
    else
        ADD_TO_WORK_DIR "r11sxxx" "system" "system/lib64/libnfc_sec_jni.so" 0 0 644 "u:object_r:system_lib_file:s0"
    fi
fi

unset TARGET_FIRMWARE_PATH
unset -f _LOG
