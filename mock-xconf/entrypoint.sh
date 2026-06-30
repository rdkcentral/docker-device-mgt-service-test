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

## Start CRL mTLS server (port 50061) + CRL control (port 50062)
## crl-control.js is loaded as a module by crl-mtls-server.js (single process)
ENABLE_CRL_L3=${ENABLE_CRL_L3:-false}
if [ "$ENABLE_CRL_L3" = "true" ]; then
	if [ -f /usr/local/bin/crl-mtls-server.js ]; then
		node /usr/local/bin/crl-mtls-server.js &
		echo "[entrypoint] crl-mtls-server started (ports 50061 + 50062)"
	else
		echo "[entrypoint] WARNING: /usr/local/bin/crl-mtls-server.js not found"
	fi

	## OCSP stapling infrastructure
	## openssl ocsp daemon (port 50063) must start before ocsp-stapling-server.js
	## so the stapling server can warm its cache during listen().
	if [ -d /etc/xconf/certs/ocsp ] && \
	   [ -f /etc/xconf/certs/ocsp/Test-CRL-ICA.pem ] && \
	   [ -f /etc/xconf/certs/ocsp/ocsp-ca-chain.pem ] && \
	   [ -f /etc/xconf/certs/ocsp/ocsp-responder.pem ] && \
	   [ -f /etc/xconf/certs/ocsp/ocsp-responder.key ]; then
		openssl ocsp \
			-index /etc/pki/test-crl/Test-CRL-Root/Test-CRL-ICA/index.txt \
			-port 50063 \
			-rsigner /etc/xconf/certs/ocsp/ocsp-responder.pem \
			-rkey   /etc/xconf/certs/ocsp/ocsp-responder.key \
			-CA     /etc/xconf/certs/ocsp/Test-CRL-ICA.pem \
			-text \
			-ignore_err &
		echo "[entrypoint] openssl ocsp responder started (port 50063)"
		# Brief pause so the responder socket is open before the Node server
		# tries to warm its cache
		sleep 1
		if [ -f /usr/local/bin/ocsp-stapling-server.js ]; then
			node /usr/local/bin/ocsp-stapling-server.js &
			echo "[entrypoint] ocsp-stapling-server started (port 50064)"
		else
			echo "[entrypoint] WARNING: /usr/local/bin/ocsp-stapling-server.js not found"
		fi
	else
		echo "[entrypoint] WARNING: OCSP PKI certs not found — skipping OCSP servers"
	fi
fi

## Keep the container running . Running an independent process will help in simulating scenarios of webservices going down and coming up
while true ; do echo "Mocked webservice heartbeat ..." && sleep 5 ; done
