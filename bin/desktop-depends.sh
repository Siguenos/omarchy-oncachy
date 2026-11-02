#!/usr/bin/env bash
# Print the omarchy-cachyos-desktop dependencies for an upstream package list.
# Usage: bin/desktop-depends.sh install/omarchy-base.packages
set -eEuo pipefail
(( $# == 1 )) || { echo "Usage: $0 OMARCHY_BASE_PACKAGES" >&2; exit 2; }
{
  # CachyOS keeps its own boot splash and kernel module handling; tealdeer
  # replaces tldr. The extras complete the audio/Qt stack Omarchy's ISO brings.
  sed 's/#.*//' "$1" | awk 'NF && $1 !~ /^(tldr|plymouth|kernel-modules-hook)$/ {print $1}'
  printf '%s\n' tealdeer pipewire pipewire-alsa pipewire-pulse qt6-wayland
} | sort -u
