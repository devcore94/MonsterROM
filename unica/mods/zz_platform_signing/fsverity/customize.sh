(
    set -e
    FSVERITY_DIR="$MODPATH/fsverity"
    STAGE="$(mktemp -d "$OUT_DIR/fsverity.XXXXXX")"
    trap 'rm -rf -- "$STAGE"' EXIT
    "$SRC_DIR/security/monsterrom/prepare-fsverity-key.sh"
    KEY_DIR="$(dirname "$(realpath "$SRC_DIR/security/local")")/fsverity"
    protoc -I "$FSVERITY_DIR" --python_out="$STAGE" "$FSVERITY_DIR/fsverity_digests.proto"

    for PARTITION in system system_ext; do
        LOCATION="$WORK_DIR/$PARTITION"
        MANIFEST=BuildManifestSystemExt.apk
        METADATA_PARTITION="$PARTITION"
        PREFIX=""
        if [[ "$PARTITION" == "system" ]]; then
            LOCATION="$WORK_DIR/system/system"
            MANIFEST=BuildManifest.apk
            PREFIX="system/"
        elif ! $TARGET_OS_BUILD_SYSTEM_EXT_PARTITION; then
            LOCATION="$WORK_DIR/system/system/system_ext"
            METADATA_PARTITION=system
            PREFIX="system/system_ext/"
        fi

        # Measure the final framework archives. A decoded archive left in APKTOOL_DIR
        # would be rebuilt again after partition modules have finished.
        mkdir -p "$STAGE/$PARTITION"
        for ARCHIVE in "$APKTOOL_DIR/$PARTITION/framework/"*.{jar,apk}; do
            [ -d "$ARCHIVE" ] || continue
            FILE="framework/$(basename "$ARCHIVE")"
            [[ "$PARTITION" == "system" ]] && FILE="system/$FILE"
            "$SRC_DIR/scripts/apktool.sh" b -j 2 "$PARTITION" "$FILE"
            mv "$ARCHIVE" "$STAGE/$PARTITION/"
        done

        MANIFEST_DIR="$LOCATION/etc/security/fsverity"
        PYTHONPATH="$STAGE" python3 "$FSVERITY_DIR/refresh.py" \
            "$LOCATION" "$PARTITION" "$MANIFEST_DIR/$MANIFEST" "$STAGE"
        while IFS= read -r FILE; do
            DELETE_FROM_WORK_DIR "$METADATA_PARTITION" "$PREFIX$FILE"
        done < "$STAGE/removed"
        while IFS= read -r FILE; do
            SET_METADATA "$METADATA_PARTITION" "$PREFIX$FILE" 0 0 644 "u:object_r:system_file:s0"
        done < "$STAGE/added"
        signapk --enable-v4 "$KEY_DIR/manifest.x509.pem" "$KEY_DIR/manifest.pk8" \
            "$STAGE/manifest-unsigned.apk" "$STAGE/$MANIFEST" "$STAGE/$MANIFEST.idsig"
        java -classpath "$TOOLS_DIR/bin/signapk.jar" "$FSVERITY_DIR/VerifyManifest.java" \
            "$STAGE/$MANIFEST" "$STAGE/$MANIFEST.idsig" "$KEY_DIR/manifest.x509.pem"
        mv -f "$STAGE/$MANIFEST" "$STAGE/$MANIFEST.idsig" "$MANIFEST_DIR/"
    done
)
