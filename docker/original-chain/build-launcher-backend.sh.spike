#!/bin/bash
# build-launcher-backend.sh — recompila moonrider-launch + libWPEBackend-mali-fbdev
# dentro do container wpebuild:cpp (WPE root em /tmp/wpe-spike/engine/root).
# Reproduz o comando de build documentado na skill electron-construct-arm64-port.
set -e
R=/work/engine/root
CC=aarch64-linux-gnu-gcc
CXX=aarch64-linux-gnu-g++
cd /work

GLIB_CFLAGS="-I/usr/include/glib-2.0 -I/usr/lib/aarch64-linux-gnu/glib-2.0/include"
GLIB_LIBS="-lglib-2.0 -lgobject-2.0 -lgio-2.0"

echo "=== [1/3] mixer de audio: muos_audio_mixer.o (miniaudio + libvorbis) ==="
# miniaudio abre libasound via dlopen em runtime (-ldl). libvorbisfile/vorbis/ogg linkadas.
# headers vorbis copiados do host em audio-mixer/vorbis-headers; libs do device em audio-mixer/devlibs.
$CC -O2 -c \
  -I audio-mixer -I audio-mixer/vorbis-headers \
  audio-mixer/muos_audio_mixer.c \
  -o audio-mixer/muos_audio_mixer.o
echo "mixer.o OK: $(file audio-mixer/muos_audio_mixer.o | cut -d, -f1-2)"

echo "=== [2/3] launcher: moonrider-launch (com evdev_gamepad + mixer) ==="
$CC -O2 \
  -I"$R/usr/include/wpe-webkit-1.1" \
  -I"$R/usr/include/wpe-1.0" \
  -I"$R/usr/include/libsoup-3.0" \
  -I audio-mixer \
  $GLIB_CFLAGS \
  backend/moonrider-launch.c backend/evdev_gamepad.c audio-mixer/muos_audio_mixer.o \
  -o backend/moonrider-launch \
  -L"$R/usr/lib/aarch64-linux-gnu" \
  -L/work/audio-mixer/devlibs \
  -Wl,--allow-shlib-undefined \
  -Wl,-rpath-link,"$R/usr/lib/aarch64-linux-gnu" \
  -Wl,-rpath-link,/work/audio-mixer/devlibs \
  -Wl,-rpath,'$ORIGIN/lib' \
  -lWPEWebKit-1.1 -lwpe-1.0 -lsoup-3.0 $GLIB_LIBS \
  -lvorbisfile -lvorbis -logg -lpthread -ldl -lm
echo "launcher OK: $(file backend/moonrider-launch | cut -d, -f1-2)"

echo "=== [3/3] backend: libWPEBackend-mali-fbdev.so ===" 
EGL_INC="-I/work/sysroot/include"
$CC -O2 -fPIC -shared \
  -I"$R/usr/include/wpe-1.0" $EGL_INC \
  $GLIB_CFLAGS \
  backend/backend-mali-fbdev.c backend/loader-impl.c \
  -o backend/libWPEBackend-mali-fbdev.so \
  -L"$R/usr/lib/aarch64-linux-gnu" \
  -Wl,--allow-shlib-undefined \
  -Wl,-rpath-link,"$R/usr/lib/aarch64-linux-gnu" \
  -lwpe-1.0 $GLIB_LIBS || {
    echo "!! falhou com loader-impl.c — tentando so backend-mali-fbdev.c"
    $CC -O2 -fPIC -shared \
      -I"$R/usr/include/wpe-1.0" $EGL_INC $GLIB_CFLAGS \
      backend/backend-mali-fbdev.c \
      -o backend/libWPEBackend-mali-fbdev.so \
      -L"$R/usr/lib/aarch64-linux-gnu" \
      -Wl,--allow-shlib-undefined \
      -Wl,-rpath-link,"$R/usr/lib/aarch64-linux-gnu" \
      -lwpe-1.0 $GLIB_LIBS
  }
echo "backend OK: $(file backend/libWPEBackend-mali-fbdev.so | cut -d, -f1-2)"
echo "=== BUILD COMPLETO ==="
ls -la backend/moonrider-launch backend/libWPEBackend-mali-fbdev.so
