#!/usr/bin/env bash
# Claude Code + automatic GitHub account switching (macOS / Linux)
# Run:   bash install.sh
#   or:  curl -fsSL https://raw.githubusercontent.com/us-urvin/claude-gh-accounts/main/install.sh | bash
# Safe to run again any time to add accounts or change folders.

# Everything lives inside main(), called on the last line, so that with "curl | bash"
# the whole file is downloaded before anything runs (no half-run scripts, and no
# command can accidentally swallow the rest of the script from stdin).
main() {
set -u
REPO_URL="https://github.com/us-urvin/claude-gh-accounts"
MAP_FILE="$HOME/.claude-gh-accounts"
BLOCK_START="# >>> claude-gh-accounts >>>"
BLOCK_END="# <<< claude-gh-accounts <<<"

c_cyan=$'\033[36m'; c_green=$'\033[32m'; c_yellow=$'\033[33m'; c_red=$'\033[31m'; c_off=$'\033[0m'
step() { printf '\n%s== Step %s: %s ==%s\n' "$c_cyan" "$1" "$2" "$c_off"; }
ok()   { printf '  %s[ok]%s %s\n' "$c_green" "$c_off" "$1"; }
info() { printf '  %s\n' "$1"; }
warn() { printf '  %s[!]%s %s\n' "$c_yellow" "$c_off" "$1"; }
fail() { printf '  %s[x]%s %s\n' "$c_red" "$c_off" "$1"; exit 1; }
has()  { command -v "$1" >/dev/null 2>&1; }

# Read from the keyboard even when the script is piped (curl ... | bash)
ask() {
  local q="$1" def="${2:-}" ans=""
  if [ -n "$def" ]; then printf '  %s [%s]: ' "$q" "$def" >/dev/tty; else printf '  %s: ' "$q" >/dev/tty; fi
  read -r ans </dev/tty || true
  printf '%s' "${ans:-$def}"
}
ask_yes() { case "$(ask "$1 (y/n)" "${2:-y}")" in y|Y|yes|YES|Yes) return 0 ;; *) return 1 ;; esac; }

[ -r /dev/tty ] || fail "This script needs a terminal to ask questions. Run it from a terminal window."

# A token in the environment would hide the accounts gh stores, and blocks "gh auth login".
# (This happens if you run the setup from inside a "claude" session.)
unset GH_TOKEN GITHUB_TOKEN

printf '%sClaude Code setup with automatic GitHub account switching%s\n' "$c_cyan" "$c_off"
info "Answer the questions as they come. You can stop with Ctrl+C and run this again later."

# ---------------------------------------------------------------- Step 1
step 1 "Checking your system"
OS="$(uname -s)"; ARCH="$(uname -m)"
case "$OS" in
  Darwin) OS_NAME="macOS" ;;
  Linux)  OS_NAME="Linux" ;;
  *) fail "This script is for macOS or Linux. On Windows, use install.ps1 instead." ;;
esac
ok "$OS_NAME, $ARCH"

PKG=""
if [ "$OS_NAME" = "macOS" ]; then
  if ! has brew; then
    warn "Homebrew (the macOS package installer) is not installed."
    if ask_yes "Install Homebrew now? It will ask for your Mac password" y; then
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" </dev/tty
      [ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
      [ -x /usr/local/bin/brew ] && eval "$(/usr/local/bin/brew shellenv)"
    fi
  fi
  has brew && PKG="brew"
else
  for p in apt-get dnf pacman zypper; do has "$p" && { PKG="$p"; break; }; done
fi
if [ -n "$PKG" ]; then ok "Package installer: $PKG"; else warn "No package installer found; missing tools must be installed by hand."; fi

install_pkg() { # $1 = friendly name, then per-manager package names: brew apt dnf pacman zypper
  local name="$1"
  info "Installing $name (you may be asked for your password)..."
  case "$PKG" in
    brew)    brew install "$2" ;;
    apt-get) sudo apt-get update -qq && sudo apt-get install -y "$3" ;;
    dnf)     sudo dnf install -y "$4" ;;
    pacman)  sudo pacman -S --noconfirm "$5" ;;
    zypper)  sudo zypper install -y "$6" ;;
    *) fail "Please install $name yourself, then run this script again." ;;
  esac
}

has curl || install_pkg "curl" curl curl curl curl curl
has curl || fail "curl is missing. Install it, then run this script again."

# ---------------------------------------------------------------- Step 2
step 2 "Git"
has git || install_pkg "Git" git git git git git
has git || fail "Git is still missing. Install it, then run this script again."
ok "$(git --version)"

# ---------------------------------------------------------------- Step 3
step 3 "GitHub CLI (gh)"
gh_ok_version() {
  local v maj min
  v="$(gh --version 2>/dev/null | head -n1 | sed -E 's/[^0-9]*([0-9]+)\.([0-9]+).*/\1 \2/')"
  maj="${v% *}"; min="${v#* }"
  case "$maj$min" in ''|*[!0-9]*) return 1 ;; esac
  [ "$maj" -gt 2 ] || { [ "$maj" -eq 2 ] && [ "$min" -ge 40 ]; }
}
install_gh_apt() {
  info "Adding GitHub's official package source..."
  sudo mkdir -p -m 755 /etc/apt/keyrings
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
  sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  sudo apt-get update -qq && sudo apt-get install -y gh
}
if ! has gh || ! gh_ok_version; then
  has gh && info "Your gh is too old for multiple accounts (needs 2.40+). Updating..."
  case "$PKG" in
    apt-get) install_gh_apt ;;
    brew)    if has gh; then brew upgrade gh; else brew install gh; fi ;;
    *)       install_pkg "GitHub CLI" gh gh gh github-cli gh ;;
  esac
  hash -r
fi
{ has gh && gh_ok_version; } || fail "GitHub CLI 2.40 or newer is needed. See https://cli.github.com, then run this script again."
ok "$(gh --version | head -n1)"

# ---------------------------------------------------------------- Step 4
step 4 "Claude Code"
export PATH="$HOME/.local/bin:$PATH"
if has claude && claude --version >/dev/null 2>&1 </dev/null; then
  ok "Claude Code works: $(claude --version 2>/dev/null </dev/null | head -n1)"
else
  has claude && warn "Found a Claude Code install that doesn't run: $(command -v claude). Reinstalling."
  if has npm && npm ls -g @anthropic-ai/claude-code >/dev/null 2>&1; then
    info "Removing old npm copy..."; npm uninstall -g @anthropic-ai/claude-code >/dev/null 2>&1 || true
  fi
  info "Installing Claude Code with the official installer..."
  curl -fsSL https://claude.ai/install.sh | bash
  hash -r
  { has claude && claude --version >/dev/null 2>&1 </dev/null; } || fail "Claude Code didn't install correctly. Copy the messages above and ask for help."
  ok "Claude Code installed: $(claude --version 2>/dev/null </dev/null | head -n1)"
fi

# ---------------------------------------------------------------- Step 5
step 5 "Your GitHub accounts"
info "Each GitHub account gets its own folder. Any repo inside that folder automatically"
info "uses that account for commits, clones, pushes and pull requests."
info ""
printf '  %sIMPORTANT:%s when the browser opens to log in, check it is signed in to the\n' "$c_yellow" "$c_off"
info "RIGHT GitHub account. If not, sign out there first or paste the link in a private window."

# Map file format, one line per account:  folder|github-user|label
first_run=1; [ -s "$MAP_FILE" ] && first_run=0
touch "$MAP_FILE"
if [ -s "$MAP_FILE" ]; then
  info ""; info "Already set up:"
  while IFS='|' read -r f u _; do [ -n "$f" ] && info "  $f  ->  $u"; done < "$MAP_FILE"
fi

# gh's own login can point all of github.com at gh's *active* account, placed after (and
# overriding) the per-folder settings. Remove it; the per-folder helpers replace it.
remove_global_gh_helper() {
  if git config --global --get-all credential.https://github.com.helper 2>/dev/null \
       | grep -Eq "gh(\.exe)?['\"]?[[:space:]]+auth[[:space:]]+git-credential"; then
    git config --global --unset-all credential.https://github.com.helper
    git config --global --unset-all credential.https://gist.github.com.helper 2>/dev/null || true
    ok "Removed a global gh git setting that would override the per-folder accounts"
  fi
}

default_name="$(git config --global user.name 2>/dev/null || true)"
another=0
if [ -s "$MAP_FILE" ]; then ask_yes "Add or update an account now?" y && another=1; else another=1; fi

while [ "$another" -eq 1 ]; do
  echo
  label="$(ask "Short name for this account (e.g. work, personal, client1)" "" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')"
  [ -z "$label" ] && { warn "Please use letters or numbers."; continue; }
  user="$(ask "GitHub username for this account" "")"
  if ! printf '%s' "$user" | grep -Eq '^[A-Za-z0-9]([A-Za-z0-9-]{0,38})$'; then
    warn "That doesn't look like a GitHub username (letters, numbers and dashes only)."; continue
  fi
  folder="$(ask "Folder for this account's repos" "$HOME/code/$label")"
  folder="${folder/#\~/$HOME}"
  case "$folder" in *'|'*) warn "The folder name can't contain '|'."; continue ;; esac
  mkdir -p "$folder" || { warn "Couldn't create $folder"; continue; }
  folder="$(cd "$folder" && pwd)"
  [ "$folder" = "/" ] || [ "$folder" = "$HOME" ] && { warn "Pick a dedicated folder, not $folder itself."; continue; }
  name="$(ask "Name to show on commits" "$default_name")"
  [ -z "$name" ] && { warn "A name is required (git won't commit without one)."; continue; }
  email="$(ask "Email for commits (one that belongs to this GitHub account)" "")"
  case "$email" in *?@?*) ;; *) warn "Please enter a valid email address."; continue ;; esac

  if gh auth token --user "$user" >/dev/null 2>&1; then
    ok "Already logged in to GitHub as $user"
  else
    while true; do
      info "Logging in as '$user'. Follow the prompts; a browser will open."
      gh auth login --hostname github.com --git-protocol https --web </dev/tty
      if gh auth token --user "$user" >/dev/null 2>&1; then ok "Logged in as $user"; break; fi
      who="$(gh api user --jq .login 2>/dev/null || true)"
      # GitHub usernames aren't case sensitive, but gh stores them exactly as GitHub spells them
      if [ -n "$who" ] && [ "$(printf '%s' "$who" | tr '[:upper:]' '[:lower:]')" = "$(printf '%s' "$user" | tr '[:upper:]' '[:lower:]')" ]; then
        user="$who"; ok "Logged in as $user"; break
      fi
      warn "That login was for '${who:-unknown}', not '$user'."
      [ -n "$who" ] && info "(To remove the wrong one later: gh auth logout --user $who)"
      ask_yes "Try logging in again?" y || { warn "Skipped. Run this script again to finish logging in as $user."; break; }
    done
  fi

  # Per-folder git settings: commit identity + which account git uses for github.com
  cfg="$HOME/.gitconfig-$label"
  rm -f "$cfg"
  git config --file "$cfg" user.name "$name"
  git config --file "$cfg" user.email "$email"
  git config --file "$cfg" --add 'credential.https://github.com.helper' ''
  git config --file "$cfg" --add 'credential.https://github.com.helper' \
    "!f() { test \"\$1\" = get && echo \"username=$user\" && echo \"password=\$(gh auth token --user $user)\"; }; f"

  # Forget earlier entries for this folder or this label (e.g. the label moved to a new folder)
  tmp="$(mktemp)"
  while IFS='|' read -r f u l; do
    [ -z "$f" ] && continue
    [ "$f" = "$folder" ] && continue
    old_cfg="$(git config --global --get "includeIf.gitdir/i:$f/.path" 2>/dev/null || true)"
    if [ "$l" = "$label" ] || [ "$old_cfg" = "$cfg" ]; then
      git config --global --unset-all "includeIf.gitdir/i:$f/.path" 2>/dev/null || true
      info "No longer using $f for '$label'"
      continue
    fi
    printf '%s|%s|%s\n' "$f" "$u" "$l" >> "$tmp"
  done < "$MAP_FILE"
  printf '%s|%s|%s\n' "$folder" "$user" "$label" >> "$tmp"
  mv "$tmp" "$MAP_FILE"
  git config --global --replace-all "includeIf.gitdir/i:$folder/.path" "$cfg"
  ok "Repos in $folder will use GitHub '$user' and commit as $name <$email>"

  remove_global_gh_helper
  ask_yes "Add another GitHub account?" n && another=1 || another=0
done
[ -s "$MAP_FILE" ] || fail "No accounts set up yet. Run this script again when you're ready."
remove_global_gh_helper

# ---------------------------------------------------------------- Step 6
step 6 'Installing the smart "claude" command'
LAUNCHER="$(cat <<'EOF'
# >>> claude-gh-accounts >>>
# Starts Claude Code with the GitHub account that matches the current folder.
# Managed by install.sh: run that script again to change accounts.
unalias claude 2>/dev/null
claude() {
  local map="$HOME/.claude-gh-accounts" here="${PWD%/}/" user="" best=0 f u l tok
  if [ -f "$map" ]; then
    while IFS='|' read -r f u l; do
      if [ -z "$f" ] || [ -z "$u" ]; then continue; fi
      f="${f%/}/"
      case "$here" in "$f"*) if [ ${#f} -gt $best ]; then user="$u"; best=${#f}; fi ;; esac
    done < "$map"
  fi
  if [ -n "$user" ]; then
    if tok="$(command gh auth token --user "$user" 2>/dev/null)" && [ -n "$tok" ]; then
      printf '\033[36mGitHub account: %s\033[0m\n' "$user"
      GH_TOKEN="$tok" command claude "$@"
      return
    fi
    printf '\033[33mNot logged in to GitHub as %s. Run: gh auth login\033[0m\n' "$user"
  fi
  command claude "$@"
}
# <<< claude-gh-accounts <<<
EOF
)"

rc_files=()
case "$(basename "${SHELL:-bash}")" in
  zsh)  rc_files=("$HOME/.zshrc") ;;
  bash) rc_files=("$HOME/.bashrc"); [ "$OS_NAME" = "macOS" ] && rc_files+=("$HOME/.bash_profile") ;;
  *)    rc_files=("$HOME/.bashrc" "$HOME/.zshrc") ;;
esac
for rc in "${rc_files[@]}"; do
  touch "$rc"
  tmp="$(mktemp)"
  awk -v s="$BLOCK_START" -v e="$BLOCK_END" '$0==s{skip=1} !skip{print} $0==e{skip=0}' "$rc" > "$tmp" && cat "$tmp" > "$rc"
  rm -f "$tmp"
  # shellcheck disable=SC2016  # $HOME/$PATH must stay literal: they expand when the rc file runs
  grep -q '.local/bin' "$rc" || printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$rc"
  printf '\n%s\n' "$LAUNCHER" >> "$rc"
  ok "Added to $rc"
done

# ---------------------------------------------------------------- Step 7
step 7 "All done"
info "Your accounts:"
while IFS='|' read -r f u _; do [ -n "$f" ] && info "  $f  ->  GitHub: $u"; done < "$MAP_FILE"
first_folder="$(head -n1 "$MAP_FILE" | cut -d'|' -f1)"
cat <<EOF

  What to do now:
  1. Close this terminal and open a NEW one.
  2. Put repos inside the matching folder, for example:
       cd "$first_folder"
       git clone https://github.com/OWNER/REPO.git
  3. Go into the repo and type:  claude
     You'll see "GitHub account: <name>". The first time, Claude asks you to log in.
  4. To double-check, ask Claude to run:  gh api user --jq .login

  Repos outside these folders keep working exactly as before.
  Run this script again any time to add an account or change a folder.
EOF

# ---------------------------------------------------------------- Star
printf '\n  %s* Did this save you time? A GitHub star helps other people find it:%s\n' "$c_yellow" "$c_off"
info "  $REPO_URL"
if [ "$first_run" -eq 1 ] && ask_yes "Open it in your browser now?" y; then
  open_url "$REPO_URL"
fi
}

# Open a web page in the default browser, or just print it if there is no browser.
open_url() {
  if [ "$(uname -s)" = "Darwin" ] && has open; then open "$1" >/dev/null 2>&1 && return
  elif has wslview; then wslview "$1" >/dev/null 2>&1 && return
  elif has xdg-open && { [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; }; then
    xdg-open "$1" >/dev/null 2>&1 & return
  fi
  info "Couldn't open a browser here. Copy the link above instead."
}

main "$@"
