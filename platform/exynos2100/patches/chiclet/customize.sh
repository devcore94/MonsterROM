if [[ "$TARGET_CODENAME" == "t2s" ]]; then
    LATEST_TAG="v7"
    KERNEL_ARCHIVE="ChicletKernel-UPSTREAM-v7_t2s_VANILLA_OFFICIAL_20-08-2026_09-36-20.zip"
else
    KERNEL_API_URL="https://api.github.com/repos/UN1CA/kernel_samsung_exynos2100/releases/latest"

    LATEST_TAG="$(
        curl -s "$KERNEL_API_URL" \
        | grep -m1 '"tag_name"' \
        | cut -d '"' -f4
    )"

    KERNEL_ARCHIVE="$(
        curl -s "$KERNEL_API_URL" \
        | grep -oE "ChicletKernel-.*_${TARGET_CODENAME}_VANILLA_OFFICIAL_.*\.zip" \
        | sort -u \
        | tail -n 1
    )"
fi

KERNEL_DL_BASE="https://github.com/UN1CA/kernel_samsung_exynos2100/releases/download/$LATEST_TAG"

LOG_STEP_IN "- Downloading vanilla kernel variant"
if [[ -d "$TMP_DIR" ]]; then
    EVAL "rm -rf \"$TMP_DIR\""
fi
mkdir -p "$TMP_DIR"

DOWNLOAD_FILE "$KERNEL_DL_BASE/$KERNEL_ARCHIVE" "$TMP_DIR/$KERNEL_ARCHIVE"
if [[ "$TARGET_CODENAME" == "t2s" ]]; then
    echo "278375d3fad3cf5f879e57bafd74517e464ecafd8d258748c913532d67576a98  $TMP_DIR/$KERNEL_ARCHIVE" | sha256sum -c - || ABORT "Invalid t2s kernel archive"
fi

for i in "boot" "dtbo" "vendor_boot"; do
    LOG "- Replacing $i.img"

    EVAL "unzip -o \"$TMP_DIR/$KERNEL_ARCHIVE\" \"files/$i.img\" -d \"$TMP_DIR\""

    if [[ -f "$WORK_DIR/kernel/$i.img" ]]; then
        EVAL "rm -f \"$WORK_DIR/kernel/$i.img\""
    fi

    EVAL "mv \"$TMP_DIR/files/$i.img\" \"$WORK_DIR/kernel/$i.img\""
done

EVAL "rm -rf \"$TMP_DIR\""

LOG_STEP_OUT

unset KERNEL_ARCHIVE KERNEL_API_URL KERNEL_DL_BASE
