# One UI 9 Settings publishes AndroidBiometrics, which Samsung's base RRO omits.
# Keep that OEM-signed overlay and the Permission APEX intact; add a separate RRO.
[ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ] || return 0

# Isolate cleanup from the sourced parent module's EXIT handler.
(
    SAFETY_BUILD="$(mktemp -d "$OUT_DIR/qpr2-safety-center.XXXXXX")" || exit 1
    trap 'rm -rf -- "$SAFETY_BUILD"' EXIT
    mkdir -p "$SAFETY_BUILD/src" "$SAFETY_BUILD/staged/product/overlay" || exit 1
    EVAL "cp -a -T \"$MODPATH/src/.\" \"$SAFETY_BUILD/src/.\"" || exit 1

    # Samsung shortens resource ZIP paths. Use the existing decoder to recover
    # their resource-table names outside the global APK rebuild queue.
    APKTOOL_DIR="$SAFETY_BUILD/base-apktool" "$SRC_DIR/scripts/apktool.sh" d \
        product overlay/SafetyCenterOverlay.apk || exit 1
    for SAFETY_VARIANT in raw raw-v37; do
        mkdir -p "$SAFETY_BUILD/src/res/$SAFETY_VARIANT" || exit 1
        EVAL "cp \"$SAFETY_BUILD/base-apktool/product/overlay/SafetyCenterOverlay.apk/res/raw-v37/safety_center_config_overlay.xml\" \"$SAFETY_BUILD/src/res/$SAFETY_VARIANT/unica_safety_center_config.xml\"" || exit 1
    done
    EVAL "git apply --check --unsafe-paths --directory=\"$SAFETY_BUILD/src\" \"$MODPATH/0001-Register-Settings-biometric-safety-source.patch\"" || exit 1
    EVAL "git apply --unsafe-paths --directory=\"$SAFETY_BUILD/src\" \"$MODPATH/0001-Register-Settings-biometric-safety-source.patch\"" || exit 1
    # Use the same shared compiler and normalized framework as Apktool.
    EVAL "unzip -p \"$TOOLS_DIR/bin/apktool.jar\" prebuilt/linux/aapt2 > \"$SAFETY_BUILD/aapt2\"" || exit 1
    chmod 755 "$SAFETY_BUILD/aapt2" || exit 1
    SAFETY_FRAMEWORK="$TOOLS_DIR/apktool/framework/1-$(GET_PROP system ro.build.version.incremental).apk"
    EVAL "\"$SAFETY_BUILD/aapt2\" compile --dir \"$SAFETY_BUILD/src/res\" -o \"$SAFETY_BUILD/compiled.zip\"" || exit 1
    EVAL "\"$SAFETY_BUILD/aapt2\" link --auto-add-overlay -I \"$SAFETY_FRAMEWORK\" --manifest \"$SAFETY_BUILD/src/AndroidManifest.xml\" --min-sdk-version 37 --target-sdk-version 37 -o \"$SAFETY_BUILD/unsigned.apk\" \"$SAFETY_BUILD/compiled.zip\"" || exit 1
    SAFETY_KEY=aosp
    $ROM_IS_OFFICIAL && SAFETY_KEY=unica
    EVAL "signapk \"$SRC_DIR/security/${SAFETY_KEY}_platform.x509.pem\" \"$SRC_DIR/security/${SAFETY_KEY}_platform.pk8\" \"$SAFETY_BUILD/unsigned.apk\" \"$SAFETY_BUILD/staged/product/overlay/UnicaSafetyCenterOverlay.apk\"" || exit 1
    ADD_TO_WORK_DIR "$SAFETY_BUILD/staged" product overlay/UnicaSafetyCenterOverlay.apk \
        0 0 644 u:object_r:system_file:s0 || exit 1
) || return 1
