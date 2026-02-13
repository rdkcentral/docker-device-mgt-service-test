#!/bin/bash
##########################################################################
# Initialize PKCS#11 tokens for mTLS testing
# Creates RDK_TOKEN with slots 0x01 (mTLS) and 0x2c (P12 patch testing)
##########################################################################

set -e

TOKEN_LABEL="RDK_TOKEN"
SO_PIN="1234"
USER_PIN="1234"
TOKEN_DIR="/var/lib/softhsm/tokens"

echo "[init-pkcs11-tokens] Initializing PKCS#11 tokens..."

# Ensure token directory exists
mkdir -p "$TOKEN_DIR"
chmod 755 "$TOKEN_DIR"

# Check if token already exists
if softhsm2-util --show-slots 2>/dev/null | grep -q "$TOKEN_LABEL"; then
    echo "[init-pkcs11-tokens] Token '$TOKEN_LABEL' already exists"
    softhsm2-util --show-slots
    exit 0
fi

# Initialize token at free slot (SoftHSM assigns slots dynamically)
echo "[init-pkcs11-tokens] Creating token '$TOKEN_LABEL'..."
softhsm2-util --init-token \
    --free \
    --label "$TOKEN_LABEL" \
    --so-pin "$SO_PIN" \
    --pin "$USER_PIN"

if [ $? -eq 0 ]; then
    echo "[init-pkcs11-tokens] Token initialized successfully"
else
    echo "[init-pkcs11-tokens] ERROR: Failed to initialize token"
    exit 1
fi

# Display token information
echo "[init-pkcs11-tokens] Token details:"
softhsm2-util --show-slots

# Export PIN for OpenSSL PKCS#11 operations
export PKCS11_PIN="$USER_PIN"

echo "[init-pkcs11-tokens] PKCS#11 token initialization complete"
echo "[init-pkcs11-tokens] Token: $TOKEN_LABEL, User PIN: $USER_PIN"
exit 0
