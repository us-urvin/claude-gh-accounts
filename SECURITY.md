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
