#!/usr/bin/env bash
# TrayForge Arch Linux install script (pacman-managed)
# Usage:  bash install.sh          # build + install
#         bash install.sh -r       # uninstall
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

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
bash "$ROOT/build.sh"

echo "=== Building & installing Arch package ==="
cd "$ROOT/packaging/arch"
mkdir -p "$ROOT/dist"
BUILDDIR=/tmp/${PKGNAME}-build PKGDEST="$ROOT/dist" makepkg -si --noconfirm

echo "=== Done: $PKGNAME is now managed by pacman ==="
echo "  Uninstall: bash install.sh -r"
echo "  Or:        sudo pacman -R $PKGNAME"
