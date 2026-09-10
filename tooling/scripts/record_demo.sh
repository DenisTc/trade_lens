#!/bin/sh
# Records the README demo. A Patrol scenario drives the app while the host
# grabs simulator frames; docs/demo/build.py turns them into the GIF.
#
#   sh tooling/scripts/record_demo.sh <simulator udid>
#
# The runner launches the app twice — once to enumerate the tests, once to
# run them — with the home screen in between, and it takes minutes to
# build before either. So a watcher follows the app's own process: the
# frames that count are the ones between its last launch and its exit.
set -e

UDID="${1:?usage: record_demo.sh <simulator udid>}"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OUT="$ROOT/build/demo"
FRAMES="$OUT/frames"
BUNDLE=com.denistc.tradelens

rm -rf "$OUT"
mkdir -p "$FRAMES"

# The demo shows the app as someone installing it would see it: no source
# a previous run picked, no portfolio it left behind. The appearance is
# the device's, so it is set too — the walk-through opens dark and
# switches to light at the end.
xcrun simctl uninstall "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
xcrun simctl ui "$UDID" appearance dark >/dev/null 2>&1 || true

# The label ends in `[` so this matches the app and not the UI-test runner,
# whose bundle id starts with the same string.
running() {
  xcrun simctl spawn "$UDID" launchctl list 2>/dev/null |
    grep -q "UIKitApplication:$BUNDLE\["
}

last_frame() {
  ls "$FRAMES" | tail -n 1
}

grab() {
  i=0
  while :; do
    i=$((i + 1))
    xcrun simctl io "$UDID" screenshot --type=png \
      "$FRAMES/$(printf '%04d' $i).png" >/dev/null 2>&1 || true
  done
}

# `running` costs a round trip into the simulator, which paces this loop
# without a sleep. `last` is written while the app is up rather than once
# it is gone: a frame seen after it exits is the home screen.
watch_app() {
  up=0
  while :; do
    if running; then
      [ "$up" = 1 ] || last_frame > "$OUT/first"
      up=1
      last_frame > "$OUT/last"
    else
      up=0
    fi
  done
}

grab &
GRABBER=$!
watch_app &
WATCHER=$!
trap 'kill $GRABBER $WATCHER 2>/dev/null || true' EXIT INT TERM

cd "$ROOT/apps/mobile"
patrol test \
  --target integration_test/demo_test.dart \
  -d "$UDID" \
  --dart-define TL_AI_DEMO=true \
  --dart-define TL_DEMO_PORTFOLIO=true

kill $GRABBER $WATCHER 2>/dev/null || true
trap - EXIT INT TERM

python3 "$ROOT/docs/demo/build.py" "$FRAMES" "$ROOT/docs/demo/tradelens.gif" \
  "$(cat "$OUT/first" 2>/dev/null)" "$(cat "$OUT/last" 2>/dev/null)"
