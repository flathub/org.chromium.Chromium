UTILS_DIR=$(dirname "$0")
docker build -t chromium-ffmpeg -f "$UTILS_DIR"/Dockerfile.ffmpeg "$UTILS_DIR"
