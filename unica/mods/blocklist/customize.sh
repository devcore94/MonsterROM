DELETE_FROM_WORK_DIR "system" "system/etc/ldu_blocklist.xml" || return 1

# Preserve the donor's shell bypass and RDU observer ABI. The custom policy is
# independent of shopdemo, and must also run before startup scan commits.
APPLY_PATCH "system" "system/framework/services.jar" \
    "$MODPATH/services.jar/0001-Allow-custom-PackageBlockListPolicy.patch" || return 1
APPLY_PATCH "system" "system/framework/services.jar" \
    "$MODPATH/services.jar/0002-Enforce-custom-blocklist-during-scan.patch" || return 1
