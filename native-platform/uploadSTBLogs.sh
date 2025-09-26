#!/bin/sh

#function for directing to logs to dcmd log file
LOG_PATH="/opt/logs"
DCM_LOG_FILE=$LOG_PATH/dcmd.log.0
uploadLog() {
    echo "`/bin/timestamp` : $0: $*" >> $DCM_LOG_FILE
}

#input arguments

TFTP_SERVER=$1
FLAG=$2
DCM_FLAG=$3
UploadOnReboot=$4
UploadProtocol=$5
UploadHttpLink=$6
TriggerType=$7
RRD_FLAG=$8
RRD_UPLOADLOG_FILE=$9


#Function to Upload Logs when Flag is true
uploadLogOnReboot()
{
    uploadLog "Called uploadLogOnReboot with $1"
}

uploadDCMLogs()
{
    uploadLog "Called uploadDCMLogs"
}

if [ -n "$RRD_FLAG" ] && [ "$RRD_FLAG" -eq 1 ]; then
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
else
    uploadLog "Triggered uploadSTBLogs.sh with arguments TFTP_SERVER=$TFTP_SERVER,FLAG=$FLAG, DCM_FLAG=$DCM_FLAG, UploadOnReboot=$UploadOnReboot, UploadProtocol=$UploadProtocol, UploadHttpLink= $UploadHttpLink &"
    #Read Upload_Flag information
    if [ -f "/tmp/DCMSettings.conf" ]; then
        upload_flag=`cat /tmp/DCMSettings.conf | grep 'urn:settings:LogUploadSettings:upload' | cut -d '=' -f2 | sed 's/^"//' | sed 's/"$//'`
        uploadLog "upload_flag = $upload_flag"
    fi

    #logupload functions
    if [ $DCM_FLAG -eq 0 ] ; then
        uploadLog "Uploading Without DCM"
        uploadLogOnReboot true
    else
        if [ $FLAG -eq 1 ] ; then
            if [ $UploadOnReboot -eq 1 ]; then
                uploadLog "UploadOnReboot set to true"
                uploadLogOnReboot true
            else
                uploadLog "UploadOnReboot set to false"
                uploadLogOnReboot false
            fi
        else
            if [ $UploadOnReboot -eq 0 ]; then
                uploadDCMLogs
            else
                uploadDCMLogs
            fi
        fi
    fi
fi

exit 0

