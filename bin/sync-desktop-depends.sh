#!/usr/bin/env bash
# Rewrite the generated depends block of omcachy-desktop from an
# upstream package list. Usage: bin/sync-desktop-depends.sh install/omarchy-base.packages
set -eEuo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PKGBUILD=$SCRIPT_DIR/../pkgbuilds/omcachy/PKGBUILD
(( $# == 1 )) || { echo "Usage: $0 OMARCHY_BASE_PACKAGES" >&2; exit 2; }
packages=$(bash "$SCRIPT_DIR/desktop-depends.sh" "$1")
[[ -n $packages ]] || { echo "No packages found in $1" >&2; exit 1; }
new=$(mktemp)
trap 'rm -f "$new"' EXIT
awk -v packages="$packages" '
  /# BEGIN depends:/ {
    print
    print "  depends=(\"omcachy=$pkgver-$pkgrel\""
    n = split(packages, list, "\n")
    for (i = 1; i <= n; i++) print "    " list[i]
    print "  )"
    skip = 1
    found = 1
    next
  }
  /# END depends/ { skip = 0 }
  !skip { print }
  END { if (!found) exit 1 }
' "$PKGBUILD" > "$new" || { echo "Generated depends markers missing in $PKGBUILD" >&2; exit 1; }
cat "$new" > "$PKGBUILD"
echo "omcachy-desktop: $(wc -l <<< "$packages") packages"
