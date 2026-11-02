#!/usr/bin/env bash
# Markdown review notes for an Omarchy update, focused on what this adapter
# filters out or reimplements. Usage: bin/upstream-report.sh OLD_VERSION NEW_VERSION
set -eEuo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
OMARCHY_REPO=https://github.com/omacom/omarchy.git
(( $# == 2 )) || { echo "Usage: $0 OLD_VERSION NEW_VERSION" >&2; exit 2; }
old=v${1#v} new=v${2#v}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
git clone -q --bare --filter=blob:none "$OMARCHY_REPO" "$work/omarchy.git"
g() { git -C "$work/omarchy.git" "$@"; }
changes() { g diff --name-status "$old" "$new" -- "$@"; }
section() {
  local title=$1 note=$2 output
  shift 2
  output=$(changes "$@")
  echo "### $title"
  echo
  echo "$note"
  echo
  if [[ -n $output ]]; then
    echo '```'
    # Keep the pull request body under GitHub's size limit.
    awk 'NR <= 150; END { if (NR > 150) print "… " NR - 150 " more" }' <<< "$output"
    echo '```'
  else
    echo '_No changes._'
  fi
  echo
}

echo "## Omarchy $old → $new"
echo
echo "$(g rev-list --count "$old..$new") commits, $(g diff --shortstat "$old" "$new"). [Compare on GitHub](https://github.com/omacom/omarchy/compare/$old...$new)"
echo
echo '### Base package list'
echo
echo 'The installer installs `install/omarchy-base.packages` (minus plymouth, kernel-modules-hook, tldr).'
echo
packages=$(g diff -U0 "$old" "$new" -- install/omarchy-base.packages | grep -E '^[+-][^+-]' || true)
if [[ -n $packages ]]; then
  echo '```diff'
  echo "$packages"
  echo '```'
else
  echo '_No changes._'
fi
echo
echo '### New migrations'
echo
echo 'The adapter does not run upstream migrations: check whether a new one needs an equivalent here.'
echo
migrations=$(g diff --name-only --diff-filter=A "$old" "$new" -- migrations)
if [[ -n $migrations ]]; then
  while read -r file; do
    # Migrations announce themselves with a leading echo.
    title=$(g show "$new:$file" | sed -n 's/^echo "\(.*\)"$/\1/p;T;q')
    echo "- \`$file\` ${title:-(no description)}"
  done <<< "$migrations"
else
  echo '_None._'
fi
echo
section 'System files (`etc/`)' 'Not shipped, except `etc/profile.d` and `etc/mise`.' etc
section 'System install scripts' 'Not run by the adapter.' \
  install/config install/hardware install/login install/post-install install/preflight
section 'User provisioning' 'Run by the adapter (`omarchy-provision-user`, `install/user` minus default-keyring).' \
  bin/omarchy-provision-user install/user
section 'Files the PKGBUILD installs at system paths' 'Staged individually in `package()`: check paths still exist.' \
  default/uwsm default/environment.d default/fontconfig default/xdg-terminal-exec \
  default/applications/mimeapps.list default/systemd default/wayland-sessions default/fonts applications/icons
section 'Replaced commands' 'The PKGBUILD overrides these with CachyOS versions.' \
  bin/omarchy-update bin/omarchy-upgrade-to-quattro
top_level=$(diff <(g ls-tree --name-only "$old") <(g ls-tree --name-only "$new") | grep '^[<>]' || true)
if [[ -n $top_level ]]; then
  echo '### Top-level entries'
  echo
  echo 'The PKGBUILD copies a fixed list of directories.'
  echo
  echo '```'
  echo "$top_level"
  echo '```'
  echo
fi
# Under pipefail, `| head` would kill the pipeline with SIGPIPE on long histories.
count=$(g rev-list --count "$old..$new")
echo "<details><summary>Commits ($count)</summary>"
echo
g log --max-count=200 --format='- %h %s' "$old..$new"
(( count <= 200 )) || echo "- … $((count - 200)) more"
echo
echo '</details>'
