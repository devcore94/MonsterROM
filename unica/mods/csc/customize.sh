# Enable Power off lock feature
SMALI_PATCH "system" "system/framework/framework.jar" \
    "smali_classes6/com/samsung/android/globalactions/util/SystemPropertiesWrapper.smali" "return" \
    'isBrazilianCountryISO()Z' 'true'
SMALI_PATCH "system_ext" "priv-app/SystemUI/SystemUI.apk" \
    "smali_classes2/com/android/systemui/bixby2/controller/DeviceController.smali" "return" \
    'isSupportPowerOffLock()Z' 'true'

# Hide Remote management tile in Settings app
# This donor removed the remote-management tile and its controller.
DECODE_APK "system" "system/priv-app/SecSettings/SecSettings.apk"
if grep -q 'TopLevelRemoteSupportPreferenceController' \
        "$APKTOOL_DIR/system/priv-app/SecSettings/SecSettings.apk/res/xml/sec_top_level_settings.xml"; then
    ABORT "Unexpected One UI 9 remote-management tile contract"
fi
LOG "- The One UI 9 remote-management tile is already absent"
