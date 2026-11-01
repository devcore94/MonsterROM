# UN1CA SELinux entries removal list
# - Append new type entries to the ENTRIES list
# - Add the EXACT type entry, DO NOT just add a common pattern (eg. "fabriccrypto", "fabriccrypto_exec" and NOT just "fabriccrypto")
# - DO NOT add the API version at the end of the entry (eg. "fabriccrypto" and NOT "fabriccrypto_30_0")
# - DO NOT add any parenthesis or statements (eg. "fabriccrypto" and NOT "expanttypeattribute ... (fabriccrypto)")
# - DO NOT add unnecessary types or remove the existing ones unless they aren't necessary anymore for all devices

# One UI 8.0 additions
ENTRIES+="
heatmap_default
heatmap_default_exec
"

DUPLICATES+="
init.svc.vendor.wvkprov_server_hal
"

# One UI 7.0 additions
ENTRIES+="
attiqi_app
attiqi_app_data_file
ker_app
kpp_app
kpp_data_file
"

# One UI 6.1.1 additions
ENTRIES+="
hal_dsms_default
hal_dsms_default_exec
proc_compaction_proactiveness
sbauth
sbauth_exec
"

# One UI 5.1.1 additions
ENTRIES+="
audiomirroring
audiomirroring_exec
audiomirroring_service
fabriccrypto
fabriccrypto_exec
fabriccrypto_data_file
hal_dsms_service
uwb_regulation_skip_prop
"

# [
GET_SYSTEM_EXT()
{
    if $TARGET_OS_BUILD_SYSTEM_EXT_PARTITION; then
        echo "system_ext"
    else
        echo "system/system/system_ext"
    fi
}

CIL_NAME="$(head -n 1 "$WORK_DIR/vendor/etc/selinux/plat_sepolicy_vers.txt")"
PATCHED=false
if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ] && [ "$CIL_NAME" = "30.0" ]; then
    # One UI 9 no longer ships API30 mappings. Keep the target declarations and
    # compat files, then apply the reviewed public type-split patch.
    for SELINUX_PARTITION in system system_ext; do
        if [ "$SELINUX_PARTITION" = system ]; then
            SELINUX_DEST="$WORK_DIR/system/system/etc/selinux"
            SELINUX_REL="system/etc/selinux/mapping"
            SELINUX_LABEL="u:object_r:sepolicy_file:s0"
        else
            SELINUX_DEST="$WORK_DIR/$(GET_SYSTEM_EXT)/etc/selinux"
            SELINUX_REL="etc/selinux/mapping"
            SELINUX_LABEL="u:object_r:system_file:s0"
        fi
        for SELINUX_FILE in 30.0.cil 30.0.compat.cil; do
            [ ! -e "$SELINUX_DEST/mapping/$SELINUX_FILE" ] || \
                ABORT "Unexpected existing API30 $SELINUX_PARTITION mapping; review it before replacing"
            ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "$SELINUX_PARTITION" \
                "$SELINUX_REL/$SELINUX_FILE" 0 0 644 "$SELINUX_LABEL"
            [ -s "$SELINUX_DEST/mapping/$SELINUX_FILE" ] || \
                ABORT "Missing original target API30 mapping: $SELINUX_PARTITION/$SELINUX_FILE"
        done
    done
    SELINUX_MAPPING_PATCH="$MODPATH/system/0001-Backport-public-type-splits-to-API30.patch"
    if [ "$TARGET_CODENAME" = "r9s" ]; then
        SELINUX_MAPPING_PATCH="$MODPATH/r9s/system/0001-Backport-public-type-splits-to-API30.patch"
    fi
    EVAL "LC_ALL=C git apply --check --unsafe-paths --directory=\"$WORK_DIR/system/system/etc/selinux\" \"$SELINUX_MAPPING_PATCH\""
    EVAL "LC_ALL=C git apply --unsafe-paths --directory=\"$WORK_DIR/system/system/etc/selinux\" \"$SELINUX_MAPPING_PATCH\""
    SET_PROP "system" "ro.unica.version" "$(GET_PROP "system" "ro.unica.version")-api30policy-r1"
    PATCHED=true
    unset SELINUX_PARTITION SELINUX_DEST SELINUX_REL SELINUX_FILE SELINUX_LABEL SELINUX_MAPPING_PATCH
fi
if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ]; then
    [ -s "$WORK_DIR/system/system/etc/selinux/mapping/$CIL_NAME.cil" ] || \
        ABORT "Missing platform SELinux mapping for vendor policy $CIL_NAME"
    [ -s "$WORK_DIR/$(GET_SYSTEM_EXT)/etc/selinux/mapping/$CIL_NAME.cil" ] || \
        ABORT "Missing system_ext SELinux mapping for vendor policy $CIL_NAME"
fi
VENDOR_API_LIST="$(find "$WORK_DIR/$(GET_SYSTEM_EXT)/etc/selinux/mapping" -type f -printf "%f\n" | \
                    sed '/.compat./d' | sed 's/.cil//' | sed 's/\./_/' | sort)"
# ]

for e in $ENTRIES; do
    if grep -q -F "($e)" "$WORK_DIR/$(GET_SYSTEM_EXT)/etc/selinux/mapping/$CIL_NAME.cil" || \
         grep -q -F "${e}_${CIL_NAME//./_}" "$WORK_DIR/$(GET_SYSTEM_EXT)/etc/selinux/mapping/$CIL_NAME.cil"; then
        # the problematic entry is currently present in system_ext, check if we need to remove it
        if ! grep -q -F "(type $e)" "$WORK_DIR/vendor/etc/selinux/plat_pub_versioned.cil"; then
            PATCHED=true
            # the problematic entry is not supported by the target device
            LOG "- \"$e\" SELinux entry not supported. Removing"
            sed -i "/($e)/d" "$WORK_DIR/$(GET_SYSTEM_EXT)/etc/selinux/mapping/$CIL_NAME.cil"
            for a in $VENDOR_API_LIST; do
                sed -i "/${e}_${a}/d" "$WORK_DIR/$(GET_SYSTEM_EXT)/etc/selinux/mapping/$CIL_NAME.cil"
            done
            if grep -q "genfscon.*$e" "$WORK_DIR/$(GET_SYSTEM_EXT)/etc/selinux/system_ext_sepolicy.cil"; then
                sed -i "/genfscon.*$e/d" "$WORK_DIR/$(GET_SYSTEM_EXT)/etc/selinux/system_ext_sepolicy.cil"
            fi
            if grep -q "genfscon.*$e" "$WORK_DIR/system/system/etc/selinux/plat_sepolicy.cil"; then
                sed -i "/genfscon.*$e/d" "$WORK_DIR/system/system/etc/selinux/plat_sepolicy.cil"
            fi
        fi
    fi
done

for e in $DUPLICATES; do
    if grep -q "^$e.*" "$WORK_DIR/$(GET_SYSTEM_EXT)/etc/selinux/system_ext_property_contexts"; then
        # the problematic entry is currently present in system_ext, check if we need to remove it
        if grep -q "^$e.*" "$WORK_DIR/vendor/etc/selinux/vendor_property_contexts"; then
            PATCHED=true
            # the problematic entry is found in target vendor
            LOG "- \"$e\" SELinux duplicate entry found. Removing"
            sed -i "s/^$e/#SEC_DUPLICATE: $e/g" "$WORK_DIR/vendor/etc/selinux/vendor_property_contexts"
        fi
    fi
done

if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ] && [ "$CIL_NAME" = "30.0" ] && \
        [ "$TARGET_PLATFORM" = "exynos2100" ]; then
    # Keep the donor assertions and exact reviewed vendor repairs. No policy
    # assertion, neverallow or runtime enforcement is relaxed by this route.
    SELINUX_VENDOR_PATCHES=("$MODPATH/vendor/"*.patch)
    if [ "$TARGET_CODENAME" = "r9s" ]; then
        SELINUX_VENDOR_PATCHES=("$MODPATH/r9s/vendor/0001-"*.patch
            "$MODPATH/r9s/vendor/0002-"*.patch
            "$MODPATH/vendor/0003-"*.patch
            "$MODPATH/r9s/vendor/0004-"*.patch
            "$MODPATH/r9s/vendor/0005-"*.patch)
    fi
    for SELINUX_PATCH in "$MODPATH/system/0002-"*.patch \
            "$MODPATH/system/0003-"*.patch "${SELINUX_VENDOR_PATCHES[@]}"; do
        [ -f "$SELINUX_PATCH" ] || ABORT "Missing reviewed One UI 9 strict-policy patch"
        case "$SELINUX_PATCH" in
            */system/*) SELINUX_DEST="$WORK_DIR/system/system/etc/selinux" ;;
            */vendor/*) SELINUX_DEST="$WORK_DIR/vendor/etc/selinux" ;;
            *) ABORT "Unexpected strict-policy patch location: $SELINUX_PATCH" ;;
        esac
        LOG "- Applying \"$(sed -n 's/^Subject: \[PATCH\] //p' "$SELINUX_PATCH")\" to SELinux policy"
        EVAL "LC_ALL=C git apply --check --unsafe-paths --directory=\"$SELINUX_DEST\" \"$SELINUX_PATCH\""
        EVAL "LC_ALL=C git apply --unsafe-paths --directory=\"$SELINUX_DEST\" \"$SELINUX_PATCH\""
    done
    SET_PROP "system" "ro.unica.version" "$(GET_PROP "system" "ro.unica.version")-strictpolicy-r1"
    PATCHED=true
    unset SELINUX_PATCH SELINUX_DEST SELINUX_VENDOR_PATCHES
fi

if ! $PATCHED; then
    LOG "\033[0;33m! Nothing to do\033[0m"
fi

unset ENTRIES DUPLICATES CIL_NAME PATCHED VENDOR_API_LIST
unset -f GET_SYSTEM_EXT
