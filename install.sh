#!/usr/bin/env bash
# TrayForge Arch Linux install script (pacman-managed)
# Usage:  bash install.sh          # build + install
#         bash install.sh -r       # uninstall
set -euo pipefail
cd "$(dirname "$0")"

PKGNAME=trayforge

if [[ "${1:-}" == "-r" ]]; then
    echo "=== Uninstalling $PKGNAME ==="
    if pacman -Q "$PKGNAME" &>/dev/null; then
        sudo pacman -R "$PKGNAME"
    else
        echo "$PKGNAME is not installed."
    fi
    exit 0
fi

echo "=== Building binary ==="
bash build.sh

echo "=== Building & installing Arch package ==="
# Build in /tmp to avoid conflicting with project src/, output package to dist/
mkdir -p dist
BUILDDIR=/tmp/${PKGNAME}-build PKGDEST="$PWD/dist" makepkg -si --noconfirm

echo "=== Done: $PKGNAME is now managed by pacman ==="
echo "  Uninstall: bash install.sh -r"
echo "  Or:        sudo pacman -R $PKGNAME"
