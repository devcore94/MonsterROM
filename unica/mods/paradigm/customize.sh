# shellcheck disable=SC2034
SKIPUNZIP=1

if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ]; then
    # Validate the entire profile before changing properties, assets or APKs.
    # Metadata and Path conversion must be selected as one native/Java cohort.
    # Selecting it does not establish a working live Camera2 extension or ISP.
    : "${UN1CA_QPR2_CAMERA_METADATA:=true}"
    : "${UN1CA_QPR2_CAMERA_PATH:=true}"
    : "${UN1CA_QPR2_SUBJECT_CPU_PREVIEW:=true}"
    : "${UN1CA_QPR2_MAINLINE:=true}"
    : "${UN1CA_QPR2_SWCODEC:=false}"
    : "${UN1CA_QPR2_RUNTIME_COHORT:=off}"
    : "${UN1CA_QPR2_CPU_LEAVES:=true}"
    : "${UN1CA_QPR2_GSI_DIR:=$SRC_DIR/prebuilts/qpr2}"

    for QPR2_OPTION in UN1CA_QPR2_CAMERA_METADATA UN1CA_QPR2_CAMERA_PATH UN1CA_QPR2_SUBJECT_CPU_PREVIEW UN1CA_QPR2_CPU_LEAVES UN1CA_QPR2_MAINLINE UN1CA_QPR2_SWCODEC; do
        case "${!QPR2_OPTION:-false}" in
            true|false) ;;
            *) ABORT "$QPR2_OPTION must be true or false"; return 1 ;;
        esac
    done
    unset QPR2_OPTION
    case "$UN1CA_QPR2_RUNTIME_COHORT" in
        off|trial-r15) ;;
        *) ABORT "UN1CA_QPR2_RUNTIME_COHORT must be off or trial-r15"; return 1 ;;
    esac
    if [ "$UN1CA_QPR2_CAMERA_METADATA" != "$UN1CA_QPR2_CAMERA_PATH" ]; then
        ABORT "Enable or disable QPR2 camera metadata and Path conversion together"
        return 1
    fi

    # The loops below must describe the complete reviewed sets, not a truncated
    # or duplicated subset that can silently skip providers and report success.
    if [ "$UN1CA_QPR2_MAINLINE" = true ]; then
        [ "$(sha256sum "$MODPATH/qpr2/mainline/modules.sha256" | cut -d ' ' -f 1)" = \
            "c983aecfbb5ac11d4d30fe7c59596b6ce2888a845ef786906e744b14474868e1" ] || {
            ABORT "Incomplete or unreviewed QPR2 contract: qpr2/mainline/modules.sha256"
            return 1
        }
    fi
    if [ "$UN1CA_QPR2_RUNTIME_COHORT" = trial-r15 ]; then
        [ "$(sha256sum "$MODPATH/qpr2/runtime_cohort/components.sha256" | cut -d ' ' -f 1)" = \
            "d07dc6ed2542d1dce8b611fc96d7eb912ff91a3992f71154748b0c21cfd407a9" ] || {
            ABORT "Incomplete or unreviewed QPR2 contract: qpr2/runtime_cohort/components.sha256"
            return 1
        }
    fi
    if [ "$UN1CA_QPR2_CPU_LEAVES" = true ]; then
        [ "$(sha256sum "$MODPATH/qpr2/cpu_leaves/libraries.sha256" | cut -d ' ' -f 1)" = \
            "c6f814b192170a6d2c05796ab0fe8396428b080268b94b876bf1719a72102f58" ] || {
            ABORT "Incomplete or unreviewed QPR2 contract: qpr2/cpu_leaves/libraries.sha256"
            return 1
        }
    fi
fi

if [ ! "$(GET_PROP "system" "ro.unica.codename")" ]; then
    LOG "- Patching /system/system/etc/selinux/plat_property_contexts"
    EVAL "echo \"ro.unica.codename u:object_r:build_prop:s0 exact string\" >> \"$WORK_DIR/system/system/etc/selinux/plat_property_contexts\""
    # Match latest Samsung's flagship device codename
    ROM_CODENAME="$(basename "$MODPATH")"
    SET_PROP "system" "ro.unica.codename" "${ROM_CODENAME^}"
    unset ROM_CODENAME
fi

PARADIGM_VERIFY_RUNTIME()
(
    # Check the retained One UI 9 providers after VNDK's native-only ARM32 graft.
    # Read actual payloads, independently of cache receipts, without rebuilding.
    QPR2_SOURCE_RUNTIME="$FW_DIR/${SOURCE_FIRMWARE%%/*}_$(cut -d / -f 2 <<< "$SOURCE_FIRMWARE")/system/system/apex/com.android.runtime.apex"
    QPR2_RUNTIME="$WORK_DIR/system/system/apex/com.android.runtime.apex"
    [ "$(sha256sum "$QPR2_SOURCE_RUNTIME" | cut -d ' ' -f 1)" = \
        "0e1941d33200a01c12f45ff9ed6439ae60c1b3a8880c95f074f58544b1633793" ] || exit 1
    if cmp -s "$QPR2_SOURCE_RUNTIME" "$QPR2_RUNTIME"; then exit 0; fi
    QPR2_RUNTIME_TEMP="$(mktemp -d "$OUT_DIR/qpr2-runtime-check.XXXXXX")" || exit 1
    # shellcheck disable=SC2329 # Invoked by the EXIT trap.
    cleanup_qpr2_runtime()
    {
        local FAILED=false POINT
        for POINT in work source; do
            if mountpoint -q "$QPR2_RUNTIME_TEMP/$POINT"; then
                sudo umount "$QPR2_RUNTIME_TEMP/$POINT" || FAILED=true
            fi
        done
        if ! $FAILED; then rm -rf -- "$QPR2_RUNTIME_TEMP"; fi
    }
    trap cleanup_qpr2_runtime EXIT
    mkdir "$QPR2_RUNTIME_TEMP/source" "$QPR2_RUNTIME_TEMP/work" || exit 1
    unzip -p "$QPR2_SOURCE_RUNTIME" apex_payload.img > "$QPR2_RUNTIME_TEMP/source.img" || exit 1
    unzip -p "$QPR2_RUNTIME" apex_payload.img > "$QPR2_RUNTIME_TEMP/work.img" || exit 1
    avbtool verify_image --image "$QPR2_RUNTIME_TEMP/work.img" \
        --key "$SRC_DIR/security/avb/testkey_rsa4096.pem" || exit 1
    sudo mount -o ro,noload "$QPR2_RUNTIME_TEMP/source.img" "$QPR2_RUNTIME_TEMP/source" || exit 1
    sudo mount -o ro,noload "$QPR2_RUNTIME_TEMP/work.img" "$QPR2_RUNTIME_TEMP/work" || exit 1
    sudo perl - "$QPR2_RUNTIME_TEMP/source" "$QPR2_RUNTIME_TEMP/work" <<'PERL'
use strict;
use warnings;
use Digest::SHA;
use File::Find;
use Fcntl ':mode';
sub need { die "$_[1]\n" unless $_[0] }
sub sha { open my $f,'<:raw',$_[0] or die "$!\n"; return Digest::SHA->new(256)->addfile($f)->hexdigest }
sub label {
    open my $f,'-|','getfattr','-h','--absolute-names','-n','security.selinux','--only-values','--',$_[0] or die "$!\n";
    local $/; my $v=<$f>//''; close $f or die "Missing runtime label: $_[0]\n"; return $v;
}
my($source,$work)=@ARGV; my $files=0;
find({no_chdir=>1,wanted=>sub {
    my $p=$File::Find::name; my $n=substr($p,length($source)); my $q="$work$n";
    my @s=lstat($p); my @t=lstat($q); need(@s && @t,"Missing original runtime provider: $n");
    need(($s[2]&0177777)==($t[2]&0177777) && $s[4]==$t[4] && $s[5]==$t[5] && label($p) eq label($q),"Original runtime metadata changed: $n");
    if(S_ISREG($s[2])) { need(sha($p) eq sha($q),"Original runtime provider changed: $n"); ++$files }
    elsif(S_ISLNK($s[2])) { need(readlink($p) eq readlink($q),"Original runtime symlink changed: $n") }
    else { need(S_ISDIR($s[2]),"Unsupported runtime node: $n") }
}},$source);
need($files>=10,'Incomplete original runtime cohort');
print "Verified $files original One UI 9 runtime providers after native ARM32 graft\n";
PERL
)

# Keep the newer One UI 9 applications and native feature cohorts. Do not
# downgrade them indiscriminately to the SDK-36/S25 payloads below.
if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ]; then
    LOG_STEP_IN "- Selecting target-compatible Samsung brand sounds"
    if ! $TARGET_AUDIO_SUPPORT_ACH_RINGTONE; then
        # One UI 9 supplies ACH-only tones. Use the original coherent ordinary
        # SoundTheme pack on non-ACH targets, not renamed haptic-channel files.
        DELETE_FROM_WORK_DIR "system" "system/media/audio/notifications"
        DELETE_FROM_WORK_DIR "system" "system/media/audio/ringtones"
        ADD_TO_WORK_DIR "a56xnaxx" "system" "system/etc/ringtones_count_list.txt" 0 0 644 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "a56xnaxx" "system" "system/media/audio/notifications" 0 0 755 "u:object_r:system_file:s0"
        ADD_TO_WORK_DIR "a56xnaxx" "system" "system/media/audio/ringtones" 0 0 755 "u:object_r:system_file:s0"
        PARADIGM_AUDIO_PREFIX=""
    else
        # The genuine One UI 9 ACH pack already supersedes the 2025 ACH payload.
        PARADIGM_AUDIO_PREFIX="ACH_"
    fi
    SET_PROP "vendor" "ro.config.ringtone" "${PARADIGM_AUDIO_PREFIX}Galaxy_Bells.ogg"
    SET_PROP "vendor" "ro.config.notification_sound" "${PARADIGM_AUDIO_PREFIX}Brightline.ogg"
    SET_PROP "vendor" "ro.config.alarm_alert" "${PARADIGM_AUDIO_PREFIX}Morning_Xylophone.ogg"
    SET_PROP "vendor" "ro.config.media_sound" "Media_preview_Over_the_horizon.ogg"
    SET_PROP "vendor" "ro.config.ringtone_2" "${PARADIGM_AUDIO_PREFIX}Atomic_Bell.ogg"
    SET_PROP "vendor" "ro.config.notification_sound_2" "${PARADIGM_AUDIO_PREFIX}Three_Star.ogg"
    unset PARADIGM_AUDIO_PREFIX
    # Keep the newer One UI 9 Horizon music/preview and the original brand-sound
    # reader behavior, which is still gated on the target's first shipping API.
    APPLY_PATCH "system" "system/priv-app/SecSoundPicker/SecSoundPicker.apk" \
        "$MODPATH/brandsound/SecSoundPicker.apk/0001-Enable-SUPPORT_SAMSUNG_BRAND_SOUND_ONEUI_7.patch"
    LOG_STEP_OUT

    # The donor has no vendor Pet Detector assets. Use the original Paradigm
    # pa2qxxx payload, not a different model with a matching filename.
    # Merge the three owned files; never remove unrelated vendor assets.
    LOG_STEP_IN "- Adding Pet Detector support in Galaxy AI features"
    (cd "$SRC_DIR/prebuilts/samsung/pa2qxxx/vendor" && sha256sum -c "$MODPATH/petdetector.sha256")
    ADD_TO_WORK_DIR "pa2qxxx" "vendor" "etc/petdetector/studio_pd/config_thresholds.json" 0 0 644 "u:object_r:vendor_configs_file:s0"
    ADD_TO_WORK_DIR "pa2qxxx" "vendor" "etc/petdetector/studio_pd/studio_pd_cnn.info" 0 0 644 "u:object_r:vendor_configs_file:s0"
    ADD_TO_WORK_DIR "pa2qxxx" "vendor" "etc/petdetector/studio_pd/studio_pd_cnn.tflite" 0 0 644 "u:object_r:vendor_configs_file:s0"
    SET_METADATA "vendor" "etc/petdetector/studio_pd/config_thresholds.json" 0 0 644 "u:object_r:vendor_configs_file:s0"
    SET_METADATA "vendor" "etc/petdetector/studio_pd/studio_pd_cnn.info" 0 0 644 "u:object_r:vendor_configs_file:s0"
    SET_METADATA "vendor" "etc/petdetector/studio_pd/studio_pd_cnn.tflite" 0 0 644 "u:object_r:vendor_configs_file:s0"
    LOG_STEP_OUT

    # QPR2 feature customization is owned here. Keep the reviewed order and
    # each former child MODPATH: payloads/contracts/patches stay in place.
    # No conditional sourcing or feature-function wrapper: errexit stays active
    # inside the original builder functions, including commands within EVAL.
    PARADIGM_MODPATH="$MODPATH"

    # Public QPR2 API and actual observer lifecycle used by current apps.
    APPLY_PATCH "system" "system/framework/framework.jar" \
        "$PARADIGM_MODPATH/qpr2/insets_lifecycle/framework.jar/0001-Port-QPR2-window-insets-animation-observers.patch"
    APPLY_PATCH "system" "system/framework/framework.jar" \
        "$PARADIGM_MODPATH/qpr2/signed_package/framework.jar/0001-Port-QPR2-SignedPackage-certificate-history.patch"

    # QPR2 mainline
    MODPATH="$PARADIGM_MODPATH/qpr2/mainline"
    LOG_STEP_IN "- Adding QPR2 mainline"
    # Complete original signed modules. No payload editing, re-signing or key change.
    if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ] && [ "${UN1CA_QPR2_MAINLINE:-false}" = "true" ]; then
        # Validate the entire finite module set before copying the first container.
        while read -r QPR2_APEX QPR2_OLD QPR2_NEW QPR2_OLD_SHA QPR2_NEW_SHA; do
            [ "$(sha256sum "$SRC_DIR/prebuilts/qpr2/system/system/apex/$QPR2_NEW" | cut -d ' ' -f 1)" = "$QPR2_NEW_SHA" ] || {
                ABORT "Unreviewed QPR2 APEX input: $QPR2_APEX"
                return 1
            }
            if [ "$QPR2_OLD" = "$QPR2_NEW" ]; then
                QPR2_CURRENT_SHA="$(sha256sum "$WORK_DIR/system/system/apex/$QPR2_OLD" | cut -d ' ' -f 1)"
                [ "$QPR2_CURRENT_SHA" = "$QPR2_OLD_SHA" ] || [ "$QPR2_CURRENT_SHA" = "$QPR2_NEW_SHA" ] || {
                    ABORT "Unreviewed existing APEX: $QPR2_APEX"
                    return 1
                }
            else
                # A reviewed new file must not hide an unrelated old container, or
                # authorize overwriting an existing unreviewed new-name container.
                if [ -f "$WORK_DIR/system/system/apex/$QPR2_OLD" ]; then
                    [ "$(sha256sum "$WORK_DIR/system/system/apex/$QPR2_OLD" | cut -d ' ' -f 1)" = "$QPR2_OLD_SHA" ] || {
                        ABORT "Unreviewed old APEX container: $QPR2_APEX"
                        return 1
                    }
                fi
                if [ -f "$WORK_DIR/system/system/apex/$QPR2_NEW" ]; then
                    [ "$(sha256sum "$WORK_DIR/system/system/apex/$QPR2_NEW" | cut -d ' ' -f 1)" = "$QPR2_NEW_SHA" ] || {
                        ABORT "Unreviewed new-name APEX container: $QPR2_APEX"
                        return 1
                    }
                elif [ ! -f "$WORK_DIR/system/system/apex/$QPR2_OLD" ]; then
                    ABORT "Missing existing APEX: $QPR2_APEX"
                    return 1
                fi
            fi
        done < "$MODPATH/modules.sha256"

        while read -r QPR2_APEX QPR2_OLD QPR2_NEW QPR2_OLD_SHA QPR2_NEW_SHA; do
            ADD_TO_WORK_DIR "$SRC_DIR/prebuilts/qpr2" "system" "system/apex/$QPR2_NEW" 0 0 644
            [ "$(sha256sum "$WORK_DIR/system/system/apex/$QPR2_NEW" | cut -d ' ' -f 1)" = "$QPR2_NEW_SHA" ] || return 1
            if [ "$QPR2_OLD" != "$QPR2_NEW" ] && [ -f "$WORK_DIR/system/system/apex/$QPR2_OLD" ]; then
                DELETE_FROM_WORK_DIR "system" "system/apex/$QPR2_OLD"
            fi
        done < "$MODPATH/modules.sha256"
        SET_PROP "system" "ro.unica.qpr2.mainline" "sdkext,tzdata"
        unset QPR2_APEX QPR2_OLD QPR2_NEW QPR2_OLD_SHA QPR2_NEW_SHA QPR2_CURRENT_SHA
    fi
    LOG_STEP_OUT

    # QPR2 swcodec
    MODPATH="$PARADIGM_MODPATH/qpr2/swcodec"
    LOG_STEP_IN "- Adding QPR2 swcodec"
    # Keep the original signed whole cohort and its isolated native providers.
    if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ] && [ "${UN1CA_QPR2_SWCODEC:-false}" = "true" ]; then
        # xHE-AAC keeps its real minor-API gate. Do not install this candidate on
        # the older profile where that existing codec would stop creating.
        [ "$(GET_PROP "system" "ro.build.version.sdk_full")" = "37.2" ] || {
            ABORT "QPR2 software codecs require the reviewed SDK-full 37.2 build profile"
            return 1
        }
        [ "$(sha256sum "$SRC_DIR/prebuilts/qpr2/system/system/apex/com.google.android.media.swcodec.apex" | cut -d ' ' -f 1)" = "6b7bd747ccf23aee92dfb041611dfd5d4c7db7d2299d747d41ea3749355cb3db" ] || {
            ABORT "Unreviewed QPR2 software-codec input"
            return 1
        }
        if [ -f "$WORK_DIR/system/system/apex/com.google.android.media.swcodec_compressed.apex" ]; then
            [ "$(sha256sum "$WORK_DIR/system/system/apex/com.google.android.media.swcodec_compressed.apex" | cut -d ' ' -f 1)" = "d66fd3d1b7d3f3686a9ba685dc49199bd6ed8fbe6ed5bccb039768a1a0608fa9" ] || {
                ABORT "Existing software-codec container has unreviewed changes"
                return 1
            }
        fi
        if [ -f "$WORK_DIR/system/system/apex/com.google.android.media.swcodec.apex" ]; then
            [ "$(sha256sum "$WORK_DIR/system/system/apex/com.google.android.media.swcodec.apex" | cut -d ' ' -f 1)" = "6b7bd747ccf23aee92dfb041611dfd5d4c7db7d2299d747d41ea3749355cb3db" ] || {
                ABORT "Existing new-name software-codec container is unreviewed"
                return 1
            }
        elif [ ! -f "$WORK_DIR/system/system/apex/com.google.android.media.swcodec_compressed.apex" ]; then
            ABORT "Missing current software-codec container"
            return 1
        fi
        PARADIGM_VERIFY_RUNTIME
        # This finite platform boundary was actually loaded on both ABIs; do not
        # flatten source libui/libc++ or weaken linker namespaces to cover changes.
        while read -r QPR2_CODEC_PROVIDER QPR2_CODEC_SHA; do
            [ "$(sha256sum "$WORK_DIR/$QPR2_CODEC_PROVIDER" | cut -d ' ' -f 1)" = "$QPR2_CODEC_SHA" ] || {
                ABORT "Retained software-codec provider changed: $QPR2_CODEC_PROVIDER"
                return 1
            }
        done < "$MODPATH/retained-providers.sha256"
        ADD_TO_WORK_DIR "$SRC_DIR/prebuilts/qpr2" "system" "system/apex/com.google.android.media.swcodec.apex" 0 0 644
        [ "$(sha256sum "$WORK_DIR/system/system/apex/com.google.android.media.swcodec.apex" | cut -d ' ' -f 1)" = "6b7bd747ccf23aee92dfb041611dfd5d4c7db7d2299d747d41ea3749355cb3db" ] || return 1
        if [ -f "$WORK_DIR/system/system/apex/com.google.android.media.swcodec_compressed.apex" ]; then
            DELETE_FROM_WORK_DIR "system" "system/apex/com.google.android.media.swcodec_compressed.apex"
        fi
        SET_PROP "system" "ro.unica.qpr2.swcodec" "373040140"
        unset QPR2_CODEC_PROVIDER QPR2_CODEC_SHA
    fi
    LOG_STEP_OUT

    # QPR2 runtime_cohort
    MODPATH="$PARADIGM_MODPATH/qpr2/runtime_cohort"
    LOG_STEP_IN "- Adding QPR2 runtime_cohort"
    # An explicit isolated custom-ROM profile. No phone/data update migration.
    if [ "${UN1CA_QPR2_RUNTIME_COHORT:-off}" = "trial-r15" ]; then
        [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ] && \
            [ "$(GET_PROP "$WORK_DIR/vendor/default.prop" "ro.zygote")" = "zygote64" ] || {
            ABORT "QPR2 runtime was exercised for the One UI 9 zygote64 cohort"
            return 1
        }
        PARADIGM_VERIFY_RUNTIME || {
            ABORT "Retained Samsung Bionic/compat32 runtime contract changed"
            return 1
        }
        [ "$(sha256sum "$WORK_DIR/system/system/lib64/libc++.so" | cut -d ' ' -f 1)" = \
            "cb118e98c74d3454858921123b9b51ba13df9cad7dfa141dd892c453661a4d78" ] || {
            ABORT "Retained Samsung libc++ cohort changed"
            return 1
        }
        # Validate both inputs and both existing identities before the first write.
        while read -r QPR2_MODULE QPR2_OLD QPR2_NEW QPR2_OLD_SHA QPR2_NEW_SHA; do
            [ "$(sha256sum "$SRC_DIR/prebuilts/qpr2-runtime/system/system/apex/$QPR2_NEW" | cut -d ' ' -f 1)" = "$QPR2_NEW_SHA" ] || {
                ABORT "Unreviewed QPR2 runtime input: $QPR2_MODULE"
                return 1
            }
            if [ -f "$WORK_DIR/system/system/apex/$QPR2_OLD" ]; then
                [ "$(sha256sum "$WORK_DIR/system/system/apex/$QPR2_OLD" | cut -d ' ' -f 1)" = "$QPR2_OLD_SHA" ] || {
                    ABORT "Unreviewed old runtime container: $QPR2_MODULE"
                    return 1
                }
            fi
            if [ -f "$WORK_DIR/system/system/apex/$QPR2_NEW" ]; then
                [ "$(sha256sum "$WORK_DIR/system/system/apex/$QPR2_NEW" | cut -d ' ' -f 1)" = "$QPR2_NEW_SHA" ] || {
                    ABORT "Unreviewed new-name runtime container: $QPR2_MODULE"
                    return 1
                }
            elif [ ! -f "$WORK_DIR/system/system/apex/$QPR2_OLD" ]; then
                ABORT "Missing original runtime container: $QPR2_MODULE"
                return 1
            fi
        done < "$MODPATH/components.sha256"
        # shellcheck disable=SC2034 # Read by the subsequent ART/Conscrypt patches.
        QPR2_RUNTIME_PREFLIGHT=trial-r15
        unset QPR2_MODULE QPR2_OLD QPR2_NEW QPR2_OLD_SHA QPR2_NEW_SHA
    fi
    LOG_STEP_OUT

    # QPR2 art_runtime
    MODPATH="$PARADIGM_MODPATH/qpr2/art_runtime"
    LOG_STEP_IN "- Adding QPR2 art_runtime"
    # Finite complete signed com.android.art input; cohort preflight runs before either copy.
    if [ "${UN1CA_QPR2_RUNTIME_COHORT:-off}" = "trial-r15" ]; then
        [ "${QPR2_RUNTIME_PREFLIGHT:-}" = "trial-r15" ] || {
            ABORT "Run the paired QPR2 runtime preflight first"
            return 1
        }
        ADD_TO_WORK_DIR "$SRC_DIR/prebuilts/qpr2-runtime" "system" "system/apex/com.google.android.art.apex" 0 0 644
        [ "$(sha256sum "$WORK_DIR/system/system/apex/com.google.android.art.apex" | cut -d ' ' -f 1)" = "f583268c55ed624b947fc78adc3fa6902bcb0ddef0aa157a58fb7a5cdb369b55" ] || return 1
        if [ -f "$WORK_DIR/system/system/apex/com.google.android.art_compressed.apex" ]; then
            DELETE_FROM_WORK_DIR "system" "system/apex/com.google.android.art_compressed.apex"
        fi
    fi
    LOG_STEP_OUT

    # QPR2 conscrypt_trust
    MODPATH="$PARADIGM_MODPATH/qpr2/conscrypt_trust"
    LOG_STEP_IN "- Adding QPR2 conscrypt_trust"
    # Finite complete signed com.android.conscrypt input; cohort preflight runs before either copy.
    if [ "${UN1CA_QPR2_RUNTIME_COHORT:-off}" = "trial-r15" ]; then
        [ "${QPR2_RUNTIME_PREFLIGHT:-}" = "trial-r15" ] || {
            ABORT "Run the paired QPR2 runtime preflight first"
            return 1
        }
        ADD_TO_WORK_DIR "$SRC_DIR/prebuilts/qpr2-runtime" "system" "system/apex/com.google.android.conscrypt.apex" 0 0 644
        [ "$(sha256sum "$WORK_DIR/system/system/apex/com.google.android.conscrypt.apex" | cut -d ' ' -f 1)" = "4d5881208615078ed816687106e7843a8fec516bea72adc7fbc6329a5d8ab15d" ] || return 1
        if [ -f "$WORK_DIR/system/system/apex/com.google.android.conscrypt_compressed.apex" ]; then
            DELETE_FROM_WORK_DIR "system" "system/apex/com.google.android.conscrypt_compressed.apex"
        fi
        SET_PROP "system" "ro.unica.qpr2.runtime_cohort" "trial-r15"
    fi
    LOG_STEP_OUT

    unset QPR2_RUNTIME_PREFLIGHT

    # QPR2 camera_extensions
    MODPATH="$PARADIGM_MODPATH/qpr2/camera_extensions"
    LOG_STEP_IN "- Adding QPR2 camera_extensions"
    # Exact One UI 9 backports. The SDK-36 source remains unchanged.
    if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ]; then
        APPLY_PATCH "system" "system/app/CameraExtensionsProxy/CameraExtensionsProxy.apk" \
            "$MODPATH/patches/CameraExtensionsProxy.apk/0001-Handle-unavailable-QPR2-subject-segmentation-contract.patch"
        APPLY_PATCH "system" "system/app/CameraExtensionsProxy/CameraExtensionsProxy.apk" \
            "$MODPATH/patches/CameraExtensionsProxy.apk/0099-Identify-reviewed-QPR2-backport.patch"
    fi
    LOG_STEP_OUT

    # QPR2 companion
    MODPATH="$PARADIGM_MODPATH/qpr2/companion"
    LOG_STEP_IN "- Adding QPR2 companion"
    # Keep the original SDK-36 / One UI 8 build unchanged.
    if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ]; then
        APPLY_PATCH "system" "system/app/CompanionDeviceManager/CompanionDeviceManager.apk" \
            "$MODPATH/patches/CompanionDeviceManager.apk/0001-Reject-obscured-consent-touches.patch"
        APPLY_PATCH "system" "system/app/CompanionDeviceManager/CompanionDeviceManager.apk" \
            "$MODPATH/patches/CompanionDeviceManager.apk/0002-Gate-consent-input-on-enter-animation.patch"
        APPLY_PATCH "system" "system/app/CompanionDeviceManager/CompanionDeviceManager.apk" \
            "$MODPATH/patches/CompanionDeviceManager.apk/0099-Identify-reviewed-QPR2-backport.patch"
    fi
    LOG_STEP_OUT

    # QPR2 diagnostics
    MODPATH="$PARADIGM_MODPATH/qpr2/diagnostics"
    LOG_STEP_IN "- Adding QPR2 diagnostics"
    # Keep the original SDK-36 / One UI 8 build unchanged.
    if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ]; then
        APPLY_PATCH "system" "system/priv-app/DeviceDiagnostics/DeviceDiagnostics.apk" \
            "$MODPATH/patches/DeviceDiagnostics.apk/0001-Retain-permission-state-across-activity-recreation.patch"
        APPLY_PATCH "system" "system/priv-app/DeviceDiagnostics/DeviceDiagnostics.apk" \
            "$MODPATH/patches/DeviceDiagnostics.apk/0099-Identify-reviewed-QPR2-backport.patch"
    fi
    LOG_STEP_OUT

    # QPR2 collections
    MODPATH="$PARADIGM_MODPATH/qpr2/collections"
    LOG_STEP_IN "- Adding QPR2 collections"
    # QPR2's additional collection APIs use the retained Samsung implementations.
    if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ]; then
        DECODE_APK "system" "system/framework/framework.jar"
        perl - collections "$APKTOOL_DIR/system/framework/framework.jar" "$MODPATH/SOURCES.json" <<'PERL'
use strict;
use warnings;
use JSON::PP;
use Digest::SHA qw(sha256_hex);
use File::Glob qw(bsd_glob);
sub need($$) { die "UN1CA: $_[1]\n" unless $_[0] }
sub raw { open my $f,'<:raw',$_[0] or die "$_[0]: $!\n"; local $/; return <$f>//'' }
sub json { decode_json(raw($_[0])) }
sub same { JSON::PP->new->canonical->encode($_[0]) eq JSON::PP->new->canonical->encode($_[1]) }
sub rel { my($path,$root)=@_; $path =~ s/^\Q$root\E\/// or die "Outside $root: $path"; return $path }
sub methods { my($text)=@_; my %m; while($text =~ /^(\.method [^\n]+\n.*?^\.end method)/msg) {my $raw=$1; my($first)=split /\n/,$raw; my($name)=$first =~ /(\S+)$/; need(!exists $m{$name},"Duplicate method $name"); $m{$name}=$raw} return \%m }
my($kind,$root,$file)=@ARGV; my $contract=json($file);
sub one {my($relative)=@_; my @found=grep {-f $_} bsd_glob("$root/smali*/$relative"); need(@found==1,"Expected one framework class: $relative"); return $found[0]}
sub normalized {my $m=methods($_[0]); for(values %$m) {s/const-string\/jumbo/const-string/g} return $m}
sub required {my($m,$names,$role)=@_; need(exists $m->{$_},"Missing $role method: $_") for @$names}
sub fields {my($text)=@_; return [$text =~ /^(\.field .+)$/mg]}
if($kind eq "collections") {
    for my $row(@{$contract->{methods}}) {my $relative=substr($row->{owner},1,-1).".smali"; my $path=one($relative); my $text=raw($path);
        need(rel($path,$root) =~ m{^smali_classes4/},"Collection moved to unreviewed DEX: $relative"); need(same([sort @{fields($text)}],$row->{retained_fields}),"Unreviewed Samsung collection fields: $relative");
        my $m=methods($text); need(!scalar(grep {/^compute\(/} keys %$m),"Collection compute API already present"); required($m,$row->{retained_required_methods},$relative)}
    for my $interface(@{$contract->{new_interfaces}}) {need(!scalar(grep {-f $_} bsd_glob("$root/smali*/android/util/$interface.smali")),"Callback interface already present: $interface")}
    for my $relative(keys %{$contract->{retained_dependencies}}) {required(methods(raw(one($relative))),$contract->{retained_dependencies}{$relative},$relative)}
} elsif($kind eq "collections_numeric") {
    for my $row(@{$contract->{classes}}) {my $relative=substr($row->{owner},1,-1).".smali"; my $path=one($relative); my $text=raw($path);
        need(rel($path,$root) =~ m{^\Q$contract->{target_DEX}\E/},"Numeric collection moved to unreviewed DEX"); need(same(fields($text),$row->{retained_fields}),"Unreviewed numeric collection field layout");
        my $m=methods($text); need(!scalar(grep {/^compute\(|^lambda\$compute\$/} keys %$m),"Numeric compute method/helper already present"); required($m,$row->{required_original_methods},$relative)}
    need(!scalar(grep {-f $_} bsd_glob("$root/smali*/$contract->{new_helper}")),"QPR2 callback bridge already present");
    my $dependency=$contract->{required_prior_collection}; my $m=normalized(raw(one($dependency->{relative})));
    need(exists($m->{$dependency->{signature}}) && sha256_hex($m->{$dependency->{signature}}) eq $dependency->{method_sha256},"Apply reviewed QPR2 SparseLongArray compute patch first");
    for my $relative(keys %{$contract->{retained_dependencies}}) {required(methods(raw(one($relative))),$contract->{retained_dependencies}{$relative},$relative)}
} elsif($kind eq "dimensions") {
    my $path=one("android/util/TypedValue.smali"); need(rel($path,$root) eq $contract->{target},"Unreviewed TypedValue DEX location"); my $text=raw($path);
    need(same(fields($text),$contract->{retained_fields}),"Unreviewed TypedValue fields"); my $m=normalized($text); need(!exists $m->{$contract->{new_private_helper}},"TypedValue helper already present");
    for my $sig(keys %{$contract->{retained_method_contracts}}) {need(exists($m->{$sig}) && sha256_hex($m->{$sig}) eq $contract->{retained_method_contracts}{$sig},"Unreviewed conversion method $sig")}
} elsif($kind eq "app_identity") {
    for my $row(@{$contract->{classes}}) {my $path=one($row->{relative}); need(rel($path,$root) eq $row->{target},"Unreviewed app identity DEX location"); my $text=raw($path);
        need(sha256_hex(join("\n",@{fields($text)})) eq $row->{retained_field_sha256},"Unreviewed Samsung identity fields"); my $m=methods($text); need(!exists $m->{$_},"QPR2 identity helper already present: $_") for keys %{$row->{added_methods}}}
    for my $relative(keys %{$contract->{retained_dependencies}}) {my $m=normalized(raw(one($relative))); for my $sig(keys %{$contract->{retained_dependencies}{$relative}}) {
        need(exists($m->{$sig}) && sha256_hex($m->{$sig}) eq $contract->{retained_dependencies}{$relative}{$sig},"Unreviewed identity dependency $relative->$sig")}}
} else {die "Unsupported QPR2 contract kind $kind\n"}
print "QPR2 $kind: retained Samsung layout/method/dependency contracts verified\n";
PERL
        APPLY_PATCH "system" "system/framework/framework.jar" \
            "$MODPATH/patches/framework.jar/0001-Backport-QPR2-sparse-collection-compute-APIs.patch"
        SET_PROP "system" "ro.unica.qpr2.collections" "sparse-compute"
    fi
    LOG_STEP_OUT

    # QPR2 collections_numeric
    MODPATH="$PARADIGM_MODPATH/qpr2/collections_numeric"
    LOG_STEP_IN "- Adding QPR2 collections_numeric"
    # These QPR2 numeric variants use the preceding SparseLongArray compute API.
    if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ]; then
        DECODE_APK "system" "system/framework/framework.jar"
        perl - collections_numeric "$APKTOOL_DIR/system/framework/framework.jar" "$MODPATH/SOURCES.json" <<'PERL'
use strict;
use warnings;
use JSON::PP;
use Digest::SHA qw(sha256_hex);
use File::Glob qw(bsd_glob);
sub need($$) { die "UN1CA: $_[1]\n" unless $_[0] }
sub raw { open my $f,'<:raw',$_[0] or die "$_[0]: $!\n"; local $/; return <$f>//'' }
sub json { decode_json(raw($_[0])) }
sub same { JSON::PP->new->canonical->encode($_[0]) eq JSON::PP->new->canonical->encode($_[1]) }
sub rel { my($path,$root)=@_; $path =~ s/^\Q$root\E\/// or die "Outside $root: $path"; return $path }
sub methods { my($text)=@_; my %m; while($text =~ /^(\.method [^\n]+\n.*?^\.end method)/msg) {my $raw=$1; my($first)=split /\n/,$raw; my($name)=$first =~ /(\S+)$/; need(!exists $m{$name},"Duplicate method $name"); $m{$name}=$raw} return \%m }
my($kind,$root,$file)=@ARGV; my $contract=json($file);
sub one {my($relative)=@_; my @found=grep {-f $_} bsd_glob("$root/smali*/$relative"); need(@found==1,"Expected one framework class: $relative"); return $found[0]}
sub normalized {my $m=methods($_[0]); for(values %$m) {s/const-string\/jumbo/const-string/g} return $m}
sub required {my($m,$names,$role)=@_; need(exists $m->{$_},"Missing $role method: $_") for @$names}
sub fields {my($text)=@_; return [$text =~ /^(\.field .+)$/mg]}
if($kind eq "collections") {
    for my $row(@{$contract->{methods}}) {my $relative=substr($row->{owner},1,-1).".smali"; my $path=one($relative); my $text=raw($path);
        need(rel($path,$root) =~ m{^smali_classes4/},"Collection moved to unreviewed DEX: $relative"); need(same([sort @{fields($text)}],$row->{retained_fields}),"Unreviewed Samsung collection fields: $relative");
        my $m=methods($text); need(!scalar(grep {/^compute\(/} keys %$m),"Collection compute API already present"); required($m,$row->{retained_required_methods},$relative)}
    for my $interface(@{$contract->{new_interfaces}}) {need(!scalar(grep {-f $_} bsd_glob("$root/smali*/android/util/$interface.smali")),"Callback interface already present: $interface")}
    for my $relative(keys %{$contract->{retained_dependencies}}) {required(methods(raw(one($relative))),$contract->{retained_dependencies}{$relative},$relative)}
} elsif($kind eq "collections_numeric") {
    for my $row(@{$contract->{classes}}) {my $relative=substr($row->{owner},1,-1).".smali"; my $path=one($relative); my $text=raw($path);
        need(rel($path,$root) =~ m{^\Q$contract->{target_DEX}\E/},"Numeric collection moved to unreviewed DEX"); need(same(fields($text),$row->{retained_fields}),"Unreviewed numeric collection field layout");
        my $m=methods($text); need(!scalar(grep {/^compute\(|^lambda\$compute\$/} keys %$m),"Numeric compute method/helper already present"); required($m,$row->{required_original_methods},$relative)}
    need(!scalar(grep {-f $_} bsd_glob("$root/smali*/$contract->{new_helper}")),"QPR2 callback bridge already present");
    my $dependency=$contract->{required_prior_collection}; my $m=normalized(raw(one($dependency->{relative})));
    need(exists($m->{$dependency->{signature}}) && sha256_hex($m->{$dependency->{signature}}) eq $dependency->{method_sha256},"Apply reviewed QPR2 SparseLongArray compute patch first");
    for my $relative(keys %{$contract->{retained_dependencies}}) {required(methods(raw(one($relative))),$contract->{retained_dependencies}{$relative},$relative)}
} elsif($kind eq "dimensions") {
    my $path=one("android/util/TypedValue.smali"); need(rel($path,$root) eq $contract->{target},"Unreviewed TypedValue DEX location"); my $text=raw($path);
    need(same(fields($text),$contract->{retained_fields}),"Unreviewed TypedValue fields"); my $m=normalized($text); need(!exists $m->{$contract->{new_private_helper}},"TypedValue helper already present");
    for my $sig(keys %{$contract->{retained_method_contracts}}) {need(exists($m->{$sig}) && sha256_hex($m->{$sig}) eq $contract->{retained_method_contracts}{$sig},"Unreviewed conversion method $sig")}
} elsif($kind eq "app_identity") {
    for my $row(@{$contract->{classes}}) {my $path=one($row->{relative}); need(rel($path,$root) eq $row->{target},"Unreviewed app identity DEX location"); my $text=raw($path);
        need(sha256_hex(join("\n",@{fields($text)})) eq $row->{retained_field_sha256},"Unreviewed Samsung identity fields"); my $m=methods($text); need(!exists $m->{$_},"QPR2 identity helper already present: $_") for keys %{$row->{added_methods}}}
    for my $relative(keys %{$contract->{retained_dependencies}}) {my $m=normalized(raw(one($relative))); for my $sig(keys %{$contract->{retained_dependencies}{$relative}}) {
        need(exists($m->{$sig}) && sha256_hex($m->{$sig}) eq $contract->{retained_dependencies}{$relative}{$sig},"Unreviewed identity dependency $relative->$sig")}}
} else {die "Unsupported QPR2 contract kind $kind\n"}
print "QPR2 $kind: retained Samsung layout/method/dependency contracts verified\n";
PERL
        APPLY_PATCH "system" "system/framework/framework.jar" \
            "$MODPATH/patches/framework.jar/0001-Backport-QPR2-long-and-double-sparse-compute.patch"
        SET_PROP "system" "ro.unica.qpr2.collections_numeric" "long-and-double"
    fi
    LOG_STEP_OUT

    # QPR2 dimensions
    MODPATH="$PARADIGM_MODPATH/qpr2/dimensions"
    LOG_STEP_IN "- Adding QPR2 dimensions"
    # Preserve Samsung's TypedValue and add QPR2's bounded rounding fallback.
    if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ]; then
        DECODE_APK "system" "system/framework/framework.jar"
        perl - dimensions "$APKTOOL_DIR/system/framework/framework.jar" "$MODPATH/SOURCES.json" <<'PERL'
use strict;
use warnings;
use JSON::PP;
use Digest::SHA qw(sha256_hex);
use File::Glob qw(bsd_glob);
sub need($$) { die "UN1CA: $_[1]\n" unless $_[0] }
sub raw { open my $f,'<:raw',$_[0] or die "$_[0]: $!\n"; local $/; return <$f>//'' }
sub json { decode_json(raw($_[0])) }
sub same { JSON::PP->new->canonical->encode($_[0]) eq JSON::PP->new->canonical->encode($_[1]) }
sub rel { my($path,$root)=@_; $path =~ s/^\Q$root\E\/// or die "Outside $root: $path"; return $path }
sub methods { my($text)=@_; my %m; while($text =~ /^(\.method [^\n]+\n.*?^\.end method)/msg) {my $raw=$1; my($first)=split /\n/,$raw; my($name)=$first =~ /(\S+)$/; need(!exists $m{$name},"Duplicate method $name"); $m{$name}=$raw} return \%m }
my($kind,$root,$file)=@ARGV; my $contract=json($file);
sub one {my($relative)=@_; my @found=grep {-f $_} bsd_glob("$root/smali*/$relative"); need(@found==1,"Expected one framework class: $relative"); return $found[0]}
sub normalized {my $m=methods($_[0]); for(values %$m) {s/const-string\/jumbo/const-string/g} return $m}
sub required {my($m,$names,$role)=@_; need(exists $m->{$_},"Missing $role method: $_") for @$names}
sub fields {my($text)=@_; return [$text =~ /^(\.field .+)$/mg]}
if($kind eq "collections") {
    for my $row(@{$contract->{methods}}) {my $relative=substr($row->{owner},1,-1).".smali"; my $path=one($relative); my $text=raw($path);
        need(rel($path,$root) =~ m{^smali_classes4/},"Collection moved to unreviewed DEX: $relative"); need(same([sort @{fields($text)}],$row->{retained_fields}),"Unreviewed Samsung collection fields: $relative");
        my $m=methods($text); need(!scalar(grep {/^compute\(/} keys %$m),"Collection compute API already present"); required($m,$row->{retained_required_methods},$relative)}
    for my $interface(@{$contract->{new_interfaces}}) {need(!scalar(grep {-f $_} bsd_glob("$root/smali*/android/util/$interface.smali")),"Callback interface already present: $interface")}
    for my $relative(keys %{$contract->{retained_dependencies}}) {required(methods(raw(one($relative))),$contract->{retained_dependencies}{$relative},$relative)}
} elsif($kind eq "collections_numeric") {
    for my $row(@{$contract->{classes}}) {my $relative=substr($row->{owner},1,-1).".smali"; my $path=one($relative); my $text=raw($path);
        need(rel($path,$root) =~ m{^\Q$contract->{target_DEX}\E/},"Numeric collection moved to unreviewed DEX"); need(same(fields($text),$row->{retained_fields}),"Unreviewed numeric collection field layout");
        my $m=methods($text); need(!scalar(grep {/^compute\(|^lambda\$compute\$/} keys %$m),"Numeric compute method/helper already present"); required($m,$row->{required_original_methods},$relative)}
    need(!scalar(grep {-f $_} bsd_glob("$root/smali*/$contract->{new_helper}")),"QPR2 callback bridge already present");
    my $dependency=$contract->{required_prior_collection}; my $m=normalized(raw(one($dependency->{relative})));
    need(exists($m->{$dependency->{signature}}) && sha256_hex($m->{$dependency->{signature}}) eq $dependency->{method_sha256},"Apply reviewed QPR2 SparseLongArray compute patch first");
    for my $relative(keys %{$contract->{retained_dependencies}}) {required(methods(raw(one($relative))),$contract->{retained_dependencies}{$relative},$relative)}
} elsif($kind eq "dimensions") {
    my $path=one("android/util/TypedValue.smali"); need(rel($path,$root) eq $contract->{target},"Unreviewed TypedValue DEX location"); my $text=raw($path);
    need(same(fields($text),$contract->{retained_fields}),"Unreviewed TypedValue fields"); my $m=normalized($text); need(!exists $m->{$contract->{new_private_helper}},"TypedValue helper already present");
    for my $sig(keys %{$contract->{retained_method_contracts}}) {need(exists($m->{$sig}) && sha256_hex($m->{$sig}) eq $contract->{retained_method_contracts}{$sig},"Unreviewed conversion method $sig")}
} elsif($kind eq "app_identity") {
    for my $row(@{$contract->{classes}}) {my $path=one($row->{relative}); need(rel($path,$root) eq $row->{target},"Unreviewed app identity DEX location"); my $text=raw($path);
        need(sha256_hex(join("\n",@{fields($text)})) eq $row->{retained_field_sha256},"Unreviewed Samsung identity fields"); my $m=methods($text); need(!exists $m->{$_},"QPR2 identity helper already present: $_") for keys %{$row->{added_methods}}}
    for my $relative(keys %{$contract->{retained_dependencies}}) {my $m=normalized(raw(one($relative))); for my $sig(keys %{$contract->{retained_dependencies}{$relative}}) {
        need(exists($m->{$sig}) && sha256_hex($m->{$sig}) eq $contract->{retained_dependencies}{$relative}{$sig},"Unreviewed identity dependency $relative->$sig")}}
} else {die "Unsupported QPR2 contract kind $kind\n"}
print "QPR2 $kind: retained Samsung layout/method/dependency contracts verified\n";
PERL
        APPLY_PATCH "system" "system/framework/framework.jar" \
            "$MODPATH/patches/framework.jar/0001-Backport-QPR2-dimension-rounding-fallback.patch"
        SET_PROP "system" "ro.unica.qpr2.dimension_rounding" "mantissa-fallback"
    fi
    LOG_STEP_OUT

    # QPR2 app_identity
    MODPATH="$PARADIGM_MODPATH/qpr2/app_identity"
    LOG_STEP_IN "- Adding QPR2 app_identity"
    # Keep Samsung Process/Signature implementations; add only QPR2 helpers.
    if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ]; then
        DECODE_APK "system" "system/framework/framework.jar"
        perl - app_identity "$APKTOOL_DIR/system/framework/framework.jar" "$MODPATH/SOURCES.json" <<'PERL'
use strict;
use warnings;
use JSON::PP;
use Digest::SHA qw(sha256_hex);
use File::Glob qw(bsd_glob);
sub need($$) { die "UN1CA: $_[1]\n" unless $_[0] }
sub raw { open my $f,'<:raw',$_[0] or die "$_[0]: $!\n"; local $/; return <$f>//'' }
sub json { decode_json(raw($_[0])) }
sub same { JSON::PP->new->canonical->encode($_[0]) eq JSON::PP->new->canonical->encode($_[1]) }
sub rel { my($path,$root)=@_; $path =~ s/^\Q$root\E\/// or die "Outside $root: $path"; return $path }
sub methods { my($text)=@_; my %m; while($text =~ /^(\.method [^\n]+\n.*?^\.end method)/msg) {my $raw=$1; my($first)=split /\n/,$raw; my($name)=$first =~ /(\S+)$/; need(!exists $m{$name},"Duplicate method $name"); $m{$name}=$raw} return \%m }
my($kind,$root,$file)=@ARGV; my $contract=json($file);
sub one {my($relative)=@_; my @found=grep {-f $_} bsd_glob("$root/smali*/$relative"); need(@found==1,"Expected one framework class: $relative"); return $found[0]}
sub normalized {my $m=methods($_[0]); for(values %$m) {s/const-string\/jumbo/const-string/g} return $m}
sub required {my($m,$names,$role)=@_; need(exists $m->{$_},"Missing $role method: $_") for @$names}
sub fields {my($text)=@_; return [$text =~ /^(\.field .+)$/mg]}
if($kind eq "collections") {
    for my $row(@{$contract->{methods}}) {my $relative=substr($row->{owner},1,-1).".smali"; my $path=one($relative); my $text=raw($path);
        need(rel($path,$root) =~ m{^smali_classes4/},"Collection moved to unreviewed DEX: $relative"); need(same([sort @{fields($text)}],$row->{retained_fields}),"Unreviewed Samsung collection fields: $relative");
        my $m=methods($text); need(!scalar(grep {/^compute\(/} keys %$m),"Collection compute API already present"); required($m,$row->{retained_required_methods},$relative)}
    for my $interface(@{$contract->{new_interfaces}}) {need(!scalar(grep {-f $_} bsd_glob("$root/smali*/android/util/$interface.smali")),"Callback interface already present: $interface")}
    for my $relative(keys %{$contract->{retained_dependencies}}) {required(methods(raw(one($relative))),$contract->{retained_dependencies}{$relative},$relative)}
} elsif($kind eq "collections_numeric") {
    for my $row(@{$contract->{classes}}) {my $relative=substr($row->{owner},1,-1).".smali"; my $path=one($relative); my $text=raw($path);
        need(rel($path,$root) =~ m{^\Q$contract->{target_DEX}\E/},"Numeric collection moved to unreviewed DEX"); need(same(fields($text),$row->{retained_fields}),"Unreviewed numeric collection field layout");
        my $m=methods($text); need(!scalar(grep {/^compute\(|^lambda\$compute\$/} keys %$m),"Numeric compute method/helper already present"); required($m,$row->{required_original_methods},$relative)}
    need(!scalar(grep {-f $_} bsd_glob("$root/smali*/$contract->{new_helper}")),"QPR2 callback bridge already present");
    my $dependency=$contract->{required_prior_collection}; my $m=normalized(raw(one($dependency->{relative})));
    need(exists($m->{$dependency->{signature}}) && sha256_hex($m->{$dependency->{signature}}) eq $dependency->{method_sha256},"Apply reviewed QPR2 SparseLongArray compute patch first");
    for my $relative(keys %{$contract->{retained_dependencies}}) {required(methods(raw(one($relative))),$contract->{retained_dependencies}{$relative},$relative)}
} elsif($kind eq "dimensions") {
    my $path=one("android/util/TypedValue.smali"); need(rel($path,$root) eq $contract->{target},"Unreviewed TypedValue DEX location"); my $text=raw($path);
    need(same(fields($text),$contract->{retained_fields}),"Unreviewed TypedValue fields"); my $m=normalized($text); need(!exists $m->{$contract->{new_private_helper}},"TypedValue helper already present");
    for my $sig(keys %{$contract->{retained_method_contracts}}) {need(exists($m->{$sig}) && sha256_hex($m->{$sig}) eq $contract->{retained_method_contracts}{$sig},"Unreviewed conversion method $sig")}
} elsif($kind eq "app_identity") {
    for my $row(@{$contract->{classes}}) {my $path=one($row->{relative}); need(rel($path,$root) eq $row->{target},"Unreviewed app identity DEX location"); my $text=raw($path);
        need(sha256_hex(join("\n",@{fields($text)})) eq $row->{retained_field_sha256},"Unreviewed Samsung identity fields"); my $m=methods($text); need(!exists $m->{$_},"QPR2 identity helper already present: $_") for keys %{$row->{added_methods}}}
    for my $relative(keys %{$contract->{retained_dependencies}}) {my $m=normalized(raw(one($relative))); for my $sig(keys %{$contract->{retained_dependencies}{$relative}}) {
        need(exists($m->{$sig}) && sha256_hex($m->{$sig}) eq $contract->{retained_dependencies}{$relative}{$sig},"Unreviewed identity dependency $relative->$sig")}}
} else {die "Unsupported QPR2 contract kind $kind\n"}
print "QPR2 $kind: retained Samsung layout/method/dependency contracts verified\n";
PERL
        APPLY_PATCH "system" "system/framework/framework.jar" \
            "$MODPATH/patches/framework.jar/0001-Backport-QPR2-app-identity-and-digest-helpers.patch"
        SET_PROP "system" "ro.unica.qpr2.app_identity" "uid-and-raw-digests"
    fi
    LOG_STEP_OUT

    # QPR2 downloads
    MODPATH="$PARADIGM_MODPATH/qpr2/downloads"
    LOG_STEP_IN "- Adding QPR2 downloads"
    # Keep the original SDK-36 / One UI 8 build unchanged.
    if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ]; then
        # android.media also contains five unmodified Samsung-signed packages.
        # Rebuilding just DownloadsProvider with our platform key breaks that UID
        # during PackageManager bootstrap. Keep its genuine media certificate;
        # retain the experimental patch files, but do not apply/re-sign them.
        LOG "Keeping Samsung-signed DownloadsProvider; QPR2 backport deferred (android.media signer)"
    fi
    LOG_STEP_OUT

    # QPR2 dream_vsync
    MODPATH="$PARADIGM_MODPATH/qpr2/dream_vsync"
    LOG_STEP_IN "- Adding QPR2 dream_vsync"
    # Original SDK-36 builds remain unchanged. Exact One UI 9 contracts only.
    if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ]; then
        # Keep the original signed APK. Scope the scheduling change to its
        # exact callback/package instead of rebuilding it with another signer.
        DECODE_APK "system" "system/framework/framework.jar" || return 1
        for QPR2_CHECK in framework apks; do
            QPR2_CHECK_ROOT="$APKTOOL_DIR/system/framework/framework.jar"
            if [ "$QPR2_CHECK" = "apks" ]; then QPR2_CHECK_ROOT="$WORK_DIR/system/system"; fi
            python3 "$PARADIGM_MODPATH/qpr2/verify_original_sources.py" \
                "$MODPATH" "$QPR2_CHECK" "$QPR2_CHECK_ROOT" || {
                ABORT "Unreviewed original-dream source contract: $QPR2_CHECK"
                return 1
            }
        done
        unset QPR2_CHECK QPR2_CHECK_ROOT
        APPLY_PATCH "system" "system/framework/framework.jar" \
            "$MODPATH/patches/framework.jar/0001-Use-next-vsync-for-original-Samsung-Colors-dream.patch" || return 1
        SET_PROP "system" "ro.unica.qpr2.dream_vsync" "true" || return 1
    fi
    LOG_STEP_OUT

    # QPR2 print_accessibility
    MODPATH="$PARADIGM_MODPATH/qpr2/print_accessibility"
    LOG_STEP_IN "- Adding QPR2 print_accessibility"
    # Keep the original SDK-36 / One UI 8 build unchanged.
    if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ]; then
        # Keep the original signed APK/data. The framework adds only this exact
        # preview class's localized selected/not-selected state description.
        DECODE_APK "system" "system/framework/framework.jar" || return 1
        for QPR2_CHECK in framework apks; do
            QPR2_CHECK_ROOT="$APKTOOL_DIR/system/framework/framework.jar"
            if [ "$QPR2_CHECK" = "apks" ]; then QPR2_CHECK_ROOT="$WORK_DIR/system/system"; fi
            python3 "$PARADIGM_MODPATH/qpr2/verify_original_sources.py" \
                "$MODPATH" "$QPR2_CHECK" "$QPR2_CHECK_ROOT" || {
                ABORT "Unreviewed original-print source contract: $QPR2_CHECK"
                return 1
            }
        done
        unset QPR2_CHECK QPR2_CHECK_ROOT
        APPLY_PATCH "system" "system/framework/framework.jar" \
            "$MODPATH/patches/framework.jar/0001-Describe-original-Samsung-print-preview-selection.patch" || return 1
        SET_PROP "system" "ro.unica.qpr2.print_accessibility" "true" || return 1
    fi
    LOG_STEP_OUT

    # QPR2 recording
    MODPATH="$PARADIGM_MODPATH/qpr2/recording"
    LOG_STEP_IN "- Adding QPR2 recording"
    # Exact One UI 9 backports. The SDK-36 source remains unchanged.
    if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ]; then
        # Review every input and dry-run the complete group before exposing its
        # setting or changing a recorder. Do not depend on the caller's errexit.
        DECODE_APK "system" "system/priv-app/SecSettings/SecSettings.apk" || return 1
        DECODE_APK "system_ext" "priv-app/SystemUI/SystemUI.apk" || return 1
        DECODE_APK "system" "system/app/SmartCapture/SmartCapture.apk" || return 1
        QPR2_RECORDING_ID_PATCH="$(python3 "$MODPATH/verify_sources.py" "$MODPATH" "$APKTOOL_DIR")" || {
            ABORT "Unreviewed QPR2 recording source or patch contract"
            return 1
        }
        APPLY_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
            "$MODPATH/patches/SecSettings.apk/0001-Expose-opt-in-QPR2-recording-microphone-routing.patch" || return 1
        APPLY_PATCH "system_ext" "priv-app/SystemUI/SystemUI.apk" \
            "$MODPATH/patches/SystemUI.apk/0001-Port-QPR2-recording-microphone-routing.patch" || return 1
        APPLY_PATCH "system" "system/app/SmartCapture/SmartCapture.apk" \
            "$MODPATH/patches/SmartCapture.apk/0001-Port-QPR2-recording-microphone-routing.patch" || return 1
        APPLY_PATCH "system" "system/app/SmartCapture/SmartCapture.apk" \
            "$MODPATH/patches/SmartCapture.apk/$QPR2_RECORDING_ID_PATCH" || return 1
        unset QPR2_RECORDING_ID_PATCH
    fi
    LOG_STEP_OUT

    # QPR2 storage_paths
    MODPATH="$PARADIGM_MODPATH/qpr2/storage_paths"
    LOG_STEP_IN "- Adding QPR2 storage_paths"
    # Original SDK-36 builds remain unchanged. Exact One UI 9 contracts only.
    if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ]; then
        APPLY_PATCH "system" "system/priv-app/ExternalStorageProvider/ExternalStorageProvider.apk" \
            "$MODPATH/patches/ExternalStorageProvider.apk/0001-Protect-QPR2-private-storage-paths.patch"
        APPLY_PATCH "system" "system/priv-app/ExternalStorageProvider/ExternalStorageProvider.apk" \
            "$MODPATH/patches/ExternalStorageProvider.apk/0099-Identify-reviewed-QPR2-backport.patch"
        SET_PROP "system" "ro.unica.qpr2.storage_paths" "unicode-and-private-trash"
    fi
    LOG_STEP_OUT

    # QPR2 usb_consent
    MODPATH="$PARADIGM_MODPATH/qpr2/usb_consent"
    LOG_STEP_IN "- Adding QPR2 usb_consent"
    # Original SDK-36 builds remain unchanged. Exact One UI 9 contracts only.
    if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ]; then
        APPLY_PATCH "system_ext" "priv-app/SystemUI/SystemUI.apk" \
            "$MODPATH/patches/SystemUI.apk/0001-Describe-QPR2-composite-USB-device-interfaces.patch"
        APPLY_PATCH "system_ext" "priv-app/SystemUI/SystemUI.apk" \
            "$MODPATH/patches/SystemUI.apk/0099-Identify-reviewed-QPR2-backport.patch"
        SET_PROP "system" "ro.unica.qpr2.usb.descriptions" "true"
    fi
    LOG_STEP_OUT

    # QPR2 usb_permissions
    MODPATH="$PARADIGM_MODPATH/qpr2/usb_permissions"
    LOG_STEP_IN "- Adding QPR2 usb_permissions"
    # Original SDK-36 builds remain unchanged. Exact One UI 9 contracts only.
    if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ]; then
        DECODE_APK "system" "system/priv-app/SecSettings/SecSettings.apk" || return 1
        # Bind the full reviewed classes, including Samsung authentication, then
        # dry-run every patch before editing Settings or publishing success.
        python3 "$MODPATH/verify_sources.py" "$MODPATH" \
            "$APKTOOL_DIR/system/priv-app/SecSettings/SecSettings.apk" || {
            ABORT "Unreviewed QPR2 USB permission source or patch contract"
            return 1
        }
        APPLY_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
            "$MODPATH/patches/SecSettings.apk/0001-Port-QPR2-USB-app-permission-management.patch" || return 1
        APPLY_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
            "$MODPATH/patches/SecSettings.apk/0002-Expose-USB-app-access-on-Samsung-Connections-page.patch" || return 1
        APPLY_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
            "$MODPATH/patches/SecSettings.apk/0099-Identify-reviewed-QPR2-backport.patch" || return 1
        SET_PROP "system" "ro.unica.qpr2.usb.permissions" "true" || return 1
    fi
    LOG_STEP_OUT

    # QPR2 webcam
    MODPATH="$PARADIGM_MODPATH/qpr2/webcam"
    LOG_STEP_IN "- Adding QPR2 webcam"
    # Original SDK-36 builds remain unchanged. Exact One UI 9 contracts only.
    if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ]; then
        APPLY_PATCH "system" "system/priv-app/DeviceAsWebcam/DeviceAsWebcam.apk" \
            "$MODPATH/patches/DeviceAsWebcam.apk/0001-Port-QPR2-responsive-camera-zoom-controls.patch"
        APPLY_PATCH "system" "system/priv-app/DeviceAsWebcam/DeviceAsWebcam.apk" \
            "$MODPATH/patches/DeviceAsWebcam.apk/0002-Reject-invalid-camera-buffers-before-native-encode.patch"
        APPLY_PATCH "system" "system/priv-app/DeviceAsWebcam/DeviceAsWebcam.apk" \
            "$MODPATH/patches/DeviceAsWebcam.apk/0003-Return-images-without-usable-hardware-buffers.patch"
        APPLY_PATCH "system" "system/priv-app/DeviceAsWebcam/DeviceAsWebcam.apk" \
            "$MODPATH/patches/DeviceAsWebcam.apk/0099-Identify-reviewed-QPR2-backport.patch"
        SET_PROP "system" "ro.unica.qpr2.webcam.zoom" "responsive"
        SET_PROP "system" "ro.unica.qpr2.webcam.buffers" "checked"
    fi
    LOG_STEP_OUT

    # QPR2 webcam_native
    MODPATH="$PARADIGM_MODPATH/qpr2/webcam_native"
    LOG_STEP_IN "- Adding QPR2 webcam_native"
    # Keep all system/vendor graphics providers and the original SDK-36 build intact.
    if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ]; then
        QPR2_SOURCE_FW="$(cut -d '/' -f 1,2 <<< "$SOURCE_FIRMWARE" | tr '/' '_')"
        QPR2_WEBCAM_LIB="$APKTOOL_DIR/system/priv-app/DeviceAsWebcam/DeviceAsWebcam.apk/lib/arm64-v8a"
        python3 "$MODPATH/verify_sources.py" "$MODPATH" \
            "$FW_DIR/$QPR2_SOURCE_FW/system/system/priv-app/DeviceAsWebcam/DeviceAsWebcam.apk" \
            "$QPR2_WEBCAM_LIB" || {
            ABORT "Unreviewed QPR2 webcam APK/native closure or existing libraries"
            return 1
        }
        DECODE_APK "system" "system/priv-app/DeviceAsWebcam/DeviceAsWebcam.apk" || return 1
        EVAL "mkdir -p \"$QPR2_WEBCAM_LIB\"" || return 1
        # The validator requires exactly these four reviewed manifest entries.
        for QPR2_LIBRARY in libjni_deviceAsWebcam.so libjpeg.so libyuv.so libnativehelper.so; do
            EVAL "cp -a \"$MODPATH/files/arm64-v8a/$QPR2_LIBRARY\" \"$QPR2_WEBCAM_LIB/$QPR2_LIBRARY\"" || return 1
        done
        SET_PROP "system" "ro.unica.qpr2.webcam.native" "app-local-qpr2" || return 1
        unset QPR2_SOURCE_FW QPR2_WEBCAM_LIB QPR2_LIBRARY
    fi
    LOG_STEP_OUT

    # QPR2 camera_metadata
    MODPATH="$PARADIGM_MODPATH/qpr2/camera_metadata"
    LOG_STEP_IN "- Adding QPR2 camera_metadata"
    # Experimental native provider, never enabled implicitly by the APK backports.
    if [ "${UN1CA_QPR2_CAMERA_METADATA:-false}" = "true" ]; then
        [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ] || {
            ABORT "QPR2 camera metadata needs the reviewed Samsung One UI 9 cohort"
            return 1
        }
        [ "$(sha256sum "$WORK_DIR/system/system/lib64/libc++.so" | cut -d ' ' -f 1)" = \
            "cb118e98c74d3454858921123b9b51ba13df9cad7dfa141dd892c453661a4d78" ] || {
            ABORT "QPR2 camera metadata needs the reviewed retained Samsung libc++"
            return 1
        }
        PARADIGM_VERIFY_RUNTIME || {
            ABORT "QPR2 camera_metadata needs the reviewed unchanged Samsung ARM64 runtime"
            return 1
        }
        QPR2_METADATA_SHA="$(sha256sum "$WORK_DIR/system/system/lib64/libcamera_metadata.so" | cut -d ' ' -f 1)"
        case "$QPR2_METADATA_SHA" in
            597e6fd78acacb8306dff02dfd6a7e4b35d1982f7b8d9e2f1c84f852eb15e73a|6f9903343859e8af58f2661db15baed9e1053286fbe19e244954661d821724f6) ;;
            *) ABORT "Unreviewed existing camera metadata provider"; return 1 ;;
        esac
        [ "$(sha256sum "$MODPATH/files/system/system/lib64/libcamera_metadata.so" | cut -d ' ' -f 1)" = \
            "6f9903343859e8af58f2661db15baed9e1053286fbe19e244954661d821724f6" ] || {
            ABORT "QPR2 camera metadata payload checksum mismatch"
            return 1
        }
        ADD_TO_WORK_DIR "$MODPATH/files" "system" "system/lib64/libcamera_metadata.so" \
            0 0 644 "u:object_r:system_lib_file:s0"
        SET_PROP "system" "ro.unica.qpr2.camera_metadata" "schema-37.2-experimental"
        unset QPR2_METADATA_SHA
    fi
    LOG_STEP_OUT

    # QPR2 camera_path
    MODPATH="$PARADIGM_MODPATH/qpr2/camera_path"
    LOG_STEP_IN "- Adding QPR2 camera_path"
    # Framework/boot-classpath change: explicit isolated-build opt-in only.
    if [ "${UN1CA_QPR2_CAMERA_PATH:-false}" = "true" ]; then
        [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ] && [ "${UN1CA_QPR2_CAMERA_METADATA:-false}" = "true" ] || {
            ABORT "QPR2 Path conversion needs One UI 9 and the explicit QPR2 metadata-schema opt-in"
            return 1
        }
        QPR2_PATH_SOURCE_FW="$(cut -d '/' -f 1,2 <<< "$SOURCE_FIRMWARE" | tr '/' '_')"
        [ "$(sha256sum "$FW_DIR/$QPR2_PATH_SOURCE_FW/system/system/framework/framework.jar" | cut -d ' ' -f 1)" = \
            "cce04246d5e13f4c46127e7daa1ceee8e32d2bb05c7637b05bac7cb6d6d98505" ] || {
            ABORT "QPR2 Path conversion needs the reviewed original Samsung framework cohort"
            return 1
        }
        [ "$(sha256sum "$WORK_DIR/system/system/lib64/libcamera_metadata.so" | cut -d ' ' -f 1)" = \
            "6f9903343859e8af58f2661db15baed9e1053286fbe19e244954661d821724f6" ] || {
            ABORT "Apply the reviewed native metadata schema before QPR2 Path conversion"
            return 1
        }
        APPLY_PATCH "system" "system/framework/framework.jar" \
            "$MODPATH/patches/framework.jar/0001-Port-QPR2-subject-Path-metadata-conversion.patch"
        APPLY_PATCH "system" "system/framework/framework.jar" \
            "$MODPATH/patches/framework.jar/0002-Reject-malformed-subject-Path-data.patch"
        unset QPR2_PATH_SOURCE_FW
    fi
    LOG_STEP_OUT

    # QPR2 subject_cpu
    MODPATH="$PARADIGM_MODPATH/qpr2/subject_cpu"
    LOG_STEP_IN "- Adding QPR2 subject_cpu"
    # Standalone preview only. Never advertise a working live subject extension.
    if [ "${UN1CA_QPR2_SUBJECT_CPU_PREVIEW:-false}" = "true" ]; then
        [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ] || {
            ABORT "Subject CPU preview was reviewed only for the Samsung One UI 9 cohort"
            return 1
        }
        QPR2_SOURCE_FW="$(cut -d '/' -f 1,2 <<< "$SOURCE_FIRMWARE" | tr '/' '_')"
        QPR2_SUBJECT_APK="$APKTOOL_DIR/system/app/CameraExtensionsProxy/CameraExtensionsProxy.apk"
        python3 "$MODPATH/verify_sources.py" "$MODPATH" \
            "$FW_DIR/$QPR2_SOURCE_FW/system/system/app/CameraExtensionsProxy/CameraExtensionsProxy.apk" \
            "$QPR2_SUBJECT_APK" || {
            ABORT "Unreviewed subject-preview APK/payload closure or existing assets"
            return 1
        }
        DECODE_APK "system" "system/app/CameraExtensionsProxy/CameraExtensionsProxy.apk" || return 1
        python3 "$MODPATH/verify_sources.py" "$MODPATH" \
            "$FW_DIR/$QPR2_SOURCE_FW/system/system/app/CameraExtensionsProxy/CameraExtensionsProxy.apk" \
            "$QPR2_SUBJECT_APK" --check-patch || return 1
        EVAL "mkdir -p \"$QPR2_SUBJECT_APK/lib/arm64-v8a\" \"$QPR2_SUBJECT_APK/assets/unica\"" || return 1
        EVAL "cp -a \"$MODPATH/files/arm64-v8a/libunica_subject_cpu.so\" \"$MODPATH/files/arm64-v8a/libtensorflowlite_c.2.16.1.camera.samsung.so\" \"$QPR2_SUBJECT_APK/lib/arm64-v8a/\"" || return 1
        EVAL "cp -a \"$MODPATH/files/assets/unica/subject-humanseg.tflite\" \"$QPR2_SUBJECT_APK/assets/unica/subject-humanseg.tflite\"" || return 1
        APPLY_PATCH "system" "system/app/CameraExtensionsProxy/CameraExtensionsProxy.apk" \
            "$MODPATH/patches/CameraExtensionsProxy.apk/0001-Add-real-humanseg-CPU-preview-without-advertising-a-live-extension.patch" || return 1
        unset QPR2_SOURCE_FW QPR2_SUBJECT_APK
    fi
    LOG_STEP_OUT

    # QPR2 subject_preview_settings
    MODPATH="$PARADIGM_MODPATH/qpr2/subject_preview_settings"
    LOG_STEP_IN "- Adding QPR2 subject_preview_settings"
    if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ]; then
        APPLY_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
            "$MODPATH/patches/SecSettings.apk/0001-Expose-the-reviewed-CPU-subject-preview-in-Samsung-Labs.patch"
    fi
    LOG_STEP_OUT

    # QPR2 gamecontrollers
    MODPATH="$PARADIGM_MODPATH/qpr2/gamecontrollers"
    LOG_STEP_IN "- Adding QPR2 gamecontrollers"
    if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ]; then
        APPLY_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
            "$MODPATH/patches/SecSettings.apk/0000-Preserve-existing-UN1CA-resource-IDs.patch"
        APPLY_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
            "$MODPATH/patches/SecSettings.apk/0001-Add-per-user-QPR2-gamecontroller-remapping.patch"
    fi
    LOG_STEP_OUT

    # QPR2 accessibility_controls
    MODPATH="$PARADIGM_MODPATH/qpr2/accessibility_controls"
    LOG_STEP_IN "- Adding QPR2 accessibility_controls"
    if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ]; then
        APPLY_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
            "$MODPATH/patches/SecSettings.apk/0001-Expose-per-user-QPR2-interface-contrast.patch"
        APPLY_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
            "$MODPATH/patches/SecSettings.apk/0002-Expose-the-real-window-magnifier-diagonal-control.patch"
        APPLY_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
            "$MODPATH/patches/SecSettings.apk/0099-Identify-the-QPR2-controls-build.patch"
    fi
    LOG_STEP_OUT

    # QPR2 glass
    MODPATH="$PARADIGM_MODPATH/qpr2/glass"
    LOG_STEP_IN "- Adding QPR2 glass"
    if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ]; then
        APPLY_PATCH "system" "system/priv-app/SamsungDialer/SamsungDialer.apk" \
            "$MODPATH/patches/SamsungDialer.apk/0001-Connect-native-Phone-glass-and-backdrop-lens.patch"
        APPLY_PATCH "system_ext" "priv-app/SystemUI/SystemUI.apk" \
            "$MODPATH/patches/SystemUI.apk/0001-Add-native-glass-to-brightness-and-volume-controls.patch"
        APPLY_PATCH "system_ext" "priv-app/SystemUI/SystemUI.apk" \
            "$MODPATH/patches/SystemUI.apk/0002-Reveal-glass-behind-native-slider-tracks.patch"
        APPLY_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
            "$MODPATH/patches/SecSettings.apk/0001-Connect-existing-blur-surfaces-to-QPR2-material.patch"
        APPLY_PATCH "system" "system/priv-app/SecMyFiles2020/SecMyFiles2020.apk" \
            "$MODPATH/patches/SecMyFiles2020.apk/0001-Connect-existing-blur-surfaces-to-QPR2-material.patch"
        APPLY_PATCH "system" "system/priv-app/SamsungGallery2018/SamsungGallery2018.apk" \
            "$MODPATH/patches/SamsungGallery2018.apk/0001-Connect-existing-blur-surfaces-to-QPR2-material.patch"
        APPLY_PATCH "system" "system/priv-app/SamsungGallery2018/SamsungGallery2018.apk" \
            "$MODPATH/patches/SamsungGallery2018.apk/0099-Identify-QPR2-r11.patch"
        APPLY_PATCH "system" "system/priv-app/SamsungContacts/SamsungContacts.apk" \
            "$MODPATH/patches/SamsungContacts.apk/0001-Connect-existing-blur-surfaces-to-QPR2-material.patch"
        APPLY_PATCH "system" "system/priv-app/SecSoundPicker/SecSoundPicker.apk" \
            "$MODPATH/patches/SecSoundPicker.apk/0001-Connect-native-volume-strip-to-QPR2-material.patch"
        APPLY_PATCH "system" "system/app/SmartCapture/SmartCapture.apk" \
            "$MODPATH/patches/SmartCapture.apk/0001-Connect-Capture-toolbars-to-QPR2-material.patch"
        APPLY_PATCH "system" "system/priv-app/SamsungVideoPlayer/SamsungVideoPlayer.apk" \
            "$MODPATH/patches/SamsungVideoPlayer.apk/0001-Connect-native-Video-blur-to-QPR2-material.patch"
        APPLY_PATCH "system" "system/priv-app/SoundAlive_C/SoundAlive_C.apk" \
            "$MODPATH/patches/SoundAlive_C.apk/0001-Add-QPR2-material-to-SoundAlive-action-rows.patch"
        APPLY_PATCH "system" "system/priv-app/SamsungMagnifier3/SamsungMagnifier3.apk" \
            "$MODPATH/patches/SamsungMagnifier3.apk/0001-Add-QPR2-material-behind-native-Magnifier-controls.patch"
    fi
    LOG_STEP_OUT

    # Source-built Camera surfaces; this child owns its temporary build trap.
    LOG_STEP_IN "- Adding One UI 9.5 camera controls"
    (
        MODPATH="$PARADIGM_MODPATH/qpr2/camera_controls"
        source "$MODPATH/customize.sh"
    ) || return 1
    LOG_STEP_OUT

    # QPR2 dialer
    MODPATH="$PARADIGM_MODPATH/qpr2/dialer"
    LOG_STEP_IN "- Adding QPR2 dialer"
    if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ]; then
        APPLY_PATCH "system" "system/priv-app/SamsungDialer/SamsungDialer.apk" \
            "$MODPATH/patches/SamsungDialer.apk/0001-Add-fourth-native-Search-action-and-accessibility.patch"
        APPLY_PATCH "system" "system/priv-app/SamsungDialer/SamsungDialer.apk" \
            "$MODPATH/patches/SamsungDialer.apk/0002-Route-QPR2-search-keyboard-shortcuts.patch"
        APPLY_PATCH "system" "system/priv-app/SamsungDialer/SamsungDialer.apk" \
            "$MODPATH/patches/SamsungDialer.apk/0099-Identify-QPR2-Phone-r10.patch"
    fi
    LOG_STEP_OUT

    # QPR2 systemui_controls
    MODPATH="$PARADIGM_MODPATH/qpr2/systemui_controls"
    LOG_STEP_IN "- Adding QPR2 systemui_controls"
    if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ]; then
        APPLY_PATCH "system_ext" "priv-app/SystemUI/SystemUI.apk" \
            "$MODPATH/patches/SystemUI.apk/0001-Port-QPR2-USB-approval-state-and-detach-handling.patch"
        APPLY_PATCH "system_ext" "priv-app/SystemUI/SystemUI.apk" \
            "$MODPATH/patches/SystemUI.apk/0002-Apply-the-QPR2-panning-choice-at-drag-start.patch"
        APPLY_PATCH "system_ext" "priv-app/SystemUI/SystemUI.apk" \
            "$MODPATH/patches/SystemUI.apk/0099-Identify-QPR2-SystemUI-r10.patch"
    fi
    LOG_STEP_OUT

    # QPR2 input_controls
    MODPATH="$PARADIGM_MODPATH/qpr2/input_controls"
    LOG_STEP_IN "- Adding QPR2 input_controls"
    if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ]; then
        APPLY_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
            "$MODPATH/patches/SecSettings.apk/0001-Integrate-QPR2-controlled-wheel-scrolling.patch"
        APPLY_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
            "$MODPATH/patches/SecSettings.apk/0002-Reset-QPR2-wheel-options-with-Samsung-mouse-settings.patch"
        APPLY_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
            "$MODPATH/patches/SecSettings.apk/0099-Identify-QPR2-r11.patch"
    fi
    LOG_STEP_OUT

    # QPR2 file_shortcuts
    MODPATH="$PARADIGM_MODPATH/qpr2/file_shortcuts"
    LOG_STEP_IN "- Adding QPR2 file_shortcuts"
    if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ]; then
        APPLY_PATCH "system" "system/priv-app/SecMyFiles2020/SecMyFiles2020.apk" \
            "$MODPATH/patches/SecMyFiles2020.apk/0001-Route-QPR2-Ctrl-Enter-through-native-rename.patch"
        APPLY_PATCH "system" "system/priv-app/SecMyFiles2020/SecMyFiles2020.apk" \
            "$MODPATH/patches/SecMyFiles2020.apk/0099-Identify-QPR2-r11.patch"
    fi
    LOG_STEP_OUT

    # QPR2 contacts_controls
    MODPATH="$PARADIGM_MODPATH/qpr2/contacts_controls"
    LOG_STEP_IN "- Adding QPR2 contacts_controls"
    if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ]; then
        APPLY_PATCH "system" "system/priv-app/SamsungContacts/SamsungContacts.apk" \
            "$MODPATH/patches/SamsungContacts.apk/0001-Port-QPR2-country-aware-recipient-matching.patch"
        APPLY_PATCH "system" "system/priv-app/SamsungContacts/SamsungContacts.apk" \
            "$MODPATH/patches/SamsungContacts.apk/0002-Retain-original-backup-certificate-with-knownSigner.patch"
        APPLY_PATCH "system" "system/priv-app/SamsungContacts/SamsungContacts.apk" \
            "$MODPATH/patches/SamsungContacts.apk/0099-Identify-QPR2-r12.patch"
    fi
    LOG_STEP_OUT

    # QPR2 audio_import
    MODPATH="$PARADIGM_MODPATH/qpr2/audio_import"
    LOG_STEP_IN "- Adding QPR2 audio_import"
    if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ]; then
        APPLY_PATCH "system" "system/priv-app/SecSoundPicker/SecSoundPicker.apk" \
            "$MODPATH/patches/SecSoundPicker.apk/0001-Port-QPR2-audio-and-OGG-document-choice.patch"
        APPLY_PATCH "system" "system/priv-app/SecSoundPicker/SecSoundPicker.apk" \
            "$MODPATH/patches/SecSoundPicker.apk/0002-Reject-empty-sound-import-results.patch"
        APPLY_PATCH "system" "system/priv-app/SecSoundPicker/SecSoundPicker.apk" \
            "$MODPATH/patches/SecSoundPicker.apk/0099-Identify-QPR2-r12.patch"
    fi
    LOG_STEP_OUT

    # QPR2 capture_actions
    MODPATH="$PARADIGM_MODPATH/qpr2/capture_actions"
    LOG_STEP_IN "- Adding QPR2 capture_actions"
    if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ]; then
        DECODE_APK "system" "system/app/SmartCapture/SmartCapture.apk" || return 1
        QPR2_CAPTURE_IDENTIFICATION="$(python3 "$MODPATH/verify_sources.py" "$MODPATH" \
            "$APKTOOL_DIR/system/app/SmartCapture/SmartCapture.apk")" || {
            ABORT "Unreviewed QPR2 capture-actions sources or version metadata"
            return 1
        }
        APPLY_PATCH "system" "system/app/SmartCapture/SmartCapture.apk" \
            "$MODPATH/patches/SmartCapture.apk/0001-Expose-QPR2-post-recording-edit-action.patch" || return 1
        APPLY_PATCH "system" "system/app/SmartCapture/SmartCapture.apk" \
            "$MODPATH/patches/SmartCapture.apk/0002-Keep-recording-actions-without-preview-bitmap.patch" || return 1
        APPLY_PATCH "system" "system/app/SmartCapture/SmartCapture.apk" \
            "$MODPATH/patches/SmartCapture.apk/$QPR2_CAPTURE_IDENTIFICATION" || return 1
        unset QPR2_CAPTURE_IDENTIFICATION
    fi
    LOG_STEP_OUT

    # QPR2 video_routes
    MODPATH="$PARADIGM_MODPATH/qpr2/video_routes"
    LOG_STEP_IN "- Adding QPR2 video_routes"
    if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ]; then
        APPLY_PATCH "system" "system/priv-app/SamsungVideoPlayer/SamsungVideoPlayer.apk" \
            "$MODPATH/patches/SamsungVideoPlayer.apk/0001-Use-QPR2-session-specific-audio-output.patch"
        APPLY_PATCH "system" "system/priv-app/SamsungVideoPlayer/SamsungVideoPlayer.apk" \
            "$MODPATH/patches/SamsungVideoPlayer.apk/0099-Identify-QPR2-r13.patch"
    fi
    LOG_STEP_OUT

    # QPR2 audio_devices
    MODPATH="$PARADIGM_MODPATH/qpr2/audio_devices"
    LOG_STEP_IN "- Adding QPR2 audio_devices"
    if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ]; then
        APPLY_PATCH "system" "system/priv-app/SoundAlive_C/SoundAlive_C.apk" \
            "$MODPATH/patches/SoundAlive_C.apk/0001-Add-QPR2-connected-audio-device-discovery.patch"
        APPLY_PATCH "system" "system/priv-app/SoundAlive_C/SoundAlive_C.apk" \
            "$MODPATH/patches/SoundAlive_C.apk/0099-Identify-QPR2-r14.patch"
    fi
    LOG_STEP_OUT

    # QPR2 magnifier_zoom
    MODPATH="$PARADIGM_MODPATH/qpr2/magnifier_zoom"
    LOG_STEP_IN "- Adding QPR2 magnifier_zoom"
    if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ]; then
        APPLY_PATCH "system" "system/priv-app/SamsungMagnifier3/SamsungMagnifier3.apk" \
            "$MODPATH/patches/SamsungMagnifier3.apk/0001-Connect-QPR2-zoom-choices-to-native-camera-levels.patch"
        APPLY_PATCH "system" "system/priv-app/SamsungMagnifier3/SamsungMagnifier3.apk" \
            "$MODPATH/patches/SamsungMagnifier3.apk/0099-Identify-QPR2-r14.patch"
    fi
    LOG_STEP_OUT

    # QPR2 cpu_leaves
    MODPATH="$PARADIGM_MODPATH/qpr2/cpu_leaves"
    LOG_STEP_IN "- Adding QPR2 cpu_leaves"
    # Selected by the reviewed One UI 9 profile; all retained-provider checks remain.
    if [ "${UN1CA_QPR2_CPU_LEAVES:-false}" = "true" ]; then
        [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ] || {
            ABORT "QPR2 CPU leaves were reviewed only for the Samsung One UI 9 cohort"
            return 1
        }
        [ -n "${UN1CA_QPR2_GSI_DIR:-}" ] && [ -d "$UN1CA_QPR2_GSI_DIR/system/system/lib64" ] || {
            ABORT "Set UN1CA_QPR2_GSI_DIR to the reviewed CRB android17QPR2gsi/ROM directory"
            return 1
        }

        # Preflight the entire set before copying any library. Do not silently replace
        # a different platform/C++/Bionic cohort merely because symbol names match.
        [ "$(sha256sum "$WORK_DIR/system/system/lib64/libc++.so" | cut -d ' ' -f 1)" = \
            "cb118e98c74d3454858921123b9b51ba13df9cad7dfa141dd892c453661a4d78" ] || {
            ABORT "QPR2 CPU leaves need the reviewed retained Samsung libc++"
            return 1
        }
        PARADIGM_VERIFY_RUNTIME || {
            ABORT "QPR2 cpu_leaves needs the reviewed unchanged Samsung ARM64 runtime"
            return 1
        }
        while read -r QPR2_LIBRARY QPR2_BASELINE_SHA QPR2_SOURCE_SHA; do
            QPR2_CURRENT_SHA="$(sha256sum "$WORK_DIR/system/system/lib64/$QPR2_LIBRARY" | cut -d ' ' -f 1)"
            [ "$QPR2_CURRENT_SHA" = "$QPR2_BASELINE_SHA" ] || [ "$QPR2_CURRENT_SHA" = "$QPR2_SOURCE_SHA" ] || {
                ABORT "Unreviewed existing CPU library: $QPR2_LIBRARY"
                return 1
            }
            [ "$(sha256sum "$UN1CA_QPR2_GSI_DIR/system/system/lib64/$QPR2_LIBRARY" | cut -d ' ' -f 1)" = "$QPR2_SOURCE_SHA" ] || {
                ABORT "Unreviewed GSI CPU library: $QPR2_LIBRARY"
                return 1
            }
        done < "$MODPATH/libraries.sha256"

        while read -r QPR2_LIBRARY QPR2_BASELINE_SHA QPR2_SOURCE_SHA; do
            ADD_TO_WORK_DIR "$UN1CA_QPR2_GSI_DIR" "system" "system/lib64/$QPR2_LIBRARY" \
                0 0 644 "u:object_r:system_lib_file:s0"
        done < "$MODPATH/libraries.sha256"
        SET_PROP "system" "ro.unica.qpr2.cpu_leaves" "sonic,speexresampler,ETC1"
        unset QPR2_LIBRARY QPR2_BASELINE_SHA QPR2_SOURCE_SHA QPR2_CURRENT_SHA
    fi
    LOG_STEP_OUT

    MODPATH="$PARADIGM_MODPATH"
    unset PARADIGM_MODPATH

    # Preserve the original Galaxy Store update route without replacing the
    # newer One UI 9 app with an older listing or changing its Samsung signer.
    LOG "- Checking latest compatible Game Booster app"
    if PARADIGM_GAME_URL="$(GET_GALAXY_STORE_DOWNLOAD_URL "com.samsung.android.game.gametools")"; then
        (
            PARADIGM_GAME_APK="$WORK_DIR/system/system/priv-app/GameTools_Dream/GameTools_Dream.apk"
            [ ! -e "$APKTOOL_DIR/system/priv-app/GameTools_Dream/GameTools_Dream.apk" ] || exit 1
            PARADIGM_GAME_TEMP="$(mktemp -d "$OUT_DIR/paradigm-game.XXXXXX")" || exit 1
            trap 'rm -rf -- "$PARADIGM_GAME_TEMP"' EXIT
            DOWNLOAD_FILE "$PARADIGM_GAME_URL" "$PARADIGM_GAME_TEMP/GameTools.apk" || exit 1
            cat > "$PARADIGM_GAME_TEMP/GameToolsUpdate.java" <<'JAVA'
import com.android.apksig.ApkVerifier;
import com.android.apksig.apk.ApkUtils;
import java.io.File;
import java.nio.ByteBuffer;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.Arrays;
import java.util.zip.ZipFile;

class GameToolsUpdate {
    static ByteBuffer manifest(String path) throws Exception {
        try (var zip = new ZipFile(path); var in = zip.getInputStream(zip.getEntry("AndroidManifest.xml"))) {
            return ByteBuffer.wrap(in.readAllBytes());
        }
    }
    public static void main(String[] args) throws Exception {
        var oldSig = new ApkVerifier.Builder(new File(args[0])).setMinCheckedPlatformVersion(37).build().verify();
        var newSig = new ApkVerifier.Builder(new File(args[1])).setMinCheckedPlatformVersion(37).build().verify();
        if (!oldSig.isVerified() || !newSig.isVerified() || oldSig.getSignerCertificates().size() != 1 ||
                newSig.getSignerCertificates().size() != 1 || !Arrays.equals(oldSig.getSignerCertificates().get(0).getEncoded(),
                newSig.getSignerCertificates().get(0).getEncoded())) throw new IllegalStateException("Game Booster signer mismatch");
        var oldXml = manifest(args[0]); var newXml = manifest(args[1]);
        if (!"com.samsung.android.game.gametools".equals(ApkUtils.getPackageNameFromBinaryAndroidManifest(oldXml.duplicate())) ||
                !"com.samsung.android.game.gametools".equals(ApkUtils.getPackageNameFromBinaryAndroidManifest(newXml.duplicate())) ||
                ApkUtils.getMinSdkVersionFromBinaryAndroidManifest(newXml.duplicate()) > 37) throw new IllegalStateException("Incompatible Game Booster package");
        long oldVersion = ApkUtils.getLongVersionCodeFromBinaryAndroidManifest(oldXml.duplicate());
        long newVersion = ApkUtils.getLongVersionCodeFromBinaryAndroidManifest(newXml.duplicate());
        if (newVersion <= oldVersion) { System.out.println("Keeping newer/equal Samsung Game Booster: " + oldVersion + " >= " + newVersion); return; }
        var staged = Files.createTempFile(Path.of(args[0]).getParent(), ".GameTools.", ".apk");
        try {
            Files.copy(Path.of(args[1]), staged, StandardCopyOption.REPLACE_EXISTING);
            Files.move(staged, Path.of(args[0]), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING);
        } finally { Files.deleteIfExists(staged); }
        System.out.println("Updated Samsung-signed Game Booster: " + oldVersion + " -> " + newVersion);
    }
}
JAVA
            java -cp "$TOOLS_DIR/bin/signapk.jar" "$PARADIGM_GAME_TEMP/GameToolsUpdate.java" \
                "$PARADIGM_GAME_APK" "$PARADIGM_GAME_TEMP/GameTools.apk"
        ) || {
            ABORT "Failed to verify the compatible Samsung Game Booster update; existing APK retained"
            return 1
        }
    else
        PARADIGM_GAME_SOURCE="$FW_DIR/${SOURCE_FIRMWARE%%/*}_$(cut -d / -f 2 <<< "$SOURCE_FIRMWARE")/system/system/priv-app/GameTools_Dream/GameTools_Dream.apk"
        cmp -s "$PARADIGM_GAME_SOURCE" "$WORK_DIR/system/system/priv-app/GameTools_Dream/GameTools_Dream.apk" || {
            ABORT "No One UI 9 Game Booster listing and the original Samsung app is not retained"
            return 1
        }
        LOGW "No compatible One UI 9 Galaxy Store listing; keeping the newer Samsung donor Game Booster (not an update)"
    fi
    unset PARADIGM_GAME_URL PARADIGM_GAME_SOURCE

    source "$MODPATH/semanticsearch/customize.sh" || return 1
    source "$MODPATH/mca/customize.sh" || return 1
    return 0
fi

# 2025 Audio Pack
LOG_STEP_IN "- Adding 2025 Audio Pack"
DELETE_FROM_WORK_DIR "system" "system/hidden/INTERNAL_SDCARD/Music/Samsung/Over_the_Horizon.mp3"
ADD_TO_WORK_DIR "pa2qxxx" "system" \
    "system/hidden/INTERNAL_SDCARD/Music/Samsung/Over_the_Horizon.m4a" 0 0 644 "u:object_r:system_file:s0"
DELETE_FROM_WORK_DIR "system" "system/media/audio/notifications"
DELETE_FROM_WORK_DIR "system" "system/media/audio/ringtones"
if $TARGET_AUDIO_SUPPORT_ACH_RINGTONE; then
    ADD_TO_WORK_DIR "pa2qxxx" "system" "system/etc/ringtones_count_list.txt" 0 0 644 "u:object_r:system_file:s0"
    ADD_TO_WORK_DIR "pa2qxxx" "system" "system/media/audio/notifications" 0 0 755 "u:object_r:system_file:s0"
    ADD_TO_WORK_DIR "pa2qxxx" "system" "system/media/audio/ringtones" 0 0 755 "u:object_r:system_file:s0"
    SET_PROP "vendor" "ro.config.ringtone" "ACH_Galaxy_Bells.ogg"
    SET_PROP "vendor" "ro.config.notification_sound" "ACH_Brightline.ogg"
    SET_PROP "vendor" "ro.config.alarm_alert" "ACH_Morning_Xylophone.ogg"
    SET_PROP "vendor" "ro.config.media_sound" "Media_preview_Over_the_horizon.ogg"
    SET_PROP "vendor" "ro.config.ringtone_2" "ACH_Atomic_Bell.ogg"
    SET_PROP "vendor" "ro.config.notification_sound_2" "ACH_Three_Star.ogg"
else
    ADD_TO_WORK_DIR "a56xnaxx" "system" "system/etc/ringtones_count_list.txt" 0 0 644 "u:object_r:system_file:s0"
    ADD_TO_WORK_DIR "a56xnaxx" "system" "system/media/audio/notifications" 0 0 755 "u:object_r:system_file:s0"
    ADD_TO_WORK_DIR "a56xnaxx" "system" "system/media/audio/ringtones" 0 0 755 "u:object_r:system_file:s0"
    SET_PROP "vendor" "ro.config.ringtone" "Galaxy_Bells.ogg"
    SET_PROP "vendor" "ro.config.notification_sound" "Brightline.ogg"
    SET_PROP "vendor" "ro.config.alarm_alert" "Morning_Xylophone.ogg"
    SET_PROP "vendor" "ro.config.media_sound" "Media_preview_Over_the_horizon.ogg"
    SET_PROP "vendor" "ro.config.ringtone_2" "Atomic_Bell.ogg"
    SET_PROP "vendor" "ro.config.notification_sound_2" "Three_Star.ogg"
fi
ADD_TO_WORK_DIR "pa2qxxx" "system" \
    "system/media/audio/ui/Media_preview_Over_the_horizon.ogg" 0 0 644 "u:object_r:system_file:s0"
APPLY_PATCH "system" "system/priv-app/SecSoundPicker/SecSoundPicker.apk" \
    "$MODPATH/brandsound/SecSoundPicker.apk/0001-Enable-SUPPORT_SAMSUNG_BRAND_SOUND_ONEUI_7.patch"
LOG_STEP_OUT

# Adaptive colour tone
LOG_STEP_IN "- Adding Adaptive colour tone feature"
ADD_TO_WORK_DIR "pa2qxxx" "system" \
    "system/etc/permissions/privapp-permissions-com.samsung.android.sead.xml" 0 0 644 "u:object_r:system_file:s0"
ADD_TO_WORK_DIR "pa2qxxx" "system" \
    "system/priv-app/EnvironmentAdaptiveDisplay/EnvironmentAdaptiveDisplay.apk" 0 0 644 "u:object_r:system_file:s0"
APPLY_PATCH "system" "system/priv-app/EnvironmentAdaptiveDisplay/EnvironmentAdaptiveDisplay.apk" \
    "$MODPATH/ead/EnvironmentAdaptiveDisplay.apk/0001-Fix-resource-IDs-mismatch.patch"
if $TARGET_LCD_SUPPORT_MDNIE_HW; then
    APPLY_PATCH "system" "system/framework/services.jar" \
        "$MODPATH/ead/services.jar/0001-Add-Adaptive-color-tone-feature.patch"
else
    APPLY_PATCH "system" "system/framework/services.jar" \
        "$MODPATH/ead_mdnie/services.jar/0001-Add-Adaptive-color-tone-feature.patch"
fi
if $TARGET_COMMON_SUPPORT_DYN_RESOLUTION_CONTROL; then
    if [ "$TARGET_PLATFORM_SDK_VERSION" -ge "36" ]; then
        APPLY_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
            "$MODPATH/ead_resolution/SecSettings.apk/0001-Add-Adaptive-color-tone-feature.patch"
    else
        APPLY_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
            "$MODPATH/ead_resolution_legacy/SecSettings.apk/0001-Add-Adaptive-color-tone-feature.patch"
    fi
else
    APPLY_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
        "$MODPATH/ead/SecSettings.apk/0001-Add-Adaptive-color-tone-feature.patch"
fi
APPLY_PATCH "system" "system/priv-app/SettingsProvider/SettingsProvider.apk" \
    "$MODPATH/ead/SettingsProvider.apk/0001-Add-Adaptive-color-tone-feature.patch"
APPLY_PATCH "system_ext" "priv-app/SystemUI/SystemUI.apk" \
    "$MODPATH/ead/SystemUI.apk/0001-Add-Adaptive-color-tone-toggle.patch"
LOG_STEP_OUT

# Set AI Version to 20253 (latest)
SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_COMMON_CONFIG_AI_VERSION" "20253"
ADD_TO_WORK_DIR "pa2qxxx" "system" "system/app/SketchBook/SketchBook.apk" 0 0 644 "u:object_r:system_file:s0"

# Media Context Analyzer
LOG_STEP_IN "- Adding Media Context Analyzer feature"
ADD_TO_WORK_DIR "a56xnaxx" "system" "system/etc/mediacontextanalyzer/Detection.tflite" 0 0 644 "u:object_r:system_file:s0"
ADD_TO_WORK_DIR "a56xnaxx" "system" "system/etc/mediacontextanalyzer/human-pet-det_SR-V131.tflite" 0 0 644 "u:object_r:system_file:s0"
ADD_TO_WORK_DIR "a56xnaxx" "system" "system/etc/mediacontextanalyzer/human-pet-pose_SR-V200.tflite" 0 0 644 "u:object_r:system_file:s0"
ADD_TO_WORK_DIR "a56xnaxx" "system" "system/etc/mediacontextanalyzer/Keyword.tflite" 0 0 644 "u:object_r:system_file:s0"
ADD_TO_WORK_DIR "a56xnaxx" "system" "system/etc/mediacontextanalyzer/keyword-classification_SR-V031.tflite" 0 0 644 "u:object_r:system_file:s0"
EVAL "ln -s \"human-pet-pose_SR-V200.tflite\" \"$WORK_DIR/system/system/etc/mediacontextanalyzer/Pose.tflite\""
SET_METADATA "system" "system/etc/mediacontextanalyzer/Pose.tflite" 0 0 644 "u:object_r:system_file:s0"
ADD_TO_WORK_DIR "a56xnaxx" "system" "system/lib64/libcontextanalyzer_jni.media.samsung.so" 0 0 644 "u:object_r:system_lib_file:s0"
ADD_TO_WORK_DIR "a56xnaxx" "system" "system/lib64/libmediacontextanalyzer.so" 0 0 644 "u:object_r:system_lib_file:s0"
ADD_TO_WORK_DIR "a56xnaxx" "system" "system/lib64/libvideo-highlight-arm64-v8a.so" 0 0 644 "u:object_r:system_lib_file:s0"
SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_MMFW_CONFIG_MEDIA_CONTEXT_ANALYZER_CORE" "GPU"
SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_MMFW_SUPPORT_MEDIA_CONTEXT_ANALYZER" "TRUE"
LOG_STEP_OUT

# Audio eraser
# Requires SEC_PRODUCT_FEATURE_MMFW_SUPPORT_MEDIA_CONTEXT_ANALYZER
LOG_STEP_IN "- Adding Audio eraser feature"
ADD_TO_WORK_DIR "pa2qxxx" "system" "system/etc/audio_ae_intervals.conf" 0 0 644 "u:object_r:system_file:s0"
ADD_TO_WORK_DIR "pa2qxxx" "system" "system/etc/fastScanner.tflite" 0 0 644 "u:object_r:system_file:s0"
ADD_TO_WORK_DIR "pa2qxxx" "system" "system/etc/mss_v0.13.0_4ch.sorione" 0 0 644 "u:object_r:system_file:s0"
ADD_TO_WORK_DIR "pa2qxxx" "system" "system/etc/public.libraries-audio.samsung.txt" 0 0 644 "u:object_r:system_file:s0"
ADD_TO_WORK_DIR "pa2qxxx" "system" "system/lib64/libmediasndk.mediacore.samsung.so" 0 0 644 "u:object_r:system_lib_file:s0"
ADD_TO_WORK_DIR "pa2qxxx" "system" "system/lib64/libmediasndk.so" 0 0 644 "u:object_r:system_lib_file:s0"
ADD_TO_WORK_DIR "pa2qxxx" "system" "system/lib64/libmultisourceseparator.audio.samsung.so" 0 0 644 "u:object_r:system_lib_file:s0"
ADD_TO_WORK_DIR "pa2qxxx" "system" "system/lib64/libmultisourceseparator.so" 0 0 644 "u:object_r:system_lib_file:s0"
ADD_TO_WORK_DIR "pa2qxxx" "system" "system/lib64/libsbs.so" 0 0 644 "u:object_r:system_lib_file:s0"
ADD_TO_WORK_DIR "pa2qxxx" "system" "system/lib64/libtensorflowlite_gpu_delegate.so" 0 0 644 "u:object_r:system_lib_file:s0"
ADD_TO_WORK_DIR "pa2qxxx" "system" "system/lib64/libveframework.videoeditor.samsung.so" 0 0 644 "u:object_r:system_lib_file:s0"
SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_AUDIO_CONFIG_MULTISOURCE_SEPARATOR" "{FastScanning_6, SourceSeparator_4, Version_1.3.0}"
LOG_STEP_OUT

# Now brief
# Requires SEC_FLOATING_FEATURE_COMMON_CONFIG_AI_VERSION >= 20251
# or SEC_FLOATING_FEATURE_FRAMEWORK_SUPPORT_AI_BRIEF_FOR_UT
LOG_STEP_IN "- Adding Now brief feature"
ADD_TO_WORK_DIR "pa2qxxx" "system" \
    "system/etc/default-permissions/default-permissions-com.samsung.android.app.moments.xml" 0 0 644 "u:object_r:system_file:s0"
ADD_TO_WORK_DIR "pa2qxxx" "system" \
    "system/etc/permissions/privapp-permissions-com.samsung.android.app.moments.xml" 0 0 644 "u:object_r:system_file:s0"
ADD_TO_WORK_DIR "pa2qxxx" "system" \
    "system/etc/sysconfig/moments.xml" 0 0 644 "u:object_r:system_file:s0"
ADD_TO_WORK_DIR "pa2qxxx" "system" "system/priv-app/Moments/Moments.apk" 0 0 644 "u:object_r:system_file:s0"
ADD_TO_WORK_DIR "$MODPATH" "system" \
    "system/priv-app/SamsungSmartSuggestions/SamsungSmartSuggestions.apk" 0 0 644 "u:object_r:system_file:s0"
# HACK [
# Samsung has released an update for the Smart suggestions app in March 2026.
# The versioning of the "basic-global-release" flavor differs from the "full-global-release" one.
# This is done on purpose: Samsung uses a lower version number to avoid installing this variant
# on unsupported devices by triggering the downgrade check in PM. To avoid users updating to the
# "non-AI" app, let's fake the versionCode so that it matches the latest available version.
DECODE_APK "system" "system/priv-app/SamsungSmartSuggestions/SamsungSmartSuggestions.apk"
LOG "- Patching versionCode in SamsungSmartSuggestions.apk"
EVAL "sed -i \"s/710500000/711100100/g\" \"$APKTOOL_DIR/system/priv-app/SamsungSmartSuggestions/SamsungSmartSuggestions.apk/apktool.yml\""
# ]
SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_FRAMEWORK_SUPPORT_PERSONALIZED_DATA_CORE" "TRUE"
LOG_STEP_OUT

# Semantic search
# Requires SEC_FLOATING_FEATURE_COMMON_CONFIG_AI_VERSION >= 20251
LOG_STEP_IN "- Adding Semantic search feature"
ADD_TO_WORK_DIR "pa2qxxx" "system" \
    "system/etc/default-permissions/default-permissions-com.samsung.mediasearch.xml" 0 0 644 "u:object_r:system_file:s0"
ADD_TO_WORK_DIR "pa2qxxx" "system" \
    "system/etc/mediasearch/data/dec_adaptor.tflite" 0 0 644 "u:object_r:system_file:s0"
ADD_TO_WORK_DIR "pa2qxxx" "system" \
    "system/etc/mediasearch/data/dec_event.tflite" 0 0 644 "u:object_r:system_file:s0"
ADD_TO_WORK_DIR "pa2qxxx" "system" \
    "system/etc/mediasearch/data/enc_image.tflite" 0 0 644 "u:object_r:system_file:s0"
ADD_TO_WORK_DIR "pa2qxxx" "system" \
    "system/etc/mediasearch/data/enc_text.tflite" 0 0 644 "u:object_r:system_file:s0"
ADD_TO_WORK_DIR "pa2qxxx" "system" \
    "system/etc/mediasearch/data/versioninfo.json" 0 0 644 "u:object_r:system_file:s0"
ADD_TO_WORK_DIR "pa2qxxx" "system" \
    "system/etc/permissions/privapp-permissions-com.samsung.mediasearch.xml" 0 0 644 "u:object_r:system_file:s0"
ADD_TO_WORK_DIR "pa2qxxx" "system" \
    "system/priv-app/MediaSearch/MediaSearch.apk" 0 0 644 "u:object_r:system_file:s0"
ADD_TO_WORK_DIR "pa2qxxx" "system" \
    "system/priv-app/SemanticSearchCore/SemanticSearchCore.apk" 0 0 644 "u:object_r:system_file:s0"
DECODE_APK "system" "system/priv-app/SecSettingsIntelligence/SecSettingsIntelligence.apk"
LOG "- Enabling Semantic search feature in /system/system/priv-app/SecSettingsIntelligence/SecSettingsIntelligence.apk"
EVAL "cp -a \"$MODPATH/semanticsearch/SecSettingsIntelligence.apk/res/raw/\"* \"$APKTOOL_DIR/system/priv-app/SecSettingsIntelligence/SecSettingsIntelligence.apk/res/raw\""
SMALI_PATCH "system" "system/priv-app/SecSettingsIntelligence/SecSettingsIntelligence.apk" \
    "smali_classes2/com/samsung/android/settings/intelligence/Rune.smali" "replaceall" \
    "const-string v1, \\\"\\\"" \
    "const-string v1, \\\"400\\\"" \
    > /dev/null
SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_MSCH_SUPPORT_NLSEARCH" "TRUE"
LOG_STEP_OUT

# Game Booster
LOG "- Downloading latest Game Booster app"
DOWNLOAD_FILE "$(GET_GALAXY_STORE_DOWNLOAD_URL "com.samsung.android.game.gametools")" \
    "$WORK_DIR/system/system/priv-app/GameTools_Dream/GameTools_Dream.apk"

# Pet Detector in Galaxy AI
LOG_STEP_IN "- Adding Pet Detector support in Galaxy AI features"
if [ -d "$WORK_DIR/vendor/etc/petdetector/studio_pd" ]; then
    DELETE_FROM_WORK_DIR "vendor" "etc/petdetector/studio_pd"
fi
ADD_TO_WORK_DIR "pa2qxxx" "vendor" "etc/petdetector/studio_pd/config_thresholds.json" 0 0 644 "u:object_r:vendor_configs_file:s0"
ADD_TO_WORK_DIR "pa2qxxx" "vendor" "etc/petdetector/studio_pd/studio_pd_cnn.info" 0 0 644 "u:object_r:vendor_configs_file:s0"
ADD_TO_WORK_DIR "pa2qxxx" "vendor" "etc/petdetector/studio_pd/studio_pd_cnn.tflite" 0 0 644 "u:object_r:vendor_configs_file:s0"
LOG_STEP_OUT
