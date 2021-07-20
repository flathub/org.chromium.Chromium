#!/bin/bash -e

ln -s /usr/lib/sdk/node12 third_party/node/linux/node-linux-x64
ln -s /usr/lib/sdk/openjdk11 third_party/jdk/current

#. /usr/lib/sdk/node12/enable.sh
#. /usr/lib/sdk/openjdk11/enable.sh
ninja -C out/ReleaseFree -j$FLATPAK_BUILDER_N_JOBS libffmpeg.so
ninja -C out/Release -j$FLATPAK_BUILDER_N_JOBS chrome
