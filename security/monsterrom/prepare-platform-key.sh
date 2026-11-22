#!/usr/bin/env bash
set -euo pipefail
umask 077

SECURITY_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
if [ ! -L "$SECURITY_DIR/local" ]; then
    KEY_ROOT="${MONSTERROM_KEY_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/MonsterROM_NEXT/keys}"
    mkdir -p "$KEY_ROOT"
    KEY_ROOT="$(cd "$KEY_ROOT" && pwd -P)"
    exec 9>"$KEY_ROOT/.platform.lock"
    flock 9
    if [ ! -d "$KEY_ROOT/platform" ]; then
        STAGE="$(mktemp -d "$KEY_ROOT/.platform.XXXXXX")"
        trap 'rm -f "$STAGE/key.pem" "$STAGE/platform.pk8" "$STAGE/platform.x509.pem"; rmdir "$STAGE" 2>/dev/null || true' EXIT
        openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -out "$STAGE/key.pem" 2>/dev/null
        openssl req -new -x509 -sha256 -days 10000 -key "$STAGE/key.pem" \
            -subj "/CN=MonsterROM_NEXT local platform/" -addext "basicConstraints=critical,CA:FALSE" \
            -addext "keyUsage=critical,digitalSignature" -out "$STAGE/platform.x509.pem"
        openssl pkcs8 -topk8 -inform PEM -outform DER -nocrypt -in "$STAGE/key.pem" -out "$STAGE/platform.pk8"
        rm "$STAGE/key.pem"
        mv -T "$STAGE" "$KEY_ROOT/platform"
        trap - EXIT
    fi
    if [ ! -L "$SECURITY_DIR/local" ]; then
        ln -sT "$KEY_ROOT/platform" "$SECURITY_DIR/local"
    fi
fi

KEY="$SECURITY_DIR/local/platform.pk8"
CERT="$SECURITY_DIR/local/platform.x509.pem"
openssl x509 -in "$CERT" -checkend 0 -noout >/dev/null
openssl pkey -in "$KEY" -inform DER -check -noout >/dev/null
cmp <(openssl x509 -in "$CERT" -pubkey -noout) <(openssl pkey -in "$KEY" -inform DER -pubout)
