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

# Clone and build rbus
export RBUS_ROOT=/usr
export RBUS_INSTALL_DIR=${RBUS_ROOT}/local
mkdir -p $RBUS_INSTALL_DIR
cd $RBUS_ROOT


git clone https://github.com/rdkcentral/rbus
cmake -Hrbus -Bbuild/rbus -DBUILD_FOR_DESKTOP=ON -DCMAKE_BUILD_TYPE=Debug
make -C build/rbus && make -C build/rbus install

WORKDIR=/opt/WORKDIR
mkdir -p $WORKDIR

# cJson flavor used in RDK stack
cd $WORKDIR
git clone https://github.com/DaveGamble/cJSON.git
cd cJSON
mkdir build
cd build
cmake ..
make && make install
cd $WORKDIR
rm -rf cJSON

# Include WDMP package
cd $WORKDIR
git clone https://github.com/xmidt-org/wdmp-c.git
cd wdmp-c
sed -i '/WDMP_ERR_SESSION_IN_PROGRESS/a\    WDMP_ERR_INTERNAL_ERROR,\n    WDMP_ERR_DEFAULT_VALUE,' src/wdmp-c.h
cmake -H. -Bbuild -DBUILD_FOR_DESKTOP=ON -DCMAKE_BUILD_TYPE=Debug
make -C build && make -C build install
cd $WORKDIR 
rm -rf wdmp-c

cd $WORKDIR 
git clone https://github.com/schmidtw/wrp-c.git
git checkout main
cd wrp-c
mkdir build
cd build
cmake ..
make && make install
mkdir -p /usr/local/include/wrp-c
cp -r ../src/wrp-c.h /usr/local/include/wrp-c/
cd $ROOT
rm -rf wrp-c

cd $WORKDIR 
git clone https://github.com/xmidt-org/libparodus.git
cd libparodus
mkdir build
cd build
cmake ..
make && make install
cp -r ../src/libparodus.h /usr/local/include/
cp -r ../src/libparodus_log.h /usr/local/include/
cd $WORKDIR 
rm -rf libparodus


wget https://sourceforge.net/projects/procps-ng/files/Production/procps-ng-3.3.17.tar.xz
tar -xf procps-ng-3.3.17.tar.xz
cd procps-3.3.17
./configure --without-ncurses
make && make install
cd $WORKDIR
rm -rf procps-ng-3.3.17.tar.xz procps-3.3.17


#rtrouted -f -l DEBUG
