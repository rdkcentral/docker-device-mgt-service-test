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

# Build ssa-cpc if ENABLE_PKCS11 is true
# Note: rdktrusthal-cpc is built into the Docker image at build time (see Dockerfile)
if [ "$ENABLE_PKCS11" = "true" ]; then
    echo "[entrypoint] ENABLE_PKCS11=true - Building ssa-cpc from shared volume..."
    
    # Build ssa-cpc CA provider libraries from shared volume
   SSA_CPC_SRC="/mnt/L2_CONTAINER_SHARED_VOLUME/ssa-cpc"
    if [ -d "$SSA_CPC_SRC" ]; then
        cd "$SSA_CPC_SRC"
        
        # Build ssa-cpc with PKCS#11 support
        if [ ! -f "Makefile" ]; then
            echo "[entrypoint] Configuring ssa-cpc..."
            autoreconf --install 2>&1 | grep -v "warning:" || true
            ./configure --prefix=/usr/local --enable-pkcs11 2>&1 | grep -v "warning:" || true
        fi
        
        echo "[entrypoint] Building ssa-cpc CA providers..."
        make clean 2>/dev/null || true
        make -j$(nproc) 2>&1 | tail -20
        make install 2>&1 | grep -E "(Installing|installed)" || true
        
        if [ -f "/usr/local/lib/libssa-cpc.so" ] || [ -f "/usr/local/lib/librdkssa.so" ]; then
            echo "[entrypoint] ✓ ssa-cpc installed"
            ldconfig
        else
            echo "[entrypoint] ⚠ ssa-cpc build may have failed (library not found)"
        fi
    else
        echo "[entrypoint] ⚠ ssa-cpc source not found at $SSA_CPC_SRC"
    fi
fi

## Certificate setup (includes OpenSSL PKCS#11 setup if enabled)
/usr/local/bin/certs.sh
CERTS_RC=$?
if [ "$CERTS_RC" -ne 0 ]; then
    echo "[entrypoint] Certificate setup failed with exit code $CERTS_RC; aborting startup."
    exit "$CERTS_RC"
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
