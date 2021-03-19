#!/bin/bash

ninja -C out/ReleaseFree -j$FLATPAK_BUILDER_N_JOBS libffmpeg.so

. /usr/lib/sdk/node12/enable.sh
. /usr/lib/sdk/openjdk11/enable.sh
. /usr/lib/sdk/llvm11/enable.sh
ninja -C out/Release -j$FLATPAK_BUILDER_N_JOBS chrome
