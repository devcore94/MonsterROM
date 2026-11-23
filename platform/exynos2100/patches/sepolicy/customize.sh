if [[ "$TARGET_CODENAME" != "t2s" ]]; then
    return 0
fi

for FILE in 30.0.cil 30.0.compat.cil; do
    ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/etc/selinux/mapping/$FILE"
    ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "system/system_ext/etc/selinux/mapping/$FILE"
done
unset FILE

# Android 17 reads the AT&T IQI label from the signer, as in the S26+ vendor policy.
sed -i 's|<package name="com\.att\.iqi"><seinfo value="attiqi"/></package>|<seinfo value="attiqi"/>|' \
    "$WORK_DIR/vendor/etc/selinux/vendor_mac_permissions.xml"
