#!/usr/bin/env bash
# Publish built packages to the pacman repository kept in the GitHub release
# "repo": sign them, add them to the database and drop superseded packages.
# Usage: bin/publish-repo.sh OUT_DIR
# Needs gh (GH_TOKEN), repo-add and gpg with SIGNING_KEY's secret key
# (GPG_PASSPHRASE if it has one).
set -eEuo pipefail
(( $# == 1 )) || { echo "Usage: $0 OUT_DIR" >&2; exit 2; }
: "${SIGNING_KEY:?SIGNING_KEY must name the signing (sub)key}"
REPO=omarchy-oncachy
TAG=repo
out=$(cd -- "$1" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

sign() {
  gpg --batch --yes --pinentry-mode loopback --passphrase "${GPG_PASSPHRASE:-}" \
    --local-user "$SIGNING_KEY!" --detach-sign "$1"
}

if ! gh release view "$TAG" >/dev/null 2>&1; then
  gh release create "$TAG" --title 'Package repository' --latest=false \
    --notes 'pacman repository for omarchy-oncachy: see the README. Files are replaced on each publication.'
fi
# Start from the published database so packages built earlier stay listed.
gh release download "$TAG" --dir "$work" --pattern "$REPO.db.tar.zst" --pattern "$REPO.files.tar.zst" || true

for package in "$out"/*.pkg.tar.zst; do
  cp "$package" "$work/"
  sign "$work/${package##*/}"
done
(cd "$work" && repo-add --remove "$REPO.db.tar.zst" ./*.pkg.tar.zst)
for db in "$REPO.db" "$REPO.files"; do
  # pacman fetches NAME.db; repo-add's symlinks would not survive the upload.
  rm -f "$work/$db" "$work/$db.sig"
  sign "$work/$db.tar.zst"
  cp "$work/$db.tar.zst" "$work/$db"
  cp "$work/$db.tar.zst.sig" "$work/$db.sig"
done

gh release upload "$TAG" --clobber "$work"/*.pkg.tar.zst "$work"/*.pkg.tar.zst.sig \
  "$work/$REPO".{db,files}{,.sig,.tar.zst,.tar.zst.sig}

# Remove packages the database no longer lists.
keep=$(bsdtar -xOf "$work/$REPO.db.tar.zst" '*/desc' | awk '/^%FILENAME%$/ {getline; print}')
gh release view "$TAG" --json assets --jq '.assets[].name' | while read -r asset; do
  [[ $asset == *.pkg.tar.zst || $asset == *.pkg.tar.zst.sig ]] || continue
  grep -qxF "${asset%.sig}" <<< "$keep" || gh release delete-asset "$TAG" "$asset" --yes
done
echo "Published:"
sed 's/^/  /' <<< "$keep"
