#!/usr/bin/env bash
set -euo pipefail

MODULE="$1"
SIGNER_CLASSES="$2"
EXPECTED="$3"
PACKAGE_DIR="$WORK_DIR/system/system/apex"
INPUT="$PACKAGE_DIR/$MODULE.capex"
if [ ! -f "$INPUT" ]; then
    INPUT="$PACKAGE_DIR/$MODULE.apex"
fi
OUTPUT="$PACKAGE_DIR/$MODULE.apex"
KEYS="$(dirname "$(realpath "$SRC_DIR/security/local")")/apex"
PLATFORM_CERT="$SRC_DIR/security/aosp_platform.x509.pem"
PLATFORM_KEY="$SRC_DIR/security/aosp_platform.pk8"
TMP="$(mktemp -d "$OUT_DIR/apex-sign.XXXXXX")"
cleanup()
{
    if mountpoint -q "$TMP/mount"; then
        sudo umount "$TMP/mount" || return 1
    fi
    rm -rf -- "$TMP"
}
trap cleanup EXIT
cd "$TMP"
mkdir -p mount apps inner
if [[ "$INPUT" == *.capex ]]; then
    unzip -p "$INPUT" original_apex > inner.apex
else
    cp -f "$INPUT" inner.apex
fi
unzip -t inner.apex > /dev/null
unzip -p inner.apex apex_payload.img > apex_payload.img
unzip -p inner.apex apex_pubkey > original.avbpubkey
for ENTRY in AndroidManifest.xml apex_manifest.pb apex_build_info.pb; do
    unzip -p inner.apex "$ENTRY" > /dev/null || {
        echo "Missing required APEX entry $ENTRY in $INPUT" >&2
        exit 1
    }
done
avbtool verify_image --image apex_payload.img
INFO="$(LC_ALL=C avbtool info_image --image apex_payload.img)"
grep -Fq "Prop: apex.key -> '$MODULE'" <<< "$INFO"
grep -Fq "$(sha1sum original.avbpubkey | cut -d ' ' -f 1)" <<< "$INFO"
SALT="$(awk '/^[[:space:]]*Salt:/ {print $2}' <<< "$INFO")"
avbtool erase_footer --image apex_payload.img

# Grow the original ext4 image, then make shared extents writable. All
# existing inodes retain their ownership, capabilities and SELinux labels.
truncate -s +16M apex_payload.img
resize2fs apex_payload.img
check_ext4()
{
    local STATUS=0
    e2fsck "$@" apex_payload.img || STATUS=$?
    [ "$STATUS" -le 1 ]
}
check_ext4 -fy -E unshare_blocks
sudo mount -o loop,rw,noatime apex_payload.img mount
while IFS= read -r -d '' FILE; do
    REL="${FILE#mount/}"
    install -D -m 644 "$FILE" "apps/$REL"
done < <(find mount -type f -name '*.apk' -print0)
java -Xmx512m -classpath "$SIGNER_CLASSES:$TOOLS_DIR/bin/signapk.jar" PlatformSigner \
    "$FW_DIR/SM-S947B_EUX/system/system/framework/framework-res.apk" "$PLATFORM_CERT" "$PLATFORM_KEY" "$TMP/apps"
COUNT=0
while IFS= read -r -d '' FILE; do
    REL="${FILE#apps/}"
    if ! cmp -s "$FILE" "mount/$REL"; then
        sudo tee "mount/$REL" < "$FILE" > /dev/null
        cmp "$FILE" "mount/$REL"
        COUNT=$((COUNT + 1))
    fi
done < <(find apps -type f -name '*.apk' -print0)
[ "$COUNT" -eq "$EXPECTED" ] || { echo "Unexpected platform APK count in $MODULE: $COUNT" >&2; exit 1; }
sudo umount "$TMP/mount"
# Record the check after the writable mount before shrinking the image.
check_ext4 -fp
resize2fs -M apex_payload.img
avbtool add_hashtree_footer --image apex_payload.img --do_not_generate_fec --algorithm SHA256_RSA4096 \
    --hash_algorithm sha256 --key "$KEYS/$MODULE.pem" --prop "apex.key:$MODULE" --salt "$SALT"
avbtool verify_image --image apex_payload.img --key "$KEYS/$MODULE.pem"
avbtool extract_public_key --key "$KEYS/$MODULE.pem" --output apex_pubkey

# Keep the complete APEX package. Only the AVB-protected payload and its
# public key change; AndroidManifest.xml, apex_manifest.pb, build metadata,
# resources, notices and any other stock entries must remain present.
unzip -q inner.apex -d inner
rm -rf inner/META-INF
cp -f apex_payload.img inner/apex_payload.img
cp -f apex_pubkey inner/apex_pubkey
(cd inner && zip -q -0 -r ../unsigned.apex .)
signapk -a 4096 --align-file-size "$KEYS/container.x509.pem" "$KEYS/container.pk8" unsigned.apex "$MODULE.apex"
jarsigner -verify "$MODULE.apex" > /dev/null
for ENTRY in AndroidManifest.xml apex_manifest.pb apex_build_info.pb apex_payload.img apex_pubkey; do
    unzip -p "$MODULE.apex" "$ENTRY" > /dev/null || {
        echo "Missing required output APEX entry $ENTRY for $MODULE" >&2
        exit 1
    }
done
unzip -l "$MODULE.apex" > package.list
if grep -Fq "original_apex" package.list; then
    echo "Output APEX unexpectedly contains original_apex: $MODULE" >&2
    exit 1
fi
unzip -p "$MODULE.apex" apex_pubkey | cmp - apex_pubkey
unzip -p "$MODULE.apex" apex_payload.img > verified-payload.img
avbtool verify_image --image verified-payload.img --key "$KEYS/$MODULE.pem"
mv -f "$MODULE.apex" "$OUTPUT"
