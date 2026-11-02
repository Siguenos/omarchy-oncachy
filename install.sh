#!/usr/bin/env bash
# Install the Omarchy desktop on an existing CachyOS system.
# Usage: ./install.sh [--yes] [--packages DIR]
#   --yes            no questions; pacman picks its default providers
#   --packages DIR   install packages built with bin/build.sh (e.g. out/)
#                    instead of the [omarchy-oncachy] repository
set -eEuo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# Omarchy's own repository supplies Hyprland, quickshell and its desktop tools.
OMARCHY_SERVER='https://pkgs.omarchy.org/stable/$arch'
OMARCHY_KEY=40DFB630FF42BCFFB047046CF0134EE680CAC571
# This project's repository, published as the GitHub release "repo", and the
# key that signs it (keys/omarchy-oncachy.asc).
ONCACHY_SERVER='https://github.com/Siguenos/omarchy-oncachy/releases/download/repo'
ONCACHY_KEY=F5CC831F86EEDEF2988D958F9C2D1A8DCDB97DAB

usage() { sed -n '2,6s/^# \{0,1\}//p' "$0"; }
yes=0 packages=''
while (( $# )); do
  case $1 in
    --yes) yes=1 ;;
    --packages) [[ -n ${2:-} ]] || { usage >&2; exit 2; }; packages=$(cd -- "$2" && pwd); shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
  shift
done

(( EUID != 0 )) || { echo "Run as your normal user, without sudo." >&2; exit 1; }
grep -qsx 'ID=["'\'']\{0,1\}cachyos["'\'']\{0,1\}' /etc/os-release || [[ -e /etc/cachyos-release ]] ||
  { echo "This installer targets CachyOS." >&2; exit 1; }
for package in gnome-shell plasma-desktop omarchy omarchy-settings; do
  if pacman -Q "$package" >/dev/null 2>&1; then
    echo "Found $package: use a CachyOS install without another desktop (e.g. Hyprland or no desktop)." >&2
    exit 1
  fi
done
if [[ -n $packages ]]; then
  local_packages=("$packages"/omarchy-oncachy-[0-9]*.pkg.tar.zst "$packages"/omarchy-oncachy-desktop-[0-9]*.pkg.tar.zst)
  for file in "${local_packages[@]}"; do
    [[ -f $file ]] || { echo "Missing package in $packages: run bin/build.sh first." >&2; exit 1; }
  done
fi

state="$HOME/.local/state/omarchy-oncachy"
mkdir -p "$state"
log="$state/install-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$log") 2>&1
trap 'echo "Stopped at line $LINENO. Log: $log" >&2' ERR
echo "Omarchy on CachyOS: installs the desktop packages, then sets up $USER's session."
echo "Keeps the CachyOS kernel, drivers and bootloader. Packages from [omarchy] take precedence."
if (( !yes )); then
  read -r -p "Continue? [y/N] " answer
  [[ $answer == [yYoO]* ]] || exit 0
fi

if sudo snapper -c root get-config >/dev/null 2>&1; then
  sudo snapper -c root create --description "Before omarchy-oncachy"
fi
sudo cp -a /etc/pacman.conf "$state/pacman.conf.$(date +%Y%m%d-%H%M%S)"
sudo pacman-key --recv-keys "$OMARCHY_KEY" --keyserver keys.openpgp.org
sudo pacman-key --lsign-key "$OMARCHY_KEY"
new_config=$(mktemp)
awk -v name=omarchy -v server="$OMARCHY_SERVER" -v siglevel='Required DatabaseOptional' \
  -f "$ROOT/bin/pacman-config.awk" /etc/pacman.conf > "$new_config"
if [[ -z $packages ]]; then
  sudo pacman-key --add "$ROOT/keys/omarchy-oncachy.asc"
  sudo pacman-key --lsign-key "$ONCACHY_KEY"
  awk -v name=omarchy-oncachy -v server="$ONCACHY_SERVER" -v siglevel='Required' \
    -f "$ROOT/bin/pacman-config.awk" "$new_config" > "$new_config.2"
  mv "$new_config.2" "$new_config"
fi
sudo install -m 644 "$new_config" /etc/pacman.conf
rm -f "$new_config"

confirm=()
(( !yes )) || confirm=(--noconfirm)
sudo pacman -Syu "${confirm[@]}"
if [[ -n $packages ]]; then
  # pacman resolves the dependencies from the configured repositories.
  sudo pacman -U --needed "${confirm[@]}" "${local_packages[@]}"
else
  sudo pacman -S --needed "${confirm[@]}" omarchy-oncachy-desktop
fi
omarchy-oncachy-setup
echo "Done. Log: $log"
