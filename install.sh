#!/usr/bin/env bash
# claude-gh-accounts: use several GitHub accounts with Claude Code (macOS / Linux)
# https://github.com/us-urvin/claude-gh-accounts
#
# Run:   bash install.sh
#   or:  curl -fsSL https://github.com/us-urvin/claude-gh-accounts/releases/latest/download/install.sh | bash
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
TOTAL_STEPS=6

# ================================================================ Look & feel
# Colors only on a real terminal (and never when NO_COLOR is set).
# Fancy symbols only when the terminal speaks UTF-8; otherwise plain ASCII.
R=""; B=""; D=""; GRN=""; YEL=""; RED=""; CYN=""; MAG=""; G1=""; G2=""; G3=""; G4=""; G5=""
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != "dumb" ]; then
  R=$'\033[0m'; B=$'\033[1m'; D=$'\033[2m'
  GRN=$'\033[32m'; YEL=$'\033[33m'; RED=$'\033[31m'; CYN=$'\033[36m'; MAG=$'\033[35m'
  if [ "$(tput colors 2>/dev/null || echo 8)" -ge 256 ] 2>/dev/null; then
    G1=$'\033[38;5;213m'; G2=$'\033[38;5;177m'; G3=$'\033[38;5;141m'; G4=$'\033[38;5;111m'; G5=$'\033[38;5;87m'
    GRN=$'\033[38;5;84m'; YEL=$'\033[38;5;221m'; RED=$'\033[38;5;203m'; CYN=$'\033[38;5;87m'; MAG=$'\033[38;5;213m'
  else
    G1="$MAG"; G2="$MAG"; G3="$CYN"; G4="$CYN"; G5="$CYN"
  fi
fi
case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
  *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) FANCY=1 ;;
  *) FANCY=0 ;;
esac
if [ "$FANCY" -eq 1 ]; then
  S_OK="✔"; S_X="✘"; S_WARN="▲"; S_Q="?"; S_ARROW="➜"; S_IN="›"; S_HEART="♥"; S_DOT="●"
  S_ON="■"; S_OFF="□"; TL="╭"; TR="╮"; BL="╰"; BR="╯"; H="─"; V="│"
else
  S_OK="+"; S_X="x"; S_WARN="!"; S_Q="?"; S_ARROW="->"; S_IN=">"; S_HEART="<3"; S_DOT="*"
  S_ON="#"; S_OFF="."; TL="+"; TR="+"; BL="+"; BR="+"; H="-"; V="|"
fi

rep()   { local i=0 out=""; while [ "$i" -lt "$2" ]; do out="$out$1"; i=$((i + 1)); done; printf '%s' "$out"; }
ok()    { printf '  %s%s%s %s\n' "$GRN" "$S_OK" "$R" "$1"; }
info()  { printf '    %s\n' "$1"; }
dim()   { printf '    %s%s%s\n' "$D" "$1" "$R"; }
warn()  { printf '  %s%s%s %s\n' "$YEL" "$S_WARN" "$R" "$1"; }
fail()  {
  printf '\n  %s%s %s%s\n' "$RED$B" "$S_X" "$1" "$R"
  printf '    %sNothing was broken. Fix the problem above, then run the installer again.%s\n\n' "$D" "$R"
  exit 1
}
has()   { command -v "$1" >/dev/null 2>&1; }
pretty() { case "$1" in "$HOME"|"$HOME"/*) printf '~%s' "${1#"$HOME"}" ;; *) printf '%s' "$1" ;; esac; }

# Step header:  ■■■□□□  STEP 3 OF 6
#               GitHub CLI
#               What it is, in plain words.
step() {
  local n="$1" i=1 bar=""
  while [ "$i" -le "$TOTAL_STEPS" ]; do
    if [ "$i" -le "$n" ]; then bar="$bar$G2$S_ON"; else bar="$bar$D$S_OFF$R"; fi
    i=$((i + 1))
  done
  printf '\n\n  %s%s  %sSTEP %s OF %s%s\n' "$bar" "$R" "$D" "$n" "$TOTAL_STEPS" "$R"
  printf '  %s%s%s\n' "$B" "$2" "$R"
  [ -n "${3:-}" ] && printf '  %s%s%s\n' "$D" "$3" "$R"
  printf '\n'
}

# A card with a title and a left border (no right border, so long text never breaks it)
card_top()    { printf '  %s%s%s %s%s%s %s%s\n' "$G3" "$TL" "$H" "$B" "$1" "$R$G3" "$(rep "$H" $((40 - ${#1})))" "$R"; }
card_line()   { printf '  %s%s%s  %s\n' "$G3" "$V" "$R" "$1"; }
card_bottom() { printf '  %s%s%s%s\n' "$G3" "$BL" "$(rep "$H" 43)" "$R"; }

# A closed box for short, fixed text without colors (padded by character count,
# so symbols like the check mark don't push the right border out of line)
box() { # $1 = color, then lines
  local color="$1" w=52 line pad; shift
  printf '  %s%s%s%s%s\n' "$color" "$TL" "$(rep "$H" "$w")" "$TR" "$R"
  for line in "$@"; do
    pad=$((w - 1 - ${#line})); [ "$pad" -lt 0 ] && pad=0
    printf '  %s%s%s %s%s%s%s%s%s\n' "$color" "$V" "$R" "$B" "$line" "$R" "$(rep ' ' "$pad")" "$color$V" "$R"
  done
  printf '  %s%s%s%s%s\n' "$color" "$BL" "$(rep "$H" "$w")" "$BR" "$R"
}

# Questions. They read from the keyboard even when the script is piped (curl ... | bash).
ask() { # $1 = question, $2 = default, $3 = hint (optional)
  local q="$1" def="${2:-}" hint="${3:-}" ans=""
  {
    printf '\n  %s%s%s %s%s%s\n' "$MAG$B" "$S_Q" "$R" "$B" "$q" "$R"
    [ -n "$hint" ] && printf '    %s%s%s\n' "$D" "$hint" "$R"
    if [ -n "$def" ]; then printf '    %s%s%s %s[%s]%s ' "$CYN" "$S_IN" "$R" "$D" "$def" "$R"
    else printf '    %s%s%s ' "$CYN" "$S_IN" "$R"; fi
  } >/dev/tty
  read -r ans </dev/tty || true
  printf '%s' "${ans:-$def}"
}
ask_yes() { # $1 = question, $2 = default y|n
  local def="${2:-y}" hint="(Y/n)" ans=""
  [ "$def" = "n" ] && hint="(y/N)"
  printf '\n  %s%s%s %s%s%s %s%s%s %s%s%s ' "$MAG$B" "$S_Q" "$R" "$B" "$1" "$R" "$D" "$hint" "$R" "$CYN" "$S_IN" "$R" >/dev/tty
  read -r ans </dev/tty || true
  case "${ans:-$def}" in y|Y|yes|YES|Yes) return 0 ;; *) return 1 ;; esac
}

[ -r /dev/tty ] || fail "This installer needs a terminal to ask questions. Please run it from a terminal window."

# A token in the environment would hide the accounts gh stores, and blocks "gh auth login".
# (This happens if you run the setup from inside a "claude" session.)
unset GH_TOKEN GITHUB_TOKEN

# ================================================================ Welcome
printf '\n'
if [ "$FANCY" -eq 1 ]; then
  printf '   %s▄▀▀ █   ▄▀▄ █ █ █▀▄ ██▀    ▄▀  █▄█%s\n' "$G1" "$R"
  printf '   %s▀▄▄ █▄▄ █▀█ ▀▄█ █▄▀ █▄▄ ▀▀ ▀▄█ █ █%s\n' "$G2" "$R"
  printf '   %s▄▀▄ ▄▀▀ ▄▀▀ ▄▀▄ █ █ █▄ █ ▀█▀ ▄▀▀%s\n' "$G4" "$R"
  printf '   %s█▀█ ▀▄▄ ▀▄▄ ▀▄▀ ▀▄█ █ ▀█  █  ▄██%s\n' "$G5" "$R"
else
  printf '   %sclaude-gh-accounts%s\n' "$B$G1" "$R"
fi
printf '\n   %sOne computer. Many GitHub accounts. Zero mix-ups.%s\n\n' "$B" "$R"
dim "This sets things up so each of your GitHub accounts (work, personal, ...)"
dim "gets its own folder. Work inside a folder and everything - commits, pushes"
dim "and Claude Code - automatically uses the right account."
printf '\n'
dim "Takes about 3 minutes. Just answer the questions; press Enter to accept"
dim "the suggestion in [brackets]. Stop any time with Ctrl+C - nothing breaks."

# ================================================================ Step 1
step 1 "Checking your computer" "Making sure we know what we're working with."
OS="$(uname -s)"; ARCH="$(uname -m)"
case "$OS" in
  Darwin) OS_NAME="macOS" ;;
  Linux)  OS_NAME="Linux" ;;
  *) fail "This installer is for macOS or Linux. On Windows, use install.ps1 instead (see the README)." ;;
esac
ok "$OS_NAME on $ARCH"

PKG=""
if [ "$OS_NAME" = "macOS" ]; then
  if ! has brew; then
    warn "Homebrew isn't installed yet. It's the standard way to install tools on a Mac."
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
if [ -n "$PKG" ]; then ok "Can install missing tools with $PKG"; else warn "No package installer found, so missing tools must be installed by hand."; fi

install_pkg() { # $1 = friendly name, then per-manager package names: brew apt dnf pacman zypper
  local name="$1"
  printf '  %s%s%s Installing %s %s(you may be asked for your password)%s\n' "$CYN" "$S_ARROW" "$R" "$name" "$D" "$R"
  case "$PKG" in
    brew)    brew install "$2" ;;
    apt-get) sudo apt-get update -qq && sudo apt-get install -y "$3" ;;
    dnf)     sudo dnf install -y "$4" ;;
    pacman)  sudo pacman -S --noconfirm "$5" ;;
    zypper)  sudo zypper install -y "$6" ;;
    *) fail "Please install $name yourself, then run the installer again." ;;
  esac
}

has curl || install_pkg "curl" curl curl curl curl curl
has curl || fail "curl is missing. Install it, then run the installer again."

has git || install_pkg "Git" git git git git git
has git || fail "Git is still missing. Install it, then run the installer again."
ok "Git is ready $D($(git --version | sed 's/git version //'))$R"

# ================================================================ Step 2
step 2 "GitHub CLI" "GitHub's official tool. It logs you in and keeps your passwords safe."
gh_ok_version() {
  local v maj min
  v="$(gh --version 2>/dev/null | head -n1 | sed -E 's/[^0-9]*([0-9]+)\.([0-9]+).*/\1 \2/')"
  maj="${v% *}"; min="${v#* }"
  case "$maj$min" in ''|*[!0-9]*) return 1 ;; esac
  [ "$maj" -gt 2 ] || { [ "$maj" -eq 2 ] && [ "$min" -ge 40 ]; }
}
install_gh_apt() {
  printf '  %s%s%s Adding GitHub'"'"'s official package source\n' "$CYN" "$S_ARROW" "$R"
  sudo mkdir -p -m 755 /etc/apt/keyrings
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
  sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  sudo apt-get update -qq && sudo apt-get install -y gh
}
if ! has gh || ! gh_ok_version; then
  has gh && warn "Your GitHub CLI is too old for multiple accounts (needs 2.40+). Updating it."
  case "$PKG" in
    apt-get) install_gh_apt ;;
    brew)    if has gh; then brew upgrade gh; else brew install gh; fi ;;
    *)       install_pkg "GitHub CLI" gh gh gh github-cli gh ;;
  esac
  hash -r
fi
{ has gh && gh_ok_version; } || fail "GitHub CLI 2.40 or newer is needed. Get it from https://cli.github.com, then run the installer again."
ok "GitHub CLI is ready $D($(gh --version | head -n1 | sed -E 's/^gh version ([^ ]+).*/\1/'))$R"

# ================================================================ Step 3
step 3 "Claude Code" "Your AI coding assistant, installed with Anthropic's official installer."
export PATH="$HOME/.local/bin:$PATH"
if has claude && claude --version >/dev/null 2>&1 </dev/null; then
  ok "Claude Code is ready $D($(claude --version 2>/dev/null </dev/null | head -n1))$R"
else
  has claude && warn "Found a Claude Code install that doesn't start ($(command -v claude)). Reinstalling it."
  if has npm && npm ls -g @anthropic-ai/claude-code >/dev/null 2>&1; then
    printf '  %s%s%s Removing an old copy installed with npm\n' "$CYN" "$S_ARROW" "$R"
    npm uninstall -g @anthropic-ai/claude-code >/dev/null 2>&1 || true
  fi
  printf '  %s%s%s Installing Claude Code\n' "$CYN" "$S_ARROW" "$R"
  curl -fsSL https://claude.ai/install.sh | bash
  hash -r
  { has claude && claude --version >/dev/null 2>&1 </dev/null; } || fail "Claude Code didn't install correctly. Copy the messages above and ask for help."
  ok "Claude Code installed $D($(claude --version 2>/dev/null </dev/null | head -n1))$R"
fi

# ================================================================ Step 4
step 4 "Your GitHub accounts" "Each account gets its own folder. That's the whole trick."
card_top "How it works"
card_line "$(pretty "$HOME/code/work")       $CYN$S_ARROW$R  your work account"
card_line "$(pretty "$HOME/code/personal")   $CYN$S_ARROW$R  your personal account"
card_line ""
card_line "${D}Every project inside a folder uses that folder's account.$R"
card_bottom
printf '\n'
warn "${B}Heads-up:$R when your browser opens to log in, make sure it's signed in to"
info "the ${B}right$R GitHub account. If not, sign out on github.com first, or paste"
info "the link into a private/incognito window."

# Map file format, one line per account:  folder|github-user|label
first_run=1; [ -s "$MAP_FILE" ] && first_run=0
touch "$MAP_FILE"
if [ -s "$MAP_FILE" ]; then
  printf '\n'
  card_top "Already set up"
  while IFS='|' read -r f u l; do
    [ -n "$f" ] && card_line "$(printf '%-10s %s%s%s  %-20s %s' "${l:-?}" "$CYN" "$S_ARROW" "$R" "$u" "$D$(pretty "$f")$R")"
  done < "$MAP_FILE"
  card_bottom
fi

# gh's own login can point all of github.com at gh's *active* account. Git reads settings top to
# bottom and the last one wins, so if that setting sits below the per-folder ones it overrides
# them. Move the per-folder entries to the end of ~/.gitconfig. gh's setting stays in place, so
# repos outside the account folders keep working exactly as before.
put_accounts_last() {
  local f u l path
  while IFS='|' read -r f u l; do
    [ -z "$f" ] && continue
    path="$(git config --global --get "includeIf.gitdir/i:$f/.path" 2>/dev/null)" || continue
    git config --global --remove-section "includeIf.gitdir/i:$f/" 2>/dev/null || true
    git config --global "includeIf.gitdir/i:$f/.path" "$path"
  done < "$MAP_FILE"
}

# ---- SSH (only for accounts whose projects use git@github.com: addresses)
same_user() { [ "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" = "$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')" ]; }

# Which GitHub account does this key log in as? (empty if none)
ssh_whoami() {
  ssh -i "$1" -o IdentitiesOnly=yes -o ConnectTimeout=15 -T git@github.com 2>&1 </dev/null \
    | sed -n 's/^Hi \([^!]*\)!.*/\1/p' | head -n1
}

# Trust GitHub's SSH servers using the fingerprints from GitHub's API (fetched over HTTPS),
# so there is no "authenticity of host can't be established" question.
trust_github_host() {
  local kh="$HOME/.ssh/known_hosts" keys
  ssh-keygen -F github.com -f "$kh" >/dev/null 2>&1 && return 0
  keys="$(gh api meta --jq '.ssh_keys[]' 2>/dev/null)" || return 0
  [ -n "$keys" ] || return 0
  printf '%s\n' "$keys" | sed 's/^/github.com /' >> "$kh"
  ok "Added GitHub's official SSH fingerprints"
}

# Sets ssh_key to a working key for this account, or leaves it empty.
setup_ssh() { # $1 = label, $2 = GitHub user
  local key="$HOME/.ssh/claude-gh-$1" custom who out tok
  ssh_key=""
  if ! has ssh || ! has ssh-keygen; then
    warn "SSH isn't installed on this computer, so this account will use HTTPS only."; return 0
  fi
  mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
  if [ -f "$key" ]; then
    ok "Using the SSH key made earlier: $(pretty "$key")"
  else
    custom="$(ask "Already have an SSH key for '$2'? Type its path, or just press Enter to create one" "" "For example  ~/.ssh/id_ed25519_work   (the private key, not the .pub file)")"
    if [ -n "$custom" ]; then
      key="${custom/#\~/$HOME}"
      if [ ! -f "$key" ] || [ ! -f "$key.pub" ]; then
        warn "Couldn't find both $(pretty "$key") and $(pretty "$key").pub - this account will use HTTPS only."; return 0
      fi
    else
      ssh-keygen -q -t ed25519 -N "" -C "claude-gh-accounts $1" -f "$key" </dev/null \
        || { warn "Couldn't create an SSH key - this account will use HTTPS only."; return 0; }
      ok "Created a new SSH key: $(pretty "$key")"
    fi
  fi
  trust_github_host

  who="$(ssh_whoami "$key")"
  if [ -n "$who" ] && ! same_user "$who" "$2"; then
    warn "That key is already linked to GitHub account '$who', not '$2'."
    info "GitHub allows each key on one account only. Run the installer again and pick another key."
    return 0
  fi
  if [ -z "$who" ]; then
    printf '  %s%s%s Adding the key to GitHub account %s%s%s\n' "$CYN" "$S_ARROW" "$R" "$B" "$2" "$R"
    tok="$(gh auth token --user "$2" 2>/dev/null)"
    if ! out="$(GH_TOKEN="$tok" gh ssh-key add "$key.pub" --title "claude-gh-accounts ($(hostname 2>/dev/null || echo computer))" 2>&1)" \
       && printf '%s' "$out" | grep -qi 'scope\|403\|404'; then
      info "GitHub needs your OK to add SSH keys for $2. One more browser step:"
      gh auth switch --hostname github.com --user "$2" >/dev/null 2>&1
      gh auth refresh --hostname github.com --scopes admin:public_key </dev/tty
      tok="$(gh auth token --user "$2" 2>/dev/null)"
      GH_TOKEN="$tok" gh ssh-key add "$key.pub" --title "claude-gh-accounts ($(hostname 2>/dev/null || echo computer))" >/dev/null 2>&1
    fi
    who="$(ssh_whoami "$key")"
  fi
  if [ -n "$who" ] && same_user "$who" "$2"; then
    ssh_key="$key"; ok "SSH works for $B$2$R"
  else
    warn "GitHub didn't accept the key yet. Add it by hand, then run the installer again:"
    info "1. Open  https://github.com/settings/ssh/new  (signed in as $2)"
    info "2. Paste this key and save:"
    printf '       %s%s%s\n' "$D" "$(cat "$key.pub")" "$R"
  fi
}

# Pushes that change GitHub Actions files (.github/workflows) need the "workflow" permission.
# Logins made without it get "refusing to allow an OAuth App to create or update workflow".
ensure_workflow_scope() { # $1 = GitHub user
  local tok scopes
  tok="$(gh auth token --user "$1" 2>/dev/null)" || return 0
  scopes="$(GH_TOKEN="$tok" gh api -i user 2>/dev/null | tr -d '\r' | sed -n 's/^[Xx]-[Oo][Aa][Uu][Tt][Hh]-[Ss][Cc][Oo][Pp][Ee][Ss]: *//p')"
  [ -z "$scopes" ] && return 0  # couldn't check (offline, or a token type without scopes): don't nag
  case ",$(printf '%s' "$scopes" | tr -d ' ')," in *,workflow,*) return 0 ;; esac
  warn "The login for $1 can't change GitHub Actions files (.github/workflows),"
  info "so pushes that touch them would be refused. One more browser step fixes it."
  if ask_yes "Fix it now?" y; then
    gh auth switch --hostname github.com --user "$1" >/dev/null 2>&1
    if gh auth refresh --hostname github.com --scopes workflow </dev/tty; then ok "$1 can now push GitHub Actions changes"
    else warn "Couldn't add it. Later, run:  gh auth switch --user $1  then  gh auth refresh -s workflow"; fi
  else
    dim "Later, run:  gh auth switch --user $1  then  gh auth refresh -s workflow"
  fi
}

# ---- Smart defaults, so re-runs and new accounts are mostly "press Enter"
# GitHub accounts already logged in to gh on this computer
gh_logged_in_users() {
  gh auth status --hostname github.com 2>&1 | sed -n 's/.*Logged in to github\.com account \([A-Za-z0-9-]*\).*/\1/p'
}
# Name and email from the GitHub profile. When the email is private, use the account's
# no-reply address (<id>+<login>@users.noreply.github.com), which GitHub always accepts.
github_profile() { # $1 = user; sets gh_name, gh_email
  local tok line id login
  gh_name=""; gh_email=""
  tok="$(gh auth token --user "$1" 2>/dev/null)" || return 0
  line="$(GH_TOKEN="$tok" gh api user --jq '[.id, .login, (.name // ""), (.email // "")] | @tsv' 2>/dev/null)" || return 0
  id="$(printf '%s' "$line" | cut -f1)"; login="$(printf '%s' "$line" | cut -f2)"
  gh_name="$(printf '%s' "$line" | cut -f3)"; gh_email="$(printf '%s' "$line" | cut -f4)"
  [ -z "$gh_email" ] && [ -n "$id" ] && [ -n "$login" ] && gh_email="$id+$login@users.noreply.github.com"
  return 0
}
# What's already saved for this GitHub user? Sets ex_label, ex_folder, ex_name, ex_email, ex_ssh
existing_account() { # $1 = user
  local f u l cfgp
  ex_label=""; ex_folder=""; ex_name=""; ex_email=""; ex_ssh=""
  while IFS='|' read -r f u l; do
    [ -n "$f" ] && same_user "$u" "$1" && { ex_folder="$f"; ex_label="$l"; break; }
  done < "$MAP_FILE"
  [ -z "$ex_folder" ] && return 0
  cfgp="$(git config --global --get "includeIf.gitdir/i:$ex_folder/.path" 2>/dev/null || true)"
  [ -z "$ex_label" ] && [ -n "$cfgp" ] && ex_label="${cfgp##*/.gitconfig-}"
  [ -z "$cfgp" ] && cfgp="$HOME/.gitconfig-$ex_label"
  ex_name="$(git config --file "$cfgp" user.name 2>/dev/null || true)"
  ex_email="$(git config --file "$cfgp" user.email 2>/dev/null || true)"
  ex_ssh="$(git config --file "$cfgp" core.sshCommand 2>/dev/null || true)"
  return 0
}

default_name="$(git config --global user.name 2>/dev/null || true)"
another=0; count=0
if [ -s "$MAP_FILE" ]; then ask_yes "Add or change an account now?" n && another=1; else another=1; fi

while [ "$another" -eq 1 ]; do
  count=$((count + 1))
  printf '\n  %s%s ACCOUNT %s %s%s\n' "$G3$B" "$(rep "$H" 3)" "$count" "$(rep "$H" 40)" "$R"

  # Suggest an account that's logged in on this computer but not set up yet
  logged_in="$(gh_logged_in_users | tr '\n' ' ' | sed 's/ *$//')"
  suggest=""
  for u in $logged_in; do
    existing_account "$u"; [ -z "$ex_folder" ] && { suggest="$u"; break; }
  done
  hint="The name you log in with, shown at github.com/<username>"
  [ -n "$logged_in" ] && hint="Logged in on this computer: $(printf '%s' "$logged_in" | sed 's/ /, /g')"
  user="$(ask "Which GitHub account?" "$suggest" "$hint")"
  if ! printf '%s' "$user" | grep -Eq '^[A-Za-z0-9]([A-Za-z0-9-]{0,38})$'; then
    warn "That doesn't look like a GitHub username (letters, numbers and dashes only)."; count=$((count - 1)); continue
  fi
  existing_account "$user"
  [ -n "$ex_folder" ] && ok "'$user' is already set up - press Enter to keep each answer."

  def_label="$ex_label"
  [ -z "$def_label" ] && def_label="$(printf '%s' "$user" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')"
  label="$(ask "Give this account a nickname" "$def_label" "One word, e.g.  work,  personal,  client1" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')"
  [ -z "$label" ] && { warn "Please use letters or numbers."; count=$((count - 1)); continue; }

  printf '\n'
  if gh auth token --user "$user" >/dev/null 2>&1; then
    ok "Already logged in to GitHub as $B$user$R"
  else
    while true; do
      printf '  %s%s%s Logging in as %s%s%s. A browser window will open - follow the steps there.\n' "$CYN" "$S_ARROW" "$R" "$B" "$user" "$R"
      dim "(Choose \"Login with a web browser\" and copy the one-time code it shows.)"
      gh auth login --hostname github.com --git-protocol https --web --scopes workflow </dev/tty
      if gh auth token --user "$user" >/dev/null 2>&1; then ok "Logged in as $B$user$R"; break; fi
      who="$(gh api user --jq .login 2>/dev/null || true)"
      # GitHub usernames aren't case sensitive, but gh stores them exactly as GitHub spells them
      if [ -n "$who" ] && [ "$(printf '%s' "$who" | tr '[:upper:]' '[:lower:]')" = "$(printf '%s' "$user" | tr '[:upper:]' '[:lower:]')" ]; then
        user="$who"; ok "Logged in as $B$user$R"; break
      fi
      warn "That login was for '${who:-unknown}', not '$user'. The browser was signed in to a different account."
      [ -n "$who" ] && dim "(To remove that login later: gh auth logout --user $who)"
      ask_yes "Try logging in again?" y || { warn "Skipped. Run the installer again to finish logging in as $user."; break; }
    done
  fi
  ensure_workflow_scope "$user"
  github_profile "$user"

  def_folder="$HOME/code/$label"; [ -n "$ex_folder" ] && def_folder="$ex_folder"
  folder="$(ask "Which folder should hold the '$label' projects?" "$(pretty "$def_folder")" "It will be created if it doesn't exist yet")"
  folder="${folder/#\~/$HOME}"
  case "$folder" in *'|'*) warn "The folder name can't contain '|'."; count=$((count - 1)); continue ;; esac
  mkdir -p "$folder" || { warn "Couldn't create $folder"; count=$((count - 1)); continue; }
  folder="$(cd "$folder" && pwd -P)"  # real path: git matches folders by their real location
  if [ "$folder" = "/" ] || [ "$folder" = "$HOME" ]; then
    warn "Please pick a folder of its own, not $(pretty "$folder") itself."; count=$((count - 1)); continue
  fi

  def_name="${ex_name:-${gh_name:-$default_name}}"
  name="$(ask "Your name, as it should appear on your work" "$def_name" "Shown next to every change you save (a \"commit\")")"
  [ -z "$name" ] && { warn "A name is needed - Git won't save changes without one."; count=$((count - 1)); continue; }

  def_email="${ex_email:-$gh_email}"
  email_hint="Use an email added to this GitHub account (github.com/settings/emails)"
  case "$def_email" in *@users.noreply.github.com) email_hint="Suggested: your private GitHub address - it keeps your real email hidden" ;; esac
  email="$(ask "Email for this account" "$def_email" "$email_hint")"
  case "$email" in *?@?*) ;; *) warn "Please enter a valid email address."; count=$((count - 1)); continue ;; esac

  printf '\n'
  card_top "Quick check"
  card_line "$(printf '%-10s' Nickname)$B$label$R"
  card_line "$(printf '%-10s' GitHub)$B$user$R"
  card_line "$(printf '%-10s' Folder)$B$(pretty "$folder")$R"
  card_line "$(printf '%-10s' Commits)$B$name$R $D<$email>$R"
  card_bottom
  if ! ask_yes "Does this look right?" y; then
    info "No problem - let's try that account again."; count=$((count - 1)); continue
  fi

  ssh_key=""
  ssh_default=n; { [ -n "$ex_ssh" ] || [ -f "$HOME/.ssh/claude-gh-$label" ]; } && ssh_default=y
  printf '\n'
  dim "Project addresses look like  https://github.com/...  or  git@github.com:...  (SSH)."
  dim "HTTPS always works. If you're not sure, answer no - you can add SSH later."
  if ask_yes "Do your '$label' projects use SSH addresses (git@github.com:...)?" "$ssh_default"; then
    setup_ssh "$label" "$user"
  fi

  # Per-folder git settings: commit identity + which account git uses for github.com
  # The helper hands git this account's token, and prints a hint if GitHub ever rejects it.
  # With SSH, core.sshCommand picks this account's key for git@github.com: addresses.
  cfg="$HOME/.gitconfig-$label"
  rm -f "$cfg"
  git config --file "$cfg" user.name "$name"
  git config --file "$cfg" user.email "$email"
  git config --file "$cfg" --add 'credential.https://github.com.helper' ''
  git config --file "$cfg" --add 'credential.https://github.com.helper' \
    "!f() { case \"\$1\" in get) echo \"username=$user\"; echo \"password=\$(gh auth token --user $user)\" ;; erase) echo \"claude-gh-accounts: GitHub did not accept the saved login for $user. Log in again with: gh auth login   Help: $REPO_URL#-troubleshooting\" >&2 ;; esac; }; f"
  [ -n "$ssh_key" ] && git config --file "$cfg" core.sshCommand "ssh -i '$ssh_key' -o IdentitiesOnly=yes"

  # Forget earlier entries for this folder or this label (e.g. the label moved to a new folder)
  tmp="$(mktemp)"
  while IFS='|' read -r f u l; do
    [ -z "$f" ] && continue
    [ "$f" = "$folder" ] && continue
    old_cfg="$(git config --global --get "includeIf.gitdir/i:$f/.path" 2>/dev/null || true)"
    if [ "$l" = "$label" ] || [ "$old_cfg" = "$cfg" ]; then
      git config --global --unset-all "includeIf.gitdir/i:$f/.path" 2>/dev/null || true
      info "$f no longer uses '$label'"
      continue
    fi
    printf '%s|%s|%s\n' "$f" "$u" "$l" >> "$tmp"
  done < "$MAP_FILE"
  printf '%s|%s|%s\n' "$folder" "$user" "$label" >> "$tmp"
  mv "$tmp" "$MAP_FILE"
  git config --global --replace-all "includeIf.gitdir/i:$folder/.path" "$cfg"
  ok "Repos in $(pretty "$folder") will now use $B$user$R"

  put_accounts_last
  ask_yes "Add another GitHub account?" n && another=1 || another=0
done
[ -s "$MAP_FILE" ] || fail "No accounts are set up yet. Run the installer again when you're ready."
put_accounts_last

# ================================================================ Step 5
step 5 "Turning on auto-switching" "Teaching the claude command to pick the right account by itself."
LAUNCHER="$(cat <<'EOF'
# >>> claude-gh-accounts >>>
# Starts Claude Code with the GitHub account that matches the current folder.
# Managed by claude-gh-accounts (https://github.com/us-urvin/claude-gh-accounts):
# run the installer again to change accounts.
unalias claude 2>/dev/null
claude() {
  local map="$HOME/.claude-gh-accounts" here="${PWD%/}/" phys="$(pwd -P 2>/dev/null)/" user="" best=0 f u l tok
  if [ -f "$map" ]; then
    while IFS='|' read -r f u l; do
      if [ -z "$f" ] || [ -z "$u" ]; then continue; fi
      f="${f%/}/"
      if [ "${here#"$f"}" != "$here" ] || [ "${phys#"$f"}" != "$phys" ]; then
        if [ ${#f} -gt $best ]; then user="$u"; best=${#f}; fi
      fi
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
  ok "Added the smart claude command to $(pretty "$rc")"
done

# ================================================================ Step 6
step 6 "All done!" ""
box "$GRN" "" "  $S_OK  You're all set! Nice work." ""
printf '\n'
card_top "Your accounts"
while IFS='|' read -r f u l; do
  [ -n "$f" ] && card_line "$(printf '%s%s%s %-10s %-20s %s' "$GRN" "$S_DOT" "$R" "${l:-?}" "$u" "$D$(pretty "$f")$R")"
done < "$MAP_FILE"
card_bottom

first_folder="$(head -n1 "$MAP_FILE" | cut -d'|' -f1)"
first_user="$(head -n1 "$MAP_FILE" | cut -d'|' -f2)"
printf '\n'
card_top "What to do now"
card_line "${G2}${B}1${R}  Close this window and open a ${B}new${R} terminal."
card_line "   ${D}(This one doesn't know about the new setup yet.)$R"
card_line "${G2}${B}2${R}  Go to an account folder:   ${CYN}cd $(pretty "$first_folder")$R"
card_line "${G2}${B}3${R}  Download a project:        ${CYN}git clone https://github.com/OWNER/REPO.git$R"
card_line "   ${D}(or  git clone git@github.com:OWNER/REPO.git  if you set up SSH)$R"
card_line "${G2}${B}4${R}  Go into it and type:       ${CYN}claude$R"
card_line "   You'll see ${CYN}GitHub account: $first_user$R - that's it working!"
card_bottom
printf '\n'
dim "Projects outside these folders keep working exactly as before."
dim "Run the installer again any time to add or change an account."
dim "Push not working? Common errors and fixes: $REPO_URL#-troubleshooting"

# ================================================================ Star
printf '\n  %s%s%s  %sEnjoying it? A star on GitHub helps other people find it.%s\n' "$RED" "$S_HEART" "$R" "$B" "$R"
printf '     %s%s%s\n' "$CYN" "$REPO_URL" "$R"
if [ "$first_run" -eq 1 ] && ask_yes "Open it in your browser now?" y; then
  open_url "$REPO_URL"
  ok "Thank you!"
fi
printf '\n'
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
