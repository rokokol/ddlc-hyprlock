#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
ddlc-hyprlock — the DDLC dialog for a hyprlock lock screen

Modes:
  lock   run a lock: start hyprlock and animate its dialog until it exits.
         This is what an idle daemon's lock command should be, so that every
         lock path funnels through it
  help   this help

The dialog labels just `cat` the files this loop writes, on hyprlock's own poll.
Never signal hyprlock: its SIGUSR2 handler walks the timer vector without the
mutex and allocates inside the handler, so a push into a busy locker wedges it

The loop runs in the foreground with hyprlock as its child: no daemon to reap,
and the lock command blocks for exactly the duration of the lock. It never kills
hyprlock — dying must not unlock the screen

Typing is a Ren'Py trick: every frame renders the whole line, and the tail not
yet "typed" is hidden in a transparent span. The texture size stays constant for
the whole life of the line, and the text is pinned in place without any font
measurements; line wrapping is just a fold by character count

Glitches are a single mechanism for a wrong password and spontaneous firings (a
Poisson stream): the name and the text are garbled with a "broken encoding" and
the whole screen flashes, the text for longer than the screen. A wrong password
arrives as a line from a `journalctl -f` follower, which is also what the loop
sleeps on — so it reacts at once without polling the journal

Geometry has to be the same numbers the hyprlock config laid the text area out
at, so it comes from the environment rather than from a guess here:
  DDLC_HYPRLOCK_TEXT_W     width of the box text area, px (default 1114)
  DDLC_HYPRLOCK_FONT_PX    line font size, px (font_size * 4/3; default 32) —
                           the wrap and space-line-width metrics come from it
  DDLC_HYPRLOCK_POLL_MS    how often hyprlock re-reads the files (default 100);
                           the loop renders at exactly this rate, never faster
  DDLC_HYPRLOCK_STATE_DIR  where the rendered frame/name files live; the labels
                           in the config cat the same path

What is said and by whom:
  DDLC_HYPRLOCK_QUOTES   the topics file, blocks separated by a blank line
  DDLC_HYPRLOCK_REENTRY  the topics a lock opens with
  DDLC_HYPRLOCK_NAME     the name on the plate (default Monika)
  DDLC_HYPRLOCK_CHR      what [chr] in a line becomes: the path she names when
                         she talks about her own character file. Defaults to the
                         quotes file — the one her lines are read from

Behaviour switches:
  DDLC_HYPRLOCK_GLITCH    1 (default) or 0. 0 drops the journal follower and the
                          random glitch stream — the dialog still types, it just
                          never garbles
  DDLC_HYPRLOCK_HYPRLOCK  the locker to run (default hyprlock on PATH)

How the screen flashes on a glitch — the text garbles either way:
  DDLC_HYPRLOCK_FLASH     hyprctl (default), screen-shader, or anything else for
                          no flash at all
  DDLC_HYPRLOCK_GLITCH_SHADER  the shader the hyprctl mode sets in
                          decoration:screen_shader. That mode empties the option
                          afterwards instead of restoring it, so a shader of your
                          own does not survive a glitch. For the length of the
                          flash it also turns debug:damage_tracking and debug:vfr
                          off — an animated shader does not run with them on —
                          and puts back whatever they were
  DDLC_HYPRLOCK_SHADER    the screen-shader command, which composites the flash
                          over the effect already on screen and puts it back.
                          Missing or non-executable degrades to text-only

State is plain shell variables for the lifetime of the lock, so a fresh run is
by definition a fresh lock and starts the dialog from the re-entry line
EOF
}

# Where the assets sit relative to bin/, so an install without Nix needs no settings
HERE="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"
SHARE="$HERE/../share/ddlc-hyprlock"

QUOTES="${DDLC_HYPRLOCK_QUOTES:-$SHARE/monika-talk.txt}"
REENTRY="${DDLC_HYPRLOCK_REENTRY:-$SHARE/monika-reentry.txt}"
DIALOG_NAME="${DDLC_HYPRLOCK_NAME:-Monika}"
# What [chr] becomes: the path she names when she talks about her own character file. The
# quotes file by default, because on this machine that is where she actually lives
CHR_FILE="${DDLC_HYPRLOCK_CHR:-$QUOTES}"

TEXT_W="${DDLC_HYPRLOCK_TEXT_W:-1114}"
FONT_PX="${DDLC_HYPRLOCK_FONT_PX:-32}"
STATE_DIR="${DDLC_HYPRLOCK_STATE_DIR:-${XDG_RUNTIME_DIR:-/tmp}/hypr-ddlc}"

# 0 drops the journal follower and the spontaneous-glitch stream: the dialog still types,
# it just never garbles. The full-screen flash is a separate mechanism on top
GLITCH="${DDLC_HYPRLOCK_GLITCH:-1}"
HYPRLOCK="${DDLC_HYPRLOCK_HYPRLOCK:-hyprlock}"

# How the whole screen flashes on a glitch. hyprctl sets decoration:screen_shader and empties it
# again — it does not restore the previous value, so a shader of the user's own does not survive,
# and it turns damage tracking off for the flash because Hyprland will not animate one otherwise;
# screen-shader composites the flash over the effect already there and puts it back. Anything
# else, or a missing tool, leaves the glitch text-only
FLASH="${DDLC_HYPRLOCK_FLASH:-hyprctl}"
GLITCH_SHADER="${DDLC_HYPRLOCK_GLITCH_SHADER:-$SHARE/glitch.frag}"
SCREEN_SHADER="${DDLC_HYPRLOCK_SHADER:-screen-shader}"

# Doki metrics relative to the font size: at 32px a glyph averages 15px, space 8px
AVG_ADV=$((FONT_PX * 15 / 32))
SPACE_ADV=$((FONT_PX / 4))
WRAP_CHARS=$((TEXT_W * 9 / (AVG_ADV * 10))) # wrap with ~10% margin
BOX_LINES=3                                 # lines in the text area

CPS=10 # typing speed, characters per second

LINE_MEAN=7 # pause after a line: Exp(1/7), sec
LINE_MIN=2
LINE_MAX=40

TOPIC_MEAN=60 # empty box between topics: Exp(1/60), sec
TOPIC_MIN=10
TOPIC_MAX=300

GLITCH_MEAN=120 # spontaneous glitches: Exp(1/120) intervals, sec
GLITCH_MIN=15
GLITCH_MAX=600
GLITCH_SHADER_MS=1200 # how long the screen flashes
GLITCH_TEXT_MS=3600   # the text glitches longer than the shader

FADE_MS=600 # smooth fade-out of a line

# Frame rate, shared with the label poll in the config; 100 ms = one char at CPS=10
POLL_MS="${DDLC_HYPRLOCK_POLL_MS:-100}"
IDLE_CAP_MS=1000 # sleep ceiling: bounds how late an unlock is noticed

FRAME_FILE="$STATE_DIR/frame"
NAME_FILE="$STATE_DIR/name"

# Mojibake glyphs render in a fallback font with different line metrics — without
# anchors a glitch would change the texture height and the name would jump. The
# invisible edge glyphs keep the metrics (and, symmetrically, the centering) constant
NAME_ANCHOR='<span alpha="1">�Жð</span>'
GLYPHS=(Ã Ð Ñ Â Ø Þ ß ð þ ¤ ¥ § ¶ ¿ ¬ Œ ž Æ é ö ъ Ж �)

phase=reentry
until_ms=0
reveal_ms=0
next_glitch_ms=0
glitch_until_ms=0
shader_until_ms=0 # 0 = the screen is not flashing; the main loop clears the shader when due
damage_prev=2     # what the flash puts back: Hyprland's defaults until a flash reads the real ones
vfr_prev=1
journal_fd="" # stays empty without glitches: then wait_ms just sleeps
# both are read and written indirectly, by name, from start_topic
# shellcheck disable=SC2034
last_talk=0 # index of the previous monika-talk.txt topic (0 = none)
# shellcheck disable=SC2034
last_reentry=0 # same for monika-reentry.txt
topic_lines=() # unspoken lines of the current topic
cur=""         # current line, already wrapped
frame_prev=$'\0'
name_prev=$'\0'
now=0

# Milliseconds without spawning date: EPOCHREALTIME = "sec.usec" (bash >= 5.2, which is also
# what the pango escaping needs; the separator depends on the locale — strip dot and comma)
set_now() {
  local t=${EPOCHREALTIME//[.,]/}
  now=${t:0:-3}
}

# Exponential random pause in ms -> $exp_v: $1 = mean, $2 = min, $3 = max (sec)
exp_ms() {
  exp_v=$(awk -v m="$1" -v lo="$2" -v hi="$3" -v seed="$(((RANDOM << 15) + RANDOM))" '
    BEGIN {
      srand(seed)
      d = -m * log(1 - rand())
      if (d < lo) d = lo
      if (d > hi) d = hi
      printf "%d", d * 1000
    }')
}

# Pango entities. The backslashes are load-bearing: since bash 5.2 a bare & in a replacement
# stands for the text that matched, so &lt; would come out as <lt;
esc() {
  local s=$1
  s=${s//&/\&amp;}
  s=${s//</\&lt;}
  s=${s//>/\&gt;}
  esc_v=$s
}

# "Broken encoding" -> $glitch_v: ~30% of characters are replaced with mojibake
# glyphs; regenerated on every call so the garbage "lives". Pure bash: a fork per
# frame is exactly what this rewrite exists to avoid
glitch_text() {
  local s=$1 out="" c i
  for ((i = 0; i < ${#s}; i++)); do
    c=${s:i:1}
    if [[ $c != " " && $c != $'\n' ]] && ((RANDOM % 10 < 3)); then
      out+=${GLYPHS[RANDOM % ${#GLYPHS[@]}]}
    else
      out+=$c
    fi
  done
  glitch_v=$out
}

# Random topic from file $1: prints the chosen block's index, then the block
# itself. $2 is the index of this file's previous topic (0 = none), excluded from
# the draw so the same quote doesn't come up twice in a row. Blocks are separated
# by a blank line, lines with '#' are comments
draw_topic() {
  awk -v seed="$(((RANDOM << 15) + RANDOM))" -v skip="${2:-0}" '
    BEGIN { RS = ""; srand(seed) }
    { gsub(/(^|\n)#[^\n]*/, ""); sub(/^\n+/, ""); if ($0 != "") b[++n] = $0 }
    END {
      if (!n) exit
      # draw over n-1 options, shifting past the previous block
      if (n > 1 && skip >= 1 && skip <= n) {
        i = int(rand() * (n - 1)) + 1
        if (i >= skip) i++
      } else {
        i = int(rand() * n) + 1
      }
      print i
      print b[i]
    }
  ' "$1"
}

# Pop the first line of the topic into $cur (wrapped); returns 1 if topic is empty
next_line() {
  ((${#topic_lines[@]})) || return 1
  local line=${topic_lines[0]}
  topic_lines=("${topic_lines[@]:1}")
  line=${line//\[player\]/$USER}
  line=${line//\[chr\]/$CHR_FILE}
  cur=$(printf '%s\n' "$line" | fold -s -w "$WRAP_CHARS" | sed 's/ *$//')
}

start_typing() {
  phase=typing
  reveal_ms=$now
}

# $1 is the topics file, $2 is the name of the variable holding this file's
# previous topic index (updated to the chosen one)
start_topic() {
  local out
  mapfile -t out < <(draw_topic "$1" "${!2}")
  if ((${#out[@]})); then
    printf -v "$2" '%s' "${out[0]}"
    topic_lines=("${out[@]:1}")
  fi
  next_line || true
  start_typing
}

# An int option out of hyprctl -> $get_v. getoption prints "int: 2" and "set: true", so one
# line is the whole parser
hypr_get_int() {
  local key val
  get_v=""
  while read -r key val _; do
    if [[ "$key" == "int:" ]]; then
      get_v=$val
      break
    fi
  done < <(hyprctl getoption "$1" 2>/dev/null)
  [[ -n "$get_v" ]]
}

# Start the screen flash. screen-shader times and reverts its own flash, so there is nothing
# to remember; the hyprctl mode has to be turned off again, and the main loop does that when
# $shader_until_ms comes due — no background sleeper to outlive the lock
flash_on() {
  case "$FLASH" in
    screen-shader)
      # command -v, not -x: it may be a bare command name on PATH
      command -v "$SCREEN_SHADER" >/dev/null 2>&1 || return 0
      local sec
      printf -v sec '%d.%03d' $((GLITCH_SHADER_MS / 1000)) $((GLITCH_SHADER_MS % 1000))
      "$SCREEN_SHADER" flash glitch "$sec" </dev/null >/dev/null 2>&1 &
      ;;
    hyprctl)
      # Already flashing: re-arming would race the clear for the option
      ((shader_until_ms)) && return 0
      [[ -r "$GLITCH_SHADER" ]] || return 0
      command -v hyprctl >/dev/null 2>&1 || return 0
      # The shader is animated, and Hyprland refuses a `time` uniform while damage tracking is
      # on: it raises the error overlay and the effect never moves. So the two debug options go
      # first, in the same batch as the shader, and their old values are kept to be put back —
      # unlike the shader slot, those two are not ours to redefine
      hypr_get_int debug:damage_tracking && damage_prev=$get_v
      hypr_get_int debug:vfr && vfr_prev=$get_v
      hyprctl --batch "keyword debug:damage_tracking 0 ; keyword debug:vfr 0 ; keyword decoration:screen_shader $GLITCH_SHADER" >/dev/null 2>&1 || return 0
      shader_until_ms=$((now + GLITCH_SHADER_MS))
      ;;
  esac
}

# Clear it: the shader slot back to empty, damage tracking and VFR back to whatever they were.
# [[EMPTY]] rather than the previous shader, because that one option is the one this mode owns
# outright — the price of needing nothing but hyprctl
flash_off() {
  ((shader_until_ms)) || return 0
  shader_until_ms=0
  hyprctl --batch "keyword decoration:screen_shader [[EMPTY]] ; keyword debug:damage_tracking $damage_prev ; keyword debug:vfr $vfr_prev" >/dev/null 2>&1 || true
}

fire_glitch() {
  glitch_until_ms=$((now + GLITCH_TEXT_MS))
  # Text garbling is self-contained; the screen flash is an optional extra
  flash_on
}

# Advance the state machine: reentry -> typing -> shown -> fadeout -> typing|gap.
# The typing -> shown edge is in build_frame, where the revealed length is known
advance() {
  case "$phase" in
    reentry)
      start_topic "$REENTRY" last_reentry
      ;;
    shown)
      if ((now >= until_ms)); then
        phase=fadeout
        reveal_ms=$now # start of the fade
        until_ms=$((now + FADE_MS))
      fi
      ;;
    fadeout)
      if ((now >= until_ms)); then
        if next_line; then
          start_typing
        else
          phase=gap
          exp_ms "$TOPIC_MEAN" "$TOPIC_MIN" "$TOPIC_MAX"
          until_ms=$((now + exp_v))
        fi
      fi
      ;;
    gap)
      if ((now >= until_ms)); then
        start_topic "$QUOTES" last_talk
      fi
      ;;
  esac
}

# Frame -> $frame_v: the whole line, the untyped tail as a transparent span (a
# Ren'Py trick). The texture size stays constant for the whole life of the line
build_frame() {
  local full="" n=0 fade_alpha=65535 body nl pad="" i
  if [[ "$phase" != "gap" ]]; then
    full=$cur
    case "$phase" in
      typing)
        n=$(((now - reveal_ms) * CPS / 1000))
        if ((n >= ${#full})); then
          phase=shown
          exp_ms "$LINE_MEAN" "$LINE_MIN" "$LINE_MAX"
          until_ms=$((now + exp_v))
          n=${#full}
        fi
        ;;
      fadeout)
        n=${#full}
        fade_alpha=$((65535 - 65535 * (now - reveal_ms) / FADE_MS))
        ((fade_alpha >= 1)) || fade_alpha=1
        ;;
      *)
        n=${#full}
        ;;
    esac
    if ((now < glitch_until_ms)); then
      glitch_text "$full"
      full=$glitch_v
    fi
  fi

  esc "${full:0:n}"
  body=$esc_v
  if ((n < ${#full})); then
    esc "${full:n}"
    body+="<span alpha=\"1\">$esc_v</span>"
  fi
  if ((fade_alpha < 65535)); then
    body="<span alpha=\"$fade_alpha\">$body</span>"
  fi

  # The frame is always BOX_LINES lines + a width-line of spaces: padding with
  # empty lines keeps the texture height constant, the space-line keeps its width
  # (a label has neither width nor a corner anchor, but with a constant texture
  # size halign center + valign bottom give a fixed top-left). Requires
  # text_trim=false in hyprlock
  nl=${full//[!$'\n']/}
  for ((i = ${#nl} + 1; i < BOX_LINES; i++)); do pad+=$'\n'; done
  printf -v frame_v '%s%s\n%*s' "$body" "$pad" $((TEXT_W / SPACE_ADV)) ''
}

build_name() {
  local name="$DIALOG_NAME"
  if ((now < glitch_until_ms)); then
    glitch_text "$name"
    name=$glitch_v
  fi
  name_v="$NAME_ANCHOR$name$NAME_ANCHOR"
}

# Atomic: hyprlock polls these on its own clock and may read mid-write
publish() {
  if [[ "$frame_v" != "$frame_prev" ]]; then
    printf '%s' "$frame_v" >"$FRAME_FILE.tmp"
    mv "$FRAME_FILE.tmp" "$FRAME_FILE"
    frame_prev=$frame_v
  fi
  if [[ "$name_v" != "$name_prev" ]]; then
    printf '%s' "$name_v" >"$NAME_FILE.tmp"
    mv "$NAME_FILE.tmp" "$NAME_FILE"
    name_prev=$name_v
  fi
}

# ms until the next visible change -> $tick_v; rendering faster than the poll is wasted
next_tick_ms() {
  local t
  case "$phase" in
    typing | fadeout) t=$((now + POLL_MS)) ;;
    *) t=$until_ms ;;
  esac
  # Without glitches next_glitch_ms stays 0, which would clamp every tick to zero and spin
  ((GLITCH && next_glitch_ms < t)) && t=$next_glitch_ms
  ((glitch_until_ms > now && now + POLL_MS < t)) && t=$((now + POLL_MS))
  # The flash is cleared by this loop, so it has to wake up for it
  ((shader_until_ms && shader_until_ms < t)) && t=$shader_until_ms
  ((t > now + IDLE_CAP_MS)) && t=$((now + IDLE_CAP_MS))
  ((t < now)) && t=$now
  tick_v=$((t - now))
}

# Sleep on the journal follower so a wrong password wakes us instantly; falls back
# to sleep(1) if it dies, so a closed fd can't turn this into a spin
wait_ms() {
  local to rc=0
  printf -v to '%d.%03d' $(($1 / 1000)) $(($1 % 1000))
  if [[ -n "$journal_fd" ]]; then
    read -r -t "$to" -u "$journal_fd" _ || rc=$?
    if ((rc == 0)); then
      fire_glitch
    elif ((rc > 0 && rc <= 128)); then
      exec {journal_fd}<&- || true
      journal_fd=""
    fi
  else
    sleep "$to"
  fi
}

# A zombie still answers kill -0, /proc does not lie; stderr first, the error is the shell's
hyprlock_alive() {
  local state
  read -r _ _ state _ 2>/dev/null <"/proc/$hyprlock_pid/stat" || return 1
  [[ "$state" != "Z" ]]
}

cmd_lock() {
  mkdir -p "$STATE_DIR"
  # the labels cat these on hyprlock's very first render
  : >"$FRAME_FILE"
  : >"$NAME_FILE"

  "$HYPRLOCK" &
  hyprlock_pid=$!

  # Dying with the flash still on would leave the whole screen glitched, and the follower
  # outliving us would keep reading the journal for nothing
  trap 'flash_off; [[ -n "${JOURNAL_PID:-}" ]] && kill "$JOURNAL_PID" 2>/dev/null; true' EXIT

  # exec so $JOURNAL_PID is journalctl itself, not a subshell wrapping it.
  # Without glitches nothing reacts to a wrong password, so the follower is pure cost
  if ((GLITCH)); then
    coproc JOURNAL {
      # The tag is the locker's own name, which is its basename even when it runs
      # from a store path
      exec journalctl -f -n 0 -q -t "${HYPRLOCK##*/}" -g 'authentication failure' -o cat
    }
    journal_fd=${JOURNAL[0]}
  fi

  while hyprlock_alive; do
    set_now

    # The flash is on a clock of its own: nothing else in the loop times it out
    ((shader_until_ms && now >= shader_until_ms)) && flash_off

    # Spontaneous glitches: a Poisson stream. 0 means not scheduled yet, then we
    # only assign the first interval, without firing
    if ((GLITCH && now >= next_glitch_ms)); then
      ((next_glitch_ms > 0)) && fire_glitch
      exp_ms "$GLITCH_MEAN" "$GLITCH_MIN" "$GLITCH_MAX"
      next_glitch_ms=$((now + exp_v))
    fi

    advance
    build_frame
    build_name
    publish

    next_tick_ms
    wait_ms "$tick_v"
  done

  wait "$hyprlock_pid" 2>/dev/null || true
}

case "${1:-lock}" in
  lock) cmd_lock ;;
  help | -h | --help) usage ;;
  *)
    usage >&2
    exit 1
    ;;
esac
