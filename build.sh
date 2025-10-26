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

# Local build configuration (no registry push)
# Build images with same names as compose.yaml expects so they take precedence
REGISTRY_ROOT="ghcr.io/rdkcentral"
REPOSITORY_NAME="docker-device-mgt-service-test"
REVISION="local-build"

# Build container that provides mock xconf service
echo "Building mock-xconf image..."
cd mock-xconf
docker build --no-cache -t ${REGISTRY_ROOT}/${REPOSITORY_NAME}/mockxconf:latest -f Dockerfile .
cd -

# Test mock-xconf container functionality
echo "Testing mock-xconf container..."
docker run --rm ${REGISTRY_ROOT}/${REPOSITORY_NAME}/mockxconf:latest sh -c "/usr/local/bin/certs.sh && openssl x509 -text -noout -in /etc/xconf/certs/mock-xconf-server-cert.pem"

echo "Building native-platform image..."
cd native-platform

# Clean up any existing dependencies
rm -rf rdk_logger
rm -rf WebconfigFramework
rm -rf libSyscallWrapper
rm -rf common_utilities
rm -rf tr69hostif

# Clone dependencies with specific versions matching the workflow
echo "Cloning dependencies with specific versions..."
git clone -b IMPORT_INITIAL_develop https://github.com/rdkcentral/rdk_logger.git
git clone -b IMPORT_INITIAL_develop https://github.com/rdkcentral/WebconfigFramework.git
git clone -b IMPORT_INITIAL_develop https://github.com/rdkcentral/libSyscallWrapper.git
git clone -b 1.4.0 https://github.com/rdkcentral/common_utilities.git
git clone -b 1.2.7 https://github.com/rdkcentral/tr69hostif.git

# Build native-platform with build args for host architecture
docker build --build-arg REVISION=${REVISION} -t ${REGISTRY_ROOT}/${REPOSITORY_NAME}/native-platform:latest -f Dockerfile .

# Clean up dependencies
rm -rf rdk_logger
rm -rf WebconfigFramework
rm -rf libSyscallWrapper
rm -rf common_utilities
rm -rf tr69hostif
cd -

echo "Build completed successfully!"
echo "Built images:"
echo "  - ${REGISTRY_ROOT}/${REPOSITORY_NAME}/mockxconf:latest"
echo "  - ${REGISTRY_ROOT}/${REPOSITORY_NAME}/native-platform:latest"
echo ""
echo "These images will be used by compose.yaml instead of pulling from remote registry."



