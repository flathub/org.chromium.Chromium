UTILS_DIR=$(dirname "$0" | xargs realpath)

docker run --security-opt label=disable --rm -it \
    -v "$UTILS_DIR/ffmpeg_bashrc.sh:/ffmpeg_bashrc.sh" \
    -v $PWD:/chromium -w /chromium/third_party/ffmpeg \
    chromium-ffmpeg
