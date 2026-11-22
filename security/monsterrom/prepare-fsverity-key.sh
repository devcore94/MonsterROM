#!/usr/bin/env bash
set -euo pipefail
umask 077

SECURITY_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
"$SECURITY_DIR/monsterrom/prepare-platform-key.sh"
KEY_ROOT="$(dirname "$(realpath "$SECURITY_DIR/local")")"
exec 9>"$KEY_ROOT/.fsverity.lock"
flock 9
if [ ! -d "$KEY_ROOT/fsverity" ]; then
    STAGE="$(mktemp -d "$KEY_ROOT/.fsverity.XXXXXX")"
    trap 'rm -rf -- "$STAGE"' EXIT
    openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -out "$STAGE/key.pem" 2>/dev/null
    openssl req -new -x509 -sha256 -days 10000 -key "$STAGE/key.pem" \
        -subj "/CN=MonsterROM_NEXT fs-verity build manifest/" -addext "basicConstraints=critical,CA:FALSE" \
        -addext "keyUsage=critical,digitalSignature" -out "$STAGE/manifest.x509.pem"
    openssl pkcs8 -topk8 -nocrypt -in "$STAGE/key.pem" -outform DER -out "$STAGE/manifest.pk8"
    rm "$STAGE/key.pem"
    mv -T "$STAGE" "$KEY_ROOT/fsverity"
    trap - EXIT
fi
