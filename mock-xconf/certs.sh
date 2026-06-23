#!/bin/sh
echo "[certs.sh] Starting certificate generation..."
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
chmod 600 /etc/xconf/certs/mock-xconf-server-key.pem
cp "$SERVER_CERT" /etc/xconf/certs/mock-xconf-server-cert.pem
echo "[certs] Server certificates generated and copied to /etc/xconf/certs"

# Copy individual certificates to shared directory for native-platform to use
cp "$ROOT_CA_CERT" "$SHARED_CERTS_DIR/server/root_ca.pem"
cp "$ICA_CERT" "$SHARED_CERTS_DIR/server/intermediate_ca.pem"
echo "[certs] Server root and intermediate CA certificates copied to shared volume for native-platform"

# ─── RDK-61060: Generate Seed Certificate using Server ICA ───────────────────
# NOTE: This MUST run BEFORE the mTLS wait so that xpki-certifier.js can start
# Use Test-RDK-server-ICA to sign seed cert (simpler than dual PKI hierarchy)
# Per architecture: mock-xconf generates seed, exports to shared volume

echo "[certs] Generating seed certificate using Test-RDK-server-ICA..."

# Setup seed cert directory (xpki-certifier.js uses original cert paths directly)
SEED_CERT_DIR="$SHARED_CERTS_DIR/client"
mkdir -p "$SEED_CERT_DIR"

# Generate seed cert using rdk-cert-config (unified PKI - no separate xpki-root)
# Validity set to 1 day for testing (short-lived seed cert)
/etc/pki/scripts/create_leaf_cert.sh \
    --cert-name "test-seed-device-001" \
    --ca-name "$ICA_NAME" \
    --cn "test-seed-device-001" \
    --validity 1 \
    --type client

# Export seed cert to shared volume for native-platform
SEED_KEY="/etc/pki/${ROOT_CA_NAME}/${ICA_NAME}/private/test-seed-device-001.key"
SEED_CERT="/etc/pki/${ROOT_CA_NAME}/${ICA_NAME}/certs/test-seed-device-001.pem"
SEED_P12="/etc/pki/${ROOT_CA_NAME}/${ICA_NAME}/certs/test-seed-device-001.p12"

cp "$SEED_KEY" "$SEED_CERT_DIR/seed-cert.key"
cp "$SEED_CERT" "$SEED_CERT_DIR/seed-cert.pem"
cp "$SEED_P12" "$SEED_CERT_DIR/seed-cert.p12"

chmod 644 "$SEED_CERT_DIR/seed-cert.pem" "$SEED_CERT_DIR/seed-cert.p12"
chmod 600 "$SEED_CERT_DIR/seed-cert.key"

echo "[certs] ✓ Seed certificate (1 day validity) generated and exported to shared volume"
echo "[certs] ✓ xPKI Certifier will use Test-RDK-server-ICA from /etc/pki directly"

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
    # Operational certs are signed by Test-RDK-server-ICA which has a DIFFERENT root
    # than the client certificates, so we need the complete server chain
    if [ -f "$ICA_CERT" ] && [ -f "$ROOT_CA_CERT" ]; then
        cat "$ICA_CERT" >> /etc/xconf/trust-store/ca-chain.pem
        cat "$ROOT_CA_CERT" >> /etc/xconf/trust-store/ca-chain.pem
        echo "[certs] Server CA chain (ICA + root) appended to trust store for operational certificates"
    fi
    echo "[certs] Client CA chain imported to trust store"
    echo "[certs] mTLS certificate trust flow established"
fi

# ─── RDK-61158: CRL mTLS L3 Test PKI ─────────────────────────────────────────
# Gated on ENABLE_CRL_L3=true.  Calls scripts from rdk-cert-config/test/cert-scripts/
# to generate all PKI material.  Follows the same pattern as generate_test_rdk_certs.sh.
ENABLE_CRL_L3="${ENABLE_CRL_L3:-false}"
if [ "${ENABLE_CRL_L3}" = "true" ]; then
    echo "[certs] [CRL-L3] Starting L3 PKI generation..."

    # ── Locate cert-scripts directory ─────────────────────────────────────────
    _SCRIPTS="/etc/pki/scripts"
    if [ ! -d "${_SCRIPTS}" ] || [ ! -f "${_SCRIPTS}/generate_crl_test_certs.sh" ]; then
        _SCRIPTS="/mnt/L2_CONTAINER_SHARED_VOLUME/rdk-cert-config/test/cert-scripts"
    fi
    if [ ! -f "${_SCRIPTS}/generate_crl_test_certs.sh" ]; then
        echo "[certs] [CRL-L3] ERROR: generate_crl_test_certs.sh not found" >&2
        exit 1
    fi

    # Helper: run a script stripping CRLF (for Windows-mounted volumes)
    _run_script() {
        local _src="$1"; shift
        local _tmp="/tmp/_run_$$.sh"
        tr -d '\r' < "${_src}" > "${_tmp}"
        chmod +x "${_tmp}"
        bash "${_tmp}" "$@"
        rm -f "${_tmp}"
    }

    # Copy helper scripts to /tmp with CRLF stripped (sourced by sub-scripts)
    for _f in "${_SCRIPTS}"/*.sh; do
        tr -d '\r' < "${_f}" > "/tmp/$(basename "${_f}")" 2>/dev/null || true
    done
    chmod +x /tmp/*.sh 2>/dev/null || true

    # ── 1. Generate CRL + OCSP PKI ───────────────────────────────────────────
    CERT_DIR=/etc/pki/test-crl \
    OUT_DIR=/etc/xconf/certs/crl \
    SERVER_CN=mockxconf \
    _run_script "${_SCRIPTS}/generate_crl_test_certs.sh"

    # ── 2. Generate cross-signed PKI ─────────────────────────────────────────
    XS_OUT_DIR="/etc/xconf/certs/xs"
    mkdir -p "${XS_OUT_DIR}"
    CERT_DIR=/etc/pki/test-xs \
    OUT_DIR="${XS_OUT_DIR}" \
    XS_EXPIRY=1 \
    _run_script "${_SCRIPTS}/generate_cross_signed_test_certs.sh"

    # ── 3. Generate XS CRLs + expired bridge ─────────────────────────────────
    XS_CERT_DIR=/etc/pki/test-xs \
    XS_OUT_DIR="${XS_OUT_DIR}" \
    _run_script "${_SCRIPTS}/generate_xs_crl_and_expired_bridge.sh"

    # ── 4. Copy OCSP certs to dedicated directory for ocsp-stapling-server ────
    mkdir -p /etc/xconf/certs/ocsp
    cp /etc/xconf/certs/crl/ocsp-server.key      /etc/xconf/certs/ocsp/ocsp-server.key
    cp /etc/xconf/certs/crl/ocsp-server.pem      /etc/xconf/certs/ocsp/ocsp-server.pem
    cp /etc/xconf/certs/crl/ocsp-responder.key   /etc/xconf/certs/ocsp/ocsp-responder.key
    cp /etc/xconf/certs/crl/ocsp-responder.pem   /etc/xconf/certs/ocsp/ocsp-responder.pem
    cp /etc/xconf/certs/crl/Test-CRL-ICA.pem     /etc/xconf/certs/ocsp/Test-CRL-ICA.pem
    cp /etc/xconf/certs/crl/Test-CRL-Root.pem    /etc/xconf/certs/ocsp/Test-CRL-Root.pem
    cp /etc/xconf/certs/crl/ocsp-ca-chain.pem    /etc/xconf/certs/ocsp/ocsp-ca-chain.pem
    chmod 600 /etc/xconf/certs/ocsp/ocsp-server.key /etc/xconf/certs/ocsp/ocsp-responder.key

    # ── 5. Export client certs to shared volume for native-platform ────────────
    mkdir -p "${SHARED_CERTS_DIR}/crl-client"
    cp /etc/xconf/certs/crl/crl-client.pem        "${SHARED_CERTS_DIR}/crl-client/crl-client.pem"
    cp /etc/xconf/certs/crl/crl-client.key        "${SHARED_CERTS_DIR}/crl-client/crl-client.key"
    cp /etc/xconf/certs/crl/crl-client.p12        "${SHARED_CERTS_DIR}/crl-client/crl-client.p12"
    cp /etc/xconf/certs/crl/crl-ica-chain.pem     "${SHARED_CERTS_DIR}/crl-client/crl-ica-chain.pem"
    cp /etc/xconf/certs/crl/Test-CRL-Root.pem     "${SHARED_CERTS_DIR}/crl-client/Test-CRL-Root.pem"
    chmod 600 "${SHARED_CERTS_DIR}/crl-client/crl-client.key"
    chmod 644 "${SHARED_CERTS_DIR}/crl-client/crl-client.pem" \
              "${SHARED_CERTS_DIR}/crl-client/crl-client.p12" \
              "${SHARED_CERTS_DIR}/crl-client/crl-ica-chain.pem" \
              "${SHARED_CERTS_DIR}/crl-client/Test-CRL-Root.pem"
    echo "[certs] [CRL-L3] CRL client certs exported to shared volume"

    mkdir -p "${SHARED_CERTS_DIR}/xs-client"
    cp "${XS_OUT_DIR}/client-xsign.p12" "${SHARED_CERTS_DIR}/xs-client/client-xsign.p12"
    cp "${XS_OUT_DIR}/client-old.p12"   "${SHARED_CERTS_DIR}/xs-client/client-old.p12"
    cp "${XS_OUT_DIR}/client-expxs.p12" "${SHARED_CERTS_DIR}/xs-client/client-expxs.p12"
    [ -f "${XS_OUT_DIR}/NewRoot.pem" ] && \
        cp "${XS_OUT_DIR}/NewRoot.pem"  "${SHARED_CERTS_DIR}/xs-client/NewRoot.pem"
    chmod 644 "${SHARED_CERTS_DIR}/xs-client/"*.p12 \
              "${SHARED_CERTS_DIR}/xs-client/NewRoot.pem" 2>/dev/null || true
    echo "[certs] [CRL-L3] XS client certs exported to shared volume"
    echo "[certs] [CRL-L3] All L3 PKI generation complete"
fi

exit 0
