#!/bin/bash
##########################################################################
# Import certificates to PKCS#11 tokens
# Imports client.p12 to slot 0x01 and reference.p12 to slot 0x2c
##########################################################################

set -e

TOKEN_LABEL="RDK_TOKEN"
USER_PIN="1234"
CERT_DIR="/opt/certs"
PKCS11_MODULE="/usr/lib/softhsm/libsofthsm2.so"

echo "[import-certs-to-pkcs11] Importing certificates to PKCS#11 tokens..."

# Verify PKCS#11 module exists
if [ ! -f "$PKCS11_MODULE" ]; then
    echo "[import-certs-to-pkcs11] ERROR: PKCS#11 module not found: $PKCS11_MODULE"
    exit 1
fi

# Get token slot by searching for the label and extracting the slot number before it
SLOT=$(softhsm2-util --show-slots | grep -B 20 "Label:.*$TOKEN_LABEL" | grep "^Slot " | head -1 | awk '{print $2}')
if [ -z "$SLOT" ]; then
    echo "[import-certs-to-pkcs11] ERROR: Token '$TOKEN_LABEL' not found"
    exit 1
fi

echo "[import-certs-to-pkcs11] Found token at slot: $SLOT"

# Import client certificate and key to slot 0x01 (standard mTLS)
# Prefer using .pem and .key files directly if available, otherwise extract from .p12
if [ -f "$CERT_DIR/client.pem" ] && [ -f "$CERT_DIR/client.key" ]; then
    echo "[import-certs-to-pkcs11] Using existing client.pem and client.key files..."
    CLIENT_CERT="$CERT_DIR/client.pem"
    CLIENT_KEY="$CERT_DIR/client.key"
elif [ -f "$CERT_DIR/client.p12" ]; then
    echo "[import-certs-to-pkcs11] Extracting cert and key from client.p12..."
    # Extract cert and key from P12
    openssl pkcs12 -in "$CERT_DIR/client.p12" -passin pass:changeit \
        -out /tmp/client-cert.pem -clcerts -nokeys
    openssl pkcs12 -in "$CERT_DIR/client.p12" -passin pass:changeit \
        -out /tmp/client-key.pem -nocerts -nodes
    CLIENT_CERT="/tmp/client-cert.pem"
    CLIENT_KEY="/tmp/client-key.pem"
else
    echo "[import-certs-to-pkcs11] ERROR: No client certificate files found (client.pem/.key or client.p12)"
    exit 1
fi

echo "[import-certs-to-pkcs11] Importing client certificate to slot 0x01..."

# Import certificate to PKCS#11 at slot 0x01
pkcs11-tool --module "$PKCS11_MODULE" \
    --slot "$SLOT" \
    --login --pin "$USER_PIN" \
    --write-object "$CLIENT_CERT" \
    --type cert \
    --id 01 \
    --label "rdkclient" || echo "Certificate import warning (may already exist)"

# Import private key to PKCS#11 at slot 0x01
pkcs11-tool --module "$PKCS11_MODULE" \
    --slot "$SLOT" \
    --login --pin "$USER_PIN" \
    --write-object "$CLIENT_KEY" \
    --type privkey \
    --id 01 \
    --label "rdkclient-key" || echo "Key import warning (may already exist)"

echo "[import-certs-to-pkcs11] ✓ client certificate imported to slot 0x01"

# Import BOTH certificate and private key to slot 0x2c for P12 patch testing
# The reference.p12 uses sentinel key that redirects to this slot
if [ -f "$CERT_DIR/reference.p12" ]; then
    echo "[import-certs-to-pkcs11] Importing certificate and private key to slot 0x2c for P12 patch testing..."
    
    # Import certificate to slot 0x2c
    pkcs11-tool --module "$PKCS11_MODULE" \
        --slot "$SLOT" \
        --login --pin "$USER_PIN" \
        --write-object "$CLIENT_CERT" \
        --type cert \
        --id 2c \
        --label "rdkclient-p12" || echo "Certificate import warning (may already exist)"
    
    # Import private key to slot 0x2c
    pkcs11-tool --module "$PKCS11_MODULE" \
        --slot "$SLOT" \
        --login --pin "$USER_PIN" \
        --write-object "$CLIENT_KEY" \
        --type privkey \
        --id 2c \
        --label "rdkclient-p12-key" || echo "Private key import warning (may already exist)"
    
    echo "[import-certs-to-pkcs11] ✓ Certificate and private key imported to slot 0x2c (for P12 patch test)"
fi

# Cleanup temp files if we extracted from P12
if [ "$CLIENT_CERT" = "/tmp/client-cert.pem" ]; then
    rm -f /tmp/client-cert.pem /tmp/client-key.pem
fi

# List imported objects
echo "[import-certs-to-pkcs11] Listing objects in token:"
pkcs11-tool --module "$PKCS11_MODULE" --slot "$SLOT" --login --pin "$USER_PIN" --list-objects

echo "[import-certs-to-pkcs11] Certificate import complete"
exit 0
