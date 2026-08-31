#!/usr/bin/env bash
# Shared reporting helpers for the check scripts. Sourced, never executed.
#
# Every check prints one line saying what it verified, so a green run is a
# readable list of guarantees rather than silence.

kamome_ok()   { printf '  \033[32mok\033[0m    %s\n' "$*"; }
kamome_fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$*" >&2; }
kamome_info() { printf '        %s\n' "$*"; }
