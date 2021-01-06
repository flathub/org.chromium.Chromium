#!/bin/bash

mkdir -p /app/chromium

pushd out/Release
# Keep file names in sync with build_devel_flatpak.py
for path in chrome icudtl.dat *.so *.pak *.bin *.png locales MEIPreload; do
    cp -rv $path /app/chromium
done
popd

# Place the proprietary libffmpeg in the extension path, then overwrite it with the free one.
install -Dm 755 out/ReleaseFree/libffmpeg.so /app/chromium/libffmpeg.so
install -Dm 755 out/Release/libffmpeg.so /app/chromium/nonfree-codecs/lib/libffmpeg.so
for size in 24 48 64 128 256; do
    install -Dvm 644 chrome/app/theme/chromium/product_logo_$size.png /app/share/icons/hicolor/${size}x${size}/apps/org.chromium.Chromium.png;
done
install -Dvm 644 portal_error.txt -t /app/share/flatpak-chromium
install -Dvm 644 org.chromium.Chromium.desktop -t /app/share/applications
install -Dvm 644 org.chromium.Chromium.metainfo.xml -t /app/share/metainfo
install -Dvm 755 chromium.sh /app/bin/chromium
