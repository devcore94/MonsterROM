SMALI_PATCH "system" "system/framework/services.jar" \
    "smali_classes2/com/android/server/locksettings/SyntheticPasswordManager.smali" "replace" \
    'refreshPinLengthOnDisk(Landroid/app/admin/PasswordMetrics;JI)Z' \
    'const/4 p1, 0x6' \
    'const/4 p1, 0x4'
# shellcheck disable=SC2016
SMALI_PATCH "system" "system/framework/services.jar" \
    "smali_classes2/com/android/server/locksettings/SyntheticPasswordManager.smali" "replace" \
    'createLskfBasedProtector(Landroid/service/gatekeeper/IGateKeeperService;Lcom/android/internal/widget/LockscreenCredential;JLcom/android/internal/widget/LockscreenCredential;Lcom/android/server/locksettings/SyntheticPassword;I)Lcom/android/server/locksettings/SyntheticPasswordManager$CreatedLskfBasedProtectorIds;' \
    'const/4 v12, 0x6' \
    'const/4 v12, 0x4'
# shellcheck disable=SC2016
SMALI_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
    "smali_classes2/com/android/settings/password/ChooseLockPassword\$ChooseLockPasswordFragment.smali" "replace" \
    'handleNext$2()V' \
    'const/4 v2, 0x6' \
    'const/4 v2, 0x4'
SMALI_PATCH "system" "system/priv-app/SecSettings/SecSettings.apk" \
    "smali_classes2/com/android/settings/password/ChooseLockPassword\$ChooseLockPasswordFragment.smali" "replace" \
    'setAutoPinConfirmOption(IZ)V' \
    'const/4 p2, 0x6' \
    'const/4 p2, 0x4'
