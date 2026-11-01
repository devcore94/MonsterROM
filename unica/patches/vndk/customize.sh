if [[ "$SOURCE_BOARD_API_LEVEL" == "$TARGET_BOARD_API_LEVEL" ]]; then
    LOG "\033[0;33m! Nothing to do\033[0m"
    return 0
fi

# [
ADD_TARGET_VNDK_APEX() {
    local TARGET_FW_PATH
    TARGET_FW_PATH="$FW_DIR/$(cut -d "/" -f 1 <<< "$TARGET_FIRMWARE")_$(cut -d "/" -f 2 <<< "$TARGET_FIRMWARE")"
    if [ -f "$TARGET_FW_PATH/system_ext/apex/com.android.vndk.v$TARGET_BOARD_API_LEVEL.apex" ] || \
            [ -f "$TARGET_FW_PATH/system/system/system_ext/apex/com.android.vndk.v$TARGET_BOARD_API_LEVEL.apex" ]; then
        ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system_ext" "apex/com.android.vndk.v$TARGET_BOARD_API_LEVEL.apex" \
            0 0 644 "u:object_r:system_file:s0"
        return 0
    fi
    case "$TARGET_BOARD_API_LEVEL" in
        "30")
            ADD_TO_WORK_DIR "a73xqxx" "system_ext" "apex/com.android.vndk.v30.apex" 0 0 644 "u:object_r:system_file:s0"
            ;;
        "31")
            ADD_TO_WORK_DIR "b0qxxx" "system_ext" "apex/com.android.vndk.v31.apex" 0 0 644 "u:object_r:system_file:s0"
            ;;
        "32")
            ADD_TO_WORK_DIR "b4qxxx" "system_ext" "apex/com.android.vndk.v32.apex" 0 0 644 "u:object_r:system_file:s0"
            ;;
        "33")
            ADD_TO_WORK_DIR "dm1qxxx" "system_ext" "apex/com.android.vndk.v33.apex" 0 0 644 "u:object_r:system_file:s0"
            ;;
        "34")
            ADD_TO_WORK_DIR "gta9pxxx" "system_ext" "apex/com.android.vndk.v34.apex" 0 0 644 "u:object_r:system_file:s0"
            ;;
        *)
            ABORT "No APEX blob available for VNDK $TARGET_BOARD_API_LEVEL"
            ;;
    esac
}
# ]

if $TARGET_OS_BUILD_SYSTEM_EXT_PARTITION; then
    SYS_EXT_DIR="$WORK_DIR/system_ext"
else
    SYS_EXT_DIR="$WORK_DIR/system/system/system_ext"
fi

if [ "$SOURCE_BOARD_API_LEVEL" -gt "34" ] && [ "$TARGET_BOARD_API_LEVEL" -gt "34" ]; then
    :
elif [ "$SOURCE_BOARD_API_LEVEL" -gt "34" ] && [ "$TARGET_BOARD_API_LEVEL" -le "34" ]; then
    ADD_TARGET_VNDK_APEX
    SET_PROP "system_ext" "ro.vndk.version" "$TARGET_BOARD_API_LEVEL"
    LOG "- Patching ${SYS_EXT_DIR//$WORK_DIR/}/etc/vintf/manifest.xml"
    EVAL "sed -i \"\\\$d\" \"$SYS_EXT_DIR/etc/vintf/manifest.xml\""
    {
        echo "    <vendor-ndk>"
        echo "        <version>$TARGET_BOARD_API_LEVEL</version>"
        echo "    </vendor-ndk>"
        echo "</manifest>"
    } >> "$SYS_EXT_DIR/etc/vintf/manifest.xml"
elif [ "$SOURCE_BOARD_API_LEVEL" -le "34" ] && [ "$TARGET_BOARD_API_LEVEL" -gt "34" ]; then
    DELETE_FROM_WORK_DIR "system_ext" "apex/com.android.vndk.v$SOURCE_BOARD_API_LEVEL.apex"
    LOG "- Patching ${SYS_EXT_DIR//$WORK_DIR/}/etc/vintf/manifest.xml"
    EVAL "sed -i -e \"/vendor-ndk/d\" -e \"/version>/d\" \"$SYS_EXT_DIR/etc/vintf/manifest.xml\""
elif [ ! -f "$SYS_EXT_DIR/apex/com.android.vndk.v$TARGET_BOARD_API_LEVEL.apex" ]; then
    DELETE_FROM_WORK_DIR "system_ext" "apex/com.android.vndk.v$SOURCE_BOARD_API_LEVEL.apex"
    ADD_TARGET_VNDK_APEX
    LOG "- Patching ${SYS_EXT_DIR//$WORK_DIR/}/etc/vintf/manifest.xml"
    EVAL "sed -i \"s/version>$SOURCE_BOARD_API_LEVEL/version>$TARGET_BOARD_API_LEVEL/g\" \"$SYS_EXT_DIR/etc/vintf/manifest.xml\""
fi

unset SYS_EXT_DIR
unset -f ADD_TARGET_VNDK_APEX

if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ] && [ "$TARGET_PLATFORM" = "exynos2100" ]; then
    COMPAT32_ROOT="$FW_DIR/SM-G990E_THL"
    if [ "$(GET_PROP "$COMPAT32_ROOT/system/system/build.prop" "ro.build.version.sdk")" != "36" ]; then
        ABORT "ARM32 compatibility needs the reviewed S21 FE SDK-36 firmware"
        return 1
    fi
    LOG_STEP_IN "- Restoring native ARM32 compatibility (not 32-bit app/ART support)"

    # stock_blobs has already chosen the target audio pair, including removals.
    # Never reintroduce the S21 FE's SoundBooster 1070 on a 1050 target, or
    # overwrite a wrapper/other native file selected by an earlier module.
    COMPAT32_STAGEFRIGHT_ADDED=false
    while IFS= read -r -d '' COMPAT32_FILE; do
        COMPAT32_FILE="${COMPAT32_FILE#"$COMPAT32_ROOT/system/"}"
        case "$COMPAT32_FILE" in
            system/lib/lib_SoundAlive_play_plus_ver*.so|system/lib/libaudiosaplus_sec_legacy.so|\
            system/lib/lib_SoundBooster_ver*.so|system/lib/libsamsungSoundbooster_plus_legacy.so|\
            system/lib/libmysound_legacy.so)
                continue
                ;;
        esac
        if [ ! -e "$WORK_DIR/system/$COMPAT32_FILE" ] && [ ! -L "$WORK_DIR/system/$COMPAT32_FILE" ]; then
            ADD_TO_WORK_DIR "$COMPAT32_ROOT" "system" "$COMPAT32_FILE" || return 1
            if [ "$COMPAT32_FILE" = "system/lib/libstagefright.so" ]; then
                COMPAT32_STAGEFRIGHT_ADDED=true
            fi
        fi
    done < <(find "$COMPAT32_ROOT/system/system/lib" \( -type f -o -type l \) -print0)
    unset COMPAT32_FILE

    # Camera ran before libstagefright32 existed. Apply its exact model-property
    # substitution now, after the graft, using the original HEX_PATCH function.
    if $COMPAT32_STAGEFRIGHT_ADDED; then
        HEX_PATCH "$WORK_DIR/system/system/lib/libstagefright.so" \
            "726f2e70726f647563742e6d6f64656c00" "726f2e626f6f742e656d2e6d6f64656c00" || return 1
    fi
    unset COMPAT32_STAGEFRIGHT_ADDED
    ADD_TO_WORK_DIR "$COMPAT32_ROOT" "system" "system/bin/linker" 0 2000 755 "u:object_r:system_linker_exec:s0" || return 1

    # Only native Bionic/ICU providers are added. Preserve all One UI 9 ARM64,
    # Java, ART and data providers and the existing platform/AVB signing path.
    bash "$MODPATH/compat32/build-apex.sh" runtime || return 1
    bash "$MODPATH/compat32/build-apex.sh" i18n || return 1
    SET_PROP "system" "ro.unica.compat32" "s21fe-api36-native-only" || return 1
    SET_PROP "system" "ro.unica.compat32.icu" "s21fe-api36-native-only" || return 1

    # The donor retains 64-bit ART. Native ARM32 does not supply a 32-bit app runtime.
    if [ ! -x "$WORK_DIR/system/system/bin/app_process64" ] || [ -e "$WORK_DIR/system/system/bin/app_process32" ]; then
        ABORT "Review native-only ARM32 boot setup"
        return 1
    fi
    SET_PROP "vendor" "ro.zygote" "zygote64" || return 1
    SET_PROP "system" "ro.product.cpu.abilist" "arm64-v8a" || return 1
    SET_PROP "system" "ro.product.cpu.abilist64" "arm64-v8a" || return 1
    SET_PROP "system" "ro.product.cpu.abilist32" "" || return 1
    ADD_TO_WORK_DIR "$COMPAT32_ROOT" "system" "system/bin/boringssl_self_test32" \
        0 2000 755 "u:object_r:boringssl_self_test_exec:s0" || return 1
    ADD_TO_WORK_DIR "$MODPATH/compat32/boot" "system" "system/etc/init/unica.native32-selftest.rc" \
        0 0 644 "u:object_r:system_file:s0" || return 1

    # Keep the real system/vendor32 self-tests and their stock failure policy.
    for COMPAT32_CRYPTO in bin/boringssl_self_test32 lib/libcrypto.so; do
        cmp -s "$WORK_DIR/system/system/$COMPAT32_CRYPTO" "$COMPAT32_ROOT/system/system/$COMPAT32_CRYPTO" || return 1
    done
    COMPAT32_SOURCE="$FW_DIR/${SOURCE_FIRMWARE%%/*}_$(cut -d / -f 2 <<< "$SOURCE_FIRMWARE")"
    for COMPAT32_CRYPTO in bin/boringssl_self_test64 lib64/libcrypto.so apex/com.google.android.conscrypt_compressed.apex; do
        cmp -s "$WORK_DIR/system/system/$COMPAT32_CRYPTO" "$COMPAT32_SOURCE/system/system/$COMPAT32_CRYPTO" || return 1
    done
    for COMPAT32_SERVICE in boringssl_self_test32 boringssl_self_test64 boringssl_self_test_apex32 boringssl_self_test_apex64; do
        sed -n "/^service $COMPAT32_SERVICE /,/^$/p" "$WORK_DIR/system/system/etc/init/hw/init.rc" | \
            grep -q 'reboot_on_failure reboot,boringssl-self-check-failed' || return 1
    done
    grep -q 'service boringssl_self_test32_vendor /vendor/bin/boringssl_self_test32' \
        "$WORK_DIR/vendor/etc/init/boringssl_self_test.rc" || return 1
    grep -q 'reboot_on_failure reboot,boringssl-self-check-failed' \
        "$WORK_DIR/vendor/etc/init/boringssl_self_test.rc" || return 1
    LOG_STEP_OUT
    unset COMPAT32_ROOT COMPAT32_CRYPTO COMPAT32_SOURCE COMPAT32_SERVICE
fi
