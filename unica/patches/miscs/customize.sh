CORE_RUNE_DEX="smali_classes6"
if [[ "$TARGET_CODENAME" == "t2s" ]]; then
    CORE_RUNE_DEX="smali_classes5"
else
    SET_PROP_IF_DIFF "vendor" "ro.oem_unlock_supported" "0"
fi

# Better device/model detection in CoreRune
SMALI_PATCH "system" "system/framework/framework.jar" \
    "$CORE_RUNE_DEX/com/samsung/android/rune/CoreRune.smali" "replace" \
    '<clinit>()V' \
    'ro.product.model' \
    'ro.product.vendor.model'
SMALI_PATCH "system" "system/framework/framework.jar" \
    "$CORE_RUNE_DEX/com/samsung/android/rune/CoreRune.smali" "replace" \
    '<clinit>()V' \
    'ro.product.device' \
    'ro.product.vendor.device'

# Better model detection in FreecessController
SMALI_PATCH "system" "system/framework/services.jar" \
    "smali/com/android/server/am/FreecessController.smali" "replace" \
    '<clinit>()V' \
    'ro.product.model' \
    'ro.product.vendor.model'

unset CORE_RUNE_DEX

if [[ "$TARGET_CODENAME" != "t2s" ]]; then
    # shellcheck disable=SC2016
    # Disable RescueParty
    SMALI_PATCH "system" "system/framework/services.jar" \
        "smali/com/android/server/RescueParty.smali" "return" \
        '-$$Nest$smisDisabled()Z' \
        'true'
    APPLY_PATCH "system" "system/framework/services.jar" \
        "$MODPATH/vendor_warning/services.jar/0001-Disable-vendor-mismatch-warning.patch"
fi
