if [[ "$TARGET_CODENAME" != "t2s" ]]; then
    return 0
fi

STOCK_PLATFORM_APK="$FW_DIR/SM-S947B_EUX/system/system/framework/framework-res.apk"
SIGNER_CLASSES="$(mktemp -d "$OUT_DIR/platform-signer.XXXXXX")"
javac -classpath "$TOOLS_DIR/bin/signapk.jar" -d "$SIGNER_CLASSES" "$SRC_DIR/security/monsterrom/PlatformSigner.java"
"$SRC_DIR/security/monsterrom/prepare-apex-keys.sh"
for MODULE in com.android.bt com.android.nfcservices com.android.uwb com.android.webapp com.android.wifi; do
    COUNT=1
    [[ "$MODULE" == "com.android.wifi" ]] && COUNT=3
    "$SRC_DIR/security/monsterrom/resign-apex.sh" "$MODULE" "$SIGNER_CLASSES" "$COUNT"
    if [ ! -f "$WORK_DIR/system/system/apex/$MODULE.apex" ]; then
        ABORT "APEX resigning did not produce /system/system/apex/$MODULE.apex"
    fi
    if ! unzip -t "$WORK_DIR/system/system/apex/$MODULE.apex" > /dev/null; then
        ABORT "APEX archive validation failed for /system/system/apex/$MODULE.apex"
    fi
    SET_METADATA "system" "system/apex/$MODULE.apex" 0 0 644 "u:object_r:system_file:s0"
    if [ -f "$WORK_DIR/system/system/apex/$MODULE.capex" ]; then
        DELETE_FROM_WORK_DIR "system" "system/apex/$MODULE.capex"
    fi
    if [ -e "$WORK_DIR/system/system/apex/$MODULE.capex" ]; then
        ABORT "Stale compressed APEX remained after resigning $MODULE"
    fi
done
unset MODULE COUNT

if find "$WORK_DIR/system/system/apex" -maxdepth 1 -type f -name '*.capex' -print -quit | grep -q .; then
    ABORT "A compressed APEX remained in the final t2s system tree"
fi

java -Xmx1g -classpath "$SIGNER_CLASSES:$TOOLS_DIR/bin/signapk.jar" PlatformSigner \
    "$STOCK_PLATFORM_APK" "$SRC_DIR/security/aosp_platform.x509.pem" "$SRC_DIR/security/aosp_platform.pk8" "$WORK_DIR"
rm "$SIGNER_CLASSES/PlatformSigner.class"
rmdir "$SIGNER_CLASSES"
unset SIGNER_CLASSES STOCK_PLATFORM_APK

source "$MODPATH/fsverity/customize.sh"
