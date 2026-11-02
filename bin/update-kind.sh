#!/usr/bin/env bash
# Classify an Omarchy update: patch, minor, major, prerelease or downgrade.
# Only patch updates (same X.Y, stable, newer) are published without review.
# Usage: bin/update-kind.sh OLD_VERSION NEW_VERSION
set -eEuo pipefail
(( $# == 2 )) || { echo "Usage: $0 OLD_VERSION NEW_VERSION" >&2; exit 2; }
old=${1#v} new=${2#v}
stable='^[0-9]+\.[0-9]+\.[0-9]+$'

# sort -V orders '~' first: 4.5.0~rc3 comes before 4.5.0.
if [[ $old == "$new" ]] || [[ $(printf '%s\n' "${old//-/\~}" "${new//-/\~}" | sort -V | tail -1) != "${new//-/\~}" ]]; then
  echo downgrade
elif [[ ! $new =~ $stable ]]; then
  echo prerelease
elif [[ ${old%%.*} != "${new%%.*}" ]]; then
  echo major
elif [[ ! $old =~ $stable || ${old%.*} != "${new%.*}" ]]; then
  echo minor
else
  echo patch
fi
