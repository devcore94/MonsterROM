# The vendor's ARM32 crypto library still runs its boot self-test with a 64-bit app ABI.
RC="$WORK_DIR/vendor/etc/init/boringssl_self_test.rc"
if ! grep -Fxq 'on early-init && property:ro.product.cpu.abilist32=*' "$RC"; then
    ABORT "Unexpected G996B BoringSSL self-test trigger"
fi
sed -i 's/^on early-init && property:ro\.product\.cpu\.abilist32=\*$/on early-init/' "$RC"
unset RC
