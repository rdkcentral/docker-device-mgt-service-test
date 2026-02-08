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

# Set log4c configuration path for RDK logger
export LOG4C_RCPATH=/etc

# Start rsyslog daemon for log management
echo "[entrypoint] Starting rsyslog daemon..."
rsyslogd
if [ $? -eq 0 ]; then
    echo "[entrypoint] rsyslog daemon started successfully"
    # Verify rsyslog is running
    sleep 1
    if pgrep -x rsyslogd > /dev/null; then
        echo "[entrypoint] rsyslog daemon confirmed running (PID: $(pgrep -x rsyslogd))"
    else
        echo "[entrypoint] WARNING: rsyslog daemon process not found"
    fi
else
    echo "[entrypoint] WARNING: rsyslog daemon failed to start with exit code $?"
fi

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
if [ ! -z "$rt_routed" ]; then
    kill -9 `pidof rtrouted`
fi

rm -fr /tmp/rtroute*
rtrouted -l DEBUG 

/usr/local/bin/rfc_provider &
/usr/local/bin/tr69hostif -c /etc/mgrlist.conf -p 10999 -s 11999 | tee /opt/logs/tr69hostIf.log.0 &

/bin/bash
## Keep the container running . Running an independent process will help in simulating scenarios of webservices going down and coming up
while true ; do echo "Mocked native-platform heartbeat ..." && sleep 5 ; done
