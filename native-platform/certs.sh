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

    # Copy root CA to system trust store
    cp "$SHARED_CERTS_DIR/server/root_ca.pem" ${SYSTEM_TRUST_STORE}/mock-xconf-root-ca.pem
    chmod 644 ${SYSTEM_TRUST_STORE}/mock-xconf-root-ca.pem
    
    # Copy server ICA to shared location for ci-setup-environment.sh to use
    mkdir -p /mnt/L2_CONTAINER_SHARED_VOLUME/certs
    cp "$SHARED_CERTS_DIR/server/intermediate_ca.pem" /mnt/L2_CONTAINER_SHARED_VOLUME/certs/Test-RDK-server-ICA.pem
    echo "[certs] Server ICA copied to shared volume for CA bundle creation during build"

    # Cleanup shared server certs after import
    rm -f "$SHARED_CERTS_DIR/server/root_ca.pem" \
        "$SHARED_CERTS_DIR/server/intermediate_ca.pem"

    echo "[certs] Server CA certificates imported"
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
    if [ -f "$CLIENT_ICA_CHAIN" ]; then
        cp "$CLIENT_ICA_CHAIN" "$SHARED_CERTS_DIR/client/ca-chain.pem"
    else
        echo "[certs] WARNING: Client ICA chain not found at $CLIENT_ICA_CHAIN" >&2
    fi

    # Validate shared export exists and is non-empty
    if [ ! -s "$SHARED_CERTS_DIR/client/ca-chain.pem" ]; then
        echo "[certs] ERROR: Failed to export client CA chain to shared volume" >&2
        exit 1
    fi

    echo "[certs] Client certificates generated and copied to /opt/certs"
    echo "[certs] Client CA chain copied to shared volume for mock-xconf"

    # Generate reference P12 with sentinel key for PKCS#11 testing
    ENABLE_PKCS11=${ENABLE_PKCS11:-false}
    if [ "$ENABLE_PKCS11" = "true" ]; then
        echo "[certs] PKCS#11 enabled - generating reference P12 with sentinel key"
        if [ -f "/etc/pki/scripts/create-reference-p12.sh" ]; then
            /etc/pki/scripts/create-reference-p12.sh "$CLIENT_CERT" /opt/certs/reference.p12 changeit
            if [ $? -eq 0 ]; then
                echo "[certs] ✓ Reference P12 created for PKCS#11 testing"
            else
                echo "[certs] WARNING: Failed to create reference P12" >&2
            fi
        else
            echo "[certs] WARNING: create-reference-p12.sh not found, skipping reference P12" >&2
        fi
    fi

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
