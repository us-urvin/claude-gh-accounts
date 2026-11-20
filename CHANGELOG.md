# Changelog

All notable changes to this project are listed here. Versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.1.0] - 2026-11-21

### Added
- Windows: `claude` now switches accounts in Command Prompt too (`claude.cmd`).
- New logins include the `workflow` permission; existing logins are checked and fixed with your OK.
- If GitHub rejects a saved login, git prints a hint with the fix.
- README: Command Prompt install command and a Troubleshooting section for common push errors.
- Installers are attached to each release; install commands download the latest release
  (and the README shows an install count).

### Fixed
- Account switching for folders reached through a symlink (for example `~/code` linked elsewhere).

## [1.0.0] - 2026-11-21

First public release.

### Added
- `install.sh` (macOS / Linux) and `install.ps1` (Windows) one-line installers.
- Installs Git, GitHub CLI 2.40+ and Claude Code when missing.
- Per-folder GitHub accounts: commit identity and HTTPS credentials through `git includeIf`.
- `claude` wrapper that starts Claude Code with the matching account's `GH_TOKEN` (bash, zsh, PowerShell).
- Friendly, colorful installer screens: logo, step progress bar, plain-language explanations,
  example answers for every question and a "Quick check" before each account is saved.
  Colors turn off automatically with `NO_COLOR` or when output isn't a terminal.
- Re-running the installer adds accounts, moves an account to a new folder, or updates names and emails.
- Tests and CI on Linux, macOS (bash 3.2) and Windows (PowerShell 5.1 and 7).

[Unreleased]: https://github.com/us-urvin/claude-gh-accounts/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/us-urvin/claude-gh-accounts/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/us-urvin/claude-gh-accounts/releases/tag/v1.0.0
