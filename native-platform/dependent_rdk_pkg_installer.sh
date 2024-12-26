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

# Install dependencies of libparodus
cd $WORKDIR
git clone https://github.com/nanomsg/nanomsg.git
cd nanomsg
mkdir build
cd build
cmake ..
cmake --build .
cmake --build . --target install
cd $WORKDIR
rm -rf nanomsg

git clone https://github.com/xmidt-org/cimplog.git
cd cimplog
git checkout 8a5fb3c2f182241d17f5342bea5b7688c28cd1fd
mkdir build
cd build
cmake ..
make && make install
cd $WORKDIR
rm -rf cimplog


cd $WORKDIR 
git clone https://github.com/xmidt-org/wrp-c.git
cd wrp-c
git checkout 9587e8db33dbbfcd9b78ef66cc2eaf16dfb9afcf
# replace  7a98138f27f27290e680bf8fbf1f8d1b089bf138 with 445880108a1d171f755ff6ac77e03fbebbb23729 in CMakeLists.txt
# Message pack revision used in libparadous is not buildable with latest gcc versions
sed -i 's/7a98138f27f27290e680bf8fbf1f8d1b089bf138/445880108a1d171f755ff6ac77e03fbebbb23729/g' CMakeLists.txt
mkdir build
cd build
cmake ..
make && make install
cd $WORKDIR
rm -rf wrp-c

cd $WORKDIR 
git clone https://github.com/xmidt-org/libparodus.git
cd libparodus
# replace  7a98138f27f27290e680bf8fbf1f8d1b089bf138 with 445880108a1d171f755ff6ac77e03fbebbb23729 in CMakeLists.txt
# Message pack revision used in libparadous is not buildable with latest gcc versions
sed -i 's/7a98138f27f27290e680bf8fbf1f8d1b089bf138/445880108a1d171f755ff6ac77e03fbebbb23729/g' CMakeLists.txt
mkdir build
cd build
cmake ..
make && make install
cd $WORKDIR 
rm -rf libparodus

#rtrouted -f -l DEBUG
