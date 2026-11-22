DECODE_APK "system" "system/priv-app/SecSettings/SecSettings.apk"
for QUALIFIER in raw raw-night; do
    cp "$MODPATH/SecSettings.apk/res/$QUALIFIER/sec_nfc_antenna_animation.json" \
        "$APKTOOL_DIR/system/priv-app/SecSettings/SecSettings.apk/res/$QUALIFIER/sec_nfc_antenna_animation.json"
done
unset QUALIFIER
