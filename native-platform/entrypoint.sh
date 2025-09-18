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

# System CA trust store location
SYSTEM_TRUST_STORE="/usr/share/ca-certificates"
mkdir -p ${SYSTEM_TRUST_STORE}


# Wait for the root CA and intermediate CA to be available
echo "Waiting for server root CA and intermediate CA..."
while [ ! -f /mnt/L2_CONTAINER_SHARED_VOLUME/shared_certs/server/root_ca.pem ] || \
      [ ! -f /mnt/L2_CONTAINER_SHARED_VOLUME/shared_certs/server/intermediate_ca.pem ]; do
  sleep 1
  echo "Waiting for server certificates..."
done

# Copy individual server CA certificates to system trust store
cp /mnt/L2_CONTAINER_SHARED_VOLUME/shared_certs/server/root_ca.pem ${SYSTEM_TRUST_STORE}/mock-xconf-root-ca.pem
cp /mnt/L2_CONTAINER_SHARED_VOLUME/shared_certs/server/intermediate_ca.pem ${SYSTEM_TRUST_STORE}/mock-xconf-intermediate-ca.pem
chmod 644 ${SYSTEM_TRUST_STORE}/mock-xconf-*.pem

# Update CA certificates
echo "mock-xconf-root-ca.pem" >> /etc/ca-certificates.conf
echo "mock-xconf-intermediate-ca.pem" >> /etc/ca-certificates.conf
update-ca-certificates --fresh

if [ "$ENABLE_MTLS" = "true" ]; then
    echo "mTLS enabled - performing certificate operations"

    # Generate certificates for PKI testing
    echo "Generating client certificates..."
    /etc/pki/scripts/generate_test_rdk_certs.sh --type client --cn "rdkclient"

    # Create certificate directories for mTLS
    mkdir -p /mnt/L2_CONTAINER_SHARED_VOLUME/shared_certs/client
    mkdir -p /opt/certs

    # Copy client certificates to /opt/certs directory
    ROOT_CA_NAME="Test-RDK-root"
    ICA_NAME="Test-RDK-client-ICA"
    CERT_NAME="rdkclient"

    # Default cert paths in container
    DEFAULT_P12="/opt/certs/client.p12"
    DEFAULT_PEM="/opt/certs/client.pem"

    # Create combined PEM file with both cert and key
    cat /etc/pki/${ROOT_CA_NAME}/${ICA_NAME}/certs/${CERT_NAME}.pem > $DEFAULT_PEM
    cat /etc/pki/${ROOT_CA_NAME}/${ICA_NAME}/private/${CERT_NAME}.key >> $DEFAULT_PEM
    cp /etc/pki/${ROOT_CA_NAME}/${ICA_NAME}/certs/${CERT_NAME}.p12 $DEFAULT_P12

    # Copy client CA chain to shared volume for mock-xconf container
    mkdir -p /mnt/L2_CONTAINER_SHARED_VOLUME/shared_certs/client
    cp /etc/pki/${ROOT_CA_NAME}/${ICA_NAME}/${ICA_NAME}_chain.pem /mnt/L2_CONTAINER_SHARED_VOLUME/shared_certs/client/ca-chain.pem

    echo "Client certificates generated and copied to /opt/certs"
    echo "Client CA chain copied to shared volume for mock-xconf"

    # Create CertSelector configuration file
    echo "Creating CertSelector configuration file..."
    mkdir -p /etc/ssl/certsel

    # Create a simple certsel.cfg file directly
    echo "MTLS|SRVR_TLS,OPERFS_P12,P12,file:///${DEFAULT_P12},cfgOpsCert" > /etc/ssl/certsel/certsel.cfg
    echo "MTLS_PEM,OPERFS_PEM,PEM,file:///${DEFAULT_PEM},cfgOpsCert" >> /etc/ssl/certsel/certsel.cfg
    echo "CertSelector configuration file created at /etc/ssl/certsel/certsel.cfg"

    # Wait for server root CA and intermediate CA to be available (added by mock-xconf container)
    echo "Waiting for server certificates from mock-xconf container..."
    while [ ! -f /mnt/L2_CONTAINER_SHARED_VOLUME/shared_certs/server/root_ca.pem ] || \
          [ ! -f /mnt/L2_CONTAINER_SHARED_VOLUME/shared_certs/server/intermediate_ca.pem ]; do
      sleep 1
      echo "Waiting for server certificates..."
    done

    # No additional imports needed for mTLS since we already copied the certificates to the system trust store
    echo "Server certificates are already imported to system trust store"
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
