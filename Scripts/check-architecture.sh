#!/usr/bin/env bash
# The dependency graph and SDK confinement match Config/architecture.json.
#
# Package.swift is the rules file the compiler enforces: a module cannot import
# what is not declared there. This is the other half — Package.swift itself
# cannot gain an edge, because the edge has to be in architecture.json first,
# and editing that file is an architecture change (CLAUDE.md rule 2).
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$(dirname "$0")/.."

/usr/bin/env python3 - "$@" <<'PY'
import json, re, signal, subprocess, sys

# Do not traceback when the caller pipes this into head.
signal.signal(signal.SIGPIPE, signal.SIG_DFL)

spec = json.load(open("Config/architecture.json"))
allowed, confined = spec["allowed"], spec["confined"]
status = 0

def ok(m):   print("  \033[32mok\033[0m    %s" % m)
def fail(m): print("  \033[31mFAIL\033[0m  %s" % m, file=sys.stderr)

# 1. Package.swift's internal edges are exactly what the spec permits.
pkg = open("Package.swift").read()
declared = {}
for m in re.finditer(r'\.target\(\s*name:\s*"([^"]+)"(.*?)path:\s*"([^"]+)"', pkg, re.S):
    name, body = m.group(1), m.group(2)
    declared[name] = {d for d in re.findall(r'"([A-Za-z][A-Za-z0-9_]*)"', body)
                      if d.startswith("Kamome")}

unspecced = set(declared) - set(allowed)
if unspecced:
    fail("Package.swift declares targets absent from architecture.json: %s"
         % ", ".join(sorted(unspecced)))
    status = 1

for name, deps in sorted(declared.items()):
    if name not in allowed:
        continue
    want = set(allowed[name])
    if deps - want:
        fail("%s depends on %s — not permitted by architecture.json"
             % (name, ", ".join(sorted(deps - want))))
        status = 1
    elif want - deps:
        fail("architecture.json permits %s → %s, but Package.swift does not "
             "declare it. Remove the stale edge from the spec."
             % (name, ", ".join(sorted(want - deps))))
        status = 1

if status == 0:
    ok("dependency graph matches architecture.json (%d modules)" % len(allowed))

# 2. Each confined SDK is imported only under its declared path.
for sdk, path in sorted(confined.items()):
    out = subprocess.run(
        ["grep", "-rl", "--include=*.swift", "^import %s$" % sdk, "App", "Core", "UI"],
        capture_output=True, text=True).stdout
    files = [f for f in out.split() if f]
    stray = [f for f in files if not (f == path or f.startswith(path))]
    if stray:
        fail("import %s outside %s:" % (sdk, path))
        for f in stray:
            print("          %s" % f, file=sys.stderr)
        status = 1
    elif not files:
        fail("import %s appears nowhere — the confinement rule is dead, "
             "remove it from architecture.json" % sdk)
        status = 1
    else:
        ok("import %s confined to %s (%d file%s)"
           % (sdk, path, len(files), "" if len(files) == 1 else "s"))

sys.exit(status)
PY
