export PATH=/chromium/third_party/llvm-build/Release+Asserts/bin:$PATH

DEBIAN_ARCH_amd64=x86_64
DEBIAN_ARCH_arm64=aarch64

setup_tree() {
  for sysroot_arch in amd64 arm64; do
    case "$sysroot_arch" in
    amd64) deb_arch=x86_64 ;;
    arm64) deb_arch=aarch64 ;;
    esac

    sysroot=/chromium/build/linux/debian_sid_$sysroot_arch-sysroot
    libdir=/usr/lib/$deb_arch-linux-gnu

    ln -sf /usr/include/{fdk-aac,wels} $sysroot/usr/include
    ln -sf $libdir/lib{fdk-aac,openh264}.* $sysroot/$libdir
  done
}

build_ffmpeg() {
  chromium/scripts/build_ffmpeg.py linux arm64
  chromium/scripts/build_ffmpeg.py linux x64
}

update_configs() {
  chromium/scripts/copy_config.sh
  chromium/scripts/generate_gn.py
}
