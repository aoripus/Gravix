#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/.build"
PREFIX="$ROOT/Vendor"
JOBS=8
mkdir -p "$BUILD/logs" "$PREFIX"
export MACOSX_DEPLOYMENT_TARGET=14.0
export PATH="$BUILD/toolpy/cmake/data/bin:$PREFIX/bin:$PATH"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
fetch() {
  local archive="$1" url="$2" directory="$3"
  if [ ! -d "$BUILD/$directory" ]; then
    curl -fL --retry 3 --connect-timeout 20 "$url" -o "$BUILD/$archive"
    tar -xf "$BUILD/$archive" -C "$BUILD"
  fi
}
if ! command -v cmake >/dev/null; then
  /usr/bin/python3 -m pip install --target "$BUILD/toolpy" cmake==3.31.10 --disable-pip-version-check
fi
fetch pkg-config.tar.gz https://pkg-config.freedesktop.org/releases/pkg-config-0.29.2.tar.gz pkg-config-0.29.2
fetch openssl.tar.gz https://codeload.github.com/openssl/openssl/tar.gz/refs/tags/openssl-3.5.9 openssl-openssl-3.5.9
fetch ffmpeg.tar.xz https://ffmpeg.org/releases/ffmpeg-8.1.3.tar.xz ffmpeg-8.1.3
fetch freerdp.tar.gz https://codeload.github.com/FreeRDP/FreeRDP/tar.gz/refs/tags/3.32.1 FreeRDP-3.32.1
if [ ! -x "$PREFIX/bin/pkg-config" ]; then
  (cd "$BUILD/pkg-config-0.29.2" && CFLAGS="-Wno-int-conversion" ./configure --prefix="$PREFIX" --with-internal-glib --disable-host-tool && make -j"$JOBS" && make install) > "$BUILD/logs/pkg-config.log" 2>&1
fi
if [ ! -f "$PREFIX/lib/libssl.3.dylib" ]; then
  echo 'Building OpenSSL…'
  (cd "$BUILD/openssl-openssl-3.5.9" && ./Configure darwin64-arm64-cc --prefix="$PREFIX" --libdir=lib shared no-tests no-docs && make -j"$JOBS" && make install_sw) > "$BUILD/logs/openssl.log" 2>&1
fi
if [ ! -f "$PREFIX/lib/libavcodec.dylib" ]; then
  echo 'Building FFmpeg with VideoToolbox…'
  (cd "$BUILD/ffmpeg-8.1.3" && ./configure --prefix="$PREFIX" --arch=arm64 --target-os=darwin --cc=clang --enable-shared --disable-static --disable-programs --disable-doc --disable-autodetect --disable-everything --enable-avcodec --enable-avformat --enable-avfilter --enable-swresample --enable-swscale --enable-decoder=h264 --enable-parser=h264 --enable-hwaccel=h264_videotoolbox --enable-videotoolbox --enable-audiotoolbox --enable-decoder=aac,pcm_s16le,pcm_s16be,adpcm_ms --enable-filter=aresample --enable-protocol=file --extra-cflags='-mmacosx-version-min=14.0' --extra-ldflags='-mmacosx-version-min=14.0' && make -j"$JOBS" && make install) > "$BUILD/logs/ffmpeg.log" 2>&1
fi
echo 'Building FreeRDP…'
cmake -S "$BUILD/FreeRDP-3.32.1" -B "$BUILD/freerdp-build" \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_PREFIX_PATH="$PREFIX" -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
  -DCMAKE_OSX_ARCHITECTURES=arm64 -DBUILD_SHARED_LIBS=ON \
  -DWITH_CLIENT=OFF -DWITH_CLIENT_COMMON=ON -DWITH_CLIENT_CHANNELS=ON \
  -DWITH_SERVER=OFF -DWITH_SERVER_CHANNELS=OFF -DWITH_SAMPLE=OFF \
  -DWITH_CLIENT_SDL=OFF -DWITH_X11=OFF -DWITH_WAYLAND=OFF \
  -DWITH_FFMPEG=ON -DWITH_VIDEO_FFMPEG=ON -DWITH_FFMPEG_HWACCEL=ON \
  -DWITH_DSP_FFMPEG=OFF -DWITH_SWSCALE=ON -DWITH_OPENH264=OFF \
  -DWITH_CUPS=OFF -DWITH_PCSC=OFF -DWITH_PKCS11=OFF \
  -DWITH_KRB5=OFF -DWITH_KRB5_NO_NTLM_FALLBACK=OFF \
  -DWITH_FUSE=OFF -DWITH_MANPAGES=OFF -DWITH_FFMPEG_VAAPI=OFF \
  -DWITH_JPEG=OFF -DWITH_SWSCALE_LOADING=OFF -DWITH_WEBVIEW=OFF \
  -DWITH_AAD=OFF -DWITH_WINPR_JSON=OFF -DWITH_SMARTCARD_EMULATE=OFF \
  -DWITH_WINPR_TOOLS=OFF -DWITH_LIBUSB=OFF -DCHANNEL_URBDRC=OFF -DCHANNEL_URBDRC_CLIENT=OFF \
  -DBUILD_TESTING=OFF -DWITH_DSP_EXPERIMENTAL=OFF \
  -DOPENSSL_ROOT_DIR="$PREFIX" > "$BUILD/logs/freerdp-configure.log" 2>&1
cmake --build "$BUILD/freerdp-build" -j "$JOBS" > "$BUILD/logs/freerdp-build.log" 2>&1
cmake --install "$BUILD/freerdp-build" > "$BUILD/logs/freerdp-install.log" 2>&1
echo 'Dependencies ready.'
