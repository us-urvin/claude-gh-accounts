# Security policy

This installer handles GitHub login and git credentials, so security reports are taken seriously.

## Reporting a vulnerability

Please **don't open a public issue**. Report it privately through GitHub instead:

**[Report a vulnerability](https://github.com/us-urvin/claude-gh-accounts/security/advisories/new)**

You'll get a reply as soon as possible. Once a fix is released, you'll be credited unless you'd rather not be.

## Supported versions

Only the latest version on `main` is supported. The install commands always fetch it.

## How the scripts handle credentials

- Tokens are never written to disk by these scripts. They stay in GitHub CLI's own secure storage (macOS Keychain, Windows Credential Manager, or the Linux keyring).
- The per-folder git credential helper asks `gh auth token --user <name>` for a token each time git needs one.
- The `claude` wrapper sets `GH_TOKEN` only for the Claude Code process it starts. On Windows it restores the previous value afterwards.
- SSH (optional, per account): keys are created by your system's `ssh-keygen` in `~/.ssh` (`claude-gh-<nickname>`), with your user's normal file permissions. They have no passphrase, so they work without prompts, just like many default setups. Use your own passphrase-protected key instead by typing its path when asked. GitHub's host fingerprints come from GitHub's API over HTTPS, not from a first-time network guess.
