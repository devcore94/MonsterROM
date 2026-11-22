if [[ "$TARGET_CODENAME" != "t2s" ]]; then
    return 0
fi

if [ -f "$WORK_DIR/vendor/ueventd.rc" ]; then
    if [ -f "$WORK_DIR/vendor/etc/ueventd.rc" ] && ! cmp -s "$WORK_DIR/vendor/ueventd.rc" "$WORK_DIR/vendor/etc/ueventd.rc"; then
        ABORT "Conflicting vendor ueventd rules"
    fi
    LOG "- Moving /vendor/ueventd.rc to /vendor/etc/ueventd.rc"
    cp -p "$WORK_DIR/vendor/ueventd.rc" "$WORK_DIR/vendor/etc/ueventd.rc"
    DELETE_FROM_WORK_DIR "vendor" "ueventd.rc"
fi

[ -s "$WORK_DIR/vendor/etc/ueventd.rc" ] || ABORT "Missing /vendor/etc/ueventd.rc"
SET_METADATA "vendor" "etc/ueventd.rc" 0 0 644 "u:object_r:vendor_configs_file:s0"
