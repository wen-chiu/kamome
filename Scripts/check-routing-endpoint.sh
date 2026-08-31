#!/usr/bin/env bash
# The committed routing endpoint is reachable from someone else's network.
#
# matching.base_url must be "" or https. A LAN address is correct on the
# developer's desk and unreachable everywhere else, where it costs one
# matching.timeout_s per leg (P0 2026-08-15). AppConfig.loadOrDie catches the
# archive; this catches the commit. A working-tree edit reaches neither.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$(dirname "$0")/.."

url=$(/usr/bin/env python3 -c \
  'import json; print(json.load(open("Config/TrackingConfig.json"))["matching"]["base_url"])')

case "$url" in
  "" | https://*) kamome_ok "matching.base_url is distributable: \"$url\"" ;;
  *) kamome_fail "matching.base_url must be \"\" or https, got \"$url\""; exit 1 ;;
esac
