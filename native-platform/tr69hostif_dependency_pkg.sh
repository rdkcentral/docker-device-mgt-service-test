#!/bin/bash

rm -rf tr69hostif_dependency_pkg

mkdir tr69hostif_dependency_pkg
cd tr69hostif_dependency_pkg

# Clone iarmbus
git clone git@github.com:rdk-e/iarmbus.git

# Clone Tr69Hostif
git clone git@github.com:rdk-e/tr69hostif.git

# Clone Safeclib
git clone https://github.com/rurban/safeclib.git

# Clone libsyscallWrapper
git clone https://code.rdkcentral.com/r/rdk/components/generic/libSyscallWrapper

# Clone RFC
git clone -b 24Q4_sprint ssh://gerrit.teamccp.com:29418/rdk/components/generic/rfc/generic

# Clone ssa-cpc for safec_lib.h
git clone -b stable2 ssh://gerrit.teamccp.com:29418/rdk/components/cpc/ssa-cpc

# Clone Device Settings
git clone git@github.com:rdkcentral/rdk-halif-device_settings.git
git clone -b master https://code.rdkcentral.com/r/rdk/components/generic/devicesettings

# Test in CI pipeline
ls ./

cd devicesettings
cp ../../devicesettings_compilation.patch ./
git apply devicesettings_compilation.patch
