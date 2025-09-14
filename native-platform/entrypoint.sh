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

# Enable mTLS if specified via environment variable (default: disabled)
ENABLE_MTLS=${ENABLE_MTLS:-false}
export ENABLE_MTLS

# Log mTLS status
echo "Starting with mTLS: $ENABLE_MTLS"

# Always create the basic directory for application certificates
mkdir -p /opt/certs

if [ "$ENABLE_MTLS" = "true" ]; then
    echo "mTLS enabled - performing certificate operations"

    # Generate certificates for PKI testing
    echo "Generating client certificates..."
    /usr/local/share/cert-scripts/generate_test_rdk_certs.sh --type client

    # Create certificate directories for mTLS
    mkdir -p /mnt/L2_CONTAINER_SHARED_VOLUME/shared_certs/client
    mkdir -p /etc/pki/server-trust

    # Copy client certificates to /opt/certs directory
    cp /etc/pki/certs/client/client.key.pem /opt/certs/
    cp /etc/pki/certs/client/client.cert.pem /opt/certs/
    cp /etc/pki/certs/client/client.p12 /opt/certs/

    # Copy client CA certificates to shared volume for mock-xconf container
    cp /etc/pki/certs/client/root-ca.cert.pem /mnt/L2_CONTAINER_SHARED_VOLUME/shared_certs/client/
    cp /etc/pki/certs/client/intermediate-ca.cert.pem /mnt/L2_CONTAINER_SHARED_VOLUME/shared_certs/client/

    echo "Client certificates generated and copied to /opt/certs"
    echo "Client CA certificates copied to shared volume for mock-xconf"

    # Wait for server certificates to be available (added by mock-xconf container)
    echo "Waiting for server certificates from mock-xconf container..."
    while [ ! -f /mnt/L2_CONTAINER_SHARED_VOLUME/shared_certs/server/root-ca.cert.pem ] || [ ! -f /mnt/L2_CONTAINER_SHARED_VOLUME/shared_certs/server/intermediate-ca.cert.pem ]; do
      sleep 1
      echo "Waiting for server certificates..."
    done

    # Import server CA certificates to trust store
    cp /mnt/L2_CONTAINER_SHARED_VOLUME/shared_certs/server/root-ca.cert.pem /etc/pki/server-trust/
    cp /mnt/L2_CONTAINER_SHARED_VOLUME/shared_certs/server/intermediate-ca.cert.pem /etc/pki/server-trust/
    c_rehash /etc/pki/server-trust/

    echo "Server CA certificates imported to trust store"
    echo "mTLS certificate trust flow established"
else
    echo "mTLS disabled - skipping certificate operations"
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
