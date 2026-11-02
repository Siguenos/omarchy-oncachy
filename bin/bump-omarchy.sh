#!/usr/bin/env bash
# Pin the packages to another Omarchy release: version, tag, commit, checksum
# and the omarchy-oncachy-desktop dependencies.
# Usage: bin/bump-omarchy.sh [VERSION]   (default: latest stable vX.Y.Z tag)
set -eEuo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PKGBUILD=$SCRIPT_DIR/../pkgbuilds/omarchy-oncachy/PKGBUILD
OMARCHY_REPO=https://github.com/omacom/omarchy.git
old_tag=$(source "$PKGBUILD" && echo "$_tag")
old_commit=$(source "$PKGBUILD" && echo "$_commit")

tags=$(git ls-remote --tags "$OMARCHY_REPO")
version=${1:-}
version=${version#v}
if [[ -z $version ]]; then
  version=$(sed -n 's|.*refs/tags/v\([0-9]\+\.[0-9]\+\.[0-9]\+\)$|\1|p' <<< "$tags" | sort -V | tail -1)
  [[ -n $version ]] || { echo "No stable tag found in $OMARCHY_REPO" >&2; exit 1; }
fi
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]] || { echo "Invalid version: $version" >&2; exit 1; }
tag=v$version
# Annotated tags list the commit on the peeled ^{} line.
commit=$(awk -v t="refs/tags/$tag^{}" '$2 == t {print $1}' <<< "$tags")
[[ -n $commit ]] || commit=$(awk -v t="refs/tags/$tag" '$2 == t {print $1}' <<< "$tags")
[[ -n $commit ]] || { echo "Tag $tag not found in $OMARCHY_REPO" >&2; exit 1; }

if [[ $tag == "$old_tag" && $commit == "$old_commit" ]]; then
  echo "Already at Omarchy $tag ($commit)."
  exit 0
fi
[[ $tag != "$old_tag" ]] || { echo "Tag $tag moved from $old_commit to $commit. Stopping." >&2; exit 1; }
newest=$(printf '%s\n' "${old_tag#v}" "$version" | sort -V | tail -1)
[[ $newest == "$version" ]] || echo "Warning: $tag is older than $old_tag." >&2

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
git init -q --bare "$work/omarchy.git"
git -C "$work/omarchy.git" fetch -q --depth 1 "$OMARCHY_REPO" "refs/tags/$tag"
# Same checksum makepkg computes for a git source pinned to a commit.
sum=$(git -c core.abbrev=no -C "$work/omarchy.git" archive --format tar "$commit" | sha256sum)
sum=${sum%% *}
git -C "$work/omarchy.git" show "$commit:install/omarchy-base.packages" > "$work/omarchy-base.packages"

# pkgver may not contain '-': 4.5.0-rc2 becomes 4.5.0rc2, which sorts before 4.5.0.
sed -i "s/^pkgver=.*/pkgver=${version//-/}/; s/^pkgrel=.*/pkgrel=1/; s/^_tag=.*/_tag=$tag/; \
  s/^_commit=.*/_commit=$commit/; s/^sha256sums=('[0-9a-f]\{64\}'/sha256sums=('$sum'/" "$PKGBUILD"
grep -q "^sha256sums=('$sum'" "$PKGBUILD" || { echo "Could not update sha256sums in $PKGBUILD" >&2; exit 1; }
bash "$SCRIPT_DIR/sync-desktop-depends.sh" "$work/omarchy-base.packages"
for patch in "$(dirname -- "$PKGBUILD")"/patches/*.patch; do
  [[ ! -f $patch ]] || echo "Check that patches/${patch##*/} is still needed and still applies." >&2
done
echo "Omarchy $old_tag -> $tag ($commit)"
