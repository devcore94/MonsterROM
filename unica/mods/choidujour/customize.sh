# shellcheck disable=SC2034
SKIPUNZIP=1

if ! $ROM_IS_OFFICIAL; then
    LOG "\033[0;33m! Build is not official. Skipping\033[0m"
    return 0
fi

ADD_TO_WORK_DIR "$MODPATH" "system" "." 0 0 755 "u:object_r:system_file:s0"

LOG "- Patching /system/system/etc/security/otacerts.zip"
EVAL "rm \"$WORK_DIR/system/system/etc/security/otacerts.zip\""
EVAL "cd \"$SRC_DIR\"; zip -q \"$WORK_DIR/system/system/etc/security/otacerts.zip\" \"./security/unica_ota.x509.pem\""

DECODE_APK "system" "system/priv-app/SecSettings/SecSettings.apk"

APPLY_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
    "$MODPATH/suggestions/SecSettings.apk/0001-Launch-UN1CA-Updates-from-suggestions.patch"

# Android 17 removed SoftwareUpdateUtils.isOTAUpgradeAllowed. Hide the stock
# FOTA entry points without hiding GPSU/Mainline or our updater.
SMALI_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
    "smali_classes3/com/samsung/android/settings/privacy/SecurityDashboardUtils.smali" "return" \
    'isSecurityUpdateSupported(Landroid/content/Context;)Z' 'false'
SMALI_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
    "smali_classes3/com/samsung/android/settings/homepage/TopLevelSoftwareUpdatePreferenceController.smali" "return" \
    'getAvailabilityStatus()I' '3'

# ChoiDujour's Settings payload uses the same bounded literal injector as the
# Settings module (including its first-line homepage insertion directive).
EVAL "bash \"$SRC_DIR/unica/mods/settings/customize.sh\" --inject \"$APKTOOL_DIR/system/priv-app/SecSettings/SecSettings.apk\" \"$MODPATH/SecSettings.apk\""
