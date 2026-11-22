#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

if [ "$#" -ne 2 ] && { [ "$#" -ne 1 ] || [ ! -d "$1" ]; }; then
    echo "Usage: $0 BZK1-stock.zip BZK1-to-ZZKN.zip | verified-image-directory" >&2
    exit 1
fi
: "${FW_DIR:?Source buildenv.sh t2s first}"
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="$FW_DIR/SM-S947B_EUX"
mkdir -p "$FW_DIR"
exec 9>"$FW_DIR/.m2s-import.lock"
flock 9
if [ -e "$DEST" ]; then
    if [ "$(cat "$DEST/.extracted" 2>/dev/null)" = "S947BXXU6ZZKN" ]; then
        echo "The S947BXXU6ZZKN source is already prepared at $DEST"
        exit 0
    fi
    echo "A different or incomplete firmware tree exists at $DEST" >&2
    exit 1
fi

TEMP="$(mktemp -d "$FW_DIR/.m2s-XXXXXX")"
cleanup()
{
    if mountpoint -q "$TEMP/mount"; then
        fusermount3 -u "$TEMP/mount" || return 1
    fi
    rm -rf -- "$TEMP"
}
trap cleanup EXIT
mkdir "$TEMP/mount" "$TEMP/tree"
PARTITIONS=(system product system_ext vendor odm)

if [ "$#" -eq 2 ]; then
    STOCK="$(realpath "$1")"
    OTA="$(realpath "$2")"
    if ! command -v ota_extractor >/dev/null; then
        echo "Place LineageOS ota_extractor on PATH to apply the incremental OTA" >&2
        exit 1
    fi
    mkdir "$TEMP/base" "$TEMP/beta"
    unzip -p "$OTA" META-INF/com/android/metadata > "$TEMP/metadata"
    grep -Fxq 'pre-build-incremental=S947BXXS6BZK1' "$TEMP/metadata"
    grep -Fxq 'post-build-incremental=S947BXXU6ZZKN' "$TEMP/metadata"
    grep -Fxq 'pre-device=m2s' "$TEMP/metadata"
    unzip -p "$OTA" payload.bin > "$TEMP/payload.bin"
    echo "7102fd7c5a553b956bc4e191f81ef01da55a6caf959bda09afec2cbee022721d  $TEMP/payload.bin" | sha256sum -c -

    unzip -p "$STOCK" 'AP_S947BXXS6BZK1_*.tar.md5' > "$TEMP/AP.tar.md5"
    tar -xOf "$TEMP/AP.tar.md5" super.img.lz4 | lz4 -dc > "$TEMP/super.sparse"
    rm "$TEMP/AP.tar.md5"
    simg2img "$TEMP/super.sparse" "$TEMP/super.img"
    rm "$TEMP/super.sparse"
    for PART in "${PARTITIONS[@]}"; do
        lpunpack -p "${PART}_a" "$TEMP/super.img" "$TEMP/base"
        mv "$TEMP/base/${PART}_a.img" "$TEMP/base/$PART.img"
    done
    rm "$TEMP/super.img"
    (cd "$TEMP/base" && sha256sum -c "$HERE/base.sha256")
    ota_extractor --payload="$TEMP/payload.bin" --input_dir="$TEMP/base" --output_dir="$TEMP/beta" \
        --partitions=system,product,system_ext,vendor,odm --operation_threads=3 --verity_threads=3
    IMAGES="$TEMP/beta"
else
    IMAGES="$(realpath "$1")"
fi

(cd "$IMAGES" && sha256sum -c "$HERE/beta.sha256")
for PART in "${PARTITIONS[@]}"; do
    fuse.erofs "$IMAGES/$PART.img" "$TEMP/mount"
    python3 "$HERE/export_partition.py" "$TEMP/mount" "$PART" "$TEMP/tree"
    fusermount3 -u "$TEMP/mount"
    LC_ALL=C sort -o "$TEMP/tree/fs_config-$PART" "$TEMP/tree/fs_config-$PART"
    LC_ALL=C sort -o "$TEMP/tree/file_context-$PART" "$TEMP/tree/file_context-$PART"
done

grep -Fxq 'ro.build.version.incremental=S947BXXU6ZZKN' "$TEMP/tree/system/system/build.prop"
grep -Fxq 'ro.build.version.oneui=90500' "$TEMP/tree/system/system/build.prop"
grep -Fxq 'ro.product.odm.device=m2s' "$TEMP/tree/odm/etc/build.prop"
printf '%s' S947BXXU6ZZKN > "$TEMP/tree/.extracted"
mv -T "$TEMP/tree" "$DEST"
echo "Prepared $DEST"
