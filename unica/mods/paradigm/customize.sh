# The S26+ Photo Editor and Samsung AI Core already ship together. Keep their
# original version codes and the Gallery models installed by the SAIV module.
for FILE in system/etc/ringtones_count_list.txt system/media/audio/ringtones system/media/audio/notifications \
        system/media/audio/ui/Media_preview_Over_the_horizon.ogg \
        system/hidden/INTERNAL_SDCARD/Music/Samsung/Over_the_Horizon.m4a; do
    ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" "system" "$FILE"
done
unset FILE
