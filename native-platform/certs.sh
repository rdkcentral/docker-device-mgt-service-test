#!/usr/bin/env bash
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

##########################################################################
# Certificate setup for native-platform container
##########################################################################

# Shared certificates base directory
SHARED_CERTS_DIR="/mnt/L2_CONTAINER_SHARED_VOLUME/shared_certs"
mkdir -p "$SHARED_CERTS_DIR"

# System CA trust store location
SYSTEM_TRUST_STORE="/usr/share/ca-certificates"
mkdir -p ${SYSTEM_TRUST_STORE}

# Only import server CA if mock-xconf is resolvable (DNS check)
MOCKXCONF_HOST=${MOCKXCONF_HOST:-mockxconf}
if getent ahosts "$MOCKXCONF_HOST" >/dev/null 2>&1; then
    # Wait for the root CA and intermediate CA to be available from server
    echo "[certs] Waiting for server root CA and intermediate CA..."
    while [ ! -f "$SHARED_CERTS_DIR/server/root_ca.pem" ] || \
        [ ! -f "$SHARED_CERTS_DIR/server/intermediate_ca.pem" ]; do
    sleep 1
    echo "[certs] Waiting for server certificates..."
    done

    # Copy individual server CA certificates to system trust store
    cp "$SHARED_CERTS_DIR/server/root_ca.pem" ${SYSTEM_TRUST_STORE}/mock-xconf-root-ca.pem
    cp "$SHARED_CERTS_DIR/server/intermediate_ca.pem" ${SYSTEM_TRUST_STORE}/mock-xconf-intermediate-ca.pem
    chmod 644 ${SYSTEM_TRUST_STORE}/mock-xconf-*.pem

    # Cleanup shared server certs after import
    rm -f "$SHARED_CERTS_DIR/server/root_ca.pem" \
        "$SHARED_CERTS_DIR/server/intermediate_ca.pem"

    # Update CA certificates
    echo "mock-xconf-root-ca.pem" >> /etc/ca-certificates.conf || true
    echo "mock-xconf-intermediate-ca.pem" >> /etc/ca-certificates.conf || true
    update-ca-certificates --fresh
else
    echo "[certs] mock-xconf not resolvable (${MOCKXCONF_HOST}); skipping server CA import"
fi

# Enable mTLS if specified via environment variable (default: disabled)
ENABLE_MTLS=${ENABLE_MTLS:-false}
echo "[certs] Starting with mTLS: $ENABLE_MTLS"
if [ "$ENABLE_MTLS" = "true" ]; then
    echo "[certs] mTLS enabled - performing certificate operations"

    # Generate certificates for PKI testing
    echo "[certs] Generating client certificates..."
    /etc/pki/scripts/generate_test_rdk_certs.sh --type client --cn "rdkclient"

    # Create certificate directories for mTLS
    mkdir -p "$SHARED_CERTS_DIR/client"
    mkdir -p /opt/certs

    # Copy client certificates to /opt/certs directory
    ROOT_CA_NAME="Test-RDK-root"
    ICA_NAME="Test-RDK-client-ICA"
    CERT_NAME="rdkclient"

    # Default cert paths in container
    DEFAULT_P12="/opt/certs/client.p12"
    DEFAULT_PEM="/opt/certs/client.pem"

    # Verify expected files exist after generation
    CLIENT_CERT="/etc/pki/${ROOT_CA_NAME}/${ICA_NAME}/certs/${CERT_NAME}.pem"
    CLIENT_KEY="/etc/pki/${ROOT_CA_NAME}/${ICA_NAME}/private/${CERT_NAME}.key"
    CLIENT_P12="/etc/pki/${ROOT_CA_NAME}/${ICA_NAME}/certs/${CERT_NAME}.p12"
    CLIENT_ICA_CHAIN="/etc/pki/${ROOT_CA_NAME}/${ICA_NAME}/${ICA_NAME}_chain.pem"

    for f in "$CLIENT_CERT" "$CLIENT_KEY" "$CLIENT_P12" "$CLIENT_ICA_CHAIN"; do
        if [ ! -s "$f" ]; then
            echo "[certs] ERROR: Expected client certificate artifact missing or empty: $f" >&2
            exit 1
        fi
    done

    # Create combined PEM file with both cert and key
    cat "$CLIENT_CERT" > "$DEFAULT_PEM"
    cat "$CLIENT_KEY" >> "$DEFAULT_PEM"
    cp "$CLIENT_P12" "$DEFAULT_P12"

    # Copy client CA chain to shared volume for mock-xconf container
    mkdir -p "$SHARED_CERTS_DIR/client"
    cp "$CLIENT_ICA_CHAIN" "$SHARED_CERTS_DIR/client/ca-chain.pem"

    # Validate shared export exists and is non-empty
    if [ ! -s "$SHARED_CERTS_DIR/client/ca-chain.pem" ]; then
        echo "[certs] ERROR: Failed to export client CA chain to shared volume" >&2
        exit 1
    fi

    echo "[certs] Client certificates generated and copied to /opt/certs"
    echo "[certs] Client CA chain copied to shared volume for mock-xconf"

    # Create CertSelector configuration file
    echo "[certs] Creating CertSelector configuration file..."
    mkdir -p /etc/ssl/certsel
    echo "MTLS|SRVR_TLS,OPERFS_P12,P12,file://${DEFAULT_P12},cfgOpsCert" > /etc/ssl/certsel/certsel.cfg
    echo "MTLS_PEM,OPERFS_PEM,PEM,file://${DEFAULT_PEM},cfgOpsCert" >> /etc/ssl/certsel/certsel.cfg

    echo "[certs] mTLS certificate trust flow established"
else
    echo "[certs] mTLS disabled - skipping certificate operations"
fi

exit 0
