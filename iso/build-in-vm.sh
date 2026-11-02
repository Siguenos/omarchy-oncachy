#!/usr/bin/env bash
# Build the installer ISO on another CachyOS or Arch machine (e.g. a VM)
# reachable over SSH with sudo, for hosts where root is not available.
# Downloads the latest CachyOS desktop ISO unless one is given. With --extras,
# the AUR packages of extras/extras.packages are built there first; the ones
# that fail are skipped and listed.
# Usage: iso/build-in-vm.sh [--extras] [--iso CACHYOS_ISO] [--ssh-config FILE] HOST OUTPUT_DIR
set -eEuo pipefail
ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
ISO_BASE=https://cdn77.cachyos.org/ISO/desktop

usage() { sed -n '2,7s/^# \{0,1\}//p' "$0"; }
extras=0 iso='' ssh_args=()
while (( $# )); do
  case $1 in
    --extras) extras=1 ;;
    --iso) [[ -n ${2:-} ]] || { usage >&2; exit 2; }; iso=$2; shift ;;
    --ssh-config) [[ -n ${2:-} ]] || { usage >&2; exit 2; }; ssh_args=(-F "$2"); shift ;;
    -h|--help) usage; exit 0 ;;
    -*) usage >&2; exit 2 ;;
    *) break ;;
  esac
  shift
done
(( $# == 2 )) || { usage >&2; exit 2; }
host=$1 out_dir=$2
remote() { ssh "${ssh_args[@]}" "$host" bash -s -- "$@"; }

if [[ -z $iso ]]; then
  release=$(curl -fsSL https://cachyos.org/download/ |
    grep -oE 'desktop/[0-9]{6}/cachyos-desktop-linux-[0-9]{6}\.iso' | sort -u | tail -1)
  [[ -n $release ]] || { echo "Could not find the latest CachyOS ISO." >&2; exit 1; }
  iso="$out_dir/${release##*/}"
  if [[ ! -f $iso ]]; then
    curl -fL -o "$iso.part" "$ISO_BASE/${release#desktop/}" && mv "$iso.part" "$iso"
  fi
  curl -fsSL -o "$iso.sha256" "$ISO_BASE/${release#desktop/}.sha256"
  (cd "$out_dir" && sha256sum -c "${iso##*/}.sha256")
fi

name="omarchy-oncachy-$(date +%Y.%m.%d)-x86_64.iso"
remote <<'EOF'
sudo pacman -S --needed --noconfirm squashfs-tools xorriso gnupg >/dev/null
rm -rf ~/omarchy-oncachy-iso && mkdir -p ~/omarchy-oncachy-iso/src
EOF
# The working tree, including uncommitted changes, without build output.
git -C "$ROOT_DIR" ls-files -z --cached --others --exclude-standard |
  tar -C "$ROOT_DIR" --null -T - -cf - | ssh "${ssh_args[@]}" "$host" tar -C omarchy-oncachy-iso/src -xf -
scp "${ssh_args[@]}" -q "$iso" "$host:omarchy-oncachy-iso/cachyos.iso"
remote "$name" "$extras" <<'EOF'
set -e
name=$1 extras=$2
cd ~/omarchy-oncachy-iso
args=()
if (( extras )); then
  sudo pacman -S --needed --noconfirm base-devel git >/dev/null
  bash src/pkgbuilds/omarchy-oncachy/omarchy-oncachy-extras --build aur src/extras/extras.packages 2>&1 |
    tee build-aur.log | grep -E '^(== Building|Skipped|Extras done)'
  args=(--extras aur)
fi
sudo src/iso/remaster.sh "${args[@]}" cachyos.iso "$name"
EOF
scp "${ssh_args[@]}" -q "$host:omarchy-oncachy-iso/$name" "$host:omarchy-oncachy-iso/$name.sha256" "$out_dir/"
remote <<'EOF'
rm -rf ~/omarchy-oncachy-iso
EOF
(cd "$out_dir" && sha256sum -c "$name.sha256")
echo "ISO: $out_dir/$name"
