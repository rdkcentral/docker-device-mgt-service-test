#!/bin/bash

rm -rf tr69hostif_dependency_pkg

mkdir tr69hostif_dependency_pkg
cd tr69hostif_dependency_pkg

# Clone iarmbus
git clone git@github.com:rdk-e/iarmbus.git

# Clone Tr69Hostif
git clone git@github.com:rdk-e/tr69hostif.git

# clone libparodus
git clone -b master https://github.com/xmidt-org/libparodus.git

# Clone wrp-c
git clone -b master https://github.com/xmidt-org/wrp-c.git

# Clone Safeclib
git clone https://github.com/rurban/safeclib.git

# Clone WDMP-c
git clone https://github.com/xmidt-org/wdmp-c

# Clone libsyscallWrapper
git clone https://code.rdkcentral.com/r/rdk/components/generic/libSyscallWrapper

# Clone RFC
#git clone -b 24Q4_sprint ssh://gerrit.teamccp.com:29418/rdk/components/generic/rfc/generic
git clone -b 24Q4_sprint ssh://kjeyac936@gerrit.teamccp.com:29418/rdk/components/generic/rfc/generic.git

# Clone ssa-cpc for safec_lib.h
#git clone -b stable2 ssh://gerrit.teamccp.com:29418/rdk/components/cpc/ssa-cpc
git clone -b stable2 ssh://kjeyac936@gerrit.teamccp.com:29418/rdk/components/cpc/ssa-cpc.git

# Clone Device Settings
git clone -b master https://code.rdkcentral.com/r/rdk/components/generic/devicesettings
git clone git@github.com:rdkcentral/rdk-halif-device_settings.git

#rm -rf tr69hostif_dependency_pkg
