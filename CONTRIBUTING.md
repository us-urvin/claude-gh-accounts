# Contributing

Thanks for helping make `claude-gh-accounts` better! Bug reports, ideas and pull requests are all welcome.

## How changes get in

- `main` is protected. Nobody pushes to it directly. Every change arrives as a **pull request from a fork**.
- CI (Linux, macOS, Windows) must pass.
- The maintainer ([@us-urvin](https://github.com/us-urvin)) reviews every PR and is the only one who merges.

## Making a change

1. Fork the repo and create a branch: `git checkout -b fix-something`.
2. Make your change. Two scripts do the same job:
   - `install.sh` for macOS and Linux (bash 3.2+, also zsh for the `claude` function)
   - `install.ps1` for Windows (Windows PowerShell 5.1 and PowerShell 7)

   If your change applies to both platforms, please update both.
3. Run the tests:

   ```bash
   bash tests/test.sh                                          # macOS / Linux
   shellcheck install.sh tests/test.sh                         # if you have it
   ```

   ```powershell
   powershell -ExecutionPolicy Bypass -File tests\test.ps1     # Windows
   ```

   The tests use a throwaway home folder and fake `gh` and `claude` commands. They never touch your real setup.
4. Add a line to `CHANGELOG.md` under **Unreleased**.
5. Open a pull request and fill in the template.

## Style

- Keep messages friendly and plain. Many users aren't terminal experts.
- No new dependencies beyond Git, GitHub CLI and Claude Code.
- Keep `install.ps1` pure ASCII. Windows PowerShell 5.1 misreads non-ASCII characters in files without a BOM.

## Reporting bugs

Use the [bug report form](https://github.com/us-urvin/claude-gh-accounts/issues/new/choose). For security problems, see [SECURITY.md](SECURITY.md).

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE) and that you follow the [Code of Conduct](CODE_OF_CONDUCT.md).
