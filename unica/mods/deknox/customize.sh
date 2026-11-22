# Keep the Android 17 storage stack together. ZZKN's installd links to libdualdar
# and its vold talks to the G996B credential-storage provider.
for APP in app/BlockchainBasicKit priv-app/HdmApk priv-app/KnoxFrameBufferProvider \
        priv-app/KnoxMposAgent priv-app/KnoxNeuralNetworkRuntime priv-app/KnoxPushManager \
        priv-app/KnoxSandbox priv-app/KnoxZtFramework; do
    DELETE_FROM_WORK_DIR "system" "system/$APP"
done

for PACKAGE in com.samsung.android.coldwalletservice com.samsung.android.hdmapp \
        com.samsung.android.knox.kfbp com.samsung.android.knox.mpos com.samsung.android.knox.knnr \
        com.samsung.android.knox.pushmanager com.samsung.android.knox.sandbox com.samsung.android.knox.zt.framework; do
    for FILE in "etc/permissions/privapp-permissions-$PACKAGE.xml" "etc/sysconfig/preinstalled-packages-$PACKAGE.xml"; do
        if [ -f "$WORK_DIR/system/system/$FILE" ]; then
            DELETE_FROM_WORK_DIR "system" "system/$FILE"
        fi
    done

    if [[ "$TARGET_CODENAME" == "t2s" ]]; then
        # ZZKN also merges per-package declarations into shared system XML files.
        PACKAGE_PATTERN="${PACKAGE//./[.]}"
        sed -i "\@<install-in-user-type package=\"$PACKAGE_PATTERN\">@,\@</install-in-user-type>@d" \
            "$WORK_DIR/system/system/etc/sysconfig/preinstalled-packages-merged-system.xml"
        sed -i -E "\@<(allowed-system-preload|reviewed-in-power-save|allow-in-power-save-except-idle) package=\"$PACKAGE_PATTERN\"[[:space:]]*/>@d" \
            "$WORK_DIR/system/system/etc/sysconfig/allowed-system-preload-apps.xml" \
            "$WORK_DIR/system/system/etc/deviceidle/reviewed_allowlist.xml" \
            "$WORK_DIR/system/system/etc/permissions/platform.xml"
        sed -i "\@<package name=\"$PACKAGE_PATTERN\"[[:space:]]*/>@d" \
            "$WORK_DIR/system/system/etc/broadcast_allowlist.xml"
    fi
done

if [[ "$TARGET_CODENAME" == "t2s" ]]; then
    SET_FLOATING_FEATURE_CONFIG "SEC_FLOATING_FEATURE_FRAMEWORK_SUPPORT_BLOCKCHAIN_SERVICE" --delete
    APPLY_PATCH "system" "system/framework/framework.jar" \
        "$MODPATH/blockchain/framework.jar/0001-Remove-the-BlockchainBasicKit-feature-flag.patch"
    APPLY_PATCH "system" "system/framework/services.jar" \
        "$MODPATH/blockchain/services.jar/0001-Nuke-BlockchainTZService.patch"
fi

unset APP PACKAGE PACKAGE_PATTERN FILE
