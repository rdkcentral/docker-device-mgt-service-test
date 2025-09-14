#!/bin/sh

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

#set -m

# Enable mTLS if specified via environment variable (default: disabled)
ENABLE_MTLS=${ENABLE_MTLS:-false}
export ENABLE_MTLS

# Log mTLS status
echo "Starting with mTLS: $ENABLE_MTLS"

# Generate self-signed certificates for MockXconf at container startup
echo "Generating server certificates for MockXconf using generate_test_rdk_certs.sh..."

# Generate server certificates
/etc/pki/scripts/generate_test_rdk_certs.sh --type server

# Define certificate paths based on generate_test_rdk_certs.sh structure
ROOT_CA_NAME="Test-RDK-root"
CERT_NAME="test-rdk-server-cert"
ICA_NAME="Test-RDK-server-ICA"

# Copy the server certificates to the xconf certs directory
cp /etc/pki/${ROOT_CA_NAME}/${ICA_NAME}/private/${CERT_NAME}.key /etc/xconf/certs/mock-xconf-server-key.pem
cp /etc/pki/${ROOT_CA_NAME}/${ICA_NAME}/certs/${CERT_NAME}.pem /etc/xconf/certs/mock-xconf-server-cert.pem

echo "Server certificates generated and copied to /etc/xconf/certs"

# Always create shared certificate directory and share CA certificates
mkdir -p /mnt/L2_CONTAINER_SHARED_VOLUME/shared_certs/server

# Copy only the CA certificates (not the leaf cert) to the shared directory for native-platform to use
cp /etc/pki/${ROOT_CA_NAME}/certs/${ROOT_CA_NAME}.pem /mnt/L2_CONTAINER_SHARED_VOLUME/shared_certs/server/root-ca.cert.pem
cp /etc/pki/${ROOT_CA_NAME}/${ICA_NAME}/certs/${ICA_NAME}.pem /mnt/L2_CONTAINER_SHARED_VOLUME/shared_certs/server/intermediate-ca.cert.pem

echo "Server CA certificates copied to shared volume for native-platform"

# If mTLS is enabled at startup, wait for client certificates
if [ "$ENABLE_MTLS" = "true" ]; then
    echo "mTLS enabled - waiting for client certificates..."

    # Wait for client certificates
    while [ ! -f "/mnt/L2_CONTAINER_SHARED_VOLUME/shared_certs/client/root-ca.cert.pem" ] || [ ! -f "/mnt/L2_CONTAINER_SHARED_VOLUME/shared_certs/client/intermediate-ca.cert.pem" ]; do
        sleep 1
        echo "Waiting for client certificates..."
    done

    echo "Client certificates found - importing to trust store"

    # Import client CA certificates to trust store
    mkdir -p /etc/xconf/trust-store
    cp /mnt/L2_CONTAINER_SHARED_VOLUME/shared_certs/client/root-ca.cert.pem /etc/xconf/trust-store/
    cp /mnt/L2_CONTAINER_SHARED_VOLUME/shared_certs/client/intermediate-ca.cert.pem /etc/xconf/trust-store/
    c_rehash /etc/xconf/trust-store/

    echo "Client CA certificates imported to trust store"
    echo "mTLS certificate trust flow established"
fi

node /usr/local/bin/data-lake-mock.js &

#httpd-foreground
node /usr/local/bin/getT2DCMSettings.js &

node /usr/local/bin/getXconfData.js &

node /usr/local/bin/rfcData.js &

node /usr/local/bin/rrdFileupload.js &

## Keep the container running . Running an independent process will help in simulating scenarios of webservices going down and coming up
while true ; do echo "Mocked webservice heartbeat ..." && sleep 5 ; done