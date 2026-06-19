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
# Gated on ENABLE_CRL_L3=true; creates an independent CRL PKI (Test-CRL-Root →
# Test-CRL-ICA) plus calls generate_cross_signed_test_certs.sh for xsign certs.
ENABLE_CRL_L3="${ENABLE_CRL_L3:-false}"
if [ "${ENABLE_CRL_L3}" = "true" ]; then
    echo "[certs] [CRL-L3] Generating CRL mTLS PKI..."

    CRL_BASE="/etc/pki/test-crl"
    CRL_ROOT_DIR="${CRL_BASE}/Test-CRL-Root"
    CRL_ICA_DIR="${CRL_ROOT_DIR}/Test-CRL-ICA"

    # ── Directory structure ───────────────────────────────────────────────────
    mkdir -p "${CRL_ROOT_DIR}/certs" "${CRL_ROOT_DIR}/private" "${CRL_ROOT_DIR}/crl" \
             "${CRL_ICA_DIR}/certs"  "${CRL_ICA_DIR}/private"  "${CRL_ICA_DIR}/crl"  \
             "${CRL_ICA_DIR}/csr"
    chmod 700 "${CRL_ROOT_DIR}/private" "${CRL_ICA_DIR}/private"

    # CA database files required by openssl ca
    touch "${CRL_ICA_DIR}/index.txt"
    printf "01\n" > "${CRL_ICA_DIR}/serial"
    printf "01\n" > "${CRL_ICA_DIR}/crlnumber"

    # ── openssl.cnf for ICA — needed for openssl ca -revoke / -gencrl ─────────
    cat > "${CRL_ICA_DIR}/openssl.cnf" << 'CNFEOF'
[ ca ]
default_ca = CA_default

[ CA_default ]
dir              = /etc/pki/test-crl/Test-CRL-Root/Test-CRL-ICA
database         = $dir/index.txt
serial           = $dir/serial
crlnumber        = $dir/crlnumber
certificate      = $dir/certs/Test-CRL-ICA.pem
private_key      = $dir/private/Test-CRL-ICA.key
new_certs_dir    = $dir/certs
default_md       = sha256
preserve         = no
policy           = policy_loose
default_crl_days = 365
default_days     = 365

[ policy_loose ]
countryName             = optional
stateOrProvinceName     = optional
organizationName        = optional
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional

[ req ]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn

[ dn ]
CN = crl-client

[ client_cert ]
basicConstraints       = CA:FALSE
keyUsage               = critical, digitalSignature, keyEncipherment
extendedKeyUsage       = critical, clientAuth
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid:always
CNFEOF

    # ── Root CA (self-signed) ─────────────────────────────────────────────────
    openssl ecparam -name prime256v1 -genkey -noout \
        -out "${CRL_ROOT_DIR}/private/Test-CRL-Root.key"
    chmod 600 "${CRL_ROOT_DIR}/private/Test-CRL-Root.key"
    cat > /tmp/crl-root-req.cnf << 'ROOTCNFEOF'
[ req ]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
x509_extensions = v3_ca
[ dn ]
CN = Test-CRL-Root
O  = RDK Test
C  = US
[ v3_ca ]
basicConstraints = critical,CA:TRUE
keyUsage = critical,digitalSignature,cRLSign,keyCertSign
subjectKeyIdentifier = hash
ROOTCNFEOF
    openssl req -new -x509 \
        -key "${CRL_ROOT_DIR}/private/Test-CRL-Root.key" \
        -out "${CRL_ROOT_DIR}/certs/Test-CRL-Root.pem" \
        -days 365 -sha256 \
        -config /tmp/crl-root-req.cnf
    rm -f /tmp/crl-root-req.cnf

    # ── Root CA database and empty CRL ────────────────────────────────────────
    # Node.js 18 / OpenSSL 3.x enables CRL_CHECK_ALL which requires a CRL for
    # every certificate in the verified chain — including the Root CA itself.
    # We generate an empty Root CA CRL (no certs revoked at root level).
    touch "${CRL_ROOT_DIR}/index.txt"
    printf "01\n" > "${CRL_ROOT_DIR}/crlnumber"
    cat > "${CRL_ROOT_DIR}/openssl.cnf" << ROOTCAEOF
[ ca ]
default_ca = CA_default
[ CA_default ]
database         = ${CRL_ROOT_DIR}/index.txt
serial           = ${CRL_ROOT_DIR}/serial
crlnumber        = ${CRL_ROOT_DIR}/crlnumber
certificate      = ${CRL_ROOT_DIR}/certs/Test-CRL-Root.pem
private_key      = ${CRL_ROOT_DIR}/private/Test-CRL-Root.key
new_certs_dir    = ${CRL_ROOT_DIR}/certs
default_md       = sha256
default_crl_days = 365
policy           = policy_loose
[ policy_loose ]
commonName = supplied
ROOTCAEOF
    openssl ca -config "${CRL_ROOT_DIR}/openssl.cnf" -gencrl \
        -out "${CRL_ROOT_DIR}/crl/Test-CRL-Root.crl.pem" -batch

    # ── Intermediate CA (signed by Root) ──────────────────────────────────────
    openssl ecparam -name prime256v1 -genkey -noout \
        -out "${CRL_ICA_DIR}/private/Test-CRL-ICA.key"
    chmod 600 "${CRL_ICA_DIR}/private/Test-CRL-ICA.key"
    openssl req -new \
        -key "${CRL_ICA_DIR}/private/Test-CRL-ICA.key" \
        -out "${CRL_ICA_DIR}/csr/Test-CRL-ICA.csr" \
        -subj "/C=US/O=RDK Test/CN=Test-CRL-ICA"
    cat > /tmp/crl-ica-ext.cnf << 'ICAEXTEOF'
basicConstraints = critical,CA:TRUE,pathlen:0
keyUsage = critical,digitalSignature,cRLSign,keyCertSign
subjectKeyIdentifier = hash
ICAEXTEOF
    openssl x509 -req \
        -in "${CRL_ICA_DIR}/csr/Test-CRL-ICA.csr" \
        -CA "${CRL_ROOT_DIR}/certs/Test-CRL-Root.pem" \
        -CAkey "${CRL_ROOT_DIR}/private/Test-CRL-Root.key" \
        -CAcreateserial \
        -out "${CRL_ICA_DIR}/certs/Test-CRL-ICA.pem" \
        -days 365 -sha256 \
        -extfile /tmp/crl-ica-ext.cnf
    rm -f /tmp/crl-ica-ext.cnf

    # ── Server cert (signed by ICA, not tracked in CA DB) ────────────────────
    mkdir -p /etc/xconf/certs/crl
    openssl ecparam -name prime256v1 -genkey -noout \
        -out /etc/xconf/certs/crl/crl-server.key
    chmod 600 /etc/xconf/certs/crl/crl-server.key
    openssl req -new \
        -key /etc/xconf/certs/crl/crl-server.key \
        -out /tmp/crl-server.csr \
        -subj "/C=US/O=RDK Test/CN=crl-server"
    cat > /tmp/crl-srv-ext.cnf << 'SRVEXTEOF'
basicConstraints = CA:FALSE
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth
subjectKeyIdentifier = hash
subjectAltName = DNS:mockxconf
SRVEXTEOF
    openssl x509 -req \
        -in /tmp/crl-server.csr \
        -CA "${CRL_ICA_DIR}/certs/Test-CRL-ICA.pem" \
        -CAkey "${CRL_ICA_DIR}/private/Test-CRL-ICA.key" \
        -CAcreateserial \
        -out /etc/xconf/certs/crl/crl-server.pem \
        -days 365 -sha256 \
        -extfile /tmp/crl-srv-ext.cnf
    rm -f /tmp/crl-server.csr /tmp/crl-srv-ext.cnf
    cp "${CRL_ICA_DIR}/certs/Test-CRL-ICA.pem" /etc/xconf/certs/crl/Test-CRL-ICA.pem
    cp "${CRL_ROOT_DIR}/certs/Test-CRL-Root.pem" /etc/xconf/certs/crl/Test-CRL-Root.pem
    cp "${CRL_ROOT_DIR}/crl/Test-CRL-Root.crl.pem" /etc/xconf/certs/crl/Test-CRL-Root.crl.pem
    echo "[certs] [CRL-L3] Root CA, ICA, and server cert created"

    # ── Client cert via openssl ca (records in DB → revocable) ───────────────
    openssl ecparam -name prime256v1 -genkey -noout \
        -out "${CRL_ICA_DIR}/private/crl-client.key"
    chmod 600 "${CRL_ICA_DIR}/private/crl-client.key"
    openssl req -new \
        -key "${CRL_ICA_DIR}/private/crl-client.key" \
        -out "${CRL_ICA_DIR}/csr/crl-client.csr" \
        -subj "/C=US/O=RDK Test/CN=crl-client"
    openssl ca \
        -config "${CRL_ICA_DIR}/openssl.cnf" \
        -in "${CRL_ICA_DIR}/csr/crl-client.csr" \
        -out "${CRL_ICA_DIR}/certs/crl-client.pem" \
        -extensions client_cert \
        -days 365 \
        -batch \
        -notext 2>/dev/null

    # ── Initial empty CRL ────────────────────────────────────────────────────
    openssl ca \
        -config "${CRL_ICA_DIR}/openssl.cnf" \
        -gencrl \
        -out /etc/xconf/certs/crl/Test-CRL-ICA.crl.pem \
        -crldays 365 2>/dev/null
    echo "[certs] [CRL-L3] Client cert created in CA DB and initial empty CRL generated"

    # ── Client P12 bundle ────────────────────────────────────────────────────
    _CRL_ICA_CHAIN="/tmp/crl-ica-chain.pem"
    cat "${CRL_ICA_DIR}/certs/Test-CRL-ICA.pem" \
        "${CRL_ROOT_DIR}/certs/Test-CRL-Root.pem" > "${_CRL_ICA_CHAIN}"
    PKCS12_PASS="changeit" openssl pkcs12 -export \
        -in "${CRL_ICA_DIR}/certs/crl-client.pem" \
        -inkey "${CRL_ICA_DIR}/private/crl-client.key" \
        -certfile "${_CRL_ICA_CHAIN}" \
        -out "${CRL_ICA_DIR}/certs/crl-client.p12" \
        -name "crl-client" \
        -passout env:PKCS12_PASS 2>/dev/null
    chmod 644 "${CRL_ICA_DIR}/certs/crl-client.p12"

    # ── Export to shared volume ───────────────────────────────────────────────
    mkdir -p "${SHARED_CERTS_DIR}/crl-client"
    cp "${CRL_ICA_DIR}/certs/crl-client.pem"    "${SHARED_CERTS_DIR}/crl-client/crl-client.pem"
    cp "${CRL_ICA_DIR}/private/crl-client.key"  "${SHARED_CERTS_DIR}/crl-client/crl-client.key"
    cp "${CRL_ICA_DIR}/certs/crl-client.p12"    "${SHARED_CERTS_DIR}/crl-client/crl-client.p12"
    cp "${_CRL_ICA_CHAIN}"                       "${SHARED_CERTS_DIR}/crl-client/crl-ica-chain.pem"
    # Export root CA as a single-cert PEM so native-platform can install it in
    # the system trust store (update-ca-certificates rejects multi-cert files).
    cp "${CRL_ROOT_DIR}/certs/Test-CRL-Root.pem" "${SHARED_CERTS_DIR}/crl-client/Test-CRL-Root.pem"
    chmod 600 "${SHARED_CERTS_DIR}/crl-client/crl-client.key"
    chmod 644 "${SHARED_CERTS_DIR}/crl-client/crl-client.pem" \
              "${SHARED_CERTS_DIR}/crl-client/crl-client.p12" \
              "${SHARED_CERTS_DIR}/crl-client/crl-ica-chain.pem" \
              "${SHARED_CERTS_DIR}/crl-client/Test-CRL-Root.pem"
    rm -f "${_CRL_ICA_CHAIN}"
    echo "[certs] [CRL-L3] Client cert assets exported to ${SHARED_CERTS_DIR}/crl-client/"

    # ── Cross-signed PKI: XS_EXPIRY=1 (shortest valid period; effectively pre-expired) ──
    # Prefer the installed script; fall back to the workspace mount (pre-push).
    _GEN_XS="/etc/pki/scripts/generate_cross_signed_test_certs.sh"
    if [ ! -x "${_GEN_XS}" ]; then
        _GEN_XS="/mnt/L2_CONTAINER_SHARED_VOLUME/rdk-cert-config/test/cert-scripts/generate_cross_signed_test_certs.sh"
    fi
    if [ ! -x "${_GEN_XS}" ] && [ -f "${_GEN_XS}" ]; then
        chmod +x "${_GEN_XS}"
    fi
    if [ ! -f "${_GEN_XS}" ]; then
        echo "[certs] [CRL-L3] ERROR: generate_cross_signed_test_certs.sh not found" >&2
        exit 1
    fi
    XS_OUT_DIR="/etc/xconf/certs/xs"
    mkdir -p "${XS_OUT_DIR}"
    CERT_DIR=/etc/pki/test-xs \
    OUT_DIR="${XS_OUT_DIR}" \
    XS_EXPIRY=1 \
    "${_GEN_XS}"
    echo "[certs] [CRL-L3] Cross-signed PKI generated (XS_EXPIRY=1)"

    # ── Generate empty CRLs for all XS PKI CAs ───────────────────────────────
    # Node.js 18/OpenSSL 3 uses CRL_CHECK_ALL when the 'crl' TLS option is
    # set, meaning every certificate in the verified chain — including all
    # intermediates — requires a matching CRL in the server's store.
    # Generate empty CRLs for each XS CA so the cross-signed chain verifies.
    _XS_BASE="/etc/pki/test-xs"
    for _XS_CA_DIR in \
        "${_XS_BASE}/Test-XS-OldRoot" \
        "${_XS_BASE}/Test-XS-OldRoot/Test-XS-OldICA" \
        "${_XS_BASE}/Test-XS-OldRoot/Test-XS-RevokedICA" \
        "${_XS_BASE}/Test-XS-NewRoot" \
        "${_XS_BASE}/Test-XS-NewRoot/Test-XS-NewICA"; do
        _XS_CA_NAME=$(basename "${_XS_CA_DIR}")
        _XS_CERT="${_XS_CA_DIR}/certs/${_XS_CA_NAME}.pem"
        _XS_KEY="${_XS_CA_DIR}/private/${_XS_CA_NAME}.key"
        _XS_IDX="${_XS_CA_DIR}/index.txt"
        _XS_CRLNUM="${_XS_CA_DIR}/crlnumber"
        [ -f "${_XS_CERT}" ] && [ -f "${_XS_KEY}" ] || continue
        mkdir -p "${_XS_CA_DIR}/crl"
        # crlnumber must exist for gencrl
        [ -f "${_XS_CRLNUM}" ] || printf "01\n" > "${_XS_CRLNUM}"
        cat > /tmp/xs-ca-tmp.cnf << XSCNFEOF
[ ca ]
default_ca = CA_default
[ CA_default ]
database         = ${_XS_CA_DIR}/index.txt
serial           = ${_XS_CA_DIR}/serial
crlnumber        = ${_XS_CA_DIR}/crlnumber
certificate      = ${_XS_CERT}
private_key      = ${_XS_KEY}
new_certs_dir    = ${_XS_CA_DIR}/certs
default_md       = sha256
default_crl_days = 365
policy           = policy_loose
[ policy_loose ]
commonName = supplied
XSCNFEOF
        openssl ca -config /tmp/xs-ca-tmp.cnf -gencrl \
            -out "${_XS_CA_DIR}/crl/${_XS_CA_NAME}.crl.pem" -batch 2>/dev/null && \
            cp "${_XS_CA_DIR}/crl/${_XS_CA_NAME}.crl.pem" \
               "${XS_OUT_DIR}/${_XS_CA_NAME}.crl.pem"
    done
    rm -f /tmp/xs-ca-tmp.cnf
    echo "[certs] [CRL-L3] XS PKI CRLs generated"

    # ── Replace expxs bridge with a truly-expired cert ────────────────────────
    # generate_cross_signed_test_certs.sh produces a 1-day-valid bridge; for L3
    # we need one that is already expired at container start time.
    # openssl x509 -new -not_before/-not_after is available in OpenSSL 3.x
    # (ubuntu:noble), so we re-sign OldRoot under NewRoot with a past date range.
    _XS_BASE="/etc/pki/test-xs"
    _EXPXS_BRIDGE="${_XS_BASE}/Test-XS-NewRoot/cross-signed/OldRoot-expxs.pem"
    _NEWROOT_CERT="${_XS_BASE}/Test-XS-NewRoot/certs/Test-XS-NewRoot.pem"
    _NEWROOT_KEY="${_XS_BASE}/Test-XS-NewRoot/private/Test-XS-NewRoot.key"
    _OLDROOT_CERT="${_XS_BASE}/Test-XS-OldRoot/certs/Test-XS-OldRoot.pem"
    _OLDROOT_KEY="${_XS_BASE}/Test-XS-OldRoot/private/Test-XS-OldRoot.key"

    # ── Replace expxs bridge with a truly-expired cert ────────────────────────
    # The entire block runs under set +e so any failure is non-fatal; the
    # 1-day bridge from generate_cross_signed_test_certs.sh is kept as fallback.
    set +e
    _OLD_SUBJ=$(openssl x509 -in "${_OLDROOT_CERT}" -noout -subject -nameopt compat 2>/dev/null | sed 's/^subject=//')
    _NR_DIR="${_XS_BASE}/Test-XS-NewRoot"

    # Temporary openssl.cnf so NewRoot can act as a signing CA
    cat > /tmp/newroot-ca.cnf << NEWROOTCNFEOF
[ ca ]
default_ca = CA_default
[ CA_default ]
dir            = ${_NR_DIR}
certificate    = ${_NEWROOT_CERT}
private_key    = ${_NEWROOT_KEY}
new_certs_dir  = ${_NR_DIR}/certs
database       = ${_NR_DIR}/index.txt
serial         = ${_NR_DIR}/serial
crlnumber      = ${_NR_DIR}/crlnumber
default_md     = sha256
preserve       = no
policy         = policy_loose
x509_extensions = v3_ca
[ policy_loose ]
commonName             = supplied
organizationName       = optional
organizationalUnitName = optional
countryName            = optional
stateOrProvinceName    = optional
localityName           = optional
UID                    = optional
[ v3_ca ]
basicConstraints       = critical,CA:TRUE
keyUsage               = critical,digitalSignature,cRLSign,keyCertSign
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid:always,issuer
NEWROOTCNFEOF

    # Build a CSR from OldRoot's private key (preserves same public key)
    openssl req -new \
        -key "${_OLDROOT_KEY}" \
        -out /tmp/oldroot-expired.csr \
        -subj "${_OLD_SUBJ}" 2>/dev/null

    # Sign with NewRoot CA using explicit past dates
    openssl ca \
        -config /tmp/newroot-ca.cnf \
        -in /tmp/oldroot-expired.csr \
        -out "${_EXPXS_BRIDGE}" \
        -startdate 20240101000000Z \
        -enddate   20240102000000Z \
        -extensions v3_ca \
        -batch \
        -notext 2>/dev/null
    _EXPXS_RC=$?
    rm -f /tmp/oldroot-expired.csr /tmp/newroot-ca.cnf

    if [ ${_EXPXS_RC} -eq 0 ] && [ -s "${_EXPXS_BRIDGE}" ]; then
        # Re-bundle client-expxs.p12 with the now-expired bridge
        _EXPXS_KEY=$(find "${_XS_BASE}" -name "client-expxs.key" 2>/dev/null | head -1)
        _EXPXS_PEM=$(find "${_XS_BASE}" -name "client-expxs.pem" 2>/dev/null | head -1)
        _OLD_ICA_PEM="${_XS_BASE}/Test-XS-OldRoot/Test-XS-OldICA/certs/Test-XS-OldICA.pem"
        _EXPXS_CHAIN_TMP="/tmp/expxs-chain.pem"
        cat "${_OLD_ICA_PEM}" "${_OLDROOT_CERT}" "${_EXPXS_BRIDGE}" "${_NEWROOT_CERT}" > "${_EXPXS_CHAIN_TMP}"
        if [ -n "${_EXPXS_KEY}" ] && [ -n "${_EXPXS_PEM}" ]; then
            PKCS12_PASS="changeit" openssl pkcs12 -export \
                -in "${_EXPXS_PEM}" \
                -inkey "${_EXPXS_KEY}" \
                -certfile "${_EXPXS_CHAIN_TMP}" \
                -out "${XS_OUT_DIR}/client-expxs.p12" \
                -name "client-expxs" \
                -passout env:PKCS12_PASS 2>/dev/null
            chmod 644 "${XS_OUT_DIR}/client-expxs.p12"
        fi
        rm -f "${_EXPXS_CHAIN_TMP}"
        echo "[certs] [CRL-L3] Replaced OldRoot-expxs bridge with truly-expired cert (2024-01-01/02)"
    else
        echo "[certs] [CRL-L3] Warning: Could not create expired bridge — client-expxs.p12 uses 1-day bridge"
    fi
    set -e

    # Copy NewRoot to /etc/xconf/certs/xs/ for crl-mtls-server.js trust anchor
    _NEW_ROOT="/etc/pki/test-xs/Test-XS-NewRoot/certs/Test-XS-NewRoot.pem"
    [ -f "${_NEW_ROOT}" ] && cp "${_NEW_ROOT}" "${XS_OUT_DIR}/NewRoot.pem"

    # ── Export xsign P12s and NewRoot to shared volume ────────────────────────
    mkdir -p "${SHARED_CERTS_DIR}/xs-client"
    cp "${XS_OUT_DIR}/client-xsign.p12" "${SHARED_CERTS_DIR}/xs-client/client-xsign.p12"
    cp "${XS_OUT_DIR}/client-old.p12"   "${SHARED_CERTS_DIR}/xs-client/client-old.p12"
    cp "${XS_OUT_DIR}/client-expxs.p12" "${SHARED_CERTS_DIR}/xs-client/client-expxs.p12"
    [ -f "${XS_OUT_DIR}/NewRoot.pem" ] && \
        cp "${XS_OUT_DIR}/NewRoot.pem"  "${SHARED_CERTS_DIR}/xs-client/NewRoot.pem"
    chmod 644 "${SHARED_CERTS_DIR}/xs-client/"*.p12 \
              "${SHARED_CERTS_DIR}/xs-client/NewRoot.pem" 2>/dev/null || true
    echo "[certs] [CRL-L3] Cross-signed P12 bundles exported to ${SHARED_CERTS_DIR}/xs-client/"
fi

exit 0
