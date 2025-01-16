FROM ubuntu:jammy
ARG DEBIAN_FRONTEND=noninteractive
# Get the revision number from the build environment
# This must be a release tag derived from a github relase event context
ARG REVISION=0.0.0

# Add instructions to install autotools
RUN apt-get update && apt-get install -y build-essential \
          wget openssl tar vim git git-lfs


RUN apt-get install -y libtool autotools-dev automake zlib1g-dev ninja-build meson

RUN apt-get install -y libglib2.0-dev libcurl4-openssl-dev \
          libmsgpack-dev libsystemd-dev libssl-dev libcjson-dev python3-pip libsqlite3-dev
          
RUN apt-get install -y libgtest-dev libgmock-dev libjansson-dev libbsd-dev tcl-dev \
          libboost-all-dev libwebsocketpp-dev libcunit1 libcunit1-dev libunwind-dev

RUN apt-get update && apt-get install -y gdb valgrind lcov g++ wget gperf curl libjsonrpccpp-dev

# Add additional pytest packages 
RUN apt-get update && apt-get install -y \
    python3-pytest python3-pytest-cov software-properties-common

RUN add-apt-repository ppa:deadsnakes/ppa && apt-get update && apt-get install -y \
    python3-pytest-bdd
    
RUN pip3 install requests pytest-ordering pytest-json-report pytest-html

# Install CMake
RUN apt-get update && apt-get install -y cmake

# Install gtest libraries
RUN cd /usr/src/googletest/googlemock/ && mkdir build && cmake .. && make && make install

RUN apt-get update && apt-get install -y \
    liblog4c-dev libarchive-dev libtool-bin libgpgme-dev libsoup2.4-dev

RUN mkdir -p /opt && cd /opt && git clone git://git.yoctoproject.org/opkg \
    && cd opkg && autoreconf --install && ./configure && make && make install && \
    cd .. && rm -rf opkg

RUN cd /opt && git clone https://github.com/xmidt-org/trower-base64.git && \
    cd trower-base64 && \
    meson setup build && \
    ninja -C build && ninja -C build install
RUN rm -rf /opt/trower-base64

COPY ./mock-xconf-server-cert.pem /usr/share/ca-certificates/mock-xconf-server-cert.pem
RUN chmod 644 /usr/share/ca-certificates/mock-xconf-server-cert.pem
RUN echo "mock-xconf-server-cert.pem" >> /etc/ca-certificates.conf
RUN update-ca-certificates --fresh

# Build and install test binary that acts as a provider for all mandatory RFC parameters
RUN mkdir -p /opt 
COPY dependent_rdk_pkg_installer.sh /opt/dependent_rdk_pkg_installer.sh
RUN chmod +x /opt/dependent_rdk_pkg_installer.sh && /opt/dependent_rdk_pkg_installer.sh
RUN rm -rf /opt/dependent_rdk_pkg_installer.sh

COPY rdk_logger /opt/rdk_logger
RUN cd /opt/rdk_logger && autoreconf --install && ./configure && make && make install
RUN rm -rf /opt/rdk_logger
COPY debug.ini /etc/debug.ini
COPY log4crc /etc/log4crc

COPY WebconfigFramework /opt/WebconfigFramework
RUN cd /opt/WebconfigFramework && export INSTALL_DIR='/usr/local'&& \
export CFLAGS="-I${INSTALL_DIR}/include/rtmessage -I${INSTALL_DIR}/include/msgpack -I${INSTALL_DIR}/include/rbus -I${INSTALL_DIR}/include" && \
export LDFLAGS="-L${INSTALL_DIR}/lib" && \
autoreconf --install && \
./configure --prefix=/usr/local && make && make install && cp -r include/* /usr/local/include/
RUN rm -rf /opt/WebconfigFramework

COPY libSyscallWrapper /opt/libSyscallWrapper
RUN cd /opt/libSyscallWrapper && export INSTALL_DIR='/usr/local' && \
autoreconf --install && \
./configure --prefix=/usr/local && make && make install
RUN rm -rf /opt/libSyscallWrapper

COPY common_utilities /opt/common_utilities
RUN cd /opt/common_utilities && export INSTALL_DIR='/usr/local' && \
export CFLAGS="-Wno-error=format -Wno-unused-result -Wno-format-truncation -Wno-error=format-security -DRDK_LOGGER" && \
autoreconf --install && \
./configure --prefix=/usr/local && make && make install
RUN rm -rf /opt/common_utilities

# Mock implementation of RFC provider in target device
COPY  ./ /opt/containers
RUN cd /opt/containers/mock-rfc-providers && export INSTALL_DIR='/usr/local' && \
export CFLAGS="-I${INSTALL_DIR}/include/rtmessage -I${INSTALL_DIR}/include/msgpack -I${INSTALL_DIR}/include/rbus -I${INSTALL_DIR}/include" && \
export LDFLAGS="-L${INSTALL_DIR}/lib" && \
autoreconf --install && \
./configure --prefix=/usr/local && make && make install
RUN rm -rf /opt/containers

# Packages required for tr69hostif
RUN apt-get update && apt-get install -y libdirectfb-dev libyajl-dev libtinyxml2-dev libdbus-1-dev libdbus-glib-1-dev procps libprocps-dev 

# Trim down the docker image size
RUN rm -rf /var/lib/apt/lists/*

# Emulate the device side settings
RUN mkdir -p /opt/logs
RUN mkdir -p /etc

RUN echo "imagename=T2_Container_${REVISION}" >> /version.txt

RUN echo "BUILD_TYPE=PROD" > /etc/device.properties
RUN echo "DEVICE_NAME=DEVELOPER_CONTAINER" >> /etc/device.properties
RUN echo "MODEL_NUM=L2CNTR" >> /etc/device.properties

RUN touch /tmp/route_available
# Sample IP
RUN echo "IPV4 8.8.4.4" >> /tmp/.GatewayIP_dfltroute
# Sample DNS
RUN echo "nameserver 8.8.8.8" >> /etc/resolv.dnsmasq
RUN echo "comcast" > /opt/partnerid
# Sample MAC
RUN echo "01:23:45:67:89:ab" > /tmp/.estb_mac
# Mock RFC URL
RUN echo "RFC_CONFIG_SERVER_URL=https://mockxconf:50053/featureControl/getSettings" | tee /opt/rfc.properties /etc/rfc.properties > /dev/null
# Old RFC FWVersion
RUN echo "imagename=T2_Container_Prev${REVISION}" >> /opt/secure/RFC/.version

# Custom expectation from RDK stack to have a timezone file in the stack
RUN mkdir -p /opt/persistent
RUN echo 'US/Mountain' > /opt/persistent/timeZoneDST

# Create A Shared Volume
RUN mkdir -p /mnt/L2_CONTAINER_SHARED_VOLUME

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
RUN echo 'export PATH=$PATH:/usr/local/bin' >> ~/.bashrc
RUN echo 'export LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu:/usr/local/lib:$LD_LIBRARY_PATH' >> ~/.bashrc

# Set the entry point command
#CMD ["/bin/bash"]

CMD ["/usr/local/bin/entrypoint.sh"]
