#!/bin/bash

# DO NOT REUSE THE BELOW API KEY; it is for Flathub only.
# http://lists.debian.org/debian-legal/2013/11/msg00006.html
tools/gn/bootstrap/bootstrap.py -v --no-clean --gn-gen-args='
    use_sysroot=false
    custom_toolchain="//build/toolchain/linux/unbundle:default"
    host_toolchain="//build/toolchain/linux/unbundle:default"
    use_udev=false
    use_lld=true
    enable_nacl=false
    blink_symbol_level=0
    use_gnome_keyring=false
    use_pulseaudio=true
    clang_use_chrome_plugins=false
    is_official_build=true
    google_api_key="AIzaSyAL6fqCZVFhA7K_qBvz9GO5Z-V1JBcPO0A"
    treat_warnings_as_errors=false
    proprietary_codecs=true
    ffmpeg_branding="Chrome"
    is_component_ffmpeg=true
    use_vaapi=true
    enable_widevine=true
    chrome_pgo_phase=0
    rtc_use_pipewire=true
    rtc_link_pipewire=true
    rtc_pipewire_version="0.3"
    enable_hangout_services_extension=true
'
mkdir -p out/ReleaseFree
cp out/Release{,Free}/args.gn
echo -e 'proprietary_codecs = false\nffmpeg_branding = "Chromium"' >> out/ReleaseFree/args.gn
out/Release/gn gen out/ReleaseFree
