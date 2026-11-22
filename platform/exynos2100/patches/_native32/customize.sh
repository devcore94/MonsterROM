if [[ "$TARGET_CODENAME" != "t2s" ]]; then
    return 0
fi

NATIVE32_FW="$FW_DIR/SM-G990E_THL"
if [[ "$(GET_PROP "$NATIVE32_FW/system/system/build.prop" "ro.build.version.incremental")" != "G990EXXSOHZH4" ]]; then
    ABORT "Expected G990EXXSOHZH4 for the ARM32 vendor runtime"
fi

# Apply the base libraries before the platform's audio, camera and WFD replacements.
# The donor's module symlink belongs to its kernel partition layout.
for ENTRY in "$NATIVE32_FW/system/system/lib/"*; do
    FILE="system/lib/${ENTRY##*/}"
    [[ "$FILE" == "system/lib/modules" ]] && continue
    if [ -e "$WORK_DIR/system/$FILE" ] || [ -L "$WORK_DIR/system/$FILE" ]; then
        ABORT "Unexpected S26+ provider at /$FILE"
    fi
    ADD_TO_WORK_DIR "$NATIVE32_FW" "system" "$FILE" || ABORT "Failed to stage /$FILE"
done

for FILE in system/bin/bootstrap/linker system/bin/linker system/bin/boringssl_self_test32; do
    ADD_TO_WORK_DIR "$NATIVE32_FW" "system" "$FILE" || ABORT "Failed to stage /$FILE"
done

unset ENTRY FILE NATIVE32_FW
