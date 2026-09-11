#!/usr/bin/env bash

set -euo pipefail

here="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
VERSION=$(cat "$here/VERSION")

PREFIX="${PREFIX:-/usr/local}"
DESTDIR="${DESTDIR:-}"
OS_RELEASE="${OS_RELEASE:-/etc/os-release}"
UNINSTALL=0

usage() {
  cat <<EOF
install.sh — install the DDLC lock screen ($VERSION)

  PREFIX=$PREFIX (override with PREFIX=... or --prefix DIR)
  DESTDIR=${DESTDIR:-<empty>} (override with DESTDIR=... or --destdir DIR for staging)

  -h, --help        show this help and exit
  -v, --version     print the version and exit
      --prefix DIR  install prefix (default: /usr/local)
      --destdir DIR staging root: files land under DESTDIR/PREFIX
      --uninstall   remove everything a previous install wrote, by its manifest

The assets, the rendered hyprlock config, the glitch shader and the dialog engine go to
\$PREFIX/share/ddlc-hyprlock; \$PREFIX/bin gets a symlink to the engine, which finds the
assets beside itself, so nothing has to be set for it

Then take the config and point whatever locks your session at the engine:

  cp \$PREFIX/share/ddlc-hyprlock/hyprlock.conf ~/.config/hypr/hyprlock.conf
  ddlc-hyprlock lock

The font the config asks for is Doki, the game's own — it is not shipped here

Runtime environment (read by the installed engine, not this script; ddlc-hyprlock help
has the full list):
  DDLC_HYPRLOCK_NAME, DDLC_HYPRLOCK_QUOTES, DDLC_HYPRLOCK_REENTRY, DDLC_HYPRLOCK_GLITCH,
  DDLC_HYPRLOCK_FLASH, DDLC_HYPRLOCK_HYPRLOCK, DDLC_HYPRLOCK_POLL_MS, ...

Exit 0 done, 1 when the install could not be made — a dependency missing, a manifest
that cannot be written — and 2 on a usage error.
EOF
}

die() { # the request itself is wrong
  printf 'install.sh: %s\n' "$1" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)
      # Not ${2:?}: that exits 1 with bash's own message, and a usage error is 2
      (($# >= 2)) || die "$1 needs a directory"
      PREFIX="$2"
      shift 2
      ;;
    --destdir)
      (($# >= 2)) || die "$1 needs a directory"
      DESTDIR="$2"
      shift 2
      ;;
    --uninstall)
      UNINSTALL=1
      shift
      ;;
    -v | --version)
      echo "ddlc-hyprlock $VERSION"
      exit 0
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

[[ "$PREFIX" == /* ]] || die "PREFIX must be absolute: $PREFIX"

root="${DESTDIR%/}$PREFIX"
share_runtime="$PREFIX/share/ddlc-hyprlock"
share="${DESTDIR%/}$share_runtime"
manifest="$share/install-manifest"

# --- uninstall -------------------------------------------------------------------------

if ((UNINSTALL)); then
  if [[ ! -f "$manifest" ]]; then
    # Installs made before the manifest existed (ddlc-hyprlock <= 1.0.1): the fixed
    # list those versions wrote. Drop this arm one release later
    rm -f "$root/bin/ddlc-hyprlock"
    rm -rf "$share"
    echo "removed ddlc-hyprlock from $root"
    exit 0
  fi
  while IFS= read -r path; do
    [[ -z "$path" || "$path" == \#* ]] && continue
    rm -f "${DESTDIR%/}$path"
  done <"$manifest"
  rm -f "$manifest"
  rmdir "$share" 2>/dev/null || true
  echo "removed ddlc-hyprlock from $root"
  exit 0
fi

# --- preflight: refuse loudly, install nothing ----------------------------------------
# The engine's own tools have to exist; the session's — the locker, the compositor, the
# journal — only when a session locks, so their absence warns and the install proceeds

missing=()
absent=()

need() { command -v "$1" >/dev/null 2>&1 || missing+=("$1"); }
want() { command -v "$1" >/dev/null 2>&1 || absent+=("$1"); }

need install
need gawk
want hyprlock
want hyprctl
want journalctl

# `&` in ${s//pat/repl} means "what matched" only since bash 5.2, and the engine escapes
# markup with exactly that — an older bash renders `<lt;` into the dialog box
if ((BASH_VERSINFO[0] < 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] < 2))); then
  missing+=("bash >= 5.2 (this one is $BASH_VERSION)")
fi

distro_id() {
  sed -n 's/^ID\(_LIKE\)\?=//p' "$OS_RELEASE" 2>/dev/null | tr -d '"' | tr '\n' ' '
}

if ((${#missing[@]})); then
  pkgs=()
  for command in "${missing[@]}"; do
    case "$command" in
      gawk) pkgs+=(gawk) ;;
      bash*) pkgs+=(bash) ;;
    esac
  done
  {
    printf 'install.sh: missing dependencies:\n'
    printf '  - %s\n' "${missing[@]}"
    if ((${#pkgs[@]})); then
      case " $(distro_id) " in
        *" arch "*)
          printf '\nInstall them on Arch:\n'
          printf '  $ sudo pacman -S --needed %s\n' "${pkgs[*]}"
          ;;
        *" debian "* | *" ubuntu "*)
          printf '\nInstall them on Debian/Ubuntu:\n'
          printf '  $ sudo apt-get update\n'
          printf '  $ sudo apt-get install %s\n' "${pkgs[*]}"
          ;;
        *" fedora "*)
          printf '\nInstall them on Fedora:\n'
          printf '  $ sudo dnf install %s\n' "${pkgs[*]}"
          ;;
        *)
          printf '\nInstall them with your package manager: %s\n' "${pkgs[*]}"
          ;;
      esac
    fi
  } >&2
  exit 1
fi
if ((${#absent[@]})); then
  printf 'install.sh: not found (comes from your session, install proceeds): %s\n' \
    "${absent[@]}" >&2
fi

# --- install ---------------------------------------------------------------------------
# Every file lands in the manifest as its final runtime path (no DESTDIR): the manifest
# ships inside a staged tree and stays correct wherever the tree ends up

installed=()
rec() { installed+=("${1#"${DESTDIR%/}"}"); }

install -d "$share"
for file in "$here"/assets/*; do
  install -m644 "$file" "$share/$(basename "$file")"
  rec "$share/$(basename "$file")"
done
install -Dm644 "$here/shaders/glitch.frag" "$share/glitch.frag"
rec "$share/glitch.frag"
install -Dm644 "$here/VERSION" "$share/VERSION"
rec "$share/VERSION"

# DESTDIR is only a staging root: the installed config must name its final runtime path
escaped_share=$(printf '%s' "$share_runtime" | sed 's/[&|\\]/\\&/g')
sed "s|@share@|$escaped_share|g" "$here/dist/hyprlock.conf.in" >"$share/hyprlock.conf"
chmod 644 "$share/hyprlock.conf"
rec "$share/hyprlock.conf"

# The engine lives beside its assets; bin carries a relative symlink, and the engine
# resolves through it to find them with nothing configured
install -Dm755 "$here/ddlc-hyprlock.sh" "$share/ddlc-hyprlock.sh"
rec "$share/ddlc-hyprlock.sh"
install -d "$root/bin"
ln -sfn ../share/ddlc-hyprlock/ddlc-hyprlock.sh "$root/bin/ddlc-hyprlock"
rec "$PREFIX/bin/ddlc-hyprlock"

{
  echo "# ddlc-hyprlock $VERSION install manifest"
  printf '%s\n' "${installed[@]}"
} >"$manifest"

echo "installed ddlc-hyprlock $VERSION to $share, engine linked into $root/bin"
