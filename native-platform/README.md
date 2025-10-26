# Native Platform Container

This document provides a comprehensive overview of the software packages and their versions installed in the native-platform container used for RDK L2 testing and tr69hostif integration.

## Base Image
- **Ubuntu**: jammy (22.04 LTS)

## Build Arguments
- **REVISION**: 0.0.0 (default, overrideable at build time)
- **DEBIAN_FRONTEND**: noninteractive

## System Packages

### Core Development Tools
- **build-essential**: Latest from Ubuntu jammy repository
- **autotools-dev**: Latest from Ubuntu jammy repository  
- **automake**: Latest from Ubuntu jammy repository
- **libtool**: Latest from Ubuntu jammy repository
- **libtool-bin**: Latest from Ubuntu jammy repository
- **cmake**: Latest from Ubuntu jammy repository
- **ninja-build**: Latest from Ubuntu jammy repository
- **meson**: Latest from Ubuntu jammy repository
- **g++**: Latest from Ubuntu jammy repository
- **gperf**: Latest from Ubuntu jammy repository

### Utilities and Tools
- **wget**: Latest from Ubuntu jammy repository
- **curl**: Latest from Ubuntu jammy repository
- **openssl**: Latest from Ubuntu jammy repository
- **tar**: Latest from Ubuntu jammy repository
- **vim**: Latest from Ubuntu jammy repository
- **git**: Latest from Ubuntu jammy repository
- **git-lfs**: Latest from Ubuntu jammy repository
- **dos2unix**: Latest from Ubuntu jammy repository
- **busybox**: Latest from Ubuntu jammy repository

### Development Libraries
- **zlib1g-dev**: Latest from Ubuntu jammy repository
- **libglib2.0-dev**: Latest from Ubuntu jammy repository
- **libcurl4-openssl-dev**: Latest from Ubuntu jammy repository
- **libmsgpack-dev**: Latest from Ubuntu jammy repository
- **libsystemd-dev**: Latest from Ubuntu jammy repository
- **libssl-dev**: Latest from Ubuntu jammy repository
- **libcjson-dev**: Latest from Ubuntu jammy repository
- **libsqlite3-dev**: Latest from Ubuntu jammy repository
- **liblog4c-dev**: Latest from Ubuntu jammy repository
- **libarchive-dev**: Latest from Ubuntu jammy repository
- **libgpgme-dev**: Latest from Ubuntu jammy repository
- **libsoup2.4-dev**: Latest from Ubuntu jammy repository
- **libsoup-3.0**: Latest from Ubuntu jammy repository
- **libdirectfb-dev**: Latest from Ubuntu jammy repository
- **libyajl-dev**: Latest from Ubuntu jammy repository
- **libtinyxml2-dev**: Latest from Ubuntu jammy repository
- **libdbus-1-dev**: Latest from Ubuntu jammy repository
- **libdbus-glib-1-dev**: Latest from Ubuntu jammy repository
- **libprocps-dev**: Latest from Ubuntu jammy repository

### Testing and Development Libraries
- **libgtest-dev**: Latest from Ubuntu jammy repository
- **libgmock-dev**: Latest from Ubuntu jammy repository
- **libjansson-dev**: Latest from Ubuntu jammy repository
- **libbsd-dev**: Latest from Ubuntu jammy repository
- **tcl-dev**: Latest from Ubuntu jammy repository
- **libboost-all-dev**: Latest from Ubuntu jammy repository
- **libwebsocketpp-dev**: Latest from Ubuntu jammy repository
- **libcunit1**: Latest from Ubuntu jammy repository
- **libcunit1-dev**: Latest from Ubuntu jammy repository
- **libunwind-dev**: Latest from Ubuntu jammy repository
- **libnanomsg-dev**: Latest from Ubuntu jammy repository
- **libjsonrpccpp-dev**: Latest from Ubuntu jammy repository

### Debugging and Analysis Tools
- **gdb**: Latest from Ubuntu jammy repository
- **valgrind**: Latest from Ubuntu jammy repository
- **lcov**: Latest from Ubuntu jammy repository

### Network Tools
- **iproute2**: Latest from Ubuntu jammy repository
- **nmap**: Latest from Ubuntu jammy repository
- **netcat**: Latest from Ubuntu jammy repository
- **iptables**: Latest from Ubuntu jammy repository (configured to use legacy version)
- **net-tools**: Latest from Ubuntu jammy repository
- **arptables**: Latest from Ubuntu jammy repository (configured to use legacy version)
- **ebtables**: Latest from Ubuntu jammy repository (configured to use legacy version)

### Python Environment
- **python3-pip**: Latest from Ubuntu jammy repository
- **python3-pytest**: Latest from Ubuntu jammy repository
- **python3-pytest-cov**: Latest from Ubuntu jammy repository
- **python3-pytest-bdd**: Latest from deadsnakes PPA
- **software-properties-common**: Latest from Ubuntu jammy repository (removed after use)

### Python Packages (via pip3)
- **requests**: Latest from PyPI
- **pytest-ordering**: Latest from PyPI
- **pytest-json-report**: Latest from PyPI
- **pytest-html**: Latest from PyPI
- **msgpack**: Latest from PyPI

### Node.js
- **nodejs**: Version 22.x from NodeSource repository

## Custom Built Packages

### RDK Components (Built from Source)

#### OPKG Package Manager
- **Source**: https://git.yoctoproject.org/opkg
- **Version**: v0.7.0
- **Build Method**: autotools (autoreconf, configure, make, make install)

#### Trower Base64
- **Source**: https://github.com/xmidt-org/trower-base64.git
- **Version**: Latest from main branch
- **Build Method**: meson/ninja

#### RDK Certificate Configuration
- **Source**: https://github.com/rdkcentral/rdk-cert-config.git
- **Version**: Latest from main branch
- **Build Method**: autotools with --enable-testrdkcerts
- **Install Location**: /usr/local

#### RBUS
- **Source**: https://github.com/rdkcentral/rbus
- **Version**: Latest from main branch
- **Build Method**: CMake with -DBUILD_FOR_DESKTOP=ON -DCMAKE_BUILD_TYPE=Debug
- **Install Location**: /usr/local

#### cJSON
- **Source**: https://github.com/DaveGamble/cJSON.git
- **Version**: Latest from main branch
- **Build Method**: CMake

#### WDMP-C
- **Source**: https://github.com/xmidt-org/wdmp-c.git
- **Version**: Latest from main branch (with custom patches)
- **Build Method**: CMake with -DBUILD_FOR_DESKTOP=ON -DCMAKE_BUILD_TYPE=Debug
- **Modifications**: Added WDMP_ERR_INTERNAL_ERROR and WDMP_ERR_DEFAULT_VALUE to wdmp-c.h

#### Nanomsg
- **Source**: https://github.com/nanomsg/nanomsg.git
- **Version**: Latest from main branch
- **Build Method**: CMake

#### Cimplog
- **Source**: https://github.com/xmidt-org/cimplog.git
- **Version**: Commit 8a5fb3c2f182241d17f5342bea5b7688c28cd1fd
- **Build Method**: CMake

#### WRP-C
- **Source**: https://github.com/xmidt-org/wrp-c.git
- **Version**: Commit 9587e8db33dbbfcd9b78ef66cc2eaf16dfb9afcf
- **Build Method**: CMake
- **Modifications**: MessagePack revision updated from 7a98138f27f27290e680bf8fbf1f8d1b089bf138 to 445880108a1d171f755ff6ac77e03fbebbb23729

#### Libparodus
- **Source**: https://github.com/xmidt-org/libparodus.git
- **Version**: Latest from main branch
- **Build Method**: CMake
- **Modifications**: MessagePack revision updated from 7a98138f27f27290e680bf8fbf1f8d1b089bf138 to 445880108a1d171f755ff6ac77e03fbebbb23729

### Container-Specific Components

#### RDK Logger
- **Source**: Copied from local directory
- **Build Method**: autotools (autoreconf, configure, make, make install)

#### Webconfig Framework
- **Source**: Copied from local directory
- **Build Method**: autotools with custom CFLAGS and LDFLAGS
- **Install Location**: /usr/local

#### libSyscallWrapper
- **Source**: Copied from local directory
- **Build Method**: autotools
- **Install Location**: /usr/local

#### Common Utilities
- **Source**: Copied from local directory
- **Build Method**: autotools with custom CFLAGS including -DRDK_LOGGER
- **Install Location**: /usr/local

#### Mock RFC Providers
- **Source**: Copied from local directory (mock-rfc-providers)
- **Build Method**: autotools with custom CFLAGS and LDFLAGS for RBUS integration
- **Install Location**: /usr/local

#### TR69 Host Interface
- **Source**: Copied from local directory
- **Build Method**: Custom build script (cov_build.sh) with multi-architecture support
- **Features**: Includes Apple Silicon (aarch64) and x86_64 compatibility

## Architecture Support

The container supports multi-architecture builds:
- **x86_64**: Intel/AMD 64-bit processors
- **aarch64**: ARM 64-bit processors (Apple Silicon, ARM servers)

Architecture-specific library paths are automatically detected and configured at runtime.

## Container Configuration

### Environment Variables
- **RBUS_ROOT**: /
- **RBUS_INSTALL_DIR**: /usr/local
- **PATH**: Includes /usr/local/bin
- **LD_LIBRARY_PATH**: Multi-architecture library paths including:
  - /usr/local/lib
  - /usr/lib/x86_64-linux-gnu (x86_64)
  - /lib/aarch64-linux-gnu (aarch64)
  - Architecture-specific paths detected at runtime

### Device Properties
The container emulates RDK device properties in `/etc/device.properties`:
- **BUILD_TYPE**: PROD
- **DEVICE_NAME**: DEVELOPER_CONTAINER
- **MODEL_NUM**: L2CNTR
- **DEVICE_MAC**: AA:BB:CC:DD:EE:FF
- **RDK_PROFILE**: STB
- **DEVICE_TYPE**: mediaclient
- **ETHERNET_INTERFACE**: eth0
- **WIFI_INTERFACE**: wlan0
- **MOCA_INTERFACE**: eth0

### Exposed Ports
- **9090**: Main service port

### Entry Point
- **Command**: `/usr/local/bin/entrypoint.sh`
- **Features**: 
  - Certificate setup via `/usr/local/bin/certs.sh`
  - Multi-architecture library path configuration
  - RFC provider and tr69hostif service startup
  - Continuous heartbeat monitoring

## Volume Mounts
- **Shared Volume**: `/mnt/L2_CONTAINER_SHARED_VOLUME` for test data and certificate exchange

## Build Information
- **Image Name**: T2_Container_${REVISION}
- **Version File**: /version.txt
- **Timezone**: US/Mountain (configurable via /opt/persistent/timeZoneDST)

## Notes
- All packages use the latest available versions from their respective repositories unless specifically pinned
- The container is optimized for L2 testing and development environments
- Certificate management is handled at runtime through shared volumes
- The build process includes cleanup steps to minimize final image size
