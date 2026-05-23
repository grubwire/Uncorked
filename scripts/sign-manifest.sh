#!/bin/bash
# Signs a manifest.json with the engine manifest Ed25519 private key.
# Produces manifest.json.sig (raw 64-byte signature) alongside the manifest.
#
# Usage: scripts/sign-manifest.sh <path-to-manifest.json>
#
# Requires the private key PEM file at ENGINE_MANIFEST_KEY_FILE (env), or
# reads the raw hex seed from ENGINE_MANIFEST_SIGNING_KEY (env, CI secret).
set -euo pipefail

MANIFEST="$1"
SIG="${MANIFEST}.sig"

if [[ -n "${ENGINE_MANIFEST_KEY_FILE:-}" ]]; then
    openssl pkeyutl -sign \
        -inkey "$ENGINE_MANIFEST_KEY_FILE" \
        -rawin \
        -in "$MANIFEST" \
        -out "$SIG"
elif [[ -n "${ENGINE_MANIFEST_SIGNING_KEY:-}" ]]; then
    # Convert hex seed to PKCS#8 PEM and sign in one pipeline.
    printf '%s' "$ENGINE_MANIFEST_SIGNING_KEY" \
        | xxd -r -p \
        | openssl pkey -inform der -out /tmp/_engine_key.pem \
            -provider default -provider legacy 2>/dev/null \
        || openssl pkey -inform raw -in /dev/stdin -pubout > /dev/null 2>&1
    # Simpler: build a minimal PKCS#8 DER wrapper around the 32-byte seed.
    # Ed25519 PKCS#8 DER: 302e 0201 00 3005 0603 2b65 70 0422 0420 <seed>
    KEY_HEX="${ENGINE_MANIFEST_SIGNING_KEY}"
    printf '302e020100300506032b657004220420%s' "$KEY_HEX" \
        | xxd -r -p > /tmp/_engine_sign.der
    openssl pkeyutl -sign \
        -keyform der -inkey /tmp/_engine_sign.der \
        -rawin \
        -in "$MANIFEST" \
        -out "$SIG"
    rm -f /tmp/_engine_sign.der
else
    echo "Error: set ENGINE_MANIFEST_KEY_FILE or ENGINE_MANIFEST_SIGNING_KEY" >&2
    exit 1
fi

echo "Signed $MANIFEST -> $SIG ($(wc -c < "$SIG") bytes)"
