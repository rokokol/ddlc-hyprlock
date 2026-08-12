#!/usr/bin/env bash
# Drives the engine against a stub locker and a stub journal, and diffs the frames it
# publishes. HOME and XDG_RUNTIME_DIR are both redirected: a session exports the second one,
# and the engine would otherwise publish straight into the live lock's state directory
#
#   tests/run.sh            check the engine
#   tests/run.sh --update   rewrite the goldens from what it renders now
#
# DDLC_HYPRLOCK_BIN picks what is driven; by default the packaged command on PATH, so the
# wrapper's own defaults are under test too

set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ENGINE="${DDLC_HYPRLOCK_BIN:-ddlc-hyprlock}"
GOLDEN="$HERE/golden"
UPDATE=0
[[ "${1:-}" == "--update" ]] && UPDATE=1

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

export HOME="$WORK/home"
export XDG_RUNTIME_DIR="$WORK/run"
# A redirected HOME is not enough: a session exports XDG_DATA_HOME, and it is what the
# default [chr] path is built from
export XDG_DATA_HOME="$WORK/home/.local/share"
export PATH="$HERE/stub:$PATH"
export USER=tester
mkdir -p "$HOME" "$XDG_RUNTIME_DIR" "$GOLDEN"

STATE="$WORK/state"
SHADER_LOG="$WORK/shader.log"
HYPRCTL_LOG="$WORK/hyprctl.log"

# The geometry a 1280x720 dialog box comes out at, so the goldens are the real wrap width
export DDLC_HYPRLOCK_TEXT_W=1114
export DDLC_HYPRLOCK_FONT_PX=32
export DDLC_HYPRLOCK_POLL_MS=100
export DDLC_HYPRLOCK_STATE_DIR="$STATE"
export DDLC_HYPRLOCK_NAME=Monika
# The wrapper sets both with --set-default, so these have to win — that is the contract
export DDLC_HYPRLOCK_HYPRLOCK="$HERE/stub/hyprlock"
export DDLC_HYPRLOCK_SHADER="$HERE/stub/screen-shader"
export STUB_SHADER_LOG="$SHADER_LOG"
export STUB_HYPRCTL_LOG="$HYPRCTL_LOG"

# A stub that is not executable, or one the PATH does not reach first, silently hands the
# engine the real tool — and for hyprctl that is a live compositor rather than a log file
for tool in hyprlock journalctl screen-shader hyprctl; do
  if [[ ! -x "$HERE/stub/$tool" ]]; then
    printf 'tests/stub/%s is not executable\n' "$tool" >&2
    exit 1
  fi
  if [[ "$(command -v "$tool")" != "$HERE/stub/$tool" ]]; then
    printf '%s resolves to %s, not to the stub\n' "$tool" "$(command -v "$tool")" >&2
    exit 1
  fi
done

fails=0

ok() { printf '  ✓ %s\n' "$1"; }

fail() {
  printf '  ✗ %s\n' "$1"
  fails=$((fails + 1))
}

# One quote, so the topic draw has nothing to choose between and a golden is a golden
say() {
  printf '%s\n' "$1" >"$WORK/reentry.txt"
  printf 'nothing to say\n' >"$WORK/talk.txt"
  export DDLC_HYPRLOCK_REENTRY="$WORK/reentry.txt"
  export DDLC_HYPRLOCK_QUOTES="$WORK/talk.txt"
}

# Run a lock in the background and wait for the frame to stop changing. The engine holds the
# locker as its child, so killing the engine is what ends the lock
lock() {
  rm -rf "$STATE"
  : >"$SHADER_LOG"
  : >"$HYPRCTL_LOG"
  "$ENGINE" lock &
  engine_pid=$!
}

# Wait for a line to turn up in a stub's log, up to $2 tenths of a second
logged() {
  local file=$1 pattern=$2 tries=${3:-60} i
  for ((i = 0; i < tries; i++)); do
    grep -qF "$pattern" "$file" 2>/dev/null && return 0
    sleep 0.1
  done
  return 1
}

settled() {
  local prev="" cur="" same=0 i
  for ((i = 0; i < 400; i++)); do
    cur=$(cat "$STATE/frame" 2>/dev/null || true)
    if [[ -n "$cur" && "$cur" == "$prev" ]]; then
      same=$((same + 1))
      if ((same >= 5)); then
        printf '%s' "$cur"
        return 0
      fi
    else
      same=0
    fi
    prev=$cur
    sleep 0.05
  done
  return 1
}

stop() {
  kill "$engine_pid" 2>/dev/null || true
  wait "$engine_pid" 2>/dev/null || true
}

# Compare a rendered frame against its golden, or rewrite it under --update
golden() {
  local what=$1 file="$GOLDEN/$2" got=$3
  if ((UPDATE)); then
    printf '%s' "$got" >"$file"
    ok "$what: golden written"
    return
  fi
  if [[ ! -f "$file" ]]; then
    fail "$what: no golden — run tests/run.sh --update"
    return
  fi
  if [[ "$got" == "$(cat "$file")" ]]; then
    ok "$what"
  else
    fail "$what: the frame is not the golden one"
    diff <(cat "$file") <(printf '%s\n' "$got") || true
  fi
}

echo "typing"

export DDLC_HYPRLOCK_GLITCH=0
say 'Hi, [player]! & <3'
lock
short=$(settled) || fail "the frame never settled"
stop
golden "a short line types out, escaped and padded" short.frame "$short"

if [[ "$short" == *tester* ]]; then
  ok "[player] became the user's name"
else
  fail "[player] was not substituted"
fi

say 'Back it up: [chr]'
lock
chr=$(settled) || fail "the [chr] frame never settled"
stop
# The default is the quotes file, so the path she names is one that is really there
if [[ "$chr" == *"$WORK/talk.txt"* && -r "$WORK/talk.txt" ]]; then
  ok "[chr] became the file her lines are read from"
else
  fail "[chr] was not substituted: $chr"
fi

echo "wrapping"

say 'Ah, you are back! I kept the club running while you were away, you know — someone has to.'
lock
wrapped=$(settled) || fail "the wrapped frame never settled"
stop
golden "a long line wraps at the text-area width" wrapped.frame "$wrapped"

echo "the name plate"

name=$(cat "$STATE/name")
if [[ "$name" == *Monika* ]]; then
  ok "the plate carries the name"
else
  fail "the plate does not carry the name: $name"
fi

echo "glitches"

export DDLC_HYPRLOCK_GLITCH=1
export DDLC_HYPRLOCK_FLASH=screen-shader
say 'Hi, [player]! & <3'
lock
logged "$SHADER_LOG" "flash glitch" || fail "the journal line did not reach screen-shader"
# Read the frame while the glitch is still on — the text garbles for seconds after the flash
glitched=$(cat "$STATE/frame" 2>/dev/null || true)
stop

if grep -q '^flash glitch' "$SHADER_LOG"; then
  ok "a wrong password flashes the screen through screen-shader"
else
  fail "screen-shader was called as: $(cat "$SHADER_LOG")"
fi

# Which glyphs land where is random by construction, so the check is that the frame holds
# any byte the quote and the markup cannot account for — both are pure ASCII
if printf '%s' "$glitched" | tr -d '\n' | LC_ALL=C grep -q '[^ -~]'; then
  ok "the text is garbled while the glitch lasts"
else
  fail "the frame carries no mojibake through a glitch"
fi

echo "the flash through hyprctl"

export DDLC_HYPRLOCK_FLASH=hyprctl
lock
# The path is the packaged shader's, so the name is what both a store path and a checkout share
if logged "$HYPRCTL_LOG" "keyword decoration:screen_shader" && grep -q "glitch.frag" "$HYPRCTL_LOG"; then
  ok "the glitch sets the shader"
else
  fail "the shader was not set: $(cat "$HYPRCTL_LOG")"
fi

# Hyprland refuses to animate a shader that reads `time` while damage tracking is on, and puts
# an error overlay on screen instead — so the flash has to turn it off first, in one batch
if grep -q "damage_tracking 0 ; keyword debug:vfr 0 ; keyword decoration:screen_shader" "$HYPRCTL_LOG"; then
  ok "…with damage tracking and VFR turned off ahead of it"
else
  fail "the shader was set without them: $(cat "$HYPRCTL_LOG")"
fi

# The engine clears it on its own clock, without a background sleeper to outlive the lock
if logged "$HYPRCTL_LOG" "decoration:screen_shader [[EMPTY]]"; then
  ok "…and the flash is cleared again"
else
  fail "the shader was left on: $(cat "$HYPRCTL_LOG")"
fi

# Those two are the compositor's settings, not ours: they go back to what they were, which the
# stub reports as Hyprland's defaults
if grep -q "screen_shader \[\[EMPTY\]\] ; keyword debug:damage_tracking 2 ; keyword debug:vfr 1" "$HYPRCTL_LOG"; then
  ok "…and damage tracking and VFR are put back"
else
  fail "the debug options were not restored: $(cat "$HYPRCTL_LOG")"
fi
stop

# A lock killed mid-flash must not leave the whole screen glitched
: >"$HYPRCTL_LOG"
lock
logged "$HYPRCTL_LOG" "glitch.frag" || fail "the shader was not set before the kill"
stop
if grep -qF "decoration:screen_shader [[EMPTY]]" "$HYPRCTL_LOG"; then
  ok "a lock that dies mid-flash still clears the shader"
else
  fail "the shader outlived the engine: $(cat "$HYPRCTL_LOG")"
fi

echo "no flash at all"

export DDLC_HYPRLOCK_FLASH=none
lock
sleep 2
stop
if [[ ! -s "$HYPRCTL_LOG" && ! -s "$SHADER_LOG" ]]; then
  ok "flash = none touches neither hyprctl nor screen-shader"
else
  fail "something was called anyway: $(cat "$HYPRCTL_LOG" "$SHADER_LOG")"
fi

echo "the locker owns the lock"

export DDLC_HYPRLOCK_GLITCH=0
say 'Just Monika'
STUB_HYPRLOCK_SLEEP=1 lock
rc=0
wait "$engine_pid" || rc=$?
if ((rc == 0)); then
  ok "the engine exits with the locker, and with its status"
else
  fail "the engine exited $rc after the locker was done"
fi

if ((fails)); then
  printf '\n%d failed\n' "$fails"
  exit 1
fi
printf '\nall passed\n'
