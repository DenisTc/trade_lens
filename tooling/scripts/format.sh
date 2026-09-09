#!/usr/bin/env sh
# Formats the workspace sources. `dart format .` would also walk build
# output, which holds vendored plugin sources after an iOS build: not ours
# to format, and it made the check fail locally after every iOS run.
set -eu
cd "$(dirname "$0")/../.."
find apps packages tooling -name '*.dart' \
  -not -path '*/build/*' \
  -not -path '*/.dart_tool/*' \
  -print0 | xargs -0 dart format "$@"
