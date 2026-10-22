#!/usr/bin/env bash
# scripts/record.sh - optional: capture a clean `make verify` run as demo insurance.
# Uses asciinema when installed, otherwise util-linux `script` (plain typescript log).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p recordings
ts="$(date +%Y%m%d-%H%M%S)"
if command -v asciinema >/dev/null 2>&1; then
  asciinema rec -q -c "make verify" "recordings/verify-$ts.cast"
  echo "saved recordings/verify-$ts.cast (play: asciinema play recordings/verify-$ts.cast)"
else
  script -q -c "make verify" "recordings/verify-$ts.log"
  echo "saved recordings/verify-$ts.log (replay: cat recordings/verify-$ts.log)"
fi
