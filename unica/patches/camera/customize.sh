CAMERA_COHORT()
{
    perl - "$@" <<'PERL'
use strict;
use warnings;
use JSON::PP;
use Digest::SHA qw(sha256_hex);
sub need($$) { die "UN1CA: $_[1]\n" unless $_[0] }
sub raw { open my $f,'<:raw',$_[0] or die "$_[0]: $!\n"; local $/; return <$f>//'' }
sub sha { sha256_hex(raw($_[0])) }
sub json { decode_json(raw($_[0])) }
my %args; while(@ARGV) {my $key=shift @ARGV; need(($key eq '--target'||$key eq '--work') && @ARGV,'Expected Camera target/work paths'); $args{$key}=shift @ARGV}
my $cohort=json("$ENV{SRC_DIR}/unica/patches/camera/mass/cohort.json");
for my $scope(qw(target work)) {my $root=$args{"--$scope"}; need(defined($root),'Missing Camera cohort root'); for my $name(keys %{$cohort->{$scope}}) {my $p="$root/$name"; need(-f $p,"Missing mass Camera cohort member: $p"); need(sha($p) eq $cohort->{$scope}{$name},"Unreviewed mass Camera cohort member: $p")}}
PERL
}
CAMERA_RECORDING_DEFAULTS()
{
    "${BASH_SOURCE[0]%/*}/../../../scripts/run_xml_perl.sh" - "$@" <<'PERL'
use strict;
use warnings;
use File::Path qw(make_path);
use File::Basename qw(dirname basename);
use File::Temp qw(tempfile tempdir);
use XML::Parser;
sub need($$) { die "UN1CA: $_[1]\n" unless $_[0] }
sub raw { open my $f,'<:raw',$_[0] or die "$_[0]: $!\n"; local $/; return <$f>//'' }
sub put {
    my($path,$data)=@_; return if -f $path && raw($path) eq $data;
    make_path(dirname($path)); my($f,$name)=tempfile('.unica-native-XXXXXX',DIR=>dirname($path),UNLINK=>0);
    binmode $f; print $f $data or die "write $path: $!"; close $f or die "close $path: $!";
    chmod((-e $path ? (stat($path))[2]&0777 : 0644),$name) or die "chmod $name: $!";
    rename($name,$path) or die "rename $path: $!";
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
sub node_raw { my($doc,$node)=@_; return substr($doc->{data},$node->{start},$node->{end}-$node->{start}) }
sub edit_xml { my($doc,$edits)=@_; my $data=$doc->{data}; for my $e(sort {$b->[0]<=>$a->[0]} @$edits) {substr($data,$e->[0],$e->[1]-$e->[0])=$e->[2]} xml($data,0); return $data }
my($path)=@ARGV; my $text=raw($path); my $doc=xml($text,1); my @nodes;
sub locals {my($n)=@_; push @nodes,$n if $n->{tag} eq "local"; locals($_) for @{$n->{children}}}
locals($doc->{root}); my @edits;
for my $name(qw(BACK_CAMERA_RECORDING_DEFAULT_RESOLUTION FRONT_CAMERA_RECORDING_DEFAULT_RESOLUTION)) {
    my @found=grep {($_->{attrs}{name}//"") eq $name} @nodes; need(@found<=1,"Ambiguous Camera recording default: $name"); next unless @found;
    my $value=$found[0]{attrs}{value}//""; next unless $value =~ /^[0-9]+x[0-9]+_AUTO$/; my $replacement=node_raw($doc,$found[0]);
    my $count=($replacement =~ s/(\bvalue=")\Q$value\E(")/$1.substr($value,0,-5).$2/e); need($count==1,"Unexpected Camera recording-default XML: $name");
    push @edits,[$found[0]{start},$found[0]{end},$replacement];
}
my $out=edit_xml($doc,\@edits); xml($out,1); put($path,$out);
PERL
}
# [
_LOG() { if $DEBUG; then LOGW "$1"; else ABORT "$1"; fi }

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

# Refuse an unsafe host parser before replacing Camera inputs.
"${BASH_SOURCE[0]%/*}/../../../scripts/run_xml_perl.sh" --check || return 1

SOURCE_FIRMWARE_PATH="$(cut -d "/" -f 1 -s <<< "$SOURCE_FIRMWARE")_$(cut -d "/" -f 2 -s <<< "$SOURCE_FIRMWARE")"
TARGET_FIRMWARE_PATH="$(cut -d "/" -f 1 -s <<< "$TARGET_FIRMWARE")_$(cut -d "/" -f 2 -s <<< "$TARGET_FIRMWARE")"
CAMERA_APP_COHORT="source"

# Select the app before its first decode. Replacing an APK after APPLY_PATCH
# leaves a decoded source app which would overwrite the selected mass app.
if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ] && \
        [[ "$SOURCE_CAMERA_SUPPORT_MASS_APP_FLAVOR" != "$TARGET_CAMERA_SUPPORT_MASS_APP_FLAVOR" ]]; then
    if ! $SOURCE_CAMERA_SUPPORT_MASS_APP_FLAVOR && $TARGET_CAMERA_SUPPORT_MASS_APP_FLAVOR && \
            [ "$TARGET_CODENAME" = "r9s" ] && [ "$TARGET_PLATFORM_SDK_VERSION" -eq 36 ]; then
        # Select the app before decoding it, retaining its matched JNI cohort.
        if [ -e "$APKTOOL_DIR/system/priv-app/SamsungCamera/SamsungCamera.apk" ]; then
            ABORT "Select r9s mass Camera before decoding SamsungCamera (existing decode preserved)"
            return 1
        fi
        CAMERA_COHORT --target "$FW_DIR/$TARGET_FIRMWARE_PATH" --work "$WORK_DIR"
        ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" \
            "system/lib64/libAIQSolution_MPI.camera.samsung.so" 0 0 644 "u:object_r:system_lib_file:s0"
        ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" \
            "system/lib64/libMultiFrameProcessing30.snapwrapper.camera.samsung.so" 0 0 644 "u:object_r:system_lib_file:s0"
        for CAMERA_MASS_LIBRARY in libAIQSolution_MPI.camera.samsung.so libMultiFrameProcessing30.camera.samsung.so \
                libLocalTM_pcc.camera.samsung.so libSwIsp_wrapper_v1.camera.samsung.so; do
            if ! grep -Fxq "$CAMERA_MASS_LIBRARY" "$WORK_DIR/system/system/etc/public.libraries-camera.samsung.txt"; then
                printf '%s\n' "$CAMERA_MASS_LIBRARY" >> "$WORK_DIR/system/system/etc/public.libraries-camera.samsung.txt"
            fi
        done
        unset CAMERA_MASS_LIBRARY
        LOG "- Selecting the reviewed r9s mass Camera app/native cohort"
        DELETE_FROM_WORK_DIR "system" "system/priv-app/SamsungCamera"
        ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" \
            "system/priv-app/SamsungCamera/SamsungCamera.apk" 0 0 644 "u:object_r:system_file:s0"
        CAMERA_APP_COHORT="mass-sdk36-r9s"
    else
        ABORT "Unreviewed One UI 9 Camera flavor transition"
        return 1
    fi
fi

DELETE_FROM_WORK_DIR "system" "system/cameradata/portrait_data"
ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/cameradata/portrait_data" 0 0 755 "u:object_r:system_file:s0"
if [ -f "$SRC_DIR/target/$TARGET_CODENAME/camera/singletake/service-feature.xml" ]; then
    LOG "- Adding /system/system/cameradata/singletake/service-feature.xml"
    EVAL "cp -a \"$SRC_DIR/target/$TARGET_CODENAME/camera/singletake/service-feature.xml\" \"$WORK_DIR/system/system/cameradata/singletake/service-feature.xml\""
else
    ADD_TO_WORK_DIR "$TARGET_FIRMWARE" \
        "system" "system/cameradata/singletake/service-feature.xml" 0 0 644 "u:object_r:system_file:s0"
fi
if [ -f "$SRC_DIR/target/$TARGET_CODENAME/camera/aremoji-feature.xml" ]; then
    LOG "- Adding /system/system/cameradata/aremoji-feature.xml"
    EVAL "cp -a \"$SRC_DIR/target/$TARGET_CODENAME/camera/aremoji-feature.xml\" \"$WORK_DIR/system/system/cameradata/aremoji-feature.xml\""
else
    ADD_TO_WORK_DIR "$TARGET_FIRMWARE" \
        "system" "system/cameradata/aremoji-feature.xml" 0 0 644 "u:object_r:system_file:s0"
fi
if [ -f "$SRC_DIR/target/$TARGET_CODENAME/camera/camera-feature.xml" ]; then
    LOG "- Adding /system/system/cameradata/camera-feature.xml"
    EVAL "cp -a \"$SRC_DIR/target/$TARGET_CODENAME/camera/camera-feature.xml\" \"$WORK_DIR/system/system/cameradata/camera-feature.xml\""
elif [[ "$SOURCE_PLATFORM_SDK_VERSION" == "$TARGET_PLATFORM_SDK_VERSION" ]] || \
        [ "$CAMERA_APP_COHORT" = "mass-sdk36-r9s" ]; then
    # The mass app and this XML are from the same target build. The system's
    # SDK is not the Camera configuration parser's version.
    ADD_TO_WORK_DIR "$TARGET_FIRMWARE" \
        "system" "system/cameradata/camera-feature.xml" 0 0 644 "u:object_r:system_file:s0"
else
    _LOG "File not found: $SRC_DIR/target/$TARGET_CODENAME/camera/camera-feature.xml"
fi

LOG_STEP_IN
if grep -q "DURING_SMARTVIEW" "$WORK_DIR/system/system/cameradata/camera-feature.xml" 2> /dev/null; then
    LOG "- Removing Smart View limitations flags"
    EVAL "sed -i \"/DURING_SMARTVIEW/d\" \"$WORK_DIR/system/system/cameradata/camera-feature.xml\""
fi
if [ "$(GET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_GRAPHICS_SUPPORT_3D_SURFACE_TRANSITION_FLAG")" ]; then
    if grep -q "SUPPORT_LIVE_BLUR" "$WORK_DIR/system/system/cameradata/camera-feature.xml" 2> /dev/null; then
        LOG "- Removing native blur disable flag"
        EVAL "sed -i \"/SUPPORT_LIVE_BLUR/d\" \"$WORK_DIR/system/system/cameradata/camera-feature.xml\""
    fi
fi
LOG_STEP_OUT

if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ] && [ "$CAMERA_APP_COHORT" = "source" ]; then
    LOG "- Matching Camera recording defaults to the One UI 9 resolution parser"
    CAMERA_RECORDING_DEFAULTS \
        "$WORK_DIR/system/system/cameradata/camera-feature.xml" || return 1
    APPLY_PATCH "system" "system/priv-app/SamsungCamera/SamsungCamera.apk" \
        "$MODPATH/SamsungCamera.apk/0001-Recheck-processor-state-after-timed-wait.patch"
    APPLY_PATCH "system" "system/priv-app/SamsungCamera/SamsungCamera.apk" \
        "$MODPATH/SamsungCamera.apk/0002-Accept-One-UI-9.5-with-the-camera-contract.patch"
fi

# Samsung Camera "hal3_mass-phone-release" app flavor
if [ "$CAMERA_APP_COHORT" = "mass-sdk36-r9s" ]; then
    APPLY_PATCH "system" "system/priv-app/SamsungCamera/SamsungCamera.apk" \
        "$MODPATH/mass/SamsungCamera.apk/0001-Recheck-processor-state-after-timed-wait.patch" || return 1
    APPLY_PATCH "system" "system/priv-app/SamsungCamera/SamsungCamera.apk" \
        "$MODPATH/mass/SamsungCamera.apk/0002-Port-stylus-UI-to-View-APIs.patch" || return 1
elif ! $SOURCE_CAMERA_SUPPORT_MASS_APP_FLAVOR; then
    if $TARGET_CAMERA_SUPPORT_MASS_APP_FLAVOR; then
        ADD_TO_WORK_DIR "r9qxxx" "system" "system/priv-app/SamsungCamera/SamsungCamera.apk" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "r9qxxx" "system" "system/priv-app/SamsungCamera/SamsungCamera.apk.prof" 0 0 644 "u:object_r:system_file:s0"
    fi
else
    if ! $TARGET_CAMERA_SUPPORT_MASS_APP_FLAVOR; then
        # TODO handle this condition
        LOG_MISSING_PATCHES "SOURCE_CAMERA_SUPPORT_MASS_APP_FLAVOR" "TARGET_CAMERA_SUPPORT_MASS_APP_FLAVOR"
    fi
fi

# Add/delete Snapchat CameraKit Plugin if SHOOTING_MODE_FUN is (not) available
if [ -f "$WORK_DIR/system/system/app/FunModeSDK/FunModeSDK.apk" ]; then
    if ! grep -q "SHOOTING_MODE_FUN" "$WORK_DIR/system/system/cameradata/camera-feature.xml" 2> /dev/null; then
        DELETE_FROM_WORK_DIR "system" "system/app/FunModeSDK"
    fi
else
    if grep -q "SHOOTING_MODE_FUN" "$WORK_DIR/system/system/cameradata/camera-feature.xml" 2> /dev/null; then
        ADD_TO_WORK_DIR "a73xqxx" "system" "system/app/FunModeSDK" 0 0 755 "u:object_r:system_file:s0"
    fi
fi

# Single take "stp1-release" app flavor
if grep -q "SUPPORT_SINGLE_TAKE_HIGHLIGHT_VIDEOS.*true" "$FW_DIR/$SOURCE_FIRMWARE_PATH/system/system/cameradata/camera-feature.xml" 2> /dev/null && \
        ! grep -q "SUPPORT_SINGLE_TAKE_HIGHLIGHT_VIDEOS.*true" "$WORK_DIR/system/system/cameradata/camera-feature.xml" 2> /dev/null; then
    ADD_TO_WORK_DIR "a73xqxx" "system" "system/priv-app/SingleTakeService/SingleTakeService.apk" 0 0 644 "u:object_r:system_file:s0"
elif ! grep -q "SUPPORT_SINGLE_TAKE_HIGHLIGHT_VIDEOS.*true" "$FW_DIR/$SOURCE_FIRMWARE_PATH/system/system/cameradata/camera-feature.xml" 2> /dev/null && \
        grep -q "SUPPORT_SINGLE_TAKE_HIGHLIGHT_VIDEOS.*true" "$WORK_DIR/system/system/cameradata/camera-feature.xml" 2> /dev/null; then
    # TODO handle this condition
    # shellcheck disable=SC2034
    SOURCE_SUPPORT_SINGLE_TAKE_HIGHLIGHT_VIDEOS=false
    # shellcheck disable=SC2034
    TARGET_SUPPORT_SINGLE_TAKE_HIGHLIGHT_VIDEOS=true
    LOG_MISSING_PATCHES "SOURCE_SUPPORT_SINGLE_TAKE_HIGHLIGHT_VIDEOS" "TARGET_SUPPORT_SINGLE_TAKE_HIGHLIGHT_VIDEOS"
    unset SOURCE_SUPPORT_SINGLE_TAKE_HIGHLIGHT_VIDEOS TARGET_SUPPORT_SINGLE_TAKE_HIGHLIGHT_VIDEOS
fi

# SEC_PRODUCT_FEATURE_CAMERA_SINGLETAKE_SOLUTIONS
if ! grep -q "ENABLE_SINGLE_TAKE_LITE.*true" "$WORK_DIR/system/system/cameradata/singletake/service-feature.xml" 2>/dev/null && \
        ! grep -q "SUPPORT_SMART_CROP.*false" "$WORK_DIR/system/system/cameradata/singletake/service-feature.xml" 2>/dev/null; then
    if [ -d "$FW_DIR/$SOURCE_FIRMWARE_PATH/vendor/etc/singletake/SmartCrop" ]; then
        if [ ! -d "$WORK_DIR/vendor/etc/singletake/SmartCrop" ] || \
                [ "$TARGET_PLATFORM_SDK_VERSION" -lt "$SOURCE_PLATFORM_SDK_VERSION" ]; then
            ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" "vendor" \
                "etc/singletake/SmartCrop/SmartCrop.tflite" 0 0 644 "u:object_r:vendor_configs_file:s0"
        fi
    elif [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ] && \
            [ -f "$FW_DIR/$TARGET_FIRMWARE_PATH/vendor/etc/singletake/SmartCrop/SmartCrop.tflite" ]; then
        # Select the existing One UI 9 GPU reader, retaining inference and errors.
        SMART_CROP_GPU()
        {
            local APK="system/priv-app/SingleTakeService/SingleTakeService.apk"
            local MODEL="etc/singletake/SmartCrop/SmartCrop.tflite"
            local LIB="lib/arm64-v8a/libfixsal.so"
            local TARGET_ROOT="$FW_DIR/$TARGET_FIRMWARE_PATH"
            local NATIVE BEFORE_COUNT SNAP_HASH
            local BEFORE="ffff00a9ff0300f9680a40b9280100341f050071a1010054"
            local AFTER="ffff00a9ff0300f948008052280100341f050071a1010054"

            [ "$(sha256sum "$TARGET_ROOT/vendor/$MODEL" | cut -d ' ' -f 1)" = \
                "b96df58908394f2bcf451f3b1191bd6f70c6e6df8412841555b9a95daacfcacb" ] && \
                [ "$(unzip -p "$TARGET_ROOT/system/$APK" "$LIB" | sha256sum | cut -d ' ' -f 1)" = \
                "36745cd4fc0e344a1ab8deb41e81c0f3a0cafb75cf036c53a41daa633f088ba9" ] || {
                ABORT "Unreviewed SmartCrop target model/reader pair"
                return 1
            }
            SNAP_HASH="$(sha256sum "$WORK_DIR/system/system/lib64/libsnap_aidl.snap.samsung.so" | cut -d ' ' -f 1)"
            [[ "$SNAP_HASH" = "51e2e952e2ddfcad18581ef30773226581f40fb62f73e27a8ad4e1e16afaace1" || \
                "$SNAP_HASH" = "866697412890dd097ef20606d93d83f70e3cb4a2be83f2e1a1e9ab1ff8d26d6c" ]] && \
                cmp -s "$WORK_DIR/system/system/lib64/libsnap_aidl.snap.samsung.so" \
                    "$TARGET_ROOT/system/system/lib64/libsnap_aidl.snap.samsung.so" && \
                [ "$(sha256sum "$WORK_DIR/system/system/lib64/libOpenCv.camera.samsung.so" | cut -d ' ' -f 1)" = \
                "a040f3c2d75958faf8118d535f991d7d28158a02b7846f15d0d02eae0b3acb49" ] || {
                ABORT "SmartCrop GPU route requires the inspected S21 SNAP V3 and OpenCV cohort"
                return 1
            }
            DECODE_APK "system" "$APK"
            NATIVE="$APKTOOL_DIR/system/priv-app/SingleTakeService/SingleTakeService.apk/$LIB"
            [ "$(sha256sum "$NATIVE" | cut -d ' ' -f 1)" = \
                "a03c626acd5e06c8182a488b8bccc89edb5d8e5f400517d99d4be2cec505edf8" ] || {
                ABORT "SmartCrop GPU selector requires the exact reviewed One UI 9 reader"
                return 1
            }
            BEFORE_COUNT="$(xxd -p -c 0 "$NATIVE" | { grep -o "$BEFORE" || true; } | wc -l)"
            [ "$BEFORE_COUNT" -eq 1 ] || {
                ABORT "Missing or ambiguous SmartCrop GPU selector"
                return 1
            }
            # SaliencySnapOps::openSnapSession, VA 0xea1c: ldr w8,[x19,#8]
            # -> mov w8,#2. The stock GPU path uses SnapOptionsV3/Open +0x38.
            LOG "- Selecting SmartCrop's existing S21 GPU/TFLite model route"
            HEX_PATCH "$NATIVE" "$BEFORE" "$AFTER" > /dev/null
            ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "vendor" "$MODEL" 0 0 644 "u:object_r:vendor_configs_file:s0"
        }
        SMART_CROP_GPU
        unset -f SMART_CROP_GPU
    else
        # TODO handle this condition
        # shellcheck disable=SC2034
        SOURCE_SUPPORT_SMART_CROP=false
        # shellcheck disable=SC2034
        TARGET_SUPPORT_SMART_CROP=true
        LOG_MISSING_PATCHES "SOURCE_SUPPORT_SMART_CROP" "TARGET_SUPPORT_SMART_CROP"
        unset SOURCE_SUPPORT_SMART_CROP TARGET_SUPPORT_SMART_CROP
    fi
else
    if [ -d "$WORK_DIR/vendor/etc/singletake/SmartCrop" ]; then
        DELETE_FROM_WORK_DIR "vendor" "etc/singletake/SmartCrop"
    fi
fi

# SEC_PRODUCT_FEATURE_CAMERA_CONFIG_ACTION_CLASSIFIER
if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ]; then
    if [ "$CAMERA_APP_COHORT" = "mass-sdk36-r9s" ]; then
        CAMERA_COHORT --target "$FW_DIR/$TARGET_FIRMWARE_PATH" --work "$WORK_DIR"
        CAMERA_CODEC_VALUE=",$(GET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_CAMERA_CONFIG_VENDOR_LIB_INFO"),"
        if [[ "$CAMERA_CODEC_VALUE" != *",image_codec.samsung.v1,"* ]] || \
                [[ "$CAMERA_CODEC_VALUE" == *",image_codec.samsung.v2,"* ]]; then
            ABORT "r9s mass Camera requires its reviewed image_codec.samsung.v1 selection"
            return 1
        fi
    else
        CAMERA_CODEC_FEATURE="SEC_FLOATING_FEATURE_CAMERA_CONFIG_VENDOR_LIB_INFO"
        CAMERA_CODEC_VALUE="$(GET_FLOATING_FEATURE_CONFIG "$CAMERA_CODEC_FEATURE")"
        if [[ ",$CAMERA_CODEC_VALUE," == *",image_codec.samsung.v1,"* ]]; then
            [ "$(unzip -p "$WORK_DIR/system/system/priv-app/SamsungCamera/SamsungCamera.apk" lib/arm64-v8a/libnode-jni.so | sha256sum | cut -d ' ' -f 1)" = \
                "aefcac75f02b9045a37244618e2e4e05198a6034f020b932a036b3c1157fa571" ] && \
                [ "$(sha256sum "$WORK_DIR/system/system/lib64/libsimba.media.samsung.so" | cut -d ' ' -f 1)" = \
                "127b601643c13f60c154a65d916f37a856cf4f3be7a33ae9f561f5b609577a37" ] && \
                [ "$(sha256sum "$WORK_DIR/system/system/lib64/libheifcapture.so" | cut -d ' ' -f 1)" = \
                "1f02483acc1351519e658619a1a799c96974bab2d37e48826914fe80160e29d1" ] && \
                [ "$(sha256sum "$WORK_DIR/system/system/apex/com.samsung.android.media.imagecodec.system.signed.apex" | cut -d ' ' -f 1)" = \
                "b312ae8f7229d34be555bec1df296117d4805cbd798336f60ad202bfb596617b" ] || {
                ABORT "Camera v2 node requires the reviewed matching One UI 9 ImageCodec/Simba provider cohort"
                return 1
            }
            CAMERA_CODEC_VALUE=",$CAMERA_CODEC_VALUE,"
            CAMERA_CODEC_VALUE="${CAMERA_CODEC_VALUE/,image_codec.samsung.v1,/,image_codec.samsung.v2,}"
            CAMERA_CODEC_VALUE="${CAMERA_CODEC_VALUE#,}"
            SET_FLOATING_FEATURE_CONFIG "$CAMERA_CODEC_FEATURE" "${CAMERA_CODEC_VALUE%,}"
        fi
    fi
    unset CAMERA_CODEC_FEATURE CAMERA_CODEC_VALUE
fi

SOURCE_CAMERA_CONFIG_ACTION_CLASSIFIER="$(GET_FLOATING_FEATURE_CONFIG "$FW_DIR/$SOURCE_FIRMWARE_PATH/system/system/etc/floating_feature.xml" "SEC_FLOATING_FEATURE_CAMERA_CONFIG_ACTION_CLASSIFIER")"
TARGET_CAMERA_CONFIG_ACTION_CLASSIFIER="$(GET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_CAMERA_CONFIG_ACTION_CLASSIFIER")"
if [ "$SOURCE_CAMERA_CONFIG_ACTION_CLASSIFIER" ]; then
    if [ "$TARGET_CAMERA_CONFIG_ACTION_CLASSIFIER" ]; then
        if [ -d "$FW_DIR/$SOURCE_FIRMWARE_PATH/vendor/etc/singletake/dynamic_viewing" ]; then
            if [ -d "$WORK_DIR/vendor/etc/singletake/dynamic_viewing" ]; then
                DELETE_FROM_WORK_DIR "vendor" "etc/singletake/dynamic_viewing"
            fi
            ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" "vendor" "etc/singletake/dynamic_viewing" 0 2000 755 "u:object_r:vendor_configs_file:s0"
        else
            if [ ! -e "$WORK_DIR/system/system/lib64/libVideoClassifier.camera.samsung.so" ] && \
                    [ ! -e "$WORK_DIR/system/system/lib64/libtensorflowLite2_11_0_dynamic_camera.so" ] && \
                    [ ! -e "$FW_DIR/$SOURCE_FIRMWARE_PATH/system/system/lib64/libVideoClassifier.camera.samsung.so" ] && \
                    [ ! -e "$FW_DIR/$SOURCE_FIRMWARE_PATH/system/system/lib64/libtensorflowLite2_11_0_dynamic_camera.so" ]; then
                LOG "- Keeping original target dynamic-viewing assets; One UI 9 donor has no legacy classifier reader"
            else
                for CLASSIFIER_LIBRARY in libVideoClassifier.camera.samsung.so libOpenCv.camera.samsung.so; do
                    cmp -s "$WORK_DIR/system/system/lib64/$CLASSIFIER_LIBRARY" \
                        "$FW_DIR/$TARGET_FIRMWARE_PATH/system/system/lib64/$CLASSIFIER_LIBRARY" || {
                        ABORT "Action classifier requires its original target OpenCV/classifier ABI"
                        return 1
                    }
                done
                [ -s "$FW_DIR/$TARGET_FIRMWARE_PATH/system/system/lib64/libtensorflowLite2_11_0_dynamic_camera.so" ] && \
                    [ -d "$FW_DIR/$TARGET_FIRMWARE_PATH/vendor/etc/singletake/dynamic_viewing" ] || {
                    ABORT "Missing matched target action classifier runtime/models"
                    return 1
                }
                ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/lib64/libtensorflowLite2_11_0_dynamic_camera.so" \
                    0 0 644 "u:object_r:system_lib_file:s0"
                ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "vendor" "etc/singletake/dynamic_viewing" \
                    0 2000 755 "u:object_r:vendor_configs_file:s0"
                unset CLASSIFIER_LIBRARY
            fi
        fi
    else
        DELETE_FROM_WORK_DIR "system" "system/lib64/libVideoClassifier.camera.samsung.so"
        DELETE_FROM_WORK_DIR "system" "system/lib64/libtensorflowLite2_11_0_dynamic_camera.so"
    fi
else
    if [ "$TARGET_CAMERA_CONFIG_ACTION_CLASSIFIER" ]; then
        # TODO handle this condition
        LOG_MISSING_PATCHES "SOURCE_CAMERA_CONFIG_ACTION_CLASSIFIER" "TARGET_CAMERA_CONFIG_ACTION_CLASSIFIER"
    fi
fi

# SEC_PRODUCT_FEATURE_CAMERA_CONFIG_GPPM_SOLUTIONS
SOURCE_CAMERA_CONFIG_GPPM_SOLUTIONS="$(GET_FLOATING_FEATURE_CONFIG "$FW_DIR/$SOURCE_FIRMWARE_PATH/system/system/etc/floating_feature.xml" "SEC_FLOATING_FEATURE_CAMERA_CONFIG_GPPM_SOLUTIONS")"
TARGET_CAMERA_CONFIG_GPPM_SOLUTIONS="$(GET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_CAMERA_CONFIG_GPPM_SOLUTIONS")"
if [[ "$SOURCE_CAMERA_CONFIG_GPPM_SOLUTIONS" != "$TARGET_CAMERA_CONFIG_GPPM_SOLUTIONS" ]]; then
    if [ "$SOURCE_CAMERA_CONFIG_GPPM_SOLUTIONS" ]; then
        if [ ! "$TARGET_CAMERA_CONFIG_GPPM_SOLUTIONS" ] && \
                [ ! -f "$FW_DIR/$TARGET_FIRMWARE_PATH/system/system/priv-app/GlobalPostProcMgr/GlobalPostProcMgr.apk" ]; then
            DELETE_FROM_WORK_DIR "system" "system/etc/default-permissions/default-permissions-com.samsung.android.globalpostprocmgr.xml"
            DELETE_FROM_WORK_DIR "system" "system/etc/permissions/privapp-permissions-com.samsung.android.globalpostprocmgr.xml"
            DELETE_FROM_WORK_DIR "system" "system/priv-app/GlobalPostProcMgr"
        fi
        if [[ "$SOURCE_CAMERA_CONFIG_GPPM_SOLUTIONS" == *"startrail"* ]] && \
                [[ "$TARGET_CAMERA_CONFIG_GPPM_SOLUTIONS" != *"startrail"* ]]; then
            DELETE_FROM_WORK_DIR "system" "system/lib64/libstartrail.camera.samsung.so"
        elif [[ "$SOURCE_CAMERA_CONFIG_GPPM_SOLUTIONS" != *"startrail"* ]] && \
                [[ "$TARGET_CAMERA_CONFIG_GPPM_SOLUTIONS" == *"startrail"* ]]; then
            # TODO handle this condition
            LOG_MISSING_PATCHES "SOURCE_CAMERA_CONFIG_GPPM_SOLUTIONS" "TARGET_CAMERA_CONFIG_GPPM_SOLUTIONS"
        fi
        if [[ "$SOURCE_CAMERA_CONFIG_GPPM_SOLUTIONS" == *"motionclipper"* ]] && \
                [[ "$TARGET_CAMERA_CONFIG_GPPM_SOLUTIONS" != *"motionclipper"* ]]; then
            DELETE_FROM_WORK_DIR "system" "system/lib64/libdvs.camera.samsung.so"
        elif [[ "$SOURCE_CAMERA_CONFIG_GPPM_SOLUTIONS" != *"motionclipper"* ]] && \
                [[ "$TARGET_CAMERA_CONFIG_GPPM_SOLUTIONS" == *"motionclipper"* ]]; then
            # TODO handle this condition
            LOG_MISSING_PATCHES "SOURCE_CAMERA_CONFIG_GPPM_SOLUTIONS" "TARGET_CAMERA_CONFIG_GPPM_SOLUTIONS"
        fi
    else
        if [ "$TARGET_CAMERA_CONFIG_GPPM_SOLUTIONS" ]; then
            # TODO handle this condition
            LOG_MISSING_PATCHES "SOURCE_CAMERA_CONFIG_GPPM_SOLUTIONS" "TARGET_CAMERA_CONFIG_GPPM_SOLUTIONS"
        fi
    fi
fi

# SEC_PRODUCT_FEATURE_CAMERA_SUPPORT_SDK_SERVICE
if $SOURCE_CAMERA_SUPPORT_SDK_SERVICE; then
    if ! $TARGET_CAMERA_SUPPORT_SDK_SERVICE; then
        DELETE_FROM_WORK_DIR "system" "system/etc/permissions/cameraservice.xml"
        DELETE_FROM_WORK_DIR "system" "system/framework/scamera_sep.jar"
        DELETE_FROM_WORK_DIR "system" "system/priv-app/SCameraSDKService"
    fi
else
    if $TARGET_CAMERA_SUPPORT_SDK_SERVICE; then
        # TODO handle this condition
        LOG_MISSING_PATCHES "SOURCE_CAMERA_SUPPORT_SDK_SERVICE" "TARGET_CAMERA_SUPPORT_SDK_SERVICE"
    fi
fi

# SEC_PRODUCT_FEATURE_CAMERA_SUPPORT_CAMERAX_EXTENSION
if $SOURCE_CAMERA_SUPPORT_CAMERAX_EXTENSION; then
    if ! $TARGET_CAMERA_SUPPORT_CAMERAX_EXTENSION; then
        DELETE_FROM_WORK_DIR "system" "system/etc/permissions/sec_camerax_impl.xml"
        DELETE_FROM_WORK_DIR "system" "system/etc/permissions/sec_camerax_service.xml"
        DELETE_FROM_WORK_DIR "system" "system/framework/sec_camerax_impl.jar"
        DELETE_FROM_WORK_DIR "system" "system/lib/libsec_camerax_util_jni.camera.samsung.so"
        DELETE_FROM_WORK_DIR "system" "system/lib64/libsec_camerax_util_jni.camera.samsung.so"
        DELETE_FROM_WORK_DIR "system" "system/priv-app/sec_camerax_service"
        SET_PROP "system" "ro.camerax.extensions.enabled" --delete
    fi
else
    if $TARGET_CAMERA_SUPPORT_CAMERAX_EXTENSION; then
        # TODO handle this condition
        LOG_MISSING_PATCHES "SOURCE_CAMERA_SUPPORT_CAMERAX_EXTENSION" "TARGET_CAMERA_SUPPORT_CAMERAX_EXTENSION"
    fi
fi

# SEC_PRODUCT_FEATURE_GALLERY_CONFIG_PET_CLUSTER_VERSION
SOURCE_GALLERY_CONFIG_PET_CLUSTER_VERSION="$(GET_FLOATING_FEATURE_CONFIG "$FW_DIR/$SOURCE_FIRMWARE_PATH/system/system/etc/floating_feature.xml" "SEC_FLOATING_FEATURE_GALLERY_CONFIG_PET_CLUSTER_VERSION")"
TARGET_GALLERY_CONFIG_PET_CLUSTER_VERSION="$(GET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_GALLERY_CONFIG_PET_CLUSTER_VERSION")"
if [[ "$SOURCE_GALLERY_CONFIG_PET_CLUSTER_VERSION" != "None" ]]; then
    if [[ "$TARGET_GALLERY_CONFIG_PET_CLUSTER_VERSION" == "None" ]]; then
        DELETE_FROM_WORK_DIR "system" "system/etc/default-permissions/default-permissions-com.samsung.petservice.xml"
        DELETE_FROM_WORK_DIR "system" "system/etc/permissions/privapp-permissions-com.samsung.petservice.xml"
        DELETE_FROM_WORK_DIR "system" "system/lib64/libPetClustering.camera.samsung.so"
        DELETE_FROM_WORK_DIR "system" "system/priv-app/PetService"
    fi
else
    if [[ "$TARGET_GALLERY_CONFIG_PET_CLUSTER_VERSION" != "None" ]]; then
        # TODO handle this condition
        LOG_MISSING_PATCHES "SOURCE_GALLERY_CONFIG_PET_CLUSTER_VERSION" "TARGET_GALLERY_CONFIG_PET_CLUSTER_VERSION"
    fi
fi

# SEC_PRODUCT_FEATURE_SAIV_CONFIG_ARDOODLE_LIB
SOURCE_SAIV_CONFIG_ARDOODLE_LIB="$(GET_FLOATING_FEATURE_CONFIG "$FW_DIR/$SOURCE_FIRMWARE_PATH/system/system/etc/floating_feature.xml" "SEC_FLOATING_FEATURE_SAIV_CONFIG_ARDOODLE_LIB")"
TARGET_SAIV_CONFIG_ARDOODLE_LIB="$(GET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_SAIV_CONFIG_ARDOODLE_LIB")"
if [[ "$SOURCE_SAIV_CONFIG_ARDOODLE_LIB" != "$TARGET_SAIV_CONFIG_ARDOODLE_LIB" ]]; then
    if [ "$SOURCE_SAIV_CONFIG_ARDOODLE_LIB" ]; then
        if [[ "$SOURCE_SAIV_CONFIG_ARDOODLE_LIB" == *"IMG_PICKING"* ]] && \
                [[ "$TARGET_SAIV_CONFIG_ARDOODLE_LIB" != *"IMG_PICKING"* ]]; then
            DELETE_FROM_WORK_DIR "system" "system/etc/ardoodle"
        elif [[ "$SOURCE_SAIV_CONFIG_ARDOODLE_LIB" != *"IMG_PICKING"* ]] && \
                [[ "$TARGET_SAIV_CONFIG_ARDOODLE_LIB" == *"IMG_PICKING"* ]]; then
            # TODO handle this condition
            LOG_MISSING_PATCHES "SOURCE_SAIV_CONFIG_ARDOODLE_LIB" "TARGET_SAIV_CONFIG_ARDOODLE_LIB"
        fi
    else
        if [ "$TARGET_SAIV_CONFIG_ARDOODLE_LIB" ]; then
            # TODO handle this condition
            LOG_MISSING_PATCHES "SOURCE_SAIV_CONFIG_ARDOODLE_LIB" "TARGET_SAIV_CONFIG_ARDOODLE_LIB"
        fi
    fi
fi

# Camera libs debloat
if ! grep -q "\"system\"" "$WORK_DIR/system/system/cameradata/portrait_data/single_bokeh_feature.json" 2> /dev/null; then
    DELETE_FROM_WORK_DIR "system" "system/lib64/libRelighting_API.camera.samsung.so"
fi
if ! grep -q "SUPPORT_PET_DETECTION.*true" "$WORK_DIR/system/system/cameradata/singletake/service-feature.xml" 2> /dev/null && \
        [[ "$TARGET_SAIV_CONFIG_ARDOODLE_LIB" != *"PET_DETECTION"* ]]; then
    DELETE_FROM_WORK_DIR "system" "system/lib64/lib_pet_detection.arcsoft.so"
fi
if ! grep -q "SUPPORT_SINGLE_TAKE_BURST_CAPTURE.*true" "$WORK_DIR/system/system/cameradata/camera-feature.xml" 2> /dev/null; then
    DELETE_FROM_WORK_DIR "system" "system/lib64/libBestPhoto.camera.samsung.so"
fi
SOURCE_CAMERA_CONFIG_VENDOR_LIB_INFO="$(GET_FLOATING_FEATURE_CONFIG "$FW_DIR/$SOURCE_FIRMWARE_PATH/system/system/etc/floating_feature.xml" "SEC_FLOATING_FEATURE_CAMERA_CONFIG_VENDOR_LIB_INFO")"
TARGET_CAMERA_CONFIG_VENDOR_LIB_INFO="$(GET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_CAMERA_CONFIG_VENDOR_LIB_INFO")"
if [[ "$SOURCE_CAMERA_CONFIG_VENDOR_LIB_INFO" == *"aebhdr.arcsoft.v1"* ]] && \
        [[ "$TARGET_CAMERA_CONFIG_VENDOR_LIB_INFO" != *"aebhdr.arcsoft.v1"* ]]; then
    DELETE_FROM_WORK_DIR "system" "system/lib64/libAEBHDR_wrapper.camera.samsung.so"
    DELETE_FROM_WORK_DIR "system" "system/lib64/libae_bracket_hdr.arcsoft.so"
fi
if [ -f "$WORK_DIR/vendor/lib64/libDualCamBokehCapture.camera.samsung.so" ] || {
    [[ "$SOURCE_CAMERA_CONFIG_VENDOR_LIB_INFO" == *"dual_bokeh.samsung"* ]] && \
        [[ "$TARGET_CAMERA_CONFIG_VENDOR_LIB_INFO" != *"dual_bokeh.samsung"* ]]
}; then
    DELETE_FROM_WORK_DIR "system" "system/lib64/libDualCamBokehCapture.camera.samsung.so"
    if [ ! -f "$WORK_DIR/system/system/lib64/libRelighting_API.camera.samsung.so" ]; then
        DELETE_FROM_WORK_DIR "system" "system/lib64/libarcsoft_dualcam_portraitlighting.so"
    fi
    if ! grep -q "GlassSegSDK" "$WORK_DIR/system/system/cameradata/portrait_data/single_bokeh_feature.json" 2> /dev/null; then
        DELETE_FROM_WORK_DIR "system" "system/lib64/libarcsoft_single_cam_glasses_seg.so"
    fi
    DELETE_FROM_WORK_DIR "system" "system/lib64/libarcsoft_superresolution_bokeh.so"
    DELETE_FROM_WORK_DIR "system" "system/lib64/libdualcam_refocus_image.so"
    DELETE_FROM_WORK_DIR "system" "system/lib64/libhigh_dynamic_range_bokeh.so"
fi
if {
    [[ "$SOURCE_CAMERA_CONFIG_VENDOR_LIB_INFO" == *"fusion_high_res.arcsoft.v1"* ]] && \
        [[ "$TARGET_CAMERA_CONFIG_VENDOR_LIB_INFO" != *"fusion_high_res.arcsoft.v1"* ]]
} || {
    [[ "$SOURCE_CAMERA_CONFIG_VENDOR_LIB_INFO" == *"high_res.arcsoft.v2"* ]] && \
        [[ "$TARGET_CAMERA_CONFIG_VENDOR_LIB_INFO" != *"high_res.arcsoft.v2"* ]]
}; then
    DELETE_FROM_WORK_DIR "system" "system/lib64/libHREnhancementAPI.camera.samsung.so"
    DELETE_FROM_WORK_DIR "system" "system/lib64/libhighres_enhancement.arcsoft.so"
fi
if [[ "$SOURCE_CAMERA_CONFIG_VENDOR_LIB_INFO" == *"fr_tracking.arcsoft.v1"* ]] && \
        [[ "$TARGET_CAMERA_CONFIG_VENDOR_LIB_INFO" != *"fr_tracking.arcsoft.v1"* ]]; then
    DELETE_FROM_WORK_DIR "system" "system/lib64/libFaceRecognition.arcsoft.so"
    DELETE_FROM_WORK_DIR "system" "system/lib64/libfrtracking_engine.arcsoft.so"
fi
if [[ "$SOURCE_CAMERA_CONFIG_VENDOR_LIB_INFO" == *"hybridhdr.arcsoft.v1"* ]] && \
        [[ "$TARGET_CAMERA_CONFIG_VENDOR_LIB_INFO" != *"hybridhdr.arcsoft.v1"* ]]; then
    DELETE_FROM_WORK_DIR "system" "system/lib64/libhybridHDR_wrapper.camera.samsung.so"
    DELETE_FROM_WORK_DIR "system" "system/lib64/libhybrid_high_dynamic_range.arcsoft.so"
fi
if [[ "$SOURCE_CAMERA_CONFIG_VENDOR_LIB_INFO" == *"image_enhance.arcsoft.v1"* ]] && \
        [[ "$TARGET_CAMERA_CONFIG_VENDOR_LIB_INFO" != *"image_enhance.arcsoft.v1"* ]]; then
    DELETE_FROM_WORK_DIR "system" "system/lib64/libimage_enhancement.arcsoft.so"
fi
if [[ "$SOURCE_CAMERA_CONFIG_VENDOR_LIB_INFO" == *"pro_single_rgb.mpi.v1"* ]] && \
        [[ "$TARGET_CAMERA_CONFIG_VENDOR_LIB_INFO" != *"pro_single_rgb.mpi.v1"* ]]; then
    DELETE_FROM_WORK_DIR "system" "system/lib64/libAIQSolution_MPISingleRGB40.camera.samsung.so"
    DELETE_FROM_WORK_DIR "system" "system/lib64/libMPISingleRGB40.camera.samsung.so"
    DELETE_FROM_WORK_DIR "system" "system/lib64/libMPISingleRGB40Tuning.camera.samsung.so"
fi
if [[ "$SOURCE_CAMERA_CONFIG_VENDOR_LIB_INFO" == *"scene_detection.samsung.v1"* ]] && \
        [[ "$TARGET_CAMERA_CONFIG_VENDOR_LIB_INFO" != *"scene_detection.samsung.v1"* ]]; then
    DELETE_FROM_WORK_DIR "system" "system/lib64/libSceneDetector_v1.camera.samsung.so"
fi
if [[ "$SOURCE_CAMERA_CONFIG_VENDOR_LIB_INFO" == *"smart_scan.samsung"* ]] && \
        [[ "$TARGET_CAMERA_CONFIG_VENDOR_LIB_INFO" != *"smart_scan.samsung"* ]]; then
    DELETE_FROM_WORK_DIR "system" "system/lib64/libSmartScan.camera.samsung.so"
fi
if [[ "$SOURCE_CAMERA_CONFIG_VENDOR_LIB_INFO" == *"super_night.mpi.v2"* ]] && \
        [[ "$TARGET_CAMERA_CONFIG_VENDOR_LIB_INFO" != *"super_night.mpi.v2"* ]]; then
    DELETE_FROM_WORK_DIR "system" "system/lib64/libAIQSolution_MPI.camera.samsung.so"
    DELETE_FROM_WORK_DIR "system" "system/lib64/libLocalTM_pcc.camera.samsung.so"
    DELETE_FROM_WORK_DIR "system" "system/lib64/libMultiFrameProcessing30.camera.samsung.so"
    DELETE_FROM_WORK_DIR "system" "system/lib64/libMultiFrameProcessing30.snapwrapper.camera.samsung.so"
    DELETE_FROM_WORK_DIR "system" "system/lib64/libMultiFrameProcessing30Tuning.camera.samsung.so"
    DELETE_FROM_WORK_DIR "system" "system/lib64/libObjectDetector_v1.camera.samsung.so"
    DELETE_FROM_WORK_DIR "system" "system/lib64/libSwIsp_core.camera.samsung.so"
    DELETE_FROM_WORK_DIR "system" "system/lib64/libSwIsp_wrapper_v1.camera.samsung.so"
fi
if [[ "$SOURCE_CAMERA_CONFIG_VENDOR_LIB_INFO" == *"super_resolution_raw.arcsoft"* ]] && \
        [[ "$TARGET_CAMERA_CONFIG_VENDOR_LIB_INFO" != *"super_resolution_raw.arcsoft"* ]]; then
    DELETE_FROM_WORK_DIR "system" "system/lib64/libsuperresolutionraw_wrapper_v2.camera.samsung.so"
    DELETE_FROM_WORK_DIR "system" "system/lib64/libsuperresolution_raw.arcsoft.so"
fi
SOURCE_CAMERA_DOCUMENTSCAN_SOLUTIONS="$(GET_FLOATING_FEATURE_CONFIG "$FW_DIR/$SOURCE_FIRMWARE_PATH/system/system/etc/floating_feature.xml" "SEC_FLOATING_FEATURE_CAMERA_DOCUMENTSCAN_SOLUTIONS")"
TARGET_CAMERA_DOCUMENTSCAN_SOLUTIONS="$(GET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_CAMERA_DOCUMENTSCAN_SOLUTIONS")"
if [[ "$SOURCE_CAMERA_DOCUMENTSCAN_SOLUTIONS" == *"AI_DEWARPING"* ]] && \
        [[ "$TARGET_CAMERA_DOCUMENTSCAN_SOLUTIONS" != *"AI_DEWARPING"* ]]; then
    DELETE_FROM_WORK_DIR "system" "system/lib64/libDeepDocRectify.camera.samsung.so"
fi
if [[ "$SOURCE_CAMERA_DOCUMENTSCAN_SOLUTIONS" == *"SHADOW_REMOVAL"* ]] && \
        [[ "$TARGET_CAMERA_DOCUMENTSCAN_SOLUTIONS" != *"SHADOW_REMOVAL"* ]]; then
    DELETE_FROM_WORK_DIR "system" "system/lib64/libDocShadowRemoval.arcsoft.so"
fi
if [ -f "$WORK_DIR/system/system/lib64/libImageSegmenter_v1.camera.samsung.so" ] && \
        [ ! -d "$WORK_DIR/vendor/etc/portrait_data/LF_segmenter" ]; then
    DELETE_FROM_WORK_DIR "system" "system/lib64/libImageSegmenter_v1.camera.samsung.so"
fi

# Fix device model number in photo/video metadata
while IFS= read -r f; do
    HEX_PATCH "$f" "726f2e70726f647563742e6d6f64656c00" "726f2e626f6f742e656d2e6d6f64656c00"
done < <(grep -r -w -l "ro.product.model" "$WORK_DIR/vendor" | grep "camera")
if [ -f "$WORK_DIR/system/system/lib/libstagefright.so" ]; then
    HEX_PATCH "$WORK_DIR/system/system/lib/libstagefright.so" \
        "726f2e70726f647563742e6d6f64656c00" "726f2e626f6f742e656d2e6d6f64656c00"
elif [ "$SOURCE_PLATFORM_SDK_VERSION" -lt 37 ]; then
    ABORT "Expected the source firmware's 32-bit libstagefright"
    return 1
fi
HEX_PATCH "$WORK_DIR/system/system/lib64/libstagefright.so" \
    "726f2e70726f647563742e6d6f64656c00" "726f2e626f6f742e656d2e6d6f64656c00"

# Fix object capture
if [[ "$TARGET_OS_SINGLE_SYSTEM_IMAGE" == "essi" ]]; then
    if {
        [[ "$(GET_PROP "system" "ro.product.device")" =~ r0|g0|b0 ]] && \
            ! [[ "$(GET_PROP "vendor" "ro.product.vendor.device")" =~ r0|g0|b0 ]]
    } || {
        [[ "$(GET_PROP "system" "ro.product.device")" == "a56"* ]] && \
            [[ "$(GET_PROP "vendor" "ro.product.vendor.device")" != "a56"* ]]
    }; then
        HEX_PATCH "$WORK_DIR/system/system/lib64/libobjectcapture_jni.arcsoft.so" \
            "e503162a47020094e022009121008052e203162a" "8500805247020094e02200912100805282008052"
    elif ! [[ "$(GET_PROP "system" "ro.product.device")" =~ r0|g0|b0 ]] && \
            [[ "$(GET_PROP "vendor" "ro.product.vendor.device")" =~ r0|g0|b0 ]]; then
        HEX_PATCH "$WORK_DIR/system/system/lib64/libobjectcapture_jni.arcsoft.so" \
            "e503162a47020094e022009121008052e203162a" "4500805247020094e02200912100805242008052"
    elif [[ "$(GET_PROP "system" "ro.product.device")" != "a56"* ]] && \
            [[ "$(GET_PROP "vendor" "ro.product.vendor.device")" == "a56"* ]]; then
        HEX_PATCH "$WORK_DIR/system/system/lib64/libobjectcapture_jni.arcsoft.so" \
            "e503162a47020094e022009121008052e203162a" "c500805247020094e022009121008052c2008052"
    fi
fi

# Fix portrait mode
if [ -f "$WORK_DIR/vendor/lib64/libDualCamBokehCapture.camera.samsung.so" ]; then
    if grep -q "ro.build.flavor" "$WORK_DIR/vendor/lib64/libDualCamBokehCapture.camera.samsung.so" 2> /dev/null; then
        SET_PROP "system" "ro.build.flavor" "$(GET_PROP "$FW_DIR/$TARGET_FIRMWARE_PATH/system/system/build.prop" "ro.build.flavor")"
    elif grep -q "ro.product.name" "$WORK_DIR/vendor/lib64/libDualCamBokehCapture.camera.samsung.so" 2> /dev/null; then
        HEX_PATCH "$WORK_DIR/vendor/lib/libDualCamBokehCapture.camera.samsung.so" \
            "726f2e70726f647563742e6e616d6500" "726f2e756e6963612e63616d65726100"
        HEX_PATCH "$WORK_DIR/vendor/lib/liblivefocus_capture_engine.so" \
            "726f2e70726f647563742e6e616d6500" "726f2e756e6963612e63616d65726100"
        HEX_PATCH "$WORK_DIR/vendor/lib/liblivefocus_preview_engine.so" \
            "726f2e70726f647563742e6e616d6500" "726f2e756e6963612e63616d65726100"
        HEX_PATCH "$WORK_DIR/vendor/lib64/libDualCamBokehCapture.camera.samsung.so" \
            "726f2e70726f647563742e6e616d6500" "726f2e756e6963612e63616d65726100"
        HEX_PATCH "$WORK_DIR/vendor/lib64/liblivefocus_capture_engine.so" \
            "726f2e70726f647563742e6e616d6500" "726f2e756e6963612e63616d65726100"
        HEX_PATCH "$WORK_DIR/vendor/lib64/liblivefocus_preview_engine.so" \
            "726f2e70726f647563742e6e616d6500" "726f2e756e6963612e63616d65726100"
        LOG "- Patching /system/system/etc/selinux/plat_property_contexts"
        EVAL "echo \"ro.unica.camera u:object_r:build_prop:s0 exact string\" >> \"$WORK_DIR/system/system/etc/selinux/plat_property_contexts\""
        SET_PROP "system" "ro.unica.camera" "$(GET_PROP "$FW_DIR/$TARGET_FIRMWARE_PATH/system/system/build.prop" "ro.product.system.name")"
    fi
fi

# Enable camera cutout protection
# Skip patch if SystemUI RRO exists
if [ ! "$(find "$WORK_DIR/product/overlay" -maxdepth 1 -type f -name "SystemUI*" 2> /dev/null)" ]; then
    if [[ "$SOURCE_CAMERA_SUPPORT_CUTOUT_PROTECTION" != "$TARGET_CAMERA_SUPPORT_CUTOUT_PROTECTION" ]]; then
        DECODE_APK "system_ext" "priv-app/SystemUI/SystemUI.apk"
        if $TARGET_CAMERA_SUPPORT_CUTOUT_PROTECTION; then
            LOG "- Enabling camera cutout protection"
        else
            LOG "- Disabling camera cutout protection"
        fi
        EVAL "sed -i \"s/config_enableDisplayCutoutProtection\\\">$SOURCE_CAMERA_SUPPORT_CUTOUT_PROTECTION/config_enableDisplayCutoutProtection\\\">$TARGET_CAMERA_SUPPORT_CUTOUT_PROTECTION/\" \"$APKTOOL_DIR/system_ext/priv-app/SystemUI/SystemUI.apk/res/values/bools.xml\""
    fi
fi

unset SOURCE_FIRMWARE_PATH TARGET_FIRMWARE_PATH CAMERA_APP_COHORT \
    SOURCE_CAMERA_CONFIG_ACTION_CLASSIFIER TARGET_CAMERA_CONFIG_ACTION_CLASSIFIER \
    SOURCE_CAMERA_CONFIG_GPPM_SOLUTIONS TARGET_CAMERA_CONFIG_GPPM_SOLUTIONS \
    SOURCE_GALLERY_CONFIG_PET_CLUSTER_VERSION TARGET_GALLERY_CONFIG_PET_CLUSTER_VERSION \
    SOURCE_SAIV_CONFIG_ARDOODLE_LIB TARGET_SAIV_CONFIG_ARDOODLE_LIB \
    SOURCE_CAMERA_CONFIG_VENDOR_LIB_INFO TARGET_CAMERA_CONFIG_VENDOR_LIB_INFO \
    SOURCE_CAMERA_DOCUMENTSCAN_SOLUTIONS TARGET_CAMERA_DOCUMENTSCAN_SOLUTIONS
unset -f _LOG LOG_MISSING_PATCHES
