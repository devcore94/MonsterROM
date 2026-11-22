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
done

unset APP PACKAGE FILE
