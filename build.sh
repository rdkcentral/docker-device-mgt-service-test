#!/bin/bash
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

REGISTRY_ROOT="ghcr.io/rdkcentral"
REPOSITORY_NAME="docker-device-mgt-service-test"

# Build container that provides mock xconf service
cd mock-xconf
docker build --no-cache -t ${REGISTRY_ROOT}/${REPOSITORY_NAME}/mockxconf:latest -f Dockerfile .
cd -


cd native-platform
rm -rf rdk_logger
rm -rf WebconfigFramework
rm -rf libSyscallWrapper
rm -rf common_utilities
rm -rf tr69hostif

git clone https://github.com/rdkcentral/rdk_logger.git
git clone https://github.com/rdkcentral/WebconfigFramework.git
git clone https://github.com/rdkcentral/libSyscallWrapper.git
git clone https://github.com/rdkcentral/common_utilities.git
git clone https://github.com/rdkcentral/tr69hostif.git

docker build -t ${REGISTRY_ROOT}/${REPOSITORY_NAME}/native-platform:latest -f Dockerfile .

rm -rf rdk_logger
rm -rf WebconfigFramework
rm -rf libSyscallWrapper
rm -rf common_utilities
rm -rf tr69hostif
cd -



