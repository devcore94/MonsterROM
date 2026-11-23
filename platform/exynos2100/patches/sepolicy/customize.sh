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

# The S26+ kgclient seapp rule selects Samsung's reserved vendor_kg identity.
for FILE in passwd group; do
    ENTRY="$(grep '^vendor_kg::5959:' "$FW_DIR/SM-S947B_EUX/vendor/etc/$FILE")" || ABORT "Missing vendor_kg in the S26+ $FILE"
    DEST="$WORK_DIR/vendor/etc/$FILE"
    if ! grep -Fxq "$ENTRY" "$DEST"; then
        if grep -Eq '^(vendor_kg:|[^:]*:[^:]*:5959:)' "$DEST"; then
            ABORT "Conflicting vendor_kg account in /vendor/etc/$FILE"
        fi
        LOG "- Adding vendor_kg to /vendor/etc/$FILE"
        printf '%s\n' "$ENTRY" >> "$DEST"
    fi
done
unset FILE ENTRY DEST
