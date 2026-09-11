#!/bin/sh
set -eu

root_dir=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$root_dir"

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    platform=windows
    ;;
  Darwin)
    platform=macos
    ;;
  *)
    platform=linux
    ;;
esac

common_configure_args="--disable-shared --enable-static --with-fft=smallft"
if [ "$platform" = windows ]; then
  speex_configure_args="$common_configure_args --disable-binaries"
  speexdsp_configure_args="$common_configure_args --disable-examples"
  cflags="${CFLAGS:-} -O2"
else
  speex_configure_args="$common_configure_args --disable-binaries"
  speexdsp_configure_args="$common_configure_args --disable-examples"
  cflags="${CFLAGS:-} -O2 -fPIC"
fi

if [ ! -x speex/configure ]; then
  (cd speex && ./autogen.sh)
fi
if [ ! -x speexdsp/configure ]; then
  mkdir -p speexdsp/m4
  cp speex/m4/pkg.m4 speexdsp/m4/pkg.m4
  # Autoconf 2.73 treats the same-line closing token in this legacy list as
  # an additional AC_CONFIG_FILES entry.
  awk '{
    if ($0 ~ /ti\/speex_C64_test\/Makefile \]\)/) {
      sub(/ \]\)$/, "")
      print
      print "])"
    } else {
      print
    }
  }' speexdsp/configure.ac > speexdsp/configure.ac.tmp
  mv speexdsp/configure.ac.tmp speexdsp/configure.ac
  (cd speexdsp && ./autogen.sh)
fi

(cd speex && CFLAGS="$cflags" ./configure $speex_configure_args)
(cd speexdsp && CFLAGS="$cflags" ./configure $speexdsp_configure_args)
make -C speex/libspeex
make -C speexdsp/libspeexdsp

rm -rf dist
mkdir -p dist/include/speex dist/include/speexdsp
cp speex/include/speex/*.h dist/include/speex/
cp speexdsp/include/speex/*.h dist/include/speexdsp/

speex_archive="$root_dir/speex/libspeex/.libs/libspeex.a"
speexdsp_archive="$root_dir/speexdsp/libspeexdsp/.libs/libspeexdsp.a"
cc="${CC:-cc}"

case "$platform" in
  windows)
    "$cc" -shared -static-libgcc -o dist/speex-combined.dll \
      -Wl,--out-implib,dist/libspeex-combined.dll.a \
      -Wl,--export-all-symbols -Wl,--whole-archive \
      "$speex_archive" "$speexdsp_archive" \
      -Wl,--no-whole-archive -lm
    nm -g dist/speex-combined.dll | grep -q 'speex_encoder_init'
    nm -g dist/speex-combined.dll | grep -q 'speex_resampler_init'
    if objdump -p dist/speex-combined.dll |
      grep -Eiq 'DLL Name: (libgcc_s|libwinpthread)' ; then
      echo "unexpected non-system MinGW runtime dependency" >&2
      exit 1
    fi
    ;;
  macos)
    "$cc" -dynamiclib -o dist/libspeex-combined.dylib \
      -Wl,-force_load,"$speex_archive" \
      -Wl,-force_load,"$speexdsp_archive" -lm
    nm -gU dist/libspeex-combined.dylib | grep -q 'speex_encoder_init'
    nm -gU dist/libspeex-combined.dylib | grep -q 'speex_resampler_init'
    ;;
  linux)
    "$cc" -shared -o dist/libspeex-combined.so \
      -Wl,--whole-archive "$speex_archive" "$speexdsp_archive" \
      -Wl,--no-whole-archive -lm
    nm -D --defined-only dist/libspeex-combined.so | grep -q 'speex_encoder_init'
    nm -D --defined-only dist/libspeex-combined.so | grep -q 'speex_resampler_init'
    ;;
esac
