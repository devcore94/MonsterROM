# Property identifying the UN1CA version
SET_PROP "system" "ro.unica.version" "$ROM_VERSION"
if [ -f "$WORK_DIR/kernel/floppy-preserved.json" ]; then
    SET_PROP "system" "ro.unica.version" "$ROM_VERSION-floppy-r54-113ce9d986f7"
fi
EVAL "echo \"ro.unica.version u:object_r:build_prop:s0 exact string\" >> \"$WORK_DIR/system/system/etc/selinux/plat_property_contexts\""

# Property identifying the UN1CA build time
SET_PROP "system" "ro.unica.timestamp" "$ROM_BUILD_TIMESTAMP"
EVAL "echo \"ro.unica.timestamp u:object_r:build_prop:s0 exact string\" >> \"$WORK_DIR/system/system/etc/selinux/plat_property_contexts\""

# Property identifying the device codename UN1CA is being built for
SET_PROP "system" "ro.unica.device" "$TARGET_CODENAME"
EVAL "echo \"ro.unica.device u:object_r:build_prop:s0 exact string\" >> \"$WORK_DIR/system/system/etc/selinux/plat_property_contexts\""

# Property identifying the UN1CA build as a whole
# This bundles the properties which aren't already part of Android OS
# unica/<ro.unica.device>:<MAJOR.MINOR.PATCH from ro.unica.version>/<8-digit commit hash from ro.unica.version><.dirty>/<ro.unica.timestamp>:<user/userdebug>/<release/test>-keys

# unica header + the target codename
FINGERPRINT="unica/${TARGET_CODENAME}:"

# version value is UN1CA version
FINGERPRINT+="$(grep -o "^[0-9]\+\.[0-9]\+\.[0-9]\+" <<< "$ROM_VERSION")/"

# build ID value is the UN1CA commit
FINGERPRINT+="$(cut -d "-" -f 2 <<< "$ROM_VERSION")"
# append .dirty if dirty
if grep -q -- "-dirty" <<< "$ROM_VERSION"; then
    FINGERPRINT+=".dirty/"
else
    FINGERPRINT+="/"
fi

# incremental value matching the UN1CA build timestamp
FINGERPRINT+="${ROM_BUILD_TIMESTAMP}:"

# user/userdebug reflecting $DEBUG
if $DEBUG; then
    FINGERPRINT+="userdebug/"
else
    FINGERPRINT+="user/"
fi

# test-keys/release-keys for $ROM_IS_OFFICIAL
if $ROM_IS_OFFICIAL; then
    FINGERPRINT+="release-keys"
else
    FINGERPRINT+="test-keys"
fi

SET_PROP "system" "ro.unica.fingerprint" "$FINGERPRINT"
EVAL "echo \"ro.unica.fingerprint u:object_r:build_prop:s0 exact string\" >> \"$WORK_DIR/system/system/etc/selinux/plat_property_contexts\""

unset FINGERPRINT

# Identify the actual backport input separately from user-selected build labels.
# The One UI 9 version profile keeps the compiled base and hardware API metadata.
if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ]; then
    SET_PROP "system" "ro.unica.qpr2.source.id" "CP41.260831.007.A3"
    SET_PROP "system" "ro.unica.qpr2.source.sdk_full" "37.2"
    SET_PROP "system" "ro.unica.qpr2.profile" "paradigm-clean5"
    SET_PROP "system" "ro.unica.qpr2.backports" \
        "companion,diagnostics,storage,usb,webcam,recording,subject-preview"
    EVAL "echo \"ro.unica.qpr2. u:object_r:build_prop:s0 prefix string\" >> \"$WORK_DIR/system/system/etc/selinux/plat_property_contexts\""

    # Preserve the user-selected QPR2 labels separately from the real Samsung
    # base. This is version metadata, not a new SDK or physical kernel release.
    SET_QPR2_PLATFORM_VERSION()
    {
        local PARTITION="$1"
        local OLD_ID OLD_INCREMENTAL VALUE PROP
        [ "$(GET_PROP "$PARTITION" "ro.${PARTITION}.build.version.sdk")" = "37" ] || return 0
        OLD_ID="$(GET_PROP "$PARTITION" "ro.${PARTITION}.build.id")"
        OLD_INCREMENTAL="$(GET_PROP "$PARTITION" "ro.${PARTITION}.build.version.incremental")"
        [ -n "$OLD_ID" ] && [ -n "$OLD_INCREMENTAL" ] || {
            ABORT "Missing One UI 9 $PARTITION version metadata"
            return 1
        }
        for PROP in "ro.${PARTITION}.build.fingerprint" "ro.build.fingerprint" "ro.build.description"; do
            VALUE="$(GET_PROP "$PARTITION" "$PROP")"
            if [ -n "$VALUE" ]; then
                VALUE="${VALUE//"$OLD_ID"/CP4A.261005.017}"
                VALUE="${VALUE//"$OLD_INCREMENTAL"/S942BXXU5CZJJ}"
                SET_PROP "$PARTITION" "$PROP" "$VALUE"
            fi
        done
        SET_PROP "$PARTITION" "ro.${PARTITION}.build.id" "CP4A.261005.017"
        SET_PROP "$PARTITION" "ro.${PARTITION}.build.version.incremental" "S942BXXU5CZJJ"
        SET_PROP "$PARTITION" "ro.${PARTITION}.build.version.sdk_full" "37.2"
        if [ "$(GET_PROP "$PARTITION" "ro.build.version.sdk")" = "37" ]; then
            SET_PROP "$PARTITION" "ro.build.id" "CP4A.261005.017"
            SET_PROP "$PARTITION" "ro.build.PDA" "S942BXXU5CZJJ"
            SET_PROP "$PARTITION" "ro.build.display.id" "CP4A.261005.017.S942BXXU5CZJJ"
            SET_PROP "$PARTITION" "ro.build.version.incremental" "S942BXXU5CZJJ"
            SET_PROP "$PARTITION" "ro.build.version.sdk_full" "37.2"
            SET_PROP "$PARTITION" "ro.build.version.oneui" "90500"
        fi
    }
    if [ -z "$(GET_PROP "system" "ro.unica.qpr2.base.sdk_full")" ]; then
        SET_PROP "system" "ro.unica.qpr2.base.sdk_full" "$(GET_PROP "system" "ro.build.version.sdk_full")"
        SET_PROP "system" "ro.unica.qpr2.base.build.id" "$(GET_PROP "system" "ro.build.id")"
    fi
    SET_PROP "system" "ro.unica.qpr2.base.knox.api" "41"
    SET_PROP "system" "ro.unica.qpr2.knox.version" "3.14"
    SET_PROP "system" "ro.unica.qpr2.knox.api" "41"
    SET_PROP "system" "ro.unica.qpr2.version_profile" "custom-czjj-r14"
    SET_QPR2_PLATFORM_VERSION "system"
    SET_QPR2_PLATFORM_VERSION "product"
    SET_QPR2_PLATFORM_VERSION "system_ext"
    unset -f SET_QPR2_PLATFORM_VERSION

    if [ "$TARGET_PLATFORM" = "exynos2100" ]; then
        # The donor advertises a VM relay endpoint. Retained Floppy has
        # CONFIG_VSOCKETS unset; libperfetto otherwise aborts startup with
        # EAFNOSUPPORT and init continuously restarts traced. Remove only
        # the optional relay listener, retaining both local tracing sockets.
        SET_PROP "product" "traced.relay_producer_port" --delete
    fi
fi
