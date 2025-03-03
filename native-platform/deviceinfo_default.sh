#!/bin/sh

sed -i '/X_COMCAST-COM_STB_MAC/ {n; n; a\
        <default type="factory" value="AA:BB:CC:DD:EE:FF"/>
}' /etc/data-model.xml
sed -i '/X_COMCAST-COM_STB_IP/ {n; n; a\
        <default type="factory" value="10.0.0.1"/>
}' /etc/data-model.xml
sed -i '/X_COMCAST-COM_FirmwareFilename/ {n; n; a\
        <default type="factory" value="Platform_Cotainer_1.0.0"/>
}' /etc/data-model.xml
sed -i '/ModelName/ {n; n; a\
        <default type="factory" value="DOCKER"/>
}' /etc/data-model.xml
