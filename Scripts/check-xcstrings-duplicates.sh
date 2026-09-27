#!/usr/bin/env bash
# No string catalogue defines a key twice.
#
# A clean git merge can leave the same key in a .xcstrings file twice, and
# nothing downstream complains: xcstringstool compiles the FIRST, Python's json
# keeps the LAST, and which wording ships is an accident (provenance_recorded,
# PR #74 and PR #83, ADR 2026-09-23 (e)). Checks every tracked catalogue, at
# every level of nesting.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$(dirname "$0")/.."

catalogues=()
while IFS= read -r f; do catalogues+=("$f"); done < <(git ls-files '*.xcstrings')
if [ ${#catalogues[@]} -eq 0 ]; then
  kamome_fail "no tracked .xcstrings found — the check would measure nothing"
  exit 1
fi

/usr/bin/env python3 - "${catalogues[@]}" <<'PY'
import collections, json, sys
failed = False
for path in sys.argv[1:]:
    dups = []
    def hook(pairs):
        counts = collections.Counter(k for k, _ in pairs)
        dups.extend(k for k, n in counts.items() if n > 1)
        return dict(pairs)
    with open(path, encoding="utf-8") as f:
        json.load(f, object_pairs_hook=hook)
    if dups:
        failed = True
        print(f"  \033[31mFAIL\033[0m  {path} defines a key twice: {', '.join(sorted(set(dups)))}", file=sys.stderr)
    else:
        print(f"  \033[32mok\033[0m    {path}: no key defined twice")
sys.exit(1 if failed else 0)
PY
