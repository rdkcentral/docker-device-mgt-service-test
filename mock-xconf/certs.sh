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

exit 0
