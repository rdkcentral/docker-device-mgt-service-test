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

# Detect architecture for multi-platform support (x86_64 and Apple Silicon/aarch64)
ARCH=$(uname -m)
case $ARCH in
    x86_64)
        ARCH_LIB_PATH="/usr/lib/x86_64-linux-gnu"
        ARCH_LIB_PATH_ALT="/lib/x86_64-linux-gnu"
        ;;
    aarch64)
        ARCH_LIB_PATH="/usr/lib/aarch64-linux-gnu"
        ARCH_LIB_PATH_ALT="/lib/aarch64-linux-gnu"
        ;;
    *)
        echo "Warning: Unsupported architecture $ARCH, defaulting to x86_64 paths"
        ARCH_LIB_PATH="/usr/lib/x86_64-linux-gnu"
        ARCH_LIB_PATH_ALT="/lib/x86_64-linux-gnu"
        ;;
esac

# Set up library path for both architectures (aligned with cov_build.sh and L2-tests.yml)
export LD_LIBRARY_PATH=${RBUS_INSTALL_DIR}/lib:/usr/lib/x86_64-linux-gnu:/lib/aarch64-linux-gnu:/usr/local/lib:$ARCH_LIB_PATH:$ARCH_LIB_PATH_ALT:${LD_LIBRARY_PATH}

ENABLE_MTLS=${ENABLE_MTLS:-false}
export ENABLE_MTLS

## Certificate setup
/usr/local/bin/certs.sh
CERTS_RC=$?
if [ "$CERTS_RC" -ne 0 ]; then
    echo "[entrypoint] Certificate setup failed with exit code $CERTS_RC; aborting startup."
    exit "$CERTS_RC"
fi

# Build and install RFC parameter provider and tr69hostif

rt_pid=`pidof rtrouted`
if [ ! -z "$rt_pid" ]; then
    kill -9 `pidof rtrouted`
fi

rm -fr /tmp/rtroute*
rtrouted -l DEBUG 

/usr/local/bin/rfc_provider &
/usr/local/bin/tr69hostif -c /etc/mgrlist.conf -d /etc/debug.ini -p 10999 -s 11999 | tee /opt/logs/tr69hostIf.log.0 &

/bin/bash
## Keep the container running . Running an independent process will help in simulating scenarios of webservices going down and coming up
while true ; do echo "Mocked native-platform heartbeat ..." && sleep 5 ; done
