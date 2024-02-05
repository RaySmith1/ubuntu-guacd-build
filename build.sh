#!/bin/bash
set -a

VER='1.5.4'
BASE_DIR='/opt/guacamole'
BUILD_HOME='/build'

#
# Prepare for Build
#
[ -d "${BASE_DIR}" ] || mkdir -p "${BASE_DIR}"
[ -d "${BUILD_HOME}" ] || mkdir -p "${BUILD_HOME}"

cd "${BUILD_HOME}" && {
    wget https://github.com/apache/guacamole-server/archive/refs/tags/${VER}.tar.gz
    tar -zxvf ${VER}.tar.gz
}

BUILD_DIR="${BUILD_HOME}/guacamole-server-${VER}"
[ -d "${BUILD_DIR}" ] || { echo "Unable to download guacamole-server."; exit 1; }

#
# Stage packages
#
apt-get -y -qq update 
apt-get -y -qq  \
  build-essential \
  autotools-dev \
  autoconf \
  make \
  cmake \
  gcc \
  fonts-dejavu-core \
  libcairo2-dev \
  libjpeg-dev \
  libpng-dev \
  libtool-bin \
  util-linux \
  libpango1.0-dev \
  libssl-dev 

#
# Follow guacamole-docker build pattern for native use
# https://github.com/apache/guacamole-server/blob/master/Dockerfile
# https://github.com/apache/guacamole-server/blob/master/src/guacd-docker/bin/build-all.sh
#
PREFIX_DIR="/opt/guacamole"

CFLAGS="-I${PREFIX_DIR}/include"
LDFLAGS="-L${PREFIX_DIR}/lib"
PKG_CONFIG_PATH="${PREFIX_DIR}/lib/pkgconfig"

WITH_FREERDP='2(\.\d+)+'
WITH_LIBSSH2='libssh2-\d+(\.\d+)+'
WITH_LIBTELNET='\d+(\.\d+)+'
WITH_LIBVNCCLIENT='LibVNCServer-\d+(\.\d+)+'
WITH_LIBWEBSOCKETS='v\d+(\.\d+)+'
WITH_OPENSSL='OpenSSL_1_1_1w'

FREERDP_OPTS="\
  -DBUILTIN_CHANNELS=OFF \
  -DCHANNEL_URBDRC=OFF \
  -DWITH_ALSA=OFF \
  -DWITH_CAIRO=ON \
  -DWITH_CHANNELS=ON \
  -DWITH_CLIENT=ON \
  -DWITH_CUPS=OFF \
  -DWITH_DIRECTFB=OFF \
  -DWITH_FFMPEG=OFF \
  -DWITH_GSM=OFF \
  -DWITH_GSSAPI=OFF \
  -DWITH_IPP=OFF \
  -DWITH_JPEG=ON \
  -DWITH_LIBSYSTEMD=OFF \
  -DWITH_MANPAGES=OFF \
  -DWITH_OPENH264=OFF \
  -DWITH_OPENSSL=ON \
  -DWITH_OSS=OFF \
  -DWITH_PCSC=OFF \
  -DWITH_PULSE=OFF \
  -DWITH_SERVER=OFF \
  -DWITH_SERVER_INTERFACE=OFF \
  -DWITH_SHADOW_MAC=OFF \
  -DWITH_SHADOW_X11=OFF \
  -DWITH_SSE2=ON \
  -DWITH_WAYLAND=OFF \
  -DWITH_X11=OFF \
  -DWITH_X264=OFF \
  -DWITH_XCURSOR=ON \
  -DWITH_XEXT=ON \
  -DWITH_XI=OFF \
  -DWITH_XINERAMA=OFF \
  -DWITH_XKBFILE=ON \
  -DWITH_XRENDER=OFF \
  -DWITH_XTEST=OFF \
  -DWITH_XV=OFF \
  -DWITH_ZLIB=ON"

GUACAMOLE_SERVER_OPTS="\
  --disable-guaclog"

LIBSSH2_OPTS="\
  -DBUILD_EXAMPLES=OFF \
  -DBUILD_SHARED_LIBS=ON"

LIBTELNET_OPTS="\
  --disable-static \
  --disable-util"

LIBVNCCLIENT_OPTS=""

LIBWEBSOCKETS_OPTS="\
  -DDISABLE_WERROR=ON \
  -DLWS_WITHOUT_SERVER=ON \
  -DLWS_WITHOUT_TESTAPPS=ON \
  -DLWS_WITHOUT_TEST_CLIENT=ON \
  -DLWS_WITHOUT_TEST_PING=ON \
  -DLWS_WITHOUT_TEST_SERVER=ON \
  -DLWS_WITHOUT_TEST_SERVER_EXTPOLL=ON \
  -DLWS_WITH_STATIC=OFF"

OPENSSL_OPTS=" \
 shared \
 zlib"

install_from_git() {

  URL="$1"
  PATTERN="$2"
  shift 2

  # Calculate top-level directory name of resulting repository from the
  # provided URL
  REPO_DIR="$(basename "$URL" .git)"

  # Allow dependencies to be manually omitted with the tag/commit pattern "NO"
  if [ "$PATTERN" = "NO" ]; then
echo "NOT building $REPO_DIR (explicitly skipped)"
return
  fi

  # Clone repository and change to top-level directory of source
  cd /tmp
  git clone "$URL"
  cd $REPO_DIR/

  # Locate tag/commit based on provided pattern
  VERSION="$(git tag -l --sort=-v:refname | grep -Px -m1 "$PATTERN" \
    || echo "$PATTERN")"

  # Switch to desired version of source
  echo "Building $REPO_DIR @ $VERSION ..."
  git -c advice.detachedHead=false checkout "$VERSION"

  # Configure build using CMake or GNU Autotools, whichever happens to be
  # used by the library being built
  if [ -e CMakeLists.txt ]; then
    cmake -DCMAKE_INSTALL_PREFIX:PATH="$PREFIX_DIR" "$@" .
  else
    if [ ! -e configure ]; then
      autoreconf -fi
      if [ ! -e configure ]; then
        # OpenSSL Workaround (contains 'config' vs configure'
        [ -e config ] && cp config configure
      fi
    fi
    ./configure --prefix="$PREFIX_DIR" "$@"
  fi

  # Build and install
  make && make install
}

#
# Build and install core protocol library dependencies
#
# install_from_git "https://github.com/openssl/openssl.git" "$WITH_OPENSSL" $OPENSSL_OPTS
install_from_git "https://github.com/FreeRDP/FreeRDP" "$WITH_FREERDP" $FREERDP_OPTS
install_from_git "https://github.com/libssh2/libssh2" "$WITH_LIBSSH2" $LIBSSH2_OPTS
install_from_git "https://github.com/seanmiddleditch/libtelnet" "$WITH_LIBTELNET" $LIBTELNET_OPTS
install_from_git "https://github.com/LibVNC/libvncserver" "$WITH_LIBVNCCLIENT" $LIBVNCCLIENT_OPTS
install_from_git "https://github.com/warmcat/libwebsockets" "$WITH_LIBWEBSOCKETS" $LIBWEBSOCKETS_OPTS

#
# Build guacamole-server
#
cd "$BUILD_DIR"
autoreconf -fi && ./configure --prefix="$PREFIX_DIR" $GUACAMOLE_SERVER_OPTS
# make && make install
make && make check && make install
