#!/usr/bin/env bash

set -euo pipefail

PREFIX="${PREFIX:-/usr/local}"

usage() {
  cat <<EOF
install.sh — install the DDLC lock screen

  PREFIX=$PREFIX (override with PREFIX=... or --prefix DIR)

The assets and the rendered hyprlock config go to \$PREFIX/share/ddlc-hyprlock and the
dialog engine to \$PREFIX/bin. The engine finds the assets from its own location, so
nothing has to be set for it

Then take the config and point whatever locks your session at the engine:

  cp \$PREFIX/share/ddlc-hyprlock/hyprlock.conf ~/.config/hypr/hyprlock.conf
  ddlc-hyprlock lock

The font the config asks for is Doki, the game's own — it is not shipped here
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)
      PREFIX="${2:?directory required}"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
done

here="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
share="$PREFIX/share/ddlc-hyprlock"

install -d "$share"
install -m644 "$here"/assets/* "$share"

# The one thing the committed config cannot know is where it will be installed
sed "s|@share@|$share|g" "$here/dist/hyprlock.conf.in" >"$share/hyprlock.conf"
chmod 644 "$share/hyprlock.conf"

install -Dm755 "$here/ddlc-hyprlock.sh" "$PREFIX/bin/ddlc-hyprlock"

echo "installed to $share, engine in $PREFIX/bin"
