#!/bin/bash
##########################################################################
# Setup OpenSSL with PKCS#11 patch for mTLS support
# This script downloads, patches, and installs OpenSSL 3.0.5
# Replaces system OpenSSL at runtime when ENABLE_PKCS11=true
##########################################################################

set -e

OPENSSL_VERSION="3.0.5"
OPENSSL_DIR="/opt/openssl-${OPENSSL_VERSION}"
PATCH_FILE="/opt/patches/pkcs11_migration_support_p12.patch"
INSTALL_PREFIX="/usr/local"

echo "[setup-pkcs11-openssl] Starting OpenSSL ${OPENSSL_VERSION} setup with PKCS#11 patch..."

# Check if already installed
if [ -f "${INSTALL_PREFIX}/bin/openssl" ]; then
    INSTALLED_VERSION=$(${INSTALL_PREFIX}/bin/openssl version 2>/dev/null | awk '{print $2}')
    if [ "$INSTALLED_VERSION" = "$OPENSSL_VERSION" ]; then
        echo "[setup-pkcs11-openssl] OpenSSL ${OPENSSL_VERSION} with PKCS#11 patch already installed"
        exit 0
    else
        echo "[setup-pkcs11-openssl] Found OpenSSL $INSTALLED_VERSION, will replace with $OPENSSL_VERSION"
        # Remove old version from /usr/local
        rm -f ${INSTALL_PREFIX}/bin/openssl
        rm -f ${INSTALL_PREFIX}/lib/libssl.* ${INSTALL_PREFIX}/lib/libcrypto.*
    fi
fi

# Remove pre-installed system OpenSSL to avoid conflicts
echo "[setup-pkcs11-openssl] Removing pre-installed system OpenSSL..."
apt-get remove -y openssl libssl-dev 2>/dev/null || true
apt-get autoremove -y 2>/dev/null || true
echo "[setup-pkcs11-openssl] System OpenSSL removed"

# Download OpenSSL
if [ ! -d "$OPENSSL_DIR" ]; then
    echo "[setup-pkcs11-openssl] Downloading OpenSSL ${OPENSSL_VERSION}..."
    cd /opt
    wget --no-check-certificate -q https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz
    if [ $? -ne 0 ]; then
        echo "[setup-pkcs11-openssl] ERROR: Failed to download OpenSSL"
        exit 1
    fi
    tar -xzf openssl-${OPENSSL_VERSION}.tar.gz
    rm openssl-${OPENSSL_VERSION}.tar.gz
fi

cd "$OPENSSL_DIR"

# Apply PKCS#11 patch
if [ -f "$PATCH_FILE" ]; then
    echo "[setup-pkcs11-openssl] Applying PKCS#11 patch..."
    # Check if already patched
    if grep -q "pkcs11_reference_key" crypto/evp/p_legacy.c 2>/dev/null; then
        echo "[setup-pkcs11-openssl] Patch already applied"
    else
        patch -p1 < "$PATCH_FILE"
        if [ $? -ne 0 ]; then
            echo "[setup-pkcs11-openssl] ERROR: Patch failed"
            exit 1
        fi
    fi
else
    echo "[setup-pkcs11-openssl] ERROR: Patch file not found: $PATCH_FILE"
    exit 1
fi

# Configure and build
echo "[setup-pkcs11-openssl] Configuring OpenSSL..."
./config --prefix=${INSTALL_PREFIX} \
         --openssldir=/etc/ssl \
         shared \
         zlib \
         -Wl,-rpath,/usr/local/lib \
         -Wl,-rpath,/usr/local/lib64

echo "[setup-pkcs11-openssl] Building OpenSSL (this may take 5-10 minutes)..."
make -j$(nproc)

if [ $? -ne 0 ]; then
    echo "[setup-pkcs11-openssl] ERROR: Build failed"
    exit 1
fi

echo "[setup-pkcs11-openssl] Installing OpenSSL..."
make install_sw install_ssldirs

if [ $? -ne 0 ]; then
    echo "[setup-pkcs11-openssl] ERROR: Installation failed"
    exit 1
fi

# Remove system OpenSSL libraries completely to avoid conflicts
echo "[setup-pkcs11-openssl] Removing system OpenSSL libraries..."
rm -f /lib/*/libssl.so* /lib/*/libcrypto.so* /usr/lib/*/libssl.so* /usr/lib/*/libcrypto.so*
echo "[setup-pkcs11-openssl] ✓ System OpenSSL libraries removed"

# Update library cache - add both lib and lib64 paths
echo "/usr/local/lib" > /etc/ld.so.conf.d/openssl-local.conf
echo "/usr/local/lib64" >> /etc/ld.so.conf.d/openssl-local.conf
ldconfig
echo "[setup-pkcs11-openssl] ✓ Library cache updated"

# Create symlink for PKCS#11 engine
# OpenSSL looks in ENGINESDIR which is /usr/local/lib/engines-3 on this build
echo "[setup-pkcs11-openssl] Creating PKCS#11 engine symlink..."

# Detect architecture and create appropriate symlink in the correct engines directory
if [ -f "/usr/lib/aarch64-linux-gnu/engines-3/pkcs11.so" ]; then
    ln -sf /usr/lib/aarch64-linux-gnu/engines-3/pkcs11.so /usr/local/lib/engines-3/pkcs11.so
    echo "[setup-pkcs11-openssl] ✓ PKCS#11 engine linked (aarch64)"
elif [ -f "/usr/lib/x86_64-linux-gnu/engines-3/pkcs11.so" ]; then
    ln -sf /usr/lib/x86_64-linux-gnu/engines-3/pkcs11.so /usr/local/lib/engines-3/pkcs11.so
    echo "[setup-pkcs11-openssl] ✓ PKCS#11 engine linked (x86_64)"
else
    echo "[setup-pkcs11-openssl] ✗ WARNING: PKCS#11 engine not found for this architecture"
fi

# Verify PKCS#11 engine is available
if ${INSTALL_PREFIX}/bin/openssl engine -t -c pkcs11 2>&1 | grep -q "pkcs11"; then
    echo "[setup-pkcs11-openssl] ✓ PKCS#11 engine verified and available"
else
    echo "[setup-pkcs11-openssl] ✗ WARNING: PKCS#11 engine not detected by OpenSSL"
fi

# Verify installation
FINAL_VERSION=$(${INSTALL_PREFIX}/bin/openssl version 2>/dev/null | awk '{print $2}')
if [ "$FINAL_VERSION" = "$OPENSSL_VERSION" ]; then
    echo "[setup-pkcs11-openssl] ✓ OpenSSL ${OPENSSL_VERSION} with PKCS#11 patch installed successfully"
    ${INSTALL_PREFIX}/bin/openssl version
else
    echo "[setup-pkcs11-openssl] ERROR: Verification failed (expected $OPENSSL_VERSION, got $FINAL_VERSION)"
    exit 1
fi

# Clean up build directory to save space
cd /opt
rm -rf "$OPENSSL_DIR"
echo "[setup-pkcs11-openssl] Build artifacts cleaned up"

exit 0
