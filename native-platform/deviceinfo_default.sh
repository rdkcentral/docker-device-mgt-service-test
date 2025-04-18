#!/bin/sh

sed -i '/X_COMCAST-COM_STB_MAC/ {n; n; a\
        <default type="factory" value="AA:BB:CC:DD:EE:FF"/>
}' /etc/data-model-stb.xml
sed -i '/X_COMCAST-COM_STB_IP/ {n; n; a\
        <default type="factory" value="10.0.0.1"/>
}' /etc/data-model-stb.xml
sed -i '/X_COMCAST-COM_FirmwareFilename/ {n; n; a\
        <default type="factory" value="Platform_Cotainer_1.0.0"/>
}' /etc/data-model-stb.xml
sed -i '/ModelName/ {n; n; a\
        <default type="factory" value="DOCKER"/>
}' /etc/data-model-stb.xml
sed -i '/ConfigURL/ {n; n; a\
        <default type="factory" value="https://mockxconf:50050/loguploader/getT2DCMSettings"/>
}' /etc/data-model-generic.xml
sed -i '/AccountID/ {n; n; a\
        <default type="factory" value="Platform_Container_Test_DEVICE"/>
}' /etc/data-model-generic.xml
sed -i '/Telemetry.MTLS/ {n; n; n; n; d;
}' /etc/data-model-generic.xml
sed -i '/Telemetry.MTLS/ {n; n; n; a\
        <default type="factory" value="false"/>
}' /etc/data-model-generic.xml
