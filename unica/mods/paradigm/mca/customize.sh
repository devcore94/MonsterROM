# Restore original Paradigm MCA highlight analysis using the One UI 9 JNI/runtime.
# Sourced by customize.sh inside its One UI 9 branch.
[ "$SOURCE_PLATFORM_SDK_VERSION" = 37 ] || { ABORT "MCA adaptation requires One UI 9"; return 1; }
[ "$TARGET_PLATFORM" = exynos2100 ] || { ABORT "MCA GPU adaptation requires Exynos2100"; return 1; }
case "$TARGET_CODENAME" in o1s|t2s|p3s|r9s) ;; *) ABORT "Unreviewed MCA target: $TARGET_CODENAME"; return 1 ;; esac
MCA_DIR="$MODPATH/mca"
MCA_LIB="$WORK_DIR/system/system/lib64/libmediacontextanalyzer.so"
python3 "$MCA_DIR/apply.py" --target "$TARGET_CODENAME" --aliases "$WORK_DIR/system/system/etc/mediacontextanalyzer" --library "$MCA_LIB" --models "$SRC_DIR/prebuilts/samsung/a56xnaxx/system/etc/mediacontextanalyzer" || { ABORT "MCA source contract failed"; return 1; }
for MCA_MODEL in human-pet-det_SR-V131.tflite human-pet-pose_SR-V200.tflite keyword-classification_SR-V031.tflite; do
    ADD_TO_WORK_DIR "a56xnaxx" "system" "system/etc/mediacontextanalyzer/$MCA_MODEL" 0 0 644 "u:object_r:system_file:s0" || return 1
done
python3 "$MCA_DIR/apply.py" --target "$TARGET_CODENAME" --models "$WORK_DIR/system/system/etc/mediacontextanalyzer" || { ABORT "MCA installed model contract failed"; return 1; }
for MCA_ALIAS in Detection:human-pet-det_SR-V131.tflite Pose:human-pet-pose_SR-V200.tflite Keyword:keyword-classification_SR-V031.tflite; do
    ln -sfn "${MCA_ALIAS#*:}" "$WORK_DIR/system/system/etc/mediacontextanalyzer/${MCA_ALIAS%%:*}.tfl" || return 1
    SET_METADATA "system" "system/etc/mediacontextanalyzer/${MCA_ALIAS%%:*}.tfl" 0 0 644 "u:object_r:system_file:s0" || return 1
done
python3 "$MCA_DIR/apply.py" --target "$TARGET_CODENAME" --library "$MCA_LIB" --apply || { ABORT "MCA native adaptation failed"; return 1; }
SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_MMFW_CONFIG_MEDIA_CONTEXT_ANALYZER_CORE" "GPU" || return 1
SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_MMFW_SUPPORT_MEDIA_CONTEXT_ANALYZER" "TRUE" || return 1
unset MCA_DIR MCA_LIB MCA_MODEL MCA_ALIAS
