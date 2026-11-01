DECODE_APK "system" "system/framework/framework.jar"
# Leave headroom in the donor's classes3.dex for added cross-dex hook references.
KEYBOX_BASE="$APKTOOL_DIR/system/framework/framework.jar"
[ -f "$KEYBOX_BASE/smali_classes3/android/os/BaseBundle.smali" ] && \
    [ ! -e "$KEYBOX_BASE/smali_classes8/android/os/BaseBundle.smali" ] || \
    ABORT "Unexpected One UI 9 BaseBundle dex layout"
EVAL "mkdir -p \"$KEYBOX_BASE/smali_classes8/android/os\""
EVAL "mv \"$KEYBOX_BASE/smali_classes3/android/os/BaseBundle.smali\" \"$KEYBOX_BASE/smali_classes8/android/os/BaseBundle.smali\""
unset KEYBOX_BASE
APPLY_PATCH "system" "system/framework/framework.jar" \
    "$MODPATH/helpers/framework.jar/0001-Introduce-KeyboxImitationHooks.patch"
for KEYBOX_PATCH in "$MODPATH/framework.jar/"*.patch; do
    APPLY_PATCH "system" "system/framework/framework.jar" "$KEYBOX_PATCH"
done
unset KEYBOX_PATCH
