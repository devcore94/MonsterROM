if [[ "$TARGET_CODENAME" != "t2s" ]]; then
    return 0
fi

# The t2s vendor targets FCM level 5. The S26+ framework starts at level 7.
for LEVEL in 5 6; do
    ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/etc/vintf/compatibility_matrix.$LEVEL.xml"
done
unset LEVEL
