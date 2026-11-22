# The Settings switch writes this boolean and individual games read it at launch.
CONTEXTS="$WORK_DIR/system/system/etc/selinux/plat_property_contexts"
if ! grep -q '^persist\.sys\.unica\.gamehooks ' "$CONTEXTS"; then
    echo "persist.sys.unica.gamehooks u:object_r:exported3_system_prop:s0 exact bool" >> "$CONTEXTS"
fi
unset CONTEXTS
