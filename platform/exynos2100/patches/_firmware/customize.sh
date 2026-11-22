if [[ "$TARGET_CODENAME" != "t2s" ]]; then
    return 0
fi

CHECK_FW_PROP()
{
    local VALUE
    VALUE="$(GET_PROP "$1" "$2")"
    if [[ "$VALUE" != "$3" ]]; then
        ABORT "Expected $2=$3 in /$1, found ${VALUE:-<missing>}"
    fi
}

# create_work_dir sets ro.product.device from the source ODM before staging target ODM.
CHECK_FW_PROP "system" "ro.product.device" "m2s"
CHECK_FW_PROP "system" "ro.build.version.oneui" "90500"
CHECK_FW_PROP "system" "ro.build.version.sdk_full" "37.2"
for PARTITION in system system_ext product; do
    CHECK_FW_PROP "$PARTITION" "ro.$PARTITION.build.version.incremental" "S947BXXU6ZZKN"
done

for PARTITION in vendor odm; do
    CHECK_FW_PROP "$PARTITION" "ro.product.$PARTITION.model" "SM-G996B"
    CHECK_FW_PROP "$PARTITION" "ro.$PARTITION.build.version.incremental" "G996BXXSJHZC2"
done

# The shared staging step installs the S22 flags when system_ext is folded into system.
ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" "system_ext" "etc/build_flags.json" 0 0 644 "u:object_r:system_file:s0" || ABORT
ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" "system_ext" "etc/NOTICE.xml.gz" 0 0 644 "u:object_r:system_file:s0" || ABORT

unset PARTITION
unset -f CHECK_FW_PROP
