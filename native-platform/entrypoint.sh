#!/usr/bin/env bash

##########################################################################
# If not stated otherwise in this file or this component's LICENSE
# file the following copyright and licenses apply:
#
# Copyright 2024 RDK Management
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

export RBUS_ROOT=/ 
export RBUS_INSTALL_DIR=/usr/local
export PATH=${RBUS_INSTALL_DIR}/bin:${PATH}
export LD_LIBRARY_PATH=${RBUS_INSTALL_DIR}/lib:${LD_LIBRARY_PATH}

ENABLE_MTLS=${ENABLE_MTLS:-false}
export ENABLE_MTLS

# PKCS#11 Support - Initialize environment variable
ENABLE_PKCS11=${ENABLE_PKCS11:-false}
export ENABLE_PKCS11

# PKCS#11 mTLS Support (requires BOTH flags)
if [ "$ENABLE_MTLS" = "true" ] && [ "$ENABLE_PKCS11" = "true" ]; then
    echo "[entrypoint] ENABLE_MTLS=true and ENABLE_PKCS11=true detected"
    echo "[entrypoint] Initializing PKCS#11 tokens for mTLS..."
    
    # Setup OpenSSL 3.0.5 with PKCS#11 patch (runtime compilation, one-time cached)
    if [ ! -f "/usr/local/openssl-pkcs11-ready" ]; then
        echo "[entrypoint] Building OpenSSL 3.0.5 with PKCS#11 patch (first run only)..."
        /usr/local/bin/setup-pkcs11-openssl.sh
        if [ $? -eq 0 ]; then
            touch /usr/local/openssl-pkcs11-ready
            echo "[entrypoint] OpenSSL 3.0.5 with PKCS#11 patch installed successfully"
        else
            echo "[entrypoint] ERROR: PKCS#11 OpenSSL setup failed"
            exit 1
        fi
    else
        OPENSSL_VERSION=$(/usr/local/bin/openssl version 2>/dev/null | awk '{print $2}')
        echo "[entrypoint] OpenSSL 3.0.5 with PKCS#11 patch already installed (cached)"
    fi
    
    # Initialize PKCS#11 tokens
    /usr/local/bin/init-pkcs11-tokens.sh
    if [ $? -eq 0 ]; then
        echo "[entrypoint] PKCS#11 tokens initialized"
    else
        echo "[entrypoint] WARNING: PKCS#11 token initialization failed"
    fi
    
    echo "[entrypoint] PKCS#11 token initialization complete (certificate import will happen after mTLS cert generation)"
elif [ "$ENABLE_MTLS" = "true" ]; then
    echo "[entrypoint] ENABLE_MTLS=true (standard mTLS without PKCS#11)"
elif [ "$ENABLE_PKCS11" = "true" ]; then
    echo "[entrypoint] WARNING: ENABLE_PKCS11=true but ENABLE_MTLS=false"
    echo "[entrypoint] PKCS#11 requires mTLS to be enabled, skipping..."
fi

## Certificate setup
/usr/local/bin/certs.sh
CERTS_RC=$?
if [ "$CERTS_RC" -ne 0 ]; then
    echo "[entrypoint] Certificate setup failed with exit code $CERTS_RC; aborting startup."
    exit "$CERTS_RC"
fi

# Import P12 certificates to PKCS#11 token (after cert generation)
if [ "$ENABLE_MTLS" = "true" ] && [ "$ENABLE_PKCS11" = "true" ]; then
    echo "[entrypoint] Importing certificates to PKCS#11 token..."
    if [ -f "/opt/certs/client.p12" ] || [ -f "/opt/certs/reference.p12" ]; then
        /usr/local/bin/import-certs-to-pkcs11.sh
        if [ $? -eq 0 ]; then
            echo "[entrypoint] ✓ Certificates imported to PKCS#11 token"
        else
            echo "[entrypoint] WARNING: PKCS#11 certificate import failed"
        fi
    else
        echo "[entrypoint] WARNING: No P12 files found in /opt/certs, skipping PKCS#11 import"
    fi
fi

# Build and install RFC parameter provider and tr69hostif

rt_pid=`pidof rtrouted`
if [ ! -z "$rt_routed" ]; then
    kill -9 `pidof rtrouted`
fi

rm -fr /tmp/rtroute*
rtrouted -l DEBUG 

/usr/local/bin/rfc_provider &
/usr/local/bin/tr69hostif -c /etc/mgrlist.conf -d /etc/debug.ini -p 10999 -s 11999 | tee /opt/logs/tr69hostIf.log.0 &

/bin/bash
## Keep the container running . Running an independent process will help in simulating scenarios of webservices going down and coming up
while true ; do echo "Mocked native-platform heartbeat ..." && sleep 5 ; done
