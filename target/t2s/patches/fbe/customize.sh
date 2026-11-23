LOG "- Patching /vendor/etc/fstab.exynos2100"

# The G996B vendor also requests metadata encryption through keydirectory.
ENCRYPTION_FLAGS='inlinecrypt|fileencryption=[^,[:space:]]+|metadata_encryption=[^,[:space:]]+|keydirectory=[^,[:space:]]+'
sed -i -E "
    \@^[[:space:]]*/dev/block/by-name/userdata[[:space:]]+/data[[:space:]]@ {
        :remove_option
        s/([[:space:],])($ENCRYPTION_FLAGS),/\1/
        t remove_option
        s/,($ENCRYPTION_FLAGS)([[:space:]]|$)/\2/g
    }
    /^[[:space:]]*#[[:space:]]*Samsung ODE[[:space:]]*$/d
    \@^[[:space:]]*/dev/block/by-name/(keydata|keyrefuge)[[:space:]]@d
" "$WORK_DIR/vendor/etc/fstab.exynos2100"
unset ENCRYPTION_FLAGS
