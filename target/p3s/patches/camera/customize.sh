# Add camera libs
ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/lib64/libsame_source_hdr.arcsoft.so" 0 0 644 "u:object_r:system_lib_file:s0"
EVAL "echo \"libsame_source_hdr.arcsoft.so\" >> \"$WORK_DIR/system/system/etc/public.libraries-arcsoft.txt\""
ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/lib64/libsuperresolution_raw.arcsoft.so" 0 0 644 "u:object_r:system_lib_file:s0"
EVAL "echo \"libsuperresolution_raw.arcsoft.so\" >> \"$WORK_DIR/system/system/etc/public.libraries-arcsoft.txt\""
ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/lib64/libsuperresolutionraw_wrapper_v2.camera.samsung.so" 0 0 644 "u:object_r:system_lib_file:s0"
ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/lib64/libuwsuperresolution.arcsoft.so" 0 0 644 "u:object_r:system_lib_file:s0"
EVAL "echo \"libuwsuperresolution.arcsoft.so\" >> \"$WORK_DIR/system/system/etc/public.libraries-arcsoft.txt\""
ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/lib64/libuwsuperresolution_wrapper_v1.camera.samsung.so" 0 0 644 "u:object_r:system_lib_file:s0"
EVAL "echo \"libuwsuperresolution_wrapper_v1.camera.samsung.so\" >> \"$WORK_DIR/system/system/etc/public.libraries-camera.samsung.txt\""

case "$SOURCE_PLATFORM_SDK_VERSION" in
    36)
        APPLY_PATCH "system" "system/priv-app/SamsungCamera/SamsungCamera.apk" \
            "$MODPATH/SamsungCamera.apk/0001-Fix-ArcSsHdrNodeBase-NPE.patch" || return 1
        ;;
    37)
        # One UI 9 passes ImageInfo/ExtraBundle directly to makeSsHdr() and no
        # longer has the two ArcSsHdrNodeBase fields used by the SDK36 fix.
        LOG "- Skipping SDK36 ArcSsHdrNodeBase fix on One UI 9"
        ;;
    *)
        ABORT "Unsupported source SDK: $SOURCE_PLATFORM_SDK_VERSION" || return 1
        ;;
esac
