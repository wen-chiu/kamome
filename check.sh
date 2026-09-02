#!/usr/bin/env bash
#
#   ./check.sh                      everything — static gates, lint, build, tests
#   ./check.sh --static             only the gates that need no Xcode (any machine, CI, a container)
#   ./check.sh --release <artifact> everything, plus the gates that only bind at a release
#
# This is the definition of done. Nothing is "fixed", "working" or "ready for
# review" until this exits 0.
#
# It never skips a stage quietly. A missing tool is a failure, not a pass with a
# gap in it — a check that silently does nothing is the worst kind, because it
# reports success and measures nothing.
set -uo pipefail
cd "$(dirname "$0")"

static_only=0
release_artifact=""
case "${1:-}" in
  --static)  static_only=1 ;;
  --release)
    release_artifact="${2:-}"
    if [ -z "$release_artifact" ]; then
      printf 'usage: ./check.sh --release <path to .ipa or .xcarchive>\n' >&2
      printf 'The release gates check the ARTIFACT, so they need one.\n' >&2
      exit 2
    fi
    ;;
  "") ;;
  *) printf 'unknown option: %s\n' "$1" >&2; exit 2 ;;
esac

failures=()
stage() { printf '\n\033[1m%s\033[0m\n' "$*"; }
record() { [ "$1" -eq 0 ] || failures+=("$2"); }

require() {
  command -v "$1" >/dev/null 2>&1 && return 0
  printf '  \033[31mFAIL\033[0m  %s is not installed — %s\n' "$1" "$2" >&2
  failures+=("$1 missing")
  return 1
}

stage "Gates"
for check in Scripts/check-*.sh; do
  "$check"
  record $? "$(basename "$check")"
done

if [ "$static_only" -eq 1 ]; then
  printf '\n\033[33mSTATIC ONLY\033[0m — lint, build and tests did NOT run. This is not a\n'
  printf 'complete check and must not be reported as one.\n'
else
  stage "Project"
  if require xcodegen "brew install xcodegen"; then
    xcodegen generate
    record $? "xcodegen"
  fi

  stage "Lint"
  if require swiftlint "brew install swiftlint"; then
    # Rosetta swiftlint cannot load Xcode 26's arm64-only SourceKit.
    XCODE_DEFAULT_TOOLCHAIN_OVERRIDE=${XCODE_DEFAULT_TOOLCHAIN_OVERRIDE:-/Library/Developer/CommandLineTools} \
      swiftlint --strict
    record $? "swiftlint"
  fi

  stage "Tests"
  if require xcodebuild "Xcode is required to run the suite"; then
    destination=${KAMOME_TEST_DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro}
    set -o pipefail
    xcodebuild -scheme Kamome test -destination "$destination" CODE_SIGNING_ALLOWED=NO
    record $? "xcodebuild test"
  fi

  # Gates that only bind at a release. They are separated because they fail on
  # work that is scheduled rather than broken, and a `main` that is permanently
  # red teaches everyone to ignore it (HANDOFF.md, "a red check means something
  # now"). Separated is not optional — see the banner below.
  if [ -n "$release_artifact" ]; then
    stage "Release"
    for check in Scripts/release/check-*.sh; do
      "$check" "$release_artifact"
      record $? "$(basename "$check")"
    done
  else
    printf '\n\033[33mRELEASE GATES DID NOT RUN\033[0m — attribution, the privacy notice and the\n'
    printf 'key scan of the built artifact are checked only by:\n'
    printf '    ./check.sh --release <path to .ipa or .xcarchive>\n'
    printf 'They are release blockers, not optional. Docs/release-readiness.md.\n'
  fi
fi

printf '\n'
if [ ${#failures[@]} -eq 0 ]; then
  printf '\033[32mAll checks passed.\033[0m\n'
  exit 0
fi
printf '\033[31m%d check(s) failed:\033[0m %s\n' "${#failures[@]}" "${failures[*]}" >&2
exit 1
