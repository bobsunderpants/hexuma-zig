#!/usr/bin/env bash
# DOSBox-X parity capture helper.
#
# Runs the original DOS Hexuma from a scratch copy with deterministic timing,
# injects a scripted command sequence, captures a stable 320x200 frame, and
# records the Zig engine's text output for the same commands. Pixel identity
# is not expected (the Zig GUI has a different layout); this harness is for
# semantic comparison and for reproducing original screenshots.
#
# Usage:
#   scripts/dosbox_parity.sh OUT_DIR "PRE_AUTOTYPE" "zig commands" "POST_AUTOTYPE"
#
# Both AUTOTYPE arguments use DOSBox-X syntax; separate multiple invocations
# with '|'. PRE_AUTOTYPE runs before hexuma.bat (useful for startup keys).
# POST_AUTOTYPE runs after it, so commands are typed into the running game, e.g.
#   "-w 8 enter" "" "-w 3 -p 0.1 untersuche enter"
set -euo pipefail

OUT_DIR="${1:?output directory required}"
PRE_AUTOTYPE_ARGS="${2:-}"
ZIG_COMMANDS="${3:-}"
POST_AUTOTYPE_ARGS="${4:-}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GAME_DIR="/home/bob/Downloads/Hexuma"
SCRATCH="${TMPDIR:-/tmp}/hexuma-parity-game"
CONF="${TMPDIR:-/tmp}/hexuma-parity.conf"
LOG="${TMPDIR:-/tmp}/hexuma-parity.log"
DISPLAY_NUM="${DISPLAY:-:1}"

command -v dosbox-x >/dev/null || { echo 'dosbox-x is required' >&2; exit 1; }
command -v import >/dev/null || { echo 'ImageMagick import is required' >&2; exit 1; }
command -v compare >/dev/null || { echo 'ImageMagick compare is required' >&2; exit 1; }

mkdir -p "$OUT_DIR" "$SCRATCH"
if [ ! -f "$SCRATCH/HEXPRG.EXE" ]; then
  cp -a "$GAME_DIR"/. "$SCRATCH"/
fi
rm -f "$LOG" "$OUT_DIR"/*.png "$OUT_DIR"/*.txt

autotype_lines=""
if [ -n "$PRE_AUTOTYPE_ARGS" ]; then
  IFS='|' read -ra parts <<< "$PRE_AUTOTYPE_ARGS"
  for part in "${parts[@]}"; do
    [ -n "$part" ] && autotype_lines+="autotype ${part}"$'\n'
  done
fi

post_autotype_lines=""
if [ -n "$POST_AUTOTYPE_ARGS" ]; then
  IFS='|' read -ra parts <<< "$POST_AUTOTYPE_ARGS"
  for part in "${parts[@]}"; do
    [ -n "$part" ] && post_autotype_lines+="autotype ${part}"$'\n'
  done
fi

cat > "$CONF" <<EOF
[sdl]
fullscreen=false
fullresolution=original
windowresolution=original
windowposition=10,10
output=surface
videodriver=x11
autolock=false
priority=normal,normal
showmenu=false
showbasic=false

[dosbox]
startbanner=false
fastbioslogo=true
quit warning=false
working directory option=noprompt

[render]
scaler=none
aspect=false
doublescan=false

[video]
scaler=none
aspect=false
doublescan=false

[cpu]
cycles=fixed 3000
core=normal

[vsync]
vsyncmode=off

[log]
logfile=$LOG

[autoexec]
mount c $SCRATCH
c:
$autotype_lines
hexuma.bat
$post_autotype_lines
EOF

find_window() {
  local id cls state
  # DOSBox-X recreates its X window on video-mode changes, and failed runs can
  # leave hidden stale windows in the EWMH client list. Only a viewable DOSBox
  # window can be captured with `import -window`; older ones give BadMatch.
  for id in $(DISPLAY="$DISPLAY_NUM" xprop -root _NET_CLIENT_LIST 2>/dev/null \
              | sed -n 's/.*# \(0x[0-9a-f]*\).*/\1/p'); do
    cls="$(DISPLAY="$DISPLAY_NUM" xprop -id "$id" WM_CLASS 2>/dev/null || true)"
    case "$cls" in
      *DOSBox*|*dosbox*) ;;
      *) continue ;;
    esac
    state="$(DISPLAY="$DISPLAY_NUM" xprop -id "$id" _NET_WM_STATE 2>/dev/null || true)"
    case "$state" in *_NET_WM_STATE_HIDDEN*) continue ;; esac
    if DISPLAY="$DISPLAY_NUM" xwininfo -id "$id" 2>/dev/null \
       | grep -q 'Map State: IsViewable'; then
      echo "$id"
      return 0
    fi
  done
  DISPLAY="$DISPLAY_NUM" xwininfo -root -tree 2>/dev/null \
    | grep -iE 'dosbox' | head -1 | sed -n 's/^ *\(0x[0-9a-f]*\).*/\1/p' || true
  return 0
}

DISPLAY="$DISPLAY_NUM" SDL_AUDIODRIVER=dummy \
  dosbox-x -conf "$CONF" -time-limit 600 >"$OUT_DIR/dosbox-stdout.txt" 2>&1 &
emu_pid=$!

window=""
for _ in $(seq 1 60); do
  kill -0 "$emu_pid" 2>/dev/null || break
  window="$(find_window)"
  [ -n "$window" ] && break
  sleep 0.25
done

# Capture until two consecutive frames are effectively identical.
prev=""
stable=0
for _ in $(seq 1 24); do
  window="$(find_window)"
  [ -z "$window" ] && break
  DISPLAY="$DISPLAY_NUM" import -silent -window "$window" "$OUT_DIR/original.png" 2>/dev/null || true
  [ -s "$OUT_DIR/original.png" ] || break
  diff=999999
  if [ -n "$prev" ] && [ -f "$prev" ]; then
    diff="$(compare -metric AE "$prev" "$OUT_DIR/original.png" null: 2>&1 | awk '{print $1}' || true)"
  fi
  if awk -v d="${diff:-999999}" 'BEGIN { exit !((d + 0) <= 8) }'; then
    stable=$((stable + 1))
    [ "$stable" -ge 2 ] && break
  else
    stable=0
  fi
  cp "$OUT_DIR/original.png" "$OUT_DIR/previous.png"
  prev="$OUT_DIR/previous.png"
  sleep 0.5
done
[ -n "$window" ] && DISPLAY="$DISPLAY_NUM" xwininfo -id "$window" >"$OUT_DIR/xwininfo.txt" 2>&1 || true

kill "$emu_pid" 2>/dev/null || true
sleep 1
kill -9 "$emu_pid" 2>/dev/null || true
wait "$emu_pid" 2>/dev/null || true

capture_status="missing"
if [ -s "$OUT_DIR/original.png" ]; then
  identify -format '%f %wx%h colors=%k mean=%[fx:mean]\n' "$OUT_DIR/original.png" \
    >"$OUT_DIR/original-info.txt" 2>/dev/null || true
  capture_status="ok"
else
  echo 'warning: no viewable DOSBox window was captured' >&2
fi

if [ -n "$ZIG_COMMANDS" ] && [ -x "$ROOT/zig-out/bin/hexuma" ]; then
  {
    IFS=';' read -ra commands <<< "$ZIG_COMMANDS"
    for command in "${commands[@]}"; do
      [ -z "$command" ] && continue
      printf '%s\nquit\n' "$command" | \
        "$ROOT/zig-out/bin/hexuma" play --extracted "$ROOT/extracted" --choices
    done
  } >"$OUT_DIR/zig-output.txt" 2>&1
fi

echo "original screenshot: $OUT_DIR/original.png ($capture_status)"
echo "zig text output:    $OUT_DIR/zig-output.txt"
echo "dosbox log:         $LOG"
