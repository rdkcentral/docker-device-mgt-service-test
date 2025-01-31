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

REGISTRY_ROOT="ghcr.io"
REPOSITORY_NAME="rdkcentral/docker-device-mgt-service-test"

# Default value for argument
tr69hostif=false

# Identify/Enable the module via arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tr69hostif)
      tr69hostif=true
      shift
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done

# Conditionally execute the dependency script if the argument is passed
if [ "$tr69hostif" = true ]; then
  echo "Executing the dependency script..."
  git apply native-platform/MockRFC_Provider.patch
else
  echo "Skipping the dependency."
fi

# Build container that provides mock xconf service
cd mock-xconf
## There is a cert file that is required to be copied to the native-platform container
##  It has a time element to it, so making sure that its nit built from cache is important
docker build --no-cache -t ${REGISTRY_ROOT}/${REPOSITORY_NAME}/mockxconf:latest -f Dockerfile .
cd -


cd native-platform
rm -rf rdk_logger
rm -rf WebconfigFramework
rm -rf libSyscallWrapper
rm -rf common_utilities

git clone https://github.com/rdkcentral/rdk_logger.git
git clone https://github.com/rdkcentral/WebconfigFramework.git
git clone https://github.com/rdkcentral/libSyscallWrapper.git
git clone https://github.com/rdkcentral/common_utilities.git

chmod +x tr69hostif_dependency_pkg.sh && ./tr69hostif_dependency_pkg.sh

# Dump the contents of /etc/xconf/certs/mock-xconf-server-cert.pem from above container into a file called mock-xconf-server-cert.pem
docker run --rm ${REGISTRY_ROOT}/${REPOSITORY_NAME}/mockxconf:latest cat /etc/xconf/certs/mock-xconf-server-cert.pem > mock-xconf-server-cert.pem

docker build -t ${REGISTRY_ROOT}/${REPOSITORY_NAME}/native-platform:latest -f Dockerfile .

rm -f mock-xconf-server-cert.pem
rm -rf rdk_logger
rm -rf WebconfigFramework
rm -rf libSyscallWrapper
rm -rf common_utilities
rm -rf tr69hostif_dependency_pkg/
cd -



