# Select the platform before installing either payload. The current platform
# never receives the legacy init_exec-labelled writer or its forbidden reverse
# transition.
# shellcheck disable=SC2034 # Read by the original module installer.
SKIPUNZIP=1

if [ "$SOURCE_PLATFORM_SDK_VERSION" -ge 37 ]; then
    PROPHIDE_PAYLOAD()
    (
        local BASE="$MODPATH" INIT="$WORK_DIR/system/system/bin/init"
        local POLICY="$WORK_DIR/system/system/etc/selinux/plat_sepolicy.cil"
        local PROPS="$WORK_DIR/system/system/etc/selinux/plat_property_contexts"
        local FILES="$WORK_DIR/system/system/etc/selinux/plat_file_contexts"
        local VENDOR="$WORK_DIR/vendor/etc/selinux/plat_pub_versioned.cil"
        local VENDOR_PATCH="$BASE/api30-properties.patch"
        local VBIMG EXPECTED HASH TMP="" FILE
        [ "$SOURCE_PLATFORM_SDK_VERSION" -eq 37 ] || { ABORT "Prophide: unsupported source SDK"; return 1; }
        case "$TARGET_CODENAME:$TARGET_FIRMWARE" in
            t2s:SM-G996B/AUT/*) EXPECTED=f6e1fce97469b0e5797713280cc4fd2eff7ab31443d70a3e34e945d71de21dbc ;;
            o1s:SM-G991B/AUT/*) EXPECTED=487cb919554ded6f4f7e7cef62a4353b3071b9caa93f592278d770598aaea4c3 ;;
            p3s:SM-G998B/AUT/*) EXPECTED=cd86d91b22e4e273abb65189cadea1c6d76683822e4fefa0c5407110462917ea ;;
            r9s:SM-G990E/THL/*) EXPECTED=722ad67938428b2086a5018dd271c1da5d7a9f9864972d20083fc1e4da1bcefa ;;
            *) ABORT "Prophide: unreviewed target/firmware cohort"; return 1 ;;
        esac
        VBIMG="$FW_DIR/${TARGET_FIRMWARE%%/*}_$(cut -d / -f 2 <<< "$TARGET_FIRMWARE")/avb/vbmeta.img"
        for FILE in "$INIT" "$POLICY" "$PROPS" "$FILES" "$VENDOR" "$VBIMG"; do
            [ -f "$FILE" ] && [ ! -L "$FILE" ] || { ABORT "Prophide: missing/non-regular input $FILE"; return 1; }
        done
        [ "$(sha256sum "$VBIMG" | cut -d ' ' -f 1)" = "$EXPECTED" ] || { ABORT "Prophide: changed target vbmeta"; return 1; }
        [ "$(avbtool info_image --image "$VBIMG" | awk '/Block:/ {sum+=$3} END {print sum}')" = 9344 ] || { ABORT "Prophide: unexpected vbmeta geometry"; return 1; }
        [ "$(GET_PROP system ro.build.version.sdk)" = 37 ] &&
            [ "$(GET_PROP system ro.build.version.security_patch)" = 2026-10-05 ] || { ABORT "Prophide: source property cohort changed"; return 1; }
        # The helper uses only these original One UI 9 bootstrap/crypto providers.
        for FILE in \
            "02ae6f415c54323d51ddf3a445da5c159ef41b756dd3e2d82214bda190189b89 system/lib64/bootstrap/libc.so" \
            "da26104a7725f09373526a17be278197208953328b038b02ff9cbf646a681577 system/lib64/libcrypto.so" \
            "a14d36a0053a2ec62222638bfebabc0564a0f6a5e7fcf310b06993f81ac2e064 system/bin/bootstrap/linker64"; do
            [ "$(sha256sum "$WORK_DIR/system/${FILE#* }" | cut -d ' ' -f 1)" = "${FILE%% *}" ] || { ABORT "Prophide: changed native provider ${FILE#* }"; return 1; }
        done
        (cd "$BASE" && sha256sum --strict -c SHA256SUMS) || { ABORT "Prophide: payload checksum failure"; return 1; }
        HASH="$(sha256sum "$INIT" | cut -d ' ' -f 1)"
        case "$HASH" in
            78d3644ddc9021364864e5dcdb41e400f28071c0da74b8a6da47171ede4bbb1b|1b3d2850aa95e88320ee6fb0cc14f0f9640aa8b7953337a4481e58fb2eb83274) ;;
            *) ABORT "Prophide: unsupported init binary; refusing an unpinned native patch"; return 1 ;;
        esac
        TMP="$(mktemp -d "$WORK_DIR/.prophide.XXXXXX")" || return 1
        trap 'rm -f "$TMP/init" "$TMP/init.hex" "$TMP/policy" "$TMP/props" "$TMP/files" "$TMP/plat_pub_versioned.cil"; rmdir "$TMP"' EXIT
        # Preflight every additive block BEFORE changing init or image metadata.
        PROPHIDE_BLOCK()
        {
            local INPUT="$1" PAYLOAD="$2" OUTPUT="$3" MARKER="$4"
            { echo "$MARKER BEGIN"; cat "$PAYLOAD"; echo "$MARKER END"; } > "$OUTPUT" || return 1
            if grep -qxF "$MARKER BEGIN" "$INPUT"; then
                cmp -s "$OUTPUT" <(sed -n "/^$MARKER BEGIN$/,/^$MARKER END$/p" "$INPUT") || { ABORT "Prophide: changed installed policy/context block"; return 1; }
                : > "$OUTPUT"
            elif grep -qi prophide "$INPUT"; then
                ABORT "Prophide: conflicting policy/context declaration in $INPUT"; return 1
            fi
        }
        PROPHIDE_BLOCK "$POLICY" "$BASE/policy.cil" "$TMP/policy" '; UN1CA Prophide' || return 1
        PROPHIDE_BLOCK "$PROPS" "$BASE/property_contexts" "$TMP/props" '# UN1CA Prophide' || return 1
        printf '/system/bin/prophide_stage u:object_r:prophide_stage_exec:s0\n' > "$TMP/files" || return 1
        PROPHIDE_BLOCK "$FILES" "$TMP/files" "$TMP/init.hex" '# UN1CA Prophide' || return 1
        mv "$TMP/init.hex" "$TMP/files" || return 1
        [ "$TARGET_CODENAME" != r9s ] || VENDOR_PATCH="$BASE/r9s-api30-properties.patch"
        cp -p "$VENDOR" "$TMP/plat_pub_versioned.cil" || return 1
        if grep -q '^[(]typeattribute unica_prophide_api30_property_reader)' "$VENDOR"; then
            git apply --reverse --check --unsafe-paths --directory="$TMP" "$VENDOR_PATCH" || return 1
        else
            git apply --check --unsafe-paths --directory="$TMP" "$VENDOR_PATCH" &&
                git apply --unsafe-paths --directory="$TMP" "$VENDOR_PATCH" || return 1
        fi
        if [ "$HASH" = 78d3644ddc9021364864e5dcdb41e400f28071c0da74b8a6da47171ede4bbb1b ]; then
            xxd -p -c 32 "$INIT" > "$TMP/init.hex" || return 1
            git apply --check --unsafe-paths --directory="$TMP" "$BASE/init.hex.patch" &&
                git apply --unsafe-paths --directory="$TMP" "$BASE/init.hex.patch" || return 1
            xxd -r -p "$TMP/init.hex" > "$TMP/init" || return 1
            [ "$(sha256sum "$TMP/init" | cut -d ' ' -f 1)" = 1b3d2850aa95e88320ee6fb0cc14f0f9640aa8b7953337a4481e58fb2eb83274 ] || { ABORT "Prophide: native patch result mismatch"; return 1; }
            chmod --reference="$INIT" "$TMP/init" || return 1
        fi
        # The payload now lives at the module root, next to the build sources.
        # Install only the two shipped entries, not the sources or the patches.
        ADD_TO_WORK_DIR "$BASE" system system/bin/prophide_stage 0 0 755 u:object_r:system_file:s0 || return 1
        ADD_TO_WORK_DIR "$BASE" system system/etc/init/prophide.rc 0 0 644 u:object_r:system_file:s0 || return 1
        if [ -f "$TMP/init" ]; then mv "$TMP/init" "$INIT" || return 1; fi
        mv "$TMP/plat_pub_versioned.cil" "$VENDOR" || return 1
        cat "$TMP/policy" >> "$POLICY" && cat "$TMP/props" >> "$PROPS" && cat "$TMP/files" >> "$FILES" || return 1
        LOG "Prophide: installed pinned init-owned handoff; device boot/readback remains unqualified"
    )
    PROPHIDE_PAYLOAD
    PROPHIDE_RESULT=$?
    unset -f PROPHIDE_PAYLOAD
    return "$PROPHIDE_RESULT"
fi

ADD_TO_WORK_DIR "$MODPATH" "system" "." 0 0 755 "u:object_r:system_file:s0" || return 1

# [
PUB_KEY_ADDR_EXTRACT() {
    local FILE="$1"

    local HEADER="256" AUTH_SZ="12" PK_OFF="64" PK_SIZE="72"

    # read 8-byte big-endian integer at offset
    READ_BE64() {
        local OFF="$1"
        local HEX
        HEX="$(dd if="$FILE" bs=1 skip="$OFF" count=8 2> /dev/null | xxd -p -c 8)"
        printf "%d" "0x$HEX"
    }

    local SKP CNT
    SKP="$((HEADER + $(READ_BE64 $AUTH_SZ) + $(READ_BE64 $PK_OFF)))"
    CNT="$(READ_BE64 $PK_SIZE)"

    echo "$SKP $CNT"
}
# ]

VBIMG="$FW_DIR/$(cut -d "/" -f 1 -s <<< "$TARGET_FIRMWARE")_$(cut -d "/" -f 2 -s <<< "$TARGET_FIRMWARE")/avb/vbmeta.img"
if [ ! -f "$VBIMG" ]; then
    ABORT "File not found: ${VBIMG//$SRC_DIR\//}"
fi

AVBINFO="$(avbtool info_image --image "$VBIMG")"
AVBSIZE="$(awk '/Block:/ {sum+=$3} END {print sum}' <<< "$AVBINFO")"
read -r PK_OFFSET PK_SIZE < <(PUB_KEY_ADDR_EXTRACT "$VBIMG")

sed -i \
    -e "s|VB_SIZE|$AVBSIZE|g" \
    -e "s|PK_OFFSET|$PK_OFFSET|g" \
    -e "s|PK_SIZE|$PK_SIZE|g" \
    "$WORK_DIR/system/system/bin/prophide.sh"

SEPOLICY="$WORK_DIR/system/system/etc/selinux/plat_sepolicy.cil"

sed -i \
    -e "/^(allow init init_exec\b/ s/)))/ execute_no_trans)))/" \
    -e "/^(typeattributeset exec_type\b/ s/))/prophide_exec ))/" \
    -e "/^(typeattributeset file_type\b/ s/))/prophide_exec ))/" \
    -e "/^(typeattributeset system_file_type\b/ s/))/prophide_exec ))/" \
    -e "/^(typeattributeset domain\b/ s/))/prophide ))/" \
    "$SEPOLICY"

# process (init) -> /system/bin/prophide.sh (prophide_exec) -> process (prophide)  |
# A                                                                                V
# | /system/bin/rezetprop (init_exec) <- /system/bin/toybox (prophide) <- /system/bin/sh (prophide)
cat <<'EOF' >> "$SEPOLICY"
; Added by unica/mods/prophide/customize.sh
; types
(type prophide)
(roletype object_r prophide)
(type prophide_exec)
(roletype object_r prophide_exec)
; init -> prophide_exec -> prophide
(typetransition init prophide_exec process prophide)
(allow init prophide (process (transition)))
(allow init prophide (process (noatsecure rlimitinh siginh)))
(allow init prophide (fd (use)))
; prophide -> init_exec -> init
(typetransition prophide init_exec process init)
(allow prophide init (process (transition)))
(allow prophide init (process (noatsecure rlimitinh siginh)))
; block access
(allow prophide block_device (blk_file (read open getattr ioctl)))
(allow prophide emmcblk_device (blk_file (read open getattr ioctl)))
; allow calling init_exec by escalating when needed
(allow init prophide_exec (file (read open execute getattr map)))
(allow prophide init_exec (file (read open execute getattr map)))
; allow calling system binaries without domain change
(allow prophide shell_exec (file (read open execute getattr map execute_no_trans)))
(allow prophide system_file (file (read open execute getattr map execute_no_trans)))
(allow prophide toolbox_exec (file (read open execute getattr map execute_no_trans)))
(allow prophide prophide_exec (file (entrypoint read open execute getattr map)))
EOF

unset VBIMG AVBINFO AVBSIZE PK_OFFSET PK_SIZE SEPOLICY
unset -f PUB_KEY_ADDR_EXTRACT
