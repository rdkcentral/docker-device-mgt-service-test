#!/bin/sh

TFTP_SERVER=$1
FLAG=$2
DCM_FLAG=$3
UploadOnReboot=$4
UploadProtocol=$5
UploadHttpLink=$6
TriggerType=$7
RRD_FLAG=$8
RRD_UPLOADLOG_FILE=$9

if [ "$RRD_FLAG" -eq 1 ]; then
    RRD_DIR="/tmp/rrd/"
    UploadHttpLink="https://mockxconf:50054/rrdUploadFile"
    ret=`curl -k -F "file=@$RRD_DIR$RRD_UPLOADLOG_FILE" $UploadHttpLink --insecure -w "%{http_code}" -o /dev/null`
    if [ $? -eq 0 ]; then
        echo "Curl command executed successfully."
        if [ "$ret" = "200" ];then
            echo "Uploading Logs through HTTP Success..., HTTP response code: $ret"
            exit 0
        else
            echo "Uploading Logs through HTTP Failed!!!, HTTP response code: $ret"
            exit 127
        fi
    else
        echo "Curl command failed with return code $?."
        exit 127
    fi
fi
