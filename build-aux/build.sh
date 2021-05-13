#!/bin/bash

. /usr/lib/sdk/node12/enable.sh
. /usr/lib/sdk/openjdk11/enable.sh
. /usr/lib/sdk/llvm12/enable.sh
ninja -C out/ReleaseFree -j$FLATPAK_BUILDER_N_JOBS libffmpeg.so
ninja -C out/Release -j$FLATPAK_BUILDER_N_JOBS chrome
