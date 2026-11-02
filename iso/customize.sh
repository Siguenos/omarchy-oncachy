#!/usr/bin/env bash
# Add Omarchy to the Calamares installer of an unpacked CachyOS live root:
# desktop choice, netinstall group, repositories and keys for the target, and
# the jobs that set it up. Safe to run again on a customized root.
# Usage: iso/customize.sh [--extras AUR_DIR] AIROOTFS OMARCHY_KEY_FILE
#   --extras AUR_DIR   also install extras/extras.packages with Omarchy, the AUR
#                      ones from AUR_DIR (omarchy-oncachy-extras --build)
#
# CachyOS Hello upgrades the installer package before starting it, which
# restores its configuration: the live root gets a copy of this kit under KIT
# and a pacman hook that runs it again after each upgrade.
set -eEuo pipefail
ISO_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(dirname -- "$ISO_DIR")
KIT=/usr/lib/omarchy-oncachy-iso
HOOK=/etc/pacman.d/hooks/90-omarchy-oncachy-calamares.hook

usage() { sed -n '2,7s/^# \{0,1\}//p' "$0"; }
aur_dir=''
if [[ ${1:-} == --extras ]]; then
  [[ -n ${2:-} ]] || { usage >&2; exit 2; }
  aur_dir=$(realpath -- "$2")
  shift 2
fi
(( $# == 2 )) || { usage >&2; exit 2; }
airootfs=$(realpath -- "$1") omarchy_key=$(realpath -- "$2")
calamares=$airootfs/etc/calamares
modules=$calamares/modules
[[ -f $modules/netinstall.yaml && -f $modules/packagechooser_desktop.conf ]] ||
  { echo "$airootfs does not look like a CachyOS live root." >&2; exit 1; }

# Rewrite FILE with an awk program, keeping its mode.
edit() {
  local file=$1
  shift
  awk "$@" "$file" > "$file.new"
  cat "$file.new" > "$file"
  rm "$file.new"
}

if [[ $(realpath -m -- "$airootfs$KIT") != "$ROOT_DIR" ]]; then
  rm -rf "${airootfs:?}$KIT"
  install -d "$airootfs$KIT"/{iso,bin,keys}
  cp -a "$ISO_DIR/customize.sh" "$ISO_DIR/calamares" "$airootfs$KIT/iso/"
  install -m 644 "$ROOT_DIR/bin/pacman-config.awk" "$airootfs$KIT/bin/"
  install -m 644 "$ROOT_DIR/keys/omarchy-oncachy.asc" "$airootfs$KIT/keys/"
  install -m 644 "$ROOT_DIR/install.sh" "$airootfs$KIT/"
  install -m 644 "$omarchy_key" "$airootfs$KIT/omarchy.asc"
  install -d "$airootfs${HOOK%/*}"
  cat > "$airootfs$HOOK" <<HOOK
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = cachyos-calamares*

[Action]
Description = Adding Omarchy to the installer...
When = PostTransaction
Exec = $KIT/iso/customize.sh / $KIT/omarchy.asc
HOOK
fi

# Files the installer jobs use.
data=$calamares/omarchy-oncachy
install -d "$data/keys"
install -m 644 "$ROOT_DIR/keys/omarchy-oncachy.asc" "$data/keys/omarchy-oncachy.asc"
install -m 644 "$omarchy_key" "$data/keys/omarchy.asc"
install -m 644 "$ROOT_DIR/bin/pacman-config.awk" "$data/pacman-config.awk"
# Same repositories and keys as install.sh.
grep -E '^(OMARCHY|ONCACHY)_(SERVER|KEY)=' "$ROOT_DIR/install.sh" > "$data/repos.sh"
(( $(wc -l < "$data/repos.sh") == 4 )) || { echo "Repository settings not found in install.sh" >&2; exit 1; }
# The extras stay from the first run when the hook runs this again.
if [[ -n $aur_dir ]]; then
  rm -rf "$data/extras"
  install -d "$data/extras/aur"
  install -m 644 "$ROOT_DIR/extras/extras.packages" "$data/extras/extras.packages"
  install -m 755 "$ROOT_DIR/pkgbuilds/omarchy-oncachy/omarchy-oncachy-extras" "$data/extras/omarchy-oncachy-extras"
  find "$aur_dir" -maxdepth 1 -name '*.pkg.tar.*' -exec install -m 644 -t "$data/extras/aur" {} +
fi
for script in omarchy-oncachy-repos omarchy-oncachy-finish; do
  install -m 755 "$ISO_DIR/calamares/$script" "$calamares/scripts/$script"
done
for config in shellprocess_omarchy_repos.conf shellprocess_omarchy_finish.conf; do
  install -m 644 "$ISO_DIR/calamares/$config" "$modules/$config"
done
install -m 644 "$ISO_DIR/calamares/omarchy.webp" "$calamares/images/omarchy.webp"

# Desktop choice (first after "No Desktop") and its netinstall group.
if ! grep -qx '    - id: Omarchy' "$modules/packagechooser_desktop.conf"; then
  edit "$modules/packagechooser_desktop.conf" -v item="$ISO_DIR/calamares/packagechooser-omarchy.yaml" '
    /^    - id: KDE-Desktop$/ && !done { while ((getline line < item) > 0) print line; done=1 }
    { print }
    END { if (!done) exit 1 }'
fi
grep -qx -- '- name: "Omarchy"' "$modules/netinstall.yaml" ||
  cat "$ISO_DIR/calamares/netinstall-omarchy.yaml" >> "$modules/netinstall.yaml"
# Calamares downloads the groups from CachyOS's GitHub first; use this copy.
edit "$modules/netinstall.conf" '
  /^groupsUrl:/ { print "groupsUrl:"; print " - file:///etc/calamares/modules/netinstall.yaml"; skip=1; next }
  skip && /^ *- / { next }
  { skip=0; print }'

# Run the jobs around the package installation of the online install.
for settings in "$airootfs"/usr/share/calamares/settings{,_online}.conf "$calamares/settings.conf"; do
  [[ -f $settings ]] && grep -qx '  - packages@online' "$settings" || continue
  ! grep -q 'omarchy_repos' "$settings" || continue
  edit "$settings" '
    /^instances:$/ {
      print
      print "- id:       omarchy_repos"
      print "  module:   shellprocess"
      print "  config:   shellprocess_omarchy_repos.conf"
      print "- id:       omarchy_finish"
      print "  module:   shellprocess"
      print "  config:   shellprocess_omarchy_finish.conf"
      changes++
      next
    }
    /^  - packages@online$/ { print "  - shellprocess@omarchy_repos"; changes++ }
    { print }
    /^  - shellprocess$/ { print "  - shellprocess@omarchy_finish"; changes++ }
    END { if (changes != 3) exit 1 }'
  echo "Updated ${settings#"$airootfs"}"
done
echo "Omarchy added to the installer (extras: $([[ -d $data/extras ]] && echo yes || echo no))."
