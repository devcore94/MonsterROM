# Scene resources and the live wallpaper service must come from the same build.
for APP in wallpaper-res SpriteWallpaper; do
    ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" "system" "system/priv-app/$APP/$APP.apk"
done
unset APP
