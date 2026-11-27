SKIPUNZIP=1

for DOCSCAN_LIB in libSmartScan.camera.samsung.so libDocRectifyWrapper.camera.samsung.so; do
    ADD_TO_WORK_DIR "$MODPATH" "system" "system/lib64/$DOCSCAN_LIB" 0 0 644 "u:object_r:system_lib_file:s0"
done

unset DOCSCAN_LIB
