if [[ "$TARGET_CODENAME" != "t2s" ]]; then
    return 0
fi

# Return an empty bounding-set bit only when the kernel does not implement the capability.
ADD_TO_WORK_DIR "m2sxxx" "system" "system/lib64/libunica_zygote_cap.so" 0 0 644 "u:object_r:system_lib_file:s0"
ADD_TO_WORK_DIR "m2sxxx" "system" "system/lib64/libcap_rust.dylib.so" 0 0 644 "u:object_r:system_lib_file:s0"
