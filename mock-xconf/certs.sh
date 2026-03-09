#!/bin/sh
set -e

##########################################################################
# If not stated otherwise in this file or this component's LICENSE
# file the following copyright and licenses apply:
#
# Copyright 2025 RDK Management
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
##########################################################################

# Cert setup for mock-xconf container

# Enable mTLS if specified via environment variable (default: disabled)
ENABLE_MTLS=${ENABLE_MTLS:-false}
echo "[certs] Starting with mTLS: $ENABLE_MTLS"

# Shared certificates base directory
SHARED_CERTS_DIR="/mnt/L2_CONTAINER_SHARED_VOLUME/shared_certs"
mkdir -p "$SHARED_CERTS_DIR"

echo "[certs] Generating server certificates for MockXconf using generate_test_rdk_certs.sh..."

# Generate server certificates with mockxconf as CN
/etc/pki/scripts/generate_test_rdk_certs.sh --type server --cn "mockxconf"

# Define certificate paths based on generate_test_rdk_certs.sh structure
ROOT_CA_NAME="Test-RDK-root"
ICA_NAME="Test-RDK-server-ICA"
CERT_NAME="mockxconf"

# Verify expected files exist after generation
SERVER_KEY="/etc/pki/${ROOT_CA_NAME}/${ICA_NAME}/private/${CERT_NAME}.key"
SERVER_CERT="/etc/pki/${ROOT_CA_NAME}/${ICA_NAME}/certs/${CERT_NAME}.pem"
ROOT_CA_CERT="/etc/pki/${ROOT_CA_NAME}/certs/${ROOT_CA_NAME}.pem"
ICA_CERT="/etc/pki/${ROOT_CA_NAME}/${ICA_NAME}/certs/${ICA_NAME}.pem"

for f in "$SERVER_KEY" "$SERVER_CERT" "$ROOT_CA_CERT" "$ICA_CERT"; do
    if [ ! -s "$f" ]; then
        echo "[certs] ERROR: Expected certificate artifact missing or empty: $f" >&2
        exit 1
    fi
done

# Ensure directories
mkdir -p /etc/xconf/certs
mkdir -p /etc/xconf/trust-store
mkdir -p "$SHARED_CERTS_DIR/server"

# Copy the server certificates to the xconf certs directory
cp "$SERVER_KEY" /etc/xconf/certs/mock-xconf-server-key.pem
cp "$SERVER_CERT" /etc/xconf/certs/mock-xconf-server-cert.pem
echo "[certs] Server certificates generated and copied to /etc/xconf/certs"

# Copy individual certificates to shared directory for native-platform to use
cp "$ROOT_CA_CERT" "$SHARED_CERTS_DIR/server/root_ca.pem"
cp "$ICA_CERT" "$SHARED_CERTS_DIR/server/intermediate_ca.pem"
echo "[certs] Server root and intermediate CA certificates copied to shared volume for native-platform"

# If mTLS is enabled at startup, wait for client certificates
if [ "$ENABLE_MTLS" = "true" ]; then
    echo "[certs] mTLS enabled - waiting for client certificates..."

    # Wait for client certificate chain
    while [ ! -f "$SHARED_CERTS_DIR/client/ca-chain.pem" ]; do
        sleep 1
        echo "[certs] Waiting for client certificates..."
    done

    echo "[certs] Client certificate chain found - importing to trust store"

    # Import client CA chain to trust store and clean it up from shared volume
    cp "$SHARED_CERTS_DIR/client/ca-chain.pem" /etc/xconf/trust-store/ca-chain.pem
    rm -f "$SHARED_CERTS_DIR/client/ca-chain.pem"
    echo "[certs] Client CA chain imported to trust store"
    echo "[certs] mTLS certificate trust flow established"
fi

# ─── RDK-61060: Generate Test-RDK-xpki-ICA for XPKI Certifier service ────────

echo "[certs] Generating Test-RDK-xpki-ICA for XPKI Certifier service..."

XPKI_DIR="/etc/xconf/xpki-certs"
mkdir -p "$XPKI_DIR"

XPKI_ROOT_KEY="$XPKI_DIR/Test-RDK-xpki-root.key"
XPKI_ROOT_CERT="$XPKI_DIR/Test-RDK-xpki-root.pem"
XPKI_ICA_KEY="$XPKI_DIR/Test-RDK-xpki-ICA.key"
XPKI_ICA_CSR="$XPKI_DIR/Test-RDK-xpki-ICA.csr"
XPKI_ICA_CERT="$XPKI_DIR/Test-RDK-xpki-ICA.pem"

# Generate xpki root CA key and self-signed cert
openssl ecparam -genkey -name prime256v1 -noout -out "$XPKI_ROOT_KEY"
openssl req -new -x509 -key "$XPKI_ROOT_KEY" \
    -out "$XPKI_ROOT_CERT" \
    -days 3650 -sha256 \
    -subj "/C=US/ST=PA/O=RDK Test Environment/OU=xPKI Test Root/CN=Test-RDK-xpki-root" \
    -extensions v3_ca \
    -addext "basicConstraints=critical,CA:TRUE"

# Generate xpki ICA key
openssl ecparam -genkey -name prime256v1 -noout -out "$XPKI_ICA_KEY"

# Create ICA CSR
openssl req -new -key "$XPKI_ICA_KEY" \
    -out "$XPKI_ICA_CSR" \
    -subj "/C=US/ST=PA/O=RDK Test Environment/OU=xPKI Test ICA/CN=Test-RDK-xpki-ICA"

# Sign ICA with xpki root
openssl x509 -req \
    -in "$XPKI_ICA_CSR" \
    -CA "$XPKI_ROOT_CERT" \
    -CAkey "$XPKI_ROOT_KEY" \
    -CAcreateserial \
    -out "$XPKI_ICA_CERT" \
    -days 3650 -sha256 \
    -extfile <(printf "basicConstraints=critical,CA:TRUE,pathlen:0\nkeyUsage=critical,keyCertSign,cRLSign\nsubjectKeyIdentifier=hash\nauthorityKeyIdentifier=keyid:always\n")

rm -f "$XPKI_ICA_CSR"

# Verify all required files are present
for f in "$XPKI_ROOT_KEY" "$XPKI_ROOT_CERT" "$XPKI_ICA_KEY" "$XPKI_ICA_CERT"; do
    if [ ! -s "$f" ]; then
        echo "[certs] ERROR: Missing XPKI cert artifact: $f" >&2
        exit 1
    fi
done

echo "[certs] Test-RDK-xpki-ICA generated successfully in $XPKI_DIR"

# Copy xpki root cert to shared volume so native-platform can trust it
cp "$XPKI_ROOT_CERT" "$SHARED_CERTS_DIR/server/xpki-root.pem"
echo "[certs] XPKI root CA copied to shared volume for native-platform trust store"

# ─── RDK-61060: Generate Seed Certificate for xPKI Seed-Scope Testing ────────

echo "[certs] Generating seed certificate for xPKI seed-scope testing..."

SEED_CERT_DIR="$SHARED_CERTS_DIR/client"
mkdir -p "$SEED_CERT_DIR"

SEED_KEY="$SEED_CERT_DIR/seed-cert.key"
SEED_CSR="$SEED_CERT_DIR/seed-cert.csr"
SEED_CERT="$SEED_CERT_DIR/seed-cert.pem"
SEED_P12="$SEED_CERT_DIR/seed-cert.p12"
SEED_PASSWORD="seedpass"

# Generate seed certificate key
openssl ecparam -genkey -name prime256v1 -noout -out "$SEED_KEY"

# Create seed certificate CSR
openssl req -new -key "$SEED_KEY" \
    -out "$SEED_CSR" \
    -subj "/C=US/ST=PA/O=RDK Test Environment/OU=xPKI Seed Scope/CN=test-seed-device-001"

# Sign seed certificate with xPKI ICA (limited validity for seed scope)
openssl x509 -req \
    -in "$SEED_CSR" \
    -CA "$XPKI_ICA_CERT" \
    -CAkey "$XPKI_ICA_KEY" \
    -CAcreateserial \
    -out "$SEED_CERT" \
    -days 30 -sha256 \
    -extfile <(printf "keyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=clientAuth\nsubjectKeyIdentifier=hash\nauthorityKeyIdentifier=keyid:always\n")

# Bundle into P12 for easy consumption by tests
openssl pkcs12 -export \
    -in "$SEED_CERT" \
    -inkey "$SEED_KEY" \
    -out "$SEED_P12" \
    -passout pass:"$SEED_PASSWORD" \
    -name "seed-cert-001"

# Also create PEM bundle for convenience
cat "$SEED_CERT" > "$SEED_CERT_DIR/seed-cert-bundle.pem"
cat "$SEED_KEY" >> "$SEED_CERT_DIR/seed-cert-bundle.pem"

# Cleanup CSR
rm -f "$SEED_CSR"

# Verify seed cert artifacts
for f in "$SEED_KEY" "$SEED_CERT" "$SEED_P12"; do
    if [ ! -s "$f" ]; then
        echo "[certs] ERROR: Missing seed cert artifact: $f" >&2
        exit 1
    fi
done

echo "[certs] Seed certificate generated successfully:"
echo "[certs]   - P12: $SEED_P12 (password: $SEED_PASSWORD)"
echo "[certs]   - PEM: $SEED_CERT"
echo "[certs]   - Key: $SEED_KEY"
echo "[certs] Seed certificate ready for xPKI seed-scope testing"

exit 0
