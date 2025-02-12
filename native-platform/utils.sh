#!/bin/sh

getMacAddressOnly()
{
    cat /etc/device.properties | grep DEVICE_MAC | awk -F '=' '{print $2}' | sed -e 's/://g' | tr a-z A-Z
}
