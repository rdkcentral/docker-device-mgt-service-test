#!/bin/sh

# This script is only for testing the L2 test cases of dcm-agent
LOG_PATH="/opt/logs/dcmd.log.0"
#Log framework to print timestamp and source script name
swupdateLog()
{
    echo "`/bin/timestamp` : $0: $*" >> $LOG_PATH
}


swupdateLog "Starting SoftwareUpdate Utility Script..."
triggerType=1
retry=0

if [ $# -eq 2 ]; then
    triggerType=$2
    retry=$1
fi
swupdateLog "trigger type=$triggerType and retry=$retry"

exit 0
