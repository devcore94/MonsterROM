# The app process can be restarted after BOOT_COMPLETED or a package broadcast.
# Refresh at query entry, while p0 still denotes the provider and all locals
# are dead. Later cursor sites reuse p0 (one branch stores integer 5 in it), so
# injecting getContext before every MatrixCursor allocation breaks ART typing.
# Keep the URI/selection parameter registers and the original frame unchanged.
SMALI_PATCH "system" "system/app/DAAgent/DAAgent.apk" \
    "smali/com/samsung/android/da/daagent/provider/DualAppProvider.smali" "replace" \
    'query(Landroid/net/Uri;[Ljava/lang/String;Ljava/lang/String;[Ljava/lang/String;Ljava/lang/String;)Landroid/database/Cursor;' \
    'sget-object p2, Lcom/samsung/android/da/daagent/provider/DualAppProvider;->COLUMN_LIST_APPS:[Ljava/lang/String;' \
    '    invoke-virtual {p0}, Landroid/content/ContentProvider;->getContext()Landroid/content/Context;\n\n    move-result-object v0\n\n    invoke-static {v0}, Lcom/samsung/android/da/daagent/provider/WhiteListApps;->refreshWhiteList(Landroid/content/Context;)V\n\n    sget-object p2, Lcom/samsung/android/da/daagent/provider/DualAppProvider;->COLUMN_LIST_APPS:[Ljava/lang/String;'
