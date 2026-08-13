#!/usr/bin/env bash
# Puts the rendered config in front of the real hyprlock, and the engine in front of the real
# journal follower. tests/run.sh cannot: its hyprlock is a shell script that sleeps, so the
# suite proves what the engine writes and nothing about whether hyprlock can read it — a key
# it does not understand is a config error only the real binary reports
#
# It never takes a lock. hyprlock parses its config before it connects to a compositor, so
# pointing it at a display that does not exist gets the parse and stops there
#
# Nothing here runs in CI: it needs the real hyprlock and a session. Run it before a tag
#
#   tests/live.sh

set -uo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO=$(dirname "$HERE")
ENGINE="${DDLC_HYPRLOCK:-$REPO/ddlc-hyprlock.sh}"
HYPRLOCK="${DDLC_HYPRLOCK_HYPRLOCK:-hyprlock}"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

fails=0
ok() { printf '  ✓ %s\n' "$1"; }

fail() {
  printf '  ✗ %s\n' "$1"
  fails=$((fails + 1))
}

command -v "$HYPRLOCK" >/dev/null || {
  echo "live: $HYPRLOCK is not on PATH — this suite needs the real locker" >&2
  exit 1
}

echo "live $("$HYPRLOCK" --version 2>&1 | head -1)"

# The committed render, with its placeholder pointed at the checkout — the same substitution
# install.sh does, so what hyprlock reads here is what a non-Nix install would get
conf="$WORK/hyprlock.conf"
sed "s|@share@|$REPO|g" "$REPO/dist/hyprlock.conf.in" >"$conf"
if grep -q '@[a-z]*@' "$conf"; then
  fail "a placeholder survived the substitution: $(grep -o '@[a-z]*@' "$conf" | sort -u | tr '\n' ' ')"
fi

# A display that cannot exist: hyprlock reads and reports the config, then fails to connect
said=$("$HYPRLOCK" --config "$conf" --display ddlc-live-no-such-display 2>&1)

if grep -q "Config has errors" <<<"$said"; then
  fail "hyprlock refused the rendered config"
  grep -A5 "Config has errors" <<<"$said" | sed 's/^/      /'
else
  ok "the real hyprlock parses the rendered config"
fi

if grep -q "Couldn't connect to a wayland compositor" <<<"$said"; then
  ok "it got past the config and stopped at the display, so nothing was locked"
else
  fail "hyprlock stopped somewhere else — read the output before trusting the check above"
  head -5 <<<"$said" | sed 's/^/      /'
fi

# The engine drives the dialog by writing files the config's labels cat. Run it against a
# locker that exits on its own, so the frames are produced by the real loop and nothing waits.
# XDG_RUNTIME_DIR is redirected rather than the state dir overridden: the config builds its
# paths out of that variable, so this is what makes the two halves meet without either the
# engine or the check writing into the live lock's state
export XDG_RUNTIME_DIR="$WORK/run"
mkdir -p "$XDG_RUNTIME_DIR"
state="$XDG_RUNTIME_DIR/hypr-ddlc"
DDLC_HYPRLOCK_HYPRLOCK="$HERE/stub/hyprlock" \
  STUB_HYPRLOCK_SLEEP=3 \
  DDLC_HYPRLOCK_GLITCH=0 \
  DDLC_HYPRLOCK_STATE_DIR="$state" \
  "$ENGINE" lock >"$WORK/engine.log" 2>&1

if [[ -s "$state/frame" ]]; then
  ok "the engine wrote a frame"
else
  fail "no frame was written"
  sed 's/^/      /' "$WORK/engine.log"
fi

# Every label in the config has to name a file the engine actually produces — a typo in
# either half is a blank dialog, and nothing but the two together can catch it
missing=0
while read -r quoted; do
  # The config spells the path as a shell word — ${XDG_RUNTIME_DIR:-/tmp}/… — because
  # hyprlock runs it through a shell, so it has to be expanded the same way here
  path=$(eval "printf '%s' \"$quoted\"")
  [[ -e $path ]] || {
    printf '      the config cats %s, which the engine never wrote\n' "$path"
    missing=1
  }
done < <(grep -oE 'cat "[^"]+"' "$conf" | sed 's/^cat "//; s/"$//' | sort -u)
if ((missing)); then
  fail "the config reads a file the engine does not write"
else
  ok "every file the config cats was written"
fi

if ((fails)); then
  printf '\n%d failed\n' "$fails"
  exit 1
fi
printf '\nall passed\n'
