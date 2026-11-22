if [[ "$TARGET_CODENAME" != "t2s" ]]; then
    return 0
fi

POLICY="$WORK_DIR/vendor/etc/seccomp_policy/samsung.software.media.c2-base-policy"
# Match the mremap flags in the target's codec2.vendor.ext.policy.
RULE="mremap: arg3 == 3 || arg3 == MREMAP_MAYMOVE"
case "$(sed -n '/^mremap:/p' "$POLICY")" in
    "mremap: arg3 == 3")
        LOG "- Updating the Samsung Codec2 mremap rule"
        sed -i "s/^mremap: arg3 == 3$/$RULE/" "$POLICY"
        ;;
    "$RULE") ;;
    *) ABORT "Unexpected mremap rule in ${POLICY#"$WORK_DIR"}" ;;
esac

unset POLICY RULE
