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

T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
BIN="$T/bin"
if command -v cygpath >/dev/null 2>&1; then # Git Bash on Windows: give native git C:/ paths
  export MSYS2_ARG_CONV_EXCL='*'; T="$(cygpath -m "$T")"
fi
export HOME="$T" GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
mkdir -p "$T/bin"
# shellcheck disable=SC2016  # $1, $4 and $GH_TOKEN expand when the fake commands run
printf '%s\n' '#!/bin/sh' \
  'case "$1 $2" in' \
  '  "auth token") [ "$4" != "nobody" ] && echo "TOKEN-for-$4" ;;' \
  '  "auth git-credential") [ "$3" = get ] && { echo username=active-user; echo password=TOKEN-active; } ;;' \
  "  \"ssh-key add\") touch '$T/uploaded' ;;" \
  '  "auth status") printf "  + Logged in to github.com account sam (keyring)\n  X Failed to log in to github.com account old (default)\n  + Logged in to github.com account al-home (keyring)\n" ;;' \
  '  "api user") printf "12345\tsam\tSam Smith\t\n" ;;' \
  'esac' > "$T/bin/gh"
# Fake ssh: records how git called it (to check which key is used). For "ssh -T" (the key
# check) it answers like GitHub once a key was uploaded: "Hi <user>! ..."
printf '%s\n' '#!/bin/sh' \
  "echo \"\$@\" >> '$T/ssh.log'" \
  "case \" \$* \" in *' -T '*) [ -f '$T/uploaded' ] && echo \"Hi \${FAKE_WHO:-sam}! You've successfully authenticated\" >&2 ;; esac" \
  'exit 1' > "$T/bin/ssh"
chmod +x "$T/bin/ssh"
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
if ! command -v cygpath >/dev/null 2>&1; then # real symlinks aren't available in Git Bash on Windows
  ln -s "$LT/code/work" "$LT/shortcut"
  check "folder reached through a symlink"       "GH_TOKEN=TOKEN-for-alice" "$(run shortcut/repo)"
fi

echo "Git config"
: > "$T/.claude-gh-accounts"; MAP_FILE="$T/.claude-gh-accounts"
ok() { :; }; info() { :; }; pretty() { printf '%s' "$1"; }
# shellcheck disable=SC2034  # color codes and repo link used by configure()
B="" R="" REPO_URL="https://github.com/us-urvin/claude-gh-accounts"
blk="$(sed -n '/# Per-folder git settings/,/ok "Repos in/p' "$SCRIPT")"
eval "configure() { $blk
}"
eval "$(sed -n '/^put_accounts_last() {/,/^}/p' "$SCRIPT")"
fill() { printf 'protocol=https\nhost=github.com\n\n' | git -C "$1" credential fill 2>/dev/null | grep -E '^(username|password)=' | tr '\n' ' '; }

# shellcheck disable=SC2034  # read by configure()
label=work user=alice name="Alice A" email=alice@example.com folder="$T/w" ssh_key=""
mkdir -p "$folder/r" && git -C "$folder/r" init -q && configure
check "commit name"                     "Alice A"           "$(git -C "$T/w/r" config user.name)"
check "commit email"                    "alice@example.com" "$(git -C "$T/w/r" config user.email)"
check "credentials come from gh"        "username=alice password=TOKEN-for-alice " "$(fill "$T/w/r")"
hint="$(printf 'protocol=https\nhost=github.com\nusername=alice\npassword=bad\n\n' | git -C "$T/w/r" credential reject 2>&1)"
case "$hint" in *"did not accept the saved login for alice"*"#-troubleshooting"*) hint=ok ;; esac
check "rejected login prints a helpful hint" "ok" "$hint"

# "gh auth login" adds its global setting *below* the per-folder entries, which would override them
git config --global --add credential.https://github.com.helper ''
git config --global --add credential.https://github.com.helper '!gh auth git-credential'
mkdir -p "$T/outside/r" && git -C "$T/outside/r" init -q
check "without the fix, gh's setting overrides the folder" "username=active-user password=TOKEN-active " "$(fill "$T/w/r")"
put_accounts_last
check "after the fix, the folder's account wins"       "username=alice password=TOKEN-for-alice " "$(fill "$T/w/r")"
check "outside folders: gh's setting still works"      "username=active-user password=TOKEN-active " "$(fill "$T/outside/r")"
check "outside folders: commit identity untouched"     "" "$(git -C "$T/outside/r" config user.email)"

folder="$T/w2"; mkdir -p "$folder/r" && git -C "$folder/r" init -q && configure
check "label moved: new folder mapped"   "alice@example.com" "$(git -C "$T/w2/r" config user.email)"
check "label moved: old folder unmapped" ""                  "$(git -C "$T/w/r" config user.email)"
check "label moved: map has one entry"   "$T/w2|alice|work"  "$(cat "$MAP_FILE")"

# shellcheck disable=SC2034
label=personal user=al-home name="Al" email=al@example.org folder="$T/p"
mkdir -p "$folder/r" && git -C "$folder/r" init -q && configure
check "second account is separate"       "username=al-home password=TOKEN-for-al-home " "$(fill "$T/p/r")"
check "first account unaffected"         "username=alice password=TOKEN-for-alice "     "$(fill "$T/w2/r")"

echo "SSH"
# shellcheck disable=SC2034
label=sshacct user=sam name="Sam" email=sam@example.com folder="$T/s" ssh_key="$T/keys/claude-gh-sshacct"
mkdir -p "$folder" && configure
: > "$T/ssh.log"
git -C "$folder" clone -q git@github.com:sam/project.git 2>/dev/null
check "clone in the folder uses the account's key" "yes" "$(grep -q -- "-i $ssh_key -o IdentitiesOnly=yes" "$T/ssh.log" && echo yes)"
: > "$T/ssh.log"
git -C "$T/outside/r" ls-remote git@github.com:sam/project.git >/dev/null 2>&1
check "outside folders: ssh untouched (no -i)"   "" "$(grep -- "-i " "$T/ssh.log")"
check "HTTPS still works in an SSH account"      "username=sam password=TOKEN-for-sam " "$(mkdir -p "$folder/r" && git -C "$folder/r" init -q && fill "$folder/r")"

if command -v ssh-keygen >/dev/null 2>&1; then
  # The installer's SSH setup: create key -> upload with gh -> confirm GitHub sees the right account
  for fn in ssh_whoami trust_github_host setup_ssh; do eval "$(sed -n "/^$fn() {/,/^}/p" "$SCRIPT")"; done
  eval "$(sed -n '/^same_user() {/p' "$SCRIPT")"
  has() { command -v "$1" >/dev/null 2>&1; }; warn() { :; }; dim() { :; }; ask() { printf ''; }
  # shellcheck disable=SC2034
  CYN="" S_ARROW="" D=""
  rm -f "$T/uploaded"
  setup_ssh newacct sam >/dev/null 2>&1
  check "SSH setup: creates a key"                "yes" "$([ -f "$T/.ssh/claude-gh-newacct" ] && [ -f "$T/.ssh/claude-gh-newacct.pub" ] && echo yes)"
  check "SSH setup: uploads it to GitHub"         "yes" "$([ -f "$T/uploaded" ] && echo yes)"
  check "SSH setup: key confirmed for the account" "$T/.ssh/claude-gh-newacct" "$ssh_key"
  FAKE_WHO=someone-else setup_ssh newacct sam >/dev/null 2>&1
  check "SSH setup: refuses a key of another account" "" "$ssh_key"
fi

echo "Smart defaults (fewer questions)"
for fn in gh_logged_in_users github_profile existing_account; do eval "$(sed -n "/^$fn() {/,/^}/p" "$SCRIPT")"; done
eval "$(sed -n '/^same_user() {/p' "$SCRIPT")"
gh_name="" gh_email="" ex_label="" ex_folder="" ex_name="" ex_email="" ex_ssh=""  # set by the functions above
check "finds accounts logged in on this computer" "sam al-home" "$(gh_logged_in_users | tr '\n' ' ' | sed 's/ *$//')"
github_profile sam
check "name comes from the GitHub profile"        "Sam Smith" "$gh_name"
check "private email -> GitHub no-reply address"  "12345+sam@users.noreply.github.com" "$gh_email"
existing_account AL-HOME
check "re-run: remembers nickname (any case)"     "personal" "$ex_label"
check "re-run: remembers folder"                  "$T/p" "$ex_folder"
check "re-run: remembers name and email"          "Al <al@example.org>" "$ex_name <$ex_email>"
existing_account sam
check "re-run: remembers SSH"                     "yes" "$([ -n "$ex_ssh" ] && echo yes)"
existing_account nobody-new
check "new account: nothing pre-filled"           "" "$ex_label$ex_folder$ex_name$ex_email"

echo
echo "$pass passed, $failed failed"
[ "$failed" -eq 0 ]
