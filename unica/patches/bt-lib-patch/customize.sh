if [ ! -f "$WORK_DIR/system/system/lib64/libbluetooth_jni.so" ]; then
    LOG_STEP_IN "- Extracting libbluetooth_jni.so from com.android.bt.apex"

    if [ -d "$TMP_DIR" ]; then
        EVAL "rm -rf \"$TMP_DIR\""
    fi
    mkdir -p "$TMP_DIR"

    EVAL "unzip -j \"$WORK_DIR/system/system/apex/com.android.bt.apex\" \"apex_payload.img\" -d \"$TMP_DIR\""

    if command -v e2cp > /dev/null 2>&1; then
        EVAL "e2cp \"$TMP_DIR/apex_payload.img:/lib64/libbluetooth_jni.so\" \"$WORK_DIR/system/system/lib64/libbluetooth_jni.so\""
    elif command -v debugfs > /dev/null 2>&1; then
        EVAL "debugfs -R \"dump -p /lib64/libbluetooth_jni.so $WORK_DIR/system/system/lib64/libbluetooth_jni.so\" \"$TMP_DIR/apex_payload.img\""
    else
        ABORT "Neither e2cp nor debugfs is available to unpack APEX image"
    fi

    rm -rf "$TMP_DIR"

    SET_METADATA "system" "system/lib64/libbluetooth_jni.so" 0 0 644 "u:object_r:system_lib_file:s0"

    LOG_STEP_OUT
fi

# Disable VaultKeeper support
# Before: [tbnz w8, #0, #0xXXXXXX]
# After: [b #0xXXXXXX]
HEX_PATCH "$WORK_DIR/system/system/lib64/libbluetooth_jni.so" \
"00122a0140395f01086b00020054" "00122a0140395f01086bde030014"
