EVAL "uniq \"$WORK_DIR/system/system/build.prop\" \"$WORK_DIR/system/system/tmp\" && mv -f \"$WORK_DIR/system/system/tmp\" \"$WORK_DIR/system/system/build.prop\""
SET_PROP "system" "debug.codec2.stop_hal_before_surface" "1"
SET_PROP "system" "ro.audio.spatializer_enabled" "true"
if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ]; then
    # One UI 9 moved these selectors to product; they must name the target APKs
    # imported by blobs, not the source's EX2600 placeholders.
    SET_PROP "product" "ro.gfx.driver.0" "com.samsung.gamedriver.ex2100"
    SET_PROP "product" "ro.gfx.driver.1" "com.samsung.pregpudriver.ex2100"
fi
EVAL "sed -i \"/PRODUCT_SYSTEM_DEFAULT_PROPERTIES/a ####################################\" \"$WORK_DIR/system/system/build.prop\""
