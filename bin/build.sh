#!/usr/bin/env bash
# Build the packages into out/. Extra arguments go to makepkg, e.g.
# --nodeps (no installed dependencies needed) or --nobuild (sources only).
set -eEuo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
export PKGDEST=${PKGDEST:-$ROOT/out}
export SRCDEST=${SRCDEST:-$ROOT/.cache/sources}
export BUILDDIR=${BUILDDIR:-$ROOT/.cache/build}
mkdir -p "$PKGDEST" "$SRCDEST" "$BUILDDIR"
cd "$ROOT/pkgbuilds/omarchy-oncachy"
makepkg --cleanbuild --force "$@"
