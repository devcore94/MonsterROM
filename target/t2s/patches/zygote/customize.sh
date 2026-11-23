# The vendor's ARM32 crypto library still runs its boot self-test with a 64-bit app ABI.
RC="$WORK_DIR/vendor/etc/init/boringssl_self_test.rc"
if ! grep -Fxq 'on early-init && property:ro.product.cpu.abilist32=*' "$RC"; then
    ABORT "Unexpected G996B BoringSSL self-test trigger"
fi
sed -i 's/^on early-init && property:ro\.product\.cpu\.abilist32=\*$/on early-init/' "$RC"
unset RC

# The donor registers its device policies when Zygote initializes each metadata class.
PRELOAD_FILE="$WORK_DIR/system/system/etc/preloaded-classes"
POLICY_CLASS="android.app.admin.metadata.CrossDevicePolicies"
if ! grep -Fxq "$POLICY_CLASS" "$PRELOAD_FILE"; then
    LOG "- Preloading $POLICY_CLASS"
    sed -i "/^android\.app\.admin\.metadata\.BrandingPolicies$/a $POLICY_CLASS" "$PRELOAD_FILE"
    grep -Fxq "$POLICY_CLASS" "$PRELOAD_FILE" || ABORT "Missing device policy metadata group in preloaded-classes"
fi
unset PRELOAD_FILE POLICY_CLASS
