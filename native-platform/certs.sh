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
    # Verify update-ca-certificates command is available
    if [ ! -x "/usr/sbin/update-ca-certificates" ]; then
        echo "[certs] ERROR: /usr/sbin/update-ca-certificates not found or not executable"
        echo "[certs] ca-certificates package may not be installed properly"
        exit 1
    fi

    # Wait for the root CA to be available from server (intermediate is optional)
    echo "[certs] Waiting for server root CA..."
    while [ ! -f "$SHARED_CERTS_DIR/server/root_ca.pem" ]; do
        sleep 1
        echo "[certs] Waiting for server root CA..."
    done

    # Copy root CA to system trust store
    cp "$SHARED_CERTS_DIR/server/root_ca.pem" ${SYSTEM_TRUST_STORE}/mock-xconf-root-ca.pem
    chmod 644 ${SYSTEM_TRUST_STORE}/mock-xconf-root-ca.pem
    
    # Copy intermediate CA to system trust store
    if [ -f "$SHARED_CERTS_DIR/server/intermediate_ca.pem" ]; then
        cp "$SHARED_CERTS_DIR/server/intermediate_ca.pem" ${SYSTEM_TRUST_STORE}/mock-xconf-intermediate-ca.pem
        chmod 644 ${SYSTEM_TRUST_STORE}/mock-xconf-intermediate-ca.pem
        grep -qxF "mock-xconf-intermediate-ca.pem" /etc/ca-certificates.conf 2>/dev/null || \
            echo "mock-xconf-intermediate-ca.pem" >> /etc/ca-certificates.conf
    fi
    
    # Register CA certificates and update system trust store
    grep -qxF "mock-xconf-root-ca.pem" /etc/ca-certificates.conf 2>/dev/null || \
        echo "mock-xconf-root-ca.pem" >> /etc/ca-certificates.conf
    /usr/sbin/update-ca-certificates --fresh
    echo "[certs] System CA trust store updated"

    # Cleanup shared server certs after import
    rm -f "$SHARED_CERTS_DIR/server/root_ca.pem" \
        "$SHARED_CERTS_DIR/server/intermediate_ca.pem"

    echo "[certs] Server CA certificates imported"
else
    echo "[certs] mock-xconf not resolvable (${MOCKXCONF_HOST}); skipping server CA import"
fi

# Enable mTLS if specified via environment variable (default: disabled)
ENABLE_MTLS=${ENABLE_MTLS:-false}
ENABLE_PKCS11=${ENABLE_PKCS11:-false}

echo "[certs] Starting with mTLS: $ENABLE_MTLS"
if [ "$ENABLE_MTLS" = "true" ]; then
    echo "[certs] mTLS enabled - performing certificate operations"

    # PKCS#11 mTLS Support - Setup OpenSSL with PKCS#11 patch
    if [ "$ENABLE_PKCS11" = "true" ]; then
        echo "[certs] ENABLE_PKCS11=true - Setting up PKCS#11 for mTLS..."
        
        if [ ! -f "/usr/local/openssl-pkcs11-ready" ]; then
            if command -v /usr/local/bin/openssl >/dev/null 2>&1; then
                OPENSSL_VERSION=$(/usr/local/bin/openssl version 2>/dev/null | awk '{print $2}')
                echo "[certs] Checking ${OPENSSL_VERSION} with PKCS#11 patch..."
            else
                echo "[certs] OpenSSL binary /usr/local/bin/openssl not found; running PKCS#11 setup..."
            fi
            
            # Verify setup script exists
            PKCS11_SETUP_SCRIPT="/usr/local/bin/setup-pkcs11-openssl.sh"
            if [ ! -x "$PKCS11_SETUP_SCRIPT" ]; then
                echo "[certs] ERROR: $PKCS11_SETUP_SCRIPT not found or not executable"
                echo "[certs] PKCS#11 OpenSSL setup script may not be installed properly"
                exit 1
            fi
            
            # Ensure engines directory exists for PKCS#11 symlink
            mkdir -p /usr/local/lib/engines-3
            
            # Run setup with proper error handling (disable set -e temporarily)
            set +e
            "$PKCS11_SETUP_SCRIPT"
            SETUP_EXIT=$?
            set -e
            
            if [ $SETUP_EXIT -eq 0 ]; then
                touch /usr/local/openssl-pkcs11-ready
                # Recompute version after successful setup
                if command -v /usr/local/bin/openssl >/dev/null 2>&1; then
                    OPENSSL_VERSION=$(/usr/local/bin/openssl version 2>/dev/null | awk '{print $2}')
                    echo "[certs] OpenSSL ${OPENSSL_VERSION} with PKCS#11 patch ready"
                else
                    echo "[certs] OpenSSL with PKCS#11 patch ready"
                fi
            else
                echo "[certs] ERROR: PKCS#11 OpenSSL setup failed with exit code $SETUP_EXIT"
                exit 1
            fi
        else
            OPENSSL_VERSION=$(/usr/local/bin/openssl version 2>/dev/null | awk '{print $2}')
            echo "[certs] ${OPENSSL_VERSION} with PKCS#11 patch already ready (cached)"
        fi
    fi

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
    
    # Generate reference P12 with sentinel key for PKCS#11 testing
    if [ "$ENABLE_PKCS11" = "true" ]; then
        echo "[certs] Generating reference P12 with sentinel key for PKCS#11..."
        
        # Verify create_reference_p12 script exists and is executable
        REF_P12_SCRIPT="/usr/local/share/cert-scripts/create_reference_p12"
        if [ ! -x "$REF_P12_SCRIPT" ]; then
            echo "[certs] ERROR: $REF_P12_SCRIPT not found or not executable" >&2
            echo "[certs] Ensure the cert-scripts package is installed and the script has execute permissions" >&2
            exit 1
        fi
        
        if "$REF_P12_SCRIPT" "$CLIENT_CERT" /opt/certs/reference.p12 "changeit"; then
            echo "[certs] Reference P12 created at /opt/certs/reference.p12"
        else
            echo "[certs] ERROR: Failed to create reference P12" >&2
            exit 1
        fi
    fi

    # Copy client CA chain to shared volume for mock-xconf container
    mkdir -p "$SHARED_CERTS_DIR/client"
    # CLIENT_ICA_CHAIN already validated above - safe to copy
    cp "$CLIENT_ICA_CHAIN" "$SHARED_CERTS_DIR/client/ca-chain.pem"

    # Validate shared export exists and is non-empty
    if [ ! -s "$SHARED_CERTS_DIR/client/ca-chain.pem" ]; then
        echo "[certs] ERROR: Failed to export client CA chain to shared volume" >&2
        exit 1
    fi

    echo "[certs] Client certificates generated and copied to /opt/certs"
    echo "[certs] Client CA chain copied to shared volume for mock-xconf"
    
    # Wait for xPKI seed certificate from mock-xconf (if PKCS#11 enabled)
    if [ "$ENABLE_PKCS11" = "true" ]; then
        echo "[certs] Waiting for xPKI seed certificate from mock-xconf..."
        WAIT_COUNT=0
        MAX_WAIT=30
        while [ ! -f "$SHARED_CERTS_DIR/client/seed-cert.pem" ] && [ $WAIT_COUNT -lt $MAX_WAIT ]; do
            sleep 1
            WAIT_COUNT=$((WAIT_COUNT + 1))
        done
        
        if [ -f "$SHARED_CERTS_DIR/client/seed-cert.pem" ] && [ -f "$SHARED_CERTS_DIR/client/seed-cert.key" ]; then
            echo "[certs] ✓ xPKI seed certificate available for PKCS#11 provisioning"
        else
            echo "[certs] ⚠ xPKI seed certificate not available (timeout after ${MAX_WAIT}s)"
            echo "[certs] PKCS#11 xPKI tests may be skipped"
        fi
    fi

    # Setup PKCS#11 token and import certificates (if PKCS#11 enabled)
    if [ "$ENABLE_PKCS11" = "true" ]; then
        echo "[certs] Setting up PKCS#11 token and importing certificates..."
        
        # reference.p12 is guaranteed to exist here (created above when ENABLE_PKCS11=true)
        # Verify setup script exists
        if [ ! -x "/usr/local/bin/setup-pkcs11.sh" ]; then
            echo "[certs] ERROR: /usr/local/bin/setup-pkcs11.sh not found or not executable"
            exit 1
        fi
        
        # Run setup with proper error handling (disable set -e temporarily)
        set +e
        /usr/local/bin/setup-pkcs11.sh
        SETUP_EXIT=$?
        set -e
        
        if [ $SETUP_EXIT -eq 0 ]; then
            echo "[certs] ✓ PKCS#11 token initialized, certificates imported, and configs created"
        else
            echo "[certs] ERROR: PKCS#11 setup failed with exit code $SETUP_EXIT"
            exit 1
        fi
    fi

    # Create CertSelector configuration file
    echo "[certs] Creating CertSelector configuration file..."
    mkdir -p /etc/ssl/certsel
    
    # Add reference.p12 first if PKCS#11 enabled (for hardware-backed certs)
    if [ "$ENABLE_PKCS11" = "true" ]; then
        echo "MTLS|SRVR_TLS,REFERENCE_P12,P12,file:///opt/certs/reference.p12,cfgOpsCert" > /etc/ssl/certsel/certsel.cfg
        echo "[certs] ✓ Added PKCS#11 reference cert as primary"
    fi
    
    # Add standard client certificates (primary if no PKCS#11, fallback if PKCS#11 enabled)
    echo "MTLS|SRVR_TLS,CLIENT_P12,P12,file://${DEFAULT_P12},cfgOpsCert" >> /etc/ssl/certsel/certsel.cfg
    echo "MTLS_PEM,CLIENT_PEM,PEM,file://${DEFAULT_PEM},cfgOpsCert" >> /etc/ssl/certsel/certsel.cfg

    echo "[certs] mTLS certificate trust flow established"
else
    echo "[certs] mTLS disabled - skipping certificate operations"
fi

exit 0
