#!/usr/bin/env bash
set -euo pipefail

# Builds the patched Hyprland package locally (no network needed except makepkg fetch).
# Usage: ./build.sh [makepkg-extra-args...]

cd "$(dirname "$0")"

# Add any missing makedepends (needs sudo for system install)
# sudo pacman -S --needed base-devel cmake ninja meson glaze hyprland-protocols

makepkg -f "$@"