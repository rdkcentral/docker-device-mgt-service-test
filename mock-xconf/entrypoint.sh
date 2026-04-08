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

ENABLE_MTLS=${ENABLE_MTLS:-false}
export ENABLE_MTLS

## Certificate setup
/usr/local/bin/certs.sh
CERTS_RC=$?
if [ "$CERTS_RC" -ne 0 ]; then
	echo "[entrypoint] Certificate setup failed with exit code $CERTS_RC; aborting startup."
	exit "$CERTS_RC"
fi

node /usr/local/bin/data-lake-mock.js &

#httpd-foreground
node /usr/local/bin/getT2DCMSettings.js &

node /usr/local/bin/getXconfData.js &

node /usr/local/bin/rfcData.js &

node /usr/local/bin/rrdFileupload.js &

node /usr/local/bin/rdmFileupload.js &

node /usr/local/bin/stbLogUpload.js &

node /usr/local/bin/crashUpload.js &

## RDK-61060: Start XPKI Certifier service (port 50055)
echo "[entrypoint] DEBUG: Checking xpki-certifier.js file..."
if [ -f /usr/local/bin/xpki-certifier.js ]; then
	echo "[entrypoint] xpki-certifier.js found, starting service..."
	node /usr/local/bin/xpki-certifier.js &
	XPKI_PID=$!
	echo "[entrypoint] xpki-certifier started (PID: $XPKI_PID) on port 50055"
else
	echo "[entrypoint] ERROR: /usr/local/bin/xpki-certifier.js NOT FOUND - xpki service will not start"
	ls -la /usr/local/bin/xpki* || echo "No xpki files in /usr/local/bin"
fi

## Signal handler for clean shutdown of background processes
trap 'echo "[entrypoint] Received shutdown signal, stopping services..."; kill $(jobs -p) 2>/dev/null; exit 0' TERM INT

## Keep the container running . Running an independent process will help in simulating scenarios of webservices going down and coming up
while true ; do echo "Mocked webservice heartbeat ..." && sleep 5 ; done
