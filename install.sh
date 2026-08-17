#!/usr/bin/env bash

set -euo pipefail

PREFIX="${PREFIX:-/usr/local}"
DESTDIR="${DESTDIR:-}"

usage() {
  cat <<EOF
install.sh — install the DDLC lock screen

  PREFIX=$PREFIX (override with PREFIX=... or --prefix DIR)
  DESTDIR=${DESTDIR:-<empty>} (override with DESTDIR=... or --destdir DIR for staging)

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
    --destdir)
      DESTDIR="${2:?directory required}"
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

if [[ -n "$DESTDIR" && "$PREFIX" != /* ]]; then
  echo "install.sh: PREFIX must be absolute when DESTDIR is set: $PREFIX" >&2
  exit 1
fi

here="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
root="${DESTDIR%/}$PREFIX"
share="$root/share/ddlc-hyprlock"
runtime_share="$PREFIX/share/ddlc-hyprlock"

install -d "$share"
install -m644 "$here"/assets/* "$share"

# DESTDIR is only a staging root: the installed config must name its final runtime path
escaped_share=$(printf '%s' "$runtime_share" | sed 's/[&|\\]/\\&/g')
sed "s|@share@|$escaped_share|g" "$here/dist/hyprlock.conf.in" >"$share/hyprlock.conf"
chmod 644 "$share/hyprlock.conf"

install -Dm755 "$here/ddlc-hyprlock.sh" "$root/bin/ddlc-hyprlock"

echo "installed to $share, engine in $root/bin"
