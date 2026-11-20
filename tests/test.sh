#!/usr/bin/env bash
# Tests for install.sh: the "claude" launcher and the per-folder git config.
# Runs in a throwaway HOME with fake "gh" and "claude" commands. Nothing real is touched.
# Usage: bash tests/test.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/install.sh"
pass=0; failed=0
check() { # $1 = description, $2 = expected, $3 = actual
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); printf '  ok   %s\n' "$1"
  else failed=$((failed + 1)); printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"; fi
}

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
BIN="$T/bin"
if command -v cygpath >/dev/null 2>&1; then # Git Bash on Windows: give native git C:/ paths
  export MSYS2_ARG_CONV_EXCL='*'; T="$(cygpath -m "$T")"
fi
export HOME="$T" GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
mkdir -p "$T/bin"
# shellcheck disable=SC2016  # $1, $4 and $GH_TOKEN expand when the fake commands run
printf '#!/bin/sh\n[ "$1 $2" = "auth token" ] && [ "$4" != "nobody" ] && echo "TOKEN-for-$4"\n' > "$T/bin/gh"
# shellcheck disable=SC2016
printf '#!/bin/sh\necho "GH_TOKEN=${GH_TOKEN:-none}"\n' > "$T/bin/claude"
chmod +x "$T/bin/gh" "$T/bin/claude"
export PATH="$BIN:$PATH"

echo "Launcher"
sed -n '/^# >>> claude-gh-accounts >>>$/,/^# <<< claude-gh-accounts <<<$/p' "$SCRIPT" > "$T/launcher.sh"
[ -s "$T/launcher.sh" ] || { echo "  FAIL could not extract launcher"; exit 1; }
mkdir -p "$T/code/work/repo" "$T/code/workshop" "$T/code/work/client/x" "$T/code/ghost" "$T/elsewhere"
LT="$(cd "$T" && pwd)" # the path as the shell sees it ($PWD)
{
  printf '%s|alice|work\n' "$LT/code/work"
  printf '%s|bob\n' "$LT/code/workshop"            # old two-field format
  printf '%s|carol|client\n' "$LT/code/work/client"
  printf '%s|nobody|ghost\n' "$LT/code/ghost"
} > "$T/.claude-gh-accounts"
run() { bash -c "cd '$LT/$1' && source '$LT/launcher.sh' && claude" 2>&1 | tail -n1; }
check "repo inside folder uses its account"      "GH_TOKEN=TOKEN-for-alice" "$(run code/work/repo)"
check "similar folder name is not confused"      "GH_TOKEN=TOKEN-for-bob"   "$(run code/workshop)"
check "nested folder: longest match wins"        "GH_TOKEN=TOKEN-for-carol" "$(run code/work/client/x)"
check "not logged in: runs without a token"      "GH_TOKEN=none"            "$(run code/ghost)"
check "outside all folders: no token"            "GH_TOKEN=none"            "$(run elsewhere)"
out="$(bash -O expand_aliases -c "cd '$LT/code/work' && alias claude=false && source '$LT/launcher.sh' && claude" 2>&1 | tail -n1)"
check "an old 'claude' alias doesn't break it"   "GH_TOKEN=TOKEN-for-alice" "$out"

echo "Git config"
: > "$T/.claude-gh-accounts"; MAP_FILE="$T/.claude-gh-accounts"
ok() { :; }; info() { :; }; pretty() { printf '%s' "$1"; }
# shellcheck disable=SC2034  # color codes used by configure()
B="" R=""
blk="$(sed -n '/# Per-folder git settings/,/ok "Repos in/p' "$SCRIPT")"
eval "configure() { $blk
}"
eval "$(sed -n '/^remove_global_gh_helper() {/,/^}/p' "$SCRIPT")"
fill() { printf 'protocol=https\nhost=github.com\n\n' | git -C "$1" credential fill 2>/dev/null | grep -E '^(username|password)=' | tr '\n' ' '; }

# shellcheck disable=SC2034  # read by configure()
label=work user=alice name="Alice A" email=alice@example.com folder="$T/w"
mkdir -p "$folder/r" && git -C "$folder/r" init -q && configure
check "commit name"                     "Alice A"           "$(git -C "$T/w/r" config user.name)"
check "commit email"                    "alice@example.com" "$(git -C "$T/w/r" config user.email)"
check "credentials come from gh"        "username=alice password=TOKEN-for-alice " "$(fill "$T/w/r")"

git config --global --add credential.https://github.com.helper ''
git config --global --add credential.https://github.com.helper "!'C:\\Program Files\\GitHub CLI\\gh.exe' auth git-credential"
remove_global_gh_helper
check "gh's global helper is removed (Windows format)" "" "$(git config --global --get-all credential.https://github.com.helper)"
check "credentials still per-folder after gh login"   "username=alice password=TOKEN-for-alice " "$(fill "$T/w/r")"

folder="$T/w2"; mkdir -p "$folder/r" && git -C "$folder/r" init -q && configure
check "label moved: new folder mapped"   "alice@example.com" "$(git -C "$T/w2/r" config user.email)"
check "label moved: old folder unmapped" ""                  "$(git -C "$T/w/r" config user.email)"
check "label moved: map has one entry"   "$T/w2|alice|work"  "$(cat "$MAP_FILE")"

# shellcheck disable=SC2034
label=personal user=al-home name="Al" email=al@example.org folder="$T/p"
mkdir -p "$folder/r" && git -C "$folder/r" init -q && configure
check "second account is separate"       "username=al-home password=TOKEN-for-al-home " "$(fill "$T/p/r")"
check "first account unaffected"         "username=alice password=TOKEN-for-alice "     "$(fill "$T/w2/r")"

echo
echo "$pass passed, $failed failed"
[ "$failed" -eq 0 ]
