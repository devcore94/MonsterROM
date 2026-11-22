if [[ "$TARGET_CODENAME" == "t2s" ]]; then
    SET_PROP "system" "debug.codec2.stop_hal_before_surface" "1"
    SET_PROP "system" "ro.audio.spatializer_enabled" "true"
    SET_PROP "vendor" "ro.sf.init.lcd_density" "$(GET_PROP "vendor" "ro.sf.lcd_density")"
    # The S26 selects its updatable graphics drivers in product.
    SET_PROP "product" "ro.gfx.driver.0" "$(GET_PROP "vendor" "ro.gfx.driver.0")"
    SET_PROP "product" "ro.gfx.driver.1" "$(GET_PROP "vendor" "ro.gfx.driver.1")"
    return 0
fi

EVAL "uniq \"$WORK_DIR/system/system/build.prop\" \"$WORK_DIR/system/system/tmp\" && mv -f \"$WORK_DIR/system/system/tmp\" \"$WORK_DIR/system/system/build.prop\""
LOG "- Adding \"debug.codec2.stop_hal_before_surface\" prop with \"1\" in /system/system/build.prop"
EVAL "sed -i \"/spatializer_enabled=true/a debug.codec2.stop_hal_before_surface=1\" \"$WORK_DIR/system/system/build.prop\""
EVAL "sed -i \"/stop_hal_before_surface/i ro.audio.spatializer_enabled=true\" \"$WORK_DIR/system/system/build.prop\""
EVAL "sed -i \"/PRODUCT_SYSTEM_DEFAULT_PROPERTIES/a ####################################\" \"$WORK_DIR/system/system/build.prop\""
