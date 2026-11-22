if [[ "$TARGET_CODENAME" != "t2s" ]]; then
    return 0
fi

STOCK_PLATFORM_APK="$FW_DIR/SM-S947B_EUX/system/system/framework/framework-res.apk"
SIGNER_CLASSES="$(mktemp -d "$OUT_DIR/platform-signer.XXXXXX")"
javac -classpath "$TOOLS_DIR/bin/signapk.jar" -d "$SIGNER_CLASSES" "$SRC_DIR/security/monsterrom/PlatformSigner.java"
java -Xmx1g -classpath "$SIGNER_CLASSES:$TOOLS_DIR/bin/signapk.jar" PlatformSigner \
    "$STOCK_PLATFORM_APK" "$SRC_DIR/security/aosp_platform.x509.pem" "$SRC_DIR/security/aosp_platform.pk8" "$WORK_DIR"
rm "$SIGNER_CLASSES/PlatformSigner.class"
rmdir "$SIGNER_CLASSES"
unset SIGNER_CLASSES STOCK_PLATFORM_APK
