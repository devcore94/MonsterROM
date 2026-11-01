SET_PROP_IF_DIFF "vendor" "ro.oem_unlock_supported" "0" || return 1

# The upstream layout applies the smali patches from smali/ through the module
# runner, after this script runs. Keep that order and do not apply them twice:
#   framework.jar 0001 - CoreRune reads the vendor model/product properties,
#   services.jar 0001  - hide the vendor firmware mismatch warning,
#   services.jar 0002  - FreecessController reads the vendor model property.

# The One UI 9 implementation lives in Mainline, not SecRescueParty. Reuse the
# original APEX packaging pattern (target/a53x/patches/bluetooth): apktool,
# read-only payload mount, build_fs_image.sh, AVB, and platform signapk.
PATCH_CRASHRECOVERY_APEX()
(
    local REAL_WORK_DIR="$WORK_DIR" REAL_TOOLS_DIR="$TOOLS_DIR"
    local SOURCE_APEX="$WORK_DIR/system/system/apex/com.google.android.crashrecovery_compressed.apex"
    local DEST_APEX="$WORK_DIR/system/system/apex/com.google.android.crashrecovery.apex"
    local STAGE IMAGE PAYLOAD MOUNT CERT_PREFIX="aosp" SALT FILE CANDIDATE=""
    local SOURCE_HASH="810151b9dacdfe81baac963f3077d4a27e9e9f506bb6897cc95d2afa8d698c0f"

    if [ ! -f "$SOURCE_APEX" ] || [ -e "$DEST_APEX" ] || \
            [ "$(sha256sum "$SOURCE_APEX" | cut -d ' ' -f 1)" != "$SOURCE_HASH" ]; then
        ABORT "RescueParty requires the reviewed, unmodified One UI 9 crashrecovery APEX"
        return 1
    fi
    case "$ROM_IS_OFFICIAL" in
        true) CERT_PREFIX="unica" ;;
        false) ;;
        *) ABORT "Invalid ROM_IS_OFFICIAL for crashrecovery signing"; return 1 ;;
    esac
    for FILE in "$SRC_DIR/security/${CERT_PREFIX}_platform.x509.pem" \
            "$SRC_DIR/security/${CERT_PREFIX}_platform.pk8" "$SRC_DIR/security/avb/testkey_rsa4096.pem"; do
        [ -f "$FILE" ] || { ABORT "Crashrecovery signing key not found: $FILE"; return 1; }
    done

    mkdir -p "$TMP_DIR" || return 1
    STAGE="$(mktemp -d "$TMP_DIR/rescueparty.XXXXXXXX")" || return 1
    MOUNT="$STAGE/mount"
    # Never remove a mounted payload, including on an interrupted build.
    trap 'if mountpoint -q "$MOUNT"; then sudo umount "$MOUNT" || exit 1; fi; [ -z "$CANDIDATE" ] || rm -f -- "$CANDIDATE"; rm -rf -- "$STAGE"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    LOG "- Decoding One UI 9 crashrecovery APEX"
    unzip -p "$SOURCE_APEX" original_apex > "$STAGE/com.google.android.crashrecovery.apex" || return 1
    apktool d -j 1 -s -r -p "$REAL_TOOLS_DIR/apktool/framework" \
        -o "$STAGE/apex" "$STAGE/com.google.android.crashrecovery.apex" || return 1
    IMAGE="$STAGE/apex/unknown/apex_payload.img"
    PAYLOAD="$STAGE/payload"
    avbtool verify_image --image "$IMAGE" || return 1
    mkdir -p "$MOUNT" "$PAYLOAD" || return 1
    if ! sudo -n -v > /dev/null 2>&1; then
        LOG "! Root permissions are required for the original read-only APEX extraction"
        sudo -v || return 1
    fi
    sudo mount -o ro,loop "$IMAGE" "$MOUNT" || return 1
    sudo cp -a -T "$MOUNT" "$PAYLOAD" || return 1
    sudo chown -hR "$(id -u):$(id -g)" "$PAYLOAD" || return 1
    # This reviewed Java-only APEX has no capabilities. Do not silently drop
    # capabilities if its payload layout ever changes.
    if [ -n "$(sudo getfattr -R -n security.capability --only-values "$MOUNT" 2> /dev/null)" ]; then
        ABORT "Unexpected file capabilities in crashrecovery payload"
        return 1
    fi
    # Redirects are intentionally owned by the invoking build user.
    # shellcheck disable=SC2024
    sudo find "$MOUNT" -exec stat -c '%n %u %g %a capabilities=0x0' '{}' \; > "$STAGE/fs_config" || return 1
    # shellcheck disable=SC2024
    sudo find "$MOUNT" -exec sh -c \
        'LABEL="$(getfattr -n security.selinux --only-values -h --absolute-names "$1")" || exit 1; printf "%s %s\n" "$1" "$LABEL"' sh '{}' \; \
        > "$STAGE/file_contexts" || return 1
    if grep -qvE '^.+ u:object_r:[A-Za-z0-9_]+:s0$' "$STAGE/file_contexts"; then
        ABORT "Missing or unexpected crashrecovery payload SELinux label"
        return 1
    fi
    sed -i -e "s|$MOUNT | |" -e "s|$MOUNT/||" "$STAGE/fs_config" || return 1
    sed -i -e "s|$MOUNT |/ |" -e "s|$MOUNT||" \
        -e 's|\.|\\.|g' -e 's|+|\\+|g' "$STAGE/file_contexts" || return 1
    sort -o "$STAGE/fs_config" "$STAGE/fs_config" || return 1
    sort -o "$STAGE/file_contexts" "$STAGE/file_contexts" || return 1
    # build_fs_image.sh detects lost+found with a literal grep, whereas a
    # file_contexts path must escape '+'. Keep its real source label instead
    # of triggering the builder's rootfs fallback; comments are valid here.
    echo '# lost+found: retain the original APEX context' >> "$STAGE/file_contexts" || return 1
    sudo umount "$MOUNT" || return 1
    rm -rf -- "$PAYLOAD/lost+found" || return 1
    cmp "$PAYLOAD/apex_manifest.pb" "$STAGE/apex/unknown/apex_manifest.pb" || return 1

    # Use the unmodified UN1CA APK/JAR pipeline with private paths. Do not
    # register this temporary JAR decode in the outer framework rebuild queue.
    export WORK_DIR="$STAGE/work" APKTOOL_DIR="$STAGE/apktool" TOOLS_DIR="$STAGE/tools"
    mkdir -p "$WORK_DIR/system/system/framework" "$TOOLS_DIR/apktool/framework" || return 1
    cp "$REAL_WORK_DIR/system/system/build.prop" "$WORK_DIR/system/system/build.prop" || return 1
    cp "$REAL_WORK_DIR/system/system/framework/framework-res.apk" "$WORK_DIR/system/system/framework/framework-res.apk" || return 1
    cp "$PAYLOAD/javalib/service-crashrecovery.jar" "$WORK_DIR/system/system/framework/service-crashrecovery.jar" || return 1
    APPLY_PATCH "system" "system/framework/service-crashrecovery.jar" \
        "$MODPATH/crashrecovery/0001-Disable-RescueParty.patch" || return 1
    "$SRC_DIR/scripts/apktool.sh" b system system/framework/service-crashrecovery.jar || return 1
    cp "$WORK_DIR/system/system/framework/service-crashrecovery.jar" "$PAYLOAD/javalib/service-crashrecovery.jar" || return 1

    LOG "- Rebuilding and signing crashrecovery payload"
    rm -f "$IMAGE" || return 1
    "$SRC_DIR/scripts/build_fs_image.sh" ext4 --no-avb -o "$IMAGE" -p system \
        "$PAYLOAD" "$STAGE/file_contexts" "$STAGE/fs_config" || return 1
    SALT="$(sha256sum "$STAGE/apex/unknown/apex_manifest.pb" | cut -d ' ' -f 1)" || return 1
    avbtool add_hashtree_footer --do_not_generate_fec --algorithm SHA256_RSA4096 --hash_algorithm sha256 \
        --key "$SRC_DIR/security/avb/testkey_rsa4096.pem" \
        --prop apex.key:com_google_android_crashrecovery-image --salt "$SALT" --image "$IMAGE" || return 1
    avbtool extract_public_key --key "$SRC_DIR/security/avb/testkey_rsa4096.pem" \
        --output "$STAGE/apex/unknown/apex_pubkey" || return 1
    avbtool verify_image --image "$IMAGE" --key "$SRC_DIR/security/avb/testkey_rsa4096.pem" || return 1

    # Publish a normal APEX, not a stale CAPEX manifest/digest around new bytes.
    # The source Google stamp is not an attestation of the rebuilt artifact.
    rm -f "$STAGE/apex/unknown/stamp-cert-sha256" || return 1
    mkdir -p "$STAGE/apex/build/apk" || return 1
    cp -a "$STAGE/apex/original/META-INF" "$STAGE/apex/build/apk/META-INF" || return 1
    apktool b -j 1 -p "$TOOLS_DIR/apktool/framework" "$STAGE/apex" || return 1
    signapk -a 4096 --align-file-size "$SRC_DIR/security/${CERT_PREFIX}_platform.x509.pem" \
        "$SRC_DIR/security/${CERT_PREFIX}_platform.pk8" \
        "$STAGE/apex/dist/com.google.android.crashrecovery.apex" "$STAGE/signed.apex" || return 1
    zipalign -c 4096 "$STAGE/signed.apex" || return 1
    cmp "$STAGE/apex/unknown/apex_manifest.pb" <(unzip -p "$STAGE/signed.apex" apex_manifest.pb) || return 1
    cmp "$STAGE/apex/unknown/apex_pubkey" <(unzip -p "$STAGE/signed.apex" apex_pubkey) || return 1
    cmp "$IMAGE" <(unzip -p "$STAGE/signed.apex" apex_payload.img) || return 1
    cmp "$STAGE/apex/AndroidManifest.xml" <(unzip -p "$STAGE/signed.apex" AndroidManifest.xml) || return 1
    if [ "$(sha256sum "$SOURCE_APEX" | cut -d ' ' -f 1)" != "$SOURCE_HASH" ] || [ -e "$DEST_APEX" ]; then
        ABORT "Crashrecovery APEX changed while being rebuilt"
        return 1
    fi

    export WORK_DIR="$REAL_WORK_DIR"
    CANDIDATE="$(mktemp "$DEST_APEX.XXXXXXXX")" || return 1
    cp "$STAGE/signed.apex" "$CANDIDATE" || return 1
    chmod 644 "$CANDIDATE" || return 1
    mv -Tn "$CANDIDATE" "$DEST_APEX" || return 1
    if [ -e "$CANDIDATE" ]; then
        ABORT "Crashrecovery destination appeared concurrently; refusing to replace it"
        return 1
    fi
    CANDIDATE=""
    SET_METADATA system system/apex/com.google.android.crashrecovery.apex 0 0 644 u:object_r:system_file:s0 || return 1
    DELETE_FROM_WORK_DIR system system/apex/com.google.android.crashrecovery_compressed.apex || return 1
    # These source preopts describe the old Mainline JAR, not the rebuilt one.
    while IFS= read -r FILE; do
        DELETE_FROM_WORK_DIR system "${FILE#"$WORK_DIR/system/"}" || return 1
    done < <(find "$WORK_DIR/system/system/framework/oat" -type f \
        -name 'apex@com.android.crashrecovery@javalib@service-crashrecovery.jar@classes.*' 2> /dev/null)
    LOG "- RescueParty disabled in the signed One UI 9 Mainline implementation"
)

if [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ]; then
    PATCH_CRASHRECOVERY_APEX || return 1
else
    # shellcheck disable=SC2016
    SMALI_PATCH "system" "system/framework/services.jar" \
        "smali/com/android/server/RescueParty.smali" "return" \
        '-$$Nest$smisDisabled()Z' \
        'true' || return 1
fi
unset -f PATCH_CRASHRECOVERY_APEX
