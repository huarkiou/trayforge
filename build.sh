#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

echo "=== Building TrayForge for Linux ==="

# Clean previous build (handle fuse hidden files on cross-fs mounts)
find dist -name '.fuse*' -delete 2>/dev/null || true
rm -rf build dist 2>/dev/null || true
mkdir -p dist

# Build with PyInstaller
PROJECT_DIR=$(pwd)
uv run pyinstaller \
  --onefile \
  --clean \
  --name TrayForge \
  --hidden-import pystray \
  --hidden-import PIL \
  --hidden-import PIL.Image \
  --hidden-import PIL.ImageDraw \
  --hidden-import PIL.ImageTk \
  --hidden-import PIL._tkinter_finder \
  --hidden-import startup \
  --hidden-import fcntl \
  --add-data "${PROJECT_DIR}/assets/icon.ico:assets" \
  --specpath build \
  src/main.pyw

echo ""
if [ -f "dist/TrayForge" ]; then
    echo "=== Build successful: dist/TrayForge ==="
    ls -lh dist/TrayForge
else
    echo "=== Build FAILED ==="
    exit 1
fi
