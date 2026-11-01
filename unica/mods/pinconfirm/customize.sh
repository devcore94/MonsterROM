PINCONFIRM_SMALI_DIR="smali"
[ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ] && PINCONFIRM_SMALI_DIR="smali_classes2"
SMALI_PATCH "system" "system/framework/services.jar" \
    "$PINCONFIRM_SMALI_DIR/com/android/server/locksettings/LockSettingsService.smali" "replace" \
    'refreshStoredPinLength(I)Z' \
    'const/4 v0, 0x6' \
    'const/4 v0, 0x4'
# shellcheck disable=SC2016
SMALI_PATCH "system" "system/framework/services.jar" \
    "$PINCONFIRM_SMALI_DIR/com/android/server/locksettings/SyntheticPasswordManager.smali" "replace" \
    'createLskfBasedProtector(Landroid/service/gatekeeper/IGateKeeperService;Lcom/android/internal/widget/LockscreenCredential;JLcom/android/internal/widget/LockscreenCredential;Lcom/android/server/locksettings/SyntheticPasswordManager$SyntheticPassword;I)J' \
    'const/4 v12, 0x6' \
    'const/4 v12, 0x4'
# shellcheck disable=SC2016
SMALI_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
    "$PINCONFIRM_SMALI_DIR/com/android/settings/password/ChooseLockPassword\$ChooseLockPasswordFragment.smali" "replace" \
    'handleNext$2()V' \
    'const/4 v4, 0x6' \
    'const/4 v4, 0x4'
SMALI_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
    "$PINCONFIRM_SMALI_DIR/com/android/settings/password/ChooseLockPassword\$ChooseLockPasswordFragment.smali" "replace" \
    'setAutoPinConfirmOption(IZ)V' \
    'const/4 p2, 0x6' \
    'const/4 p2, 0x4'
if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ]; then
    # One UI 9 also gates the screen-lock preference on the current PIN length.
    SMALI_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
        "smali_classes2/com/android/settings/security/screenlock/AutoPinConfirmPreferenceController.smali" "replace" \
        'isAvailable()Z' \
        'const/4 v0, 0x6' \
        'const/4 v0, 0x4'
fi
unset PINCONFIRM_SMALI_DIR
