#!/usr/bin/env bash
set -euo pipefail
umask 077

SECURITY_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
"$SECURITY_DIR/monsterrom/prepare-platform-key.sh"
KEY_ROOT="$(dirname "$(realpath "$SECURITY_DIR/local")")"
exec 9>"$KEY_ROOT/.apex.lock"
flock 9
if [ ! -d "$KEY_ROOT/apex" ]; then
    STAGE="$(mktemp -d "$KEY_ROOT/.apex.XXXXXX")"
    trap 'rm -rf -- "$STAGE"' EXIT
    for MODULE in com.android.bt com.android.nfcservices com.android.uwb com.android.webapp com.android.wifi; do
        openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -out "$STAGE/$MODULE.pem" 2>/dev/null
    done
    openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -out "$STAGE/container.pem" 2>/dev/null
    openssl req -new -x509 -sha256 -days 10000 -key "$STAGE/container.pem" \
        -subj "/CN=MonsterROM_NEXT local APEX container/" -addext "basicConstraints=critical,CA:FALSE" \
        -addext "keyUsage=critical,digitalSignature" -out "$STAGE/container.x509.pem"
    openssl pkcs8 -topk8 -nocrypt -in "$STAGE/container.pem" -outform DER -out "$STAGE/container.pk8"
    rm "$STAGE/container.pem"
    mv -T "$STAGE" "$KEY_ROOT/apex"
    trap - EXIT
else
    for MODULE in com.android.bt com.android.nfcservices com.android.uwb com.android.webapp com.android.wifi; do
        if [ ! -f "$KEY_ROOT/apex/$MODULE.pem" ]; then
            openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -out "$KEY_ROOT/apex/$MODULE.pem" 2>/dev/null
        fi
    done
fi
