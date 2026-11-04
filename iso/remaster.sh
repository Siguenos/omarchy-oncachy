#!/usr/bin/env bash
# Build an installer ISO from an official CachyOS desktop ISO: unpack its live
# root, add Omarchy to Calamares (iso/customize.sh), repack it and write a new
# ISO that keeps the original boot setup.
# Runs as root, with squashfs-tools, xorriso and gnupg.
# Usage: iso/remaster.sh [--extras AUR_DIR] CACHYOS_ISO OUTPUT_ISO
#   --extras AUR_DIR   also install extras/extras.packages with Omarchy, the AUR
#                      ones from AUR_DIR (omcachy-extras --build AUR_DIR)
set -eEuo pipefail
ISO_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SFS=/arch/x86_64/airootfs.sfs

usage() { sed -n '2,8s/^# \{0,1\}//p' "$0"; }
customize_args=()
if [[ ${1:-} == --extras ]]; then
  [[ -n ${2:-} ]] || { usage >&2; exit 2; }
  customize_args=(--extras "$(realpath -- "$2")")
  shift 2
fi
(( $# == 2 )) || { usage >&2; exit 2; }
input=$(realpath -- "$1") output=$(realpath -- "$2")
(( EUID == 0 )) || { echo "Run as root (unsquashfs must keep file owners)." >&2; exit 1; }
for tool in unsquashfs mksquashfs xorriso gpg; do
  command -v "$tool" >/dev/null || { echo "Missing $tool (squashfs-tools, xorriso, gnupg)." >&2; exit 1; }
done
omarchy_key=$(sed -n 's/^OMARCHY_KEY=//p' "$ISO_DIR/../install.sh")

work=$(mktemp -d -p /var/tmp omcachy-iso.XXXXXX)
trap 'rm -rf "$work"' EXIT
echo "Unpacking $SFS"
xorriso -osirrox on -indev "$input" -extract "$SFS" "$work/airootfs.sfs" 2>/dev/null
info=$(unsquashfs -s "$work/airootfs.sfs")
# Repack with the same compressor, block size and level.
squash_args=(-comp "$(awk '/^Compression /{print $2}' <<< "$info")"
  -b "$(awk '/^Block size /{print $3}' <<< "$info")")
level=$(awk '/compression-level/{print $2}' <<< "$info")
[[ -z $level ]] || squash_args+=(-Xcompression-level "$level")
unsquashfs -q -d "$work/root" "$work/airootfs.sfs"
rm "$work/airootfs.sfs"

# Omarchy's signing key, for the installed system's pacman keyring.
export GNUPGHOME=$work/gnupg
install -d -m 700 "$GNUPGHOME"
gpg --batch --quiet --keyserver hkps://keys.openpgp.org --recv-keys "$omarchy_key"
gpg --batch --armor --export "$omarchy_key" > "$work/omarchy.asc"

"$ISO_DIR/customize.sh" "${customize_args[@]}" "$work/root" "$work/omarchy.asc"

echo "Repacking with ${squash_args[*]}"
mksquashfs "$work/root" "$work/airootfs.sfs" "${squash_args[@]}" -noappend -quiet
(cd "$work" && sha512sum airootfs.sfs > airootfs.sha512)
# The boot loaders find the live medium by its volume label.
volid=$(xorriso -indev "$input" -pvd_info 2>/dev/null | sed -n 's/^Volume Id *: *//p')
rm -f "$output"
xorriso -indev "$input" -outdev "$output" -volid "$volid" -boot_image any replay \
  -map "$work/airootfs.sfs" "$SFS" -map "$work/airootfs.sha512" "${SFS%.sfs}.sha512"
(cd "$(dirname -- "$output")" && sha256sum "${output##*/}" > "${output##*/}.sha256")
echo "Built $output"
