# claude-gh-accounts

Use **several GitHub accounts with Claude Code** (work, personal, clients) and have the right one picked automatically based on the folder you're in.

- One folder per GitHub account, e.g. `~/code/work` and `~/code/personal`.
- Inside a folder, `git` commits with that account's name and email, and clones and pushes with that account's token.
- Type `claude` inside a folder and Claude Code starts with that account's GitHub token (`GH_TOKEN`), so `gh pr create` and similar commands run as the right account.
- Repos outside these folders work exactly as before.

> Community project, not affiliated with Anthropic or GitHub.

## Quick start

**macOS / Linux**

```bash
curl -fsSL https://raw.githubusercontent.com/us-urvin/claude-gh-accounts/main/install.sh | bash
```

**Windows (PowerShell)**

```powershell
irm https://raw.githubusercontent.com/us-urvin/claude-gh-accounts/main/install.ps1 | iex
```

Prefer to read it first? Download the script, look through it, then run
`bash install.sh` or `powershell -ExecutionPolicy Bypass -File .\install.ps1`.

Then **open a new terminal**, `cd` into one of your account folders, and type `claude`. You'll see:

```
GitHub account: your-work-username
```

## What the script does

1. Installs anything missing: Git, GitHub CLI 2.40+ and Claude Code (official installer). It uses Homebrew, apt, dnf, pacman, zypper or winget.
2. For each account, asks for a short name, a GitHub username, a folder, and a commit name and email, then logs that account in to `gh`. `gh` supports several logged-in accounts.
3. Writes `~/.gitconfig-<name>` (commit identity plus a credential helper that asks `gh` for that account's token) and adds an `includeIf "gitdir/i:<folder>/"` line to your global `~/.gitconfig`.
4. Removes gh's global `gh auth git-credential` helper if it's there, because it would override the per-folder choice.
5. Adds a small `claude` wrapper function to your shell profile (`~/.zshrc`, `~/.bashrc`, or PowerShell `profile.ps1`). The wrapper looks up the current folder in `~/.claude-gh-accounts`.

Run it again any time to add an account, change an account's folder, or update a name or email.

## Files it touches

| File | Purpose |
| --- | --- |
| `~/.claude-gh-accounts` | `folder\|github-user\|label` map used by the `claude` wrapper |
| `~/.gitconfig-<label>` | Per-account identity and credential helper |
| `~/.gitconfig` | One `includeIf` entry per account |
| `~/.zshrc`, `~/.bashrc`, `~/.bash_profile` | `claude` wrapper, between `# >>> claude-gh-accounts >>>` markers |
| `Documents\(Windows)PowerShell\profile.ps1` | Same wrapper for PowerShell |

## Uninstall

1. Delete the block between `# >>> claude-gh-accounts >>>` and `# <<< claude-gh-accounts <<<` in your shell profile(s).
2. Remove the `includeIf` entries from `~/.gitconfig` (`git config --global --edit`).
3. Delete `~/.claude-gh-accounts` and `~/.gitconfig-*`.
4. Optional: `gh auth logout --user <name>` for accounts you no longer need.

## Notes and limitations

- The wrapper works when you start `claude` from a terminal. The IDE extensions and desktop app don't go through your shell, so they don't get the per-folder `GH_TOKEN`. Plain `git` in those folders still uses the right account.
- Repos must live **inside** the account folder. Nested folders are fine, and the longest match wins.
- Only HTTPS remotes (`https://github.com/...`) are covered. SSH remotes use your SSH keys as usual.

## License

MIT
