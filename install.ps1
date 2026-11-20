# Claude Code + automatic GitHub account switching (Windows)
# Run:   powershell -ExecutionPolicy Bypass -File .\install.ps1
#   or:  irm https://raw.githubusercontent.com/us-urvin/claude-gh-accounts/main/install.ps1 | iex
# Safe to run again any time to add accounts or change folders.

$ErrorActionPreference = 'Continue'
$MapFile    = Join-Path $HOME '.claude-gh-accounts'
$BlockStart = '# >>> claude-gh-accounts >>>'
$BlockEnd   = '# <<< claude-gh-accounts <<<'

function Step($n, $m) { Write-Host ''; Write-Host "== Step ${n}: $m ==" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "  [ok] $m" -ForegroundColor Green }
function Info($m) { Write-Host "  $m" }
function Warn($m) { Write-Host "  [!] $m" -ForegroundColor Yellow }
function Fail($m) { Write-Host "  [x] $m" -ForegroundColor Red; throw 'Setup stopped. Fix the problem above, then run the script again.' }
function Has($c)  { [bool](Get-Command $c -CommandType Application -ErrorAction SilentlyContinue) }
function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
}
function Ask($q, $def) {
    $prompt = if ($def) { "  $q [$def]" } else { "  $q" }
    $a = Read-Host $prompt
    if ([string]::IsNullOrWhiteSpace($a)) { return $def } else { return $a.Trim() }
}
function GitQuote($s) { return '"' + (("$s" -replace '\\', '\\') -replace '"', '\"') + '"' }
function AskYes($q, $def = 'y') { return ((Ask "$q (y/n)" $def) -match '^(y|yes)$') }
function Winget-Install($id, $name) {
    if (-not (Has winget)) { Fail "$name is missing and winget isn't available. Install $name yourself, then run this script again." }
    Info "Installing $name (a permission window may pop up; click Yes)..."
    winget install --id $id -e --source winget --accept-package-agreements --accept-source-agreements
    Refresh-Path
}

# A token in the environment would hide the accounts gh stores, and blocks "gh auth login".
# (This happens if you run the setup from inside a "claude" session.)
Remove-Item Env:GH_TOKEN, Env:GITHUB_TOKEN -ErrorAction SilentlyContinue

Write-Host 'Claude Code setup with automatic GitHub account switching' -ForegroundColor Cyan
Info 'Answer the questions as they come. You can stop with Ctrl+C and run this again later.'

# ---------------------------------------------------------------- Step 1
Step 1 'Checking your system'
$arch = $env:PROCESSOR_ARCHITECTURE
try {
    $cpu = (Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1).Architecture
    if ($cpu -eq 12) { $arch = 'ARM64' } elseif ($cpu -eq 9) { $arch = 'x64' }
} catch { }
Ok "Windows, $arch, PowerShell $($PSVersionTable.PSVersion)"

# ---------------------------------------------------------------- Step 2
Step 2 'Git'
if (-not (Has git)) { Winget-Install 'Git.Git' 'Git' }
if (-not (Has git)) { Fail 'Git still not found. Close this window, open a new PowerShell and run the script again.' }
Ok (git --version)

# ---------------------------------------------------------------- Step 3
Step 3 'GitHub CLI (gh)'
function Gh-Version {
    $line = gh --version 2>$null | Select-Object -First 1
    if ($line -match '(\d+)\.(\d+)\.(\d+)') { return [version]"$($Matches[1]).$($Matches[2]).$($Matches[3])" }
    return [version]'0.0.0'
}
if (-not (Has gh)) { Winget-Install 'GitHub.cli' 'GitHub CLI' }
if (-not (Has gh)) { Fail 'GitHub CLI still not found. Close this window, open a new PowerShell and run the script again.' }
if ((Gh-Version) -lt [version]'2.40.0') {
    Info 'Your gh is too old for multiple accounts (needs 2.40+). Updating...'
    winget upgrade --id GitHub.cli -e --source winget --accept-package-agreements --accept-source-agreements
    Refresh-Path
}
if ((Gh-Version) -lt [version]'2.40.0') { Fail 'GitHub CLI 2.40 or newer is needed. Get it from https://cli.github.com' }
Ok "GitHub CLI $(Gh-Version)"

# ---------------------------------------------------------------- Step 4
Step 4 'Claude Code'
$localBin = Join-Path $HOME '.local\bin'
function First-Claude { Get-Command claude -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1 }
function Test-Claude($path) {
    try { & $path --version *> $null; return ($LASTEXITCODE -eq 0) } catch { return $false }
}
$c = First-Claude
if ($c -and (Test-Claude $c.Source)) {
    Ok "Claude Code works: $($c.Source)"
} else {
    if ($c) { Warn "Found a Claude Code install that doesn't run: $($c.Source). Reinstalling." }
    if (Has npm) {
        $npmHas = npm ls -g @anthropic-ai/claude-code 2>$null | Out-String
        if ($npmHas -match 'claude-code') {
            Info 'Removing old npm copy...'
            npm uninstall -g @anthropic-ai/claude-code 2>$null | Out-Null
        }
    }
    Info 'Installing Claude Code with the official installer...'
    $ps = (Get-Process -Id $PID).Path
    & $ps -NoProfile -ExecutionPolicy Bypass -Command 'irm https://claude.ai/install.ps1 | iex'
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not $userPath) { $userPath = '' }
    if ($userPath -notlike "*$localBin*") {
        [Environment]::SetEnvironmentVariable('Path', ($userPath.TrimEnd(';') + ";$localBin").TrimStart(';'), 'User')
    }
    Refresh-Path
    $c = First-Claude
    if (-not $c) { Fail "Claude Code didn't install correctly. Copy the messages above and ask for help." }
    if (-not (Test-Claude $c.Source)) {
        Fail "A broken Claude Code file is still in the way: $($c.Source). Delete it (as Administrator), then run this script again."
    }
    Ok "Claude Code installed: $($c.Source)"
}

# ---------------------------------------------------------------- Step 5
Step 5 'Your GitHub accounts'
Info 'Each GitHub account gets its own folder. Any repo inside that folder automatically'
Info 'uses that account for commits, clones, pushes and pull requests.'
Info ''
Write-Host '  IMPORTANT: when the browser opens to log in, check it is signed in to the' -ForegroundColor Yellow
Write-Host '  RIGHT GitHub account. If not, sign out there first or paste the link in a private window.' -ForegroundColor Yellow

# Map file format, one line per account:  folder|github-user|label
$map = New-Object System.Collections.ArrayList
if (Test-Path $MapFile) {
    foreach ($line in Get-Content $MapFile) {
        $p = $line -split '\|'
        if ($p.Count -ge 2 -and $p[0] -and $p[1]) {
            $l = if ($p.Count -ge 3) { $p[2] } else { '' }
            [void]$map.Add([pscustomobject]@{ Folder = $p[0]; User = $p[1]; Label = $l })
        }
    }
}
function Save-Map {
    $lines = foreach ($e in $map) { "$($e.Folder)|$($e.User)|$($e.Label)" }
    [IO.File]::WriteAllText($MapFile, ((@($lines) -join "`n") + "`n"), (New-Object Text.UTF8Encoding($false)))
}
function GitDir($f) { return ($f -replace '\\', '/') + '/' }
if ($map.Count) {
    Info ''; Info 'Already set up:'
    foreach ($e in $map) { Info "  $($e.Folder)  ->  $($e.User)" }
}

# gh's own login can point all of github.com at gh's *active* account, placed after (and
# overriding) the per-folder settings. Remove it; the per-folder helpers replace it.
# On Windows gh writes it as:  !'C:\Program Files\GitHub CLI\gh.exe' auth git-credential
function Remove-GlobalGhHelper {
    $old = git config --global --get-all credential.https://github.com.helper 2>$null | Out-String
    if ($old -match 'gh(\.exe)?[''"]?\s+auth\s+git-credential') {
        git config --global --unset-all credential.https://github.com.helper
        git config --global --unset-all credential.https://gist.github.com.helper 2>$null
        Ok 'Removed a global gh git setting that would override the per-folder accounts'
    }
}

$defaultName = git config --global user.name 2>$null
$another = if ($map.Count) { AskYes 'Add or update an account now?' 'y' } else { $true }

while ($another) {
    Write-Host ''
    $label = ((Ask 'Short name for this account (e.g. work, personal, client1)' '') + '').ToLower() -replace '[^a-z0-9-]', ''
    if (-not $label) { Warn 'Please use letters or numbers.'; continue }
    $user = Ask 'GitHub username for this account' ''
    if ("$user" -notmatch '^[A-Za-z0-9][A-Za-z0-9-]{0,38}$') { Warn "That doesn't look like a GitHub username (letters, numbers and dashes only)."; continue }
    $folder = Ask "Folder for this account's repos" (Join-Path $HOME "code\$label")
    if ($folder.StartsWith('~')) { $folder = $HOME + $folder.Substring(1) }
    if ($folder.Contains('|')) { Warn "The folder name can't contain '|'."; continue }
    try {
        $folder = [IO.Path]::GetFullPath($folder).TrimEnd('\')
    } catch { Warn "That folder name isn't valid: $($_.Exception.Message)"; continue }
    if ($folder.Length -le 3 -or $folder -eq $HOME.TrimEnd('\')) { Warn "Pick a dedicated folder, not $folder itself."; continue }
    try {
        New-Item -ItemType Directory -Force -Path $folder -ErrorAction Stop | Out-Null
    } catch { Warn "Couldn't create that folder: $($_.Exception.Message)"; continue }
    $name  = Ask 'Name to show on commits' $defaultName
    if (-not $name) { Warn "A name is required (git won't commit without one)."; continue }
    $email = Ask 'Email for commits (one that belongs to this GitHub account)' ''
    if ("$email" -notmatch '^\S+@\S+$') { Warn 'Please enter a valid email address.'; continue }

    gh auth token --user $user *> $null
    if ($LASTEXITCODE -eq 0) {
        Ok "Already logged in to GitHub as $user"
    } else {
        while ($true) {
            Info "Logging in as '$user'. Follow the prompts; a browser will open."
            gh auth login --hostname github.com --git-protocol https --web
            gh auth token --user $user *> $null
            if ($LASTEXITCODE -eq 0) { Ok "Logged in as $user"; break }
            $who = gh api user --jq .login 2>$null
            # GitHub usernames aren't case sensitive, but gh stores them exactly as GitHub spells them
            if ($who -and ("$who".Trim() -eq $user)) { $user = "$who".Trim(); Ok "Logged in as $user"; break }
            if (-not $who) { $who = 'unknown' }
            Warn "That login was for '$who', not '$user'."
            if ($who -ne 'unknown') { Info "(To remove the wrong one later: gh auth logout --user $who)" }
            if (-not (AskYes 'Try logging in again?' 'y')) { Warn "Skipped. Run this script again to finish logging in as $user."; break }
        }
    }

    # Per-folder git settings: commit identity + which account git uses for github.com
    # Written directly (not via "git config") because Windows PowerShell mangles quotes and empty values passed to programs
    $cfg = Join-Path $HOME ".gitconfig-$label"
    $helper = '!f() { test "$1" = get && echo "username=' + $user + '" && echo "password=$(gh auth token --user ' + $user + ')"; }; f'
    $cfgText = "[user]`n`tname = $(GitQuote $name)`n`temail = $(GitQuote $email)`n" +
               "[credential `"https://github.com`"]`n`thelper =`n`thelper = $(GitQuote $helper)`n"
    [IO.File]::WriteAllText($cfg, $cfgText, (New-Object Text.UTF8Encoding($false)))
    $cfgFwd = $cfg -replace '\\', '/'

    # Forget earlier entries for this folder or this label (e.g. the label moved to a new folder)
    foreach ($e in @($map)) {
        if ($e.Folder -eq $folder) { [void]$map.Remove($e); continue }
        $oldCfg = git config --global --get "includeIf.gitdir/i:$(GitDir $e.Folder).path" 2>$null
        if ($e.Label -eq $label -or "$oldCfg" -eq $cfgFwd) {
            git config --global --unset-all "includeIf.gitdir/i:$(GitDir $e.Folder).path" 2>$null
            Info "No longer using $($e.Folder) for '$label'"
            [void]$map.Remove($e)
        }
    }
    git config --global --replace-all "includeIf.gitdir/i:$(GitDir $folder).path" $cfgFwd
    [void]$map.Add([pscustomobject]@{ Folder = $folder; User = $user; Label = $label })
    Save-Map
    Ok "Repos in $folder will use GitHub '$user' and commit as $name <$email>"

    Remove-GlobalGhHelper
    $another = AskYes 'Add another GitHub account?' 'n'
}
if ($map.Count -eq 0) { Fail "No accounts set up yet. Run this script again when you're ready." }
Remove-GlobalGhHelper

# ---------------------------------------------------------------- Step 6
Step 6 'Installing the smart "claude" command'
$launcher = @'
# >>> claude-gh-accounts >>>
# Starts Claude Code with the GitHub account that matches the current folder.
# Managed by install.ps1: run that script again to change accounts.
function claude {
    $exe = Get-Command claude -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $exe) { Write-Host 'Claude Code was not found. Run install.ps1 again.' -ForegroundColor Red; return }
    $map  = Join-Path $HOME '.claude-gh-accounts'
    $here = (Get-Location).ProviderPath.TrimEnd('\') + '\'
    $user = $null; $best = 0
    if (Test-Path $map) {
        foreach ($line in Get-Content $map) {
            $p = $line -split '\|'
            if ($p.Count -lt 2 -or -not $p[0] -or -not $p[1]) { continue }
            $f = $p[0].TrimEnd('\') + '\'
            if ($here.StartsWith($f, [StringComparison]::OrdinalIgnoreCase) -and $f.Length -gt $best) { $user = $p[1]; $best = $f.Length }
        }
    }
    $oldToken = $env:GH_TOKEN
    try {
        if ($user) {
            $tok = gh auth token --user $user 2>$null
            if ($LASTEXITCODE -eq 0 -and $tok) {
                $env:GH_TOKEN = "$tok".Trim()
                Write-Host "GitHub account: $user" -ForegroundColor Cyan
            } else {
                Write-Host "Not logged in to GitHub as $user. Run: gh auth login" -ForegroundColor Yellow
            }
        }
        & $exe.Source @args
    } finally { $env:GH_TOKEN = $oldToken }
}
# <<< claude-gh-accounts <<<
'@

# profile.ps1 covers every PowerShell window (including the VS Code terminal), for both Windows PowerShell and PowerShell 7
$docs = [Environment]::GetFolderPath('MyDocuments')
$profiles = @((Join-Path $docs 'WindowsPowerShell\profile.ps1'), (Join-Path $docs 'PowerShell\profile.ps1'))
$pattern = '(?s)' + [regex]::Escape($BlockStart) + '.*?' + [regex]::Escape($BlockEnd)
foreach ($p in $profiles) {
    New-Item -ItemType Directory -Force -Path (Split-Path $p) | Out-Null
    $content = ''
    if (Test-Path $p) { $content = Get-Content $p -Raw }
    if ($null -eq $content) { $content = '' }
    $content = ([regex]::Replace($content, $pattern, '')).TrimEnd()
    if ($content) { $content += "`r`n`r`n" }
    $content += ($launcher -replace "`r?`n", "`r`n") + "`r`n"
    [IO.File]::WriteAllText($p, $content, [Text.Encoding]::UTF8)
    Ok "Added to $p"
}

# Let PowerShell load the profile (Windows blocks scripts by default)
$effective = 'Restricted'
foreach ($s in 'MachinePolicy', 'UserPolicy', 'CurrentUser', 'LocalMachine') {
    $v = Get-ExecutionPolicy -Scope $s
    if ("$v" -ne 'Undefined') { $effective = "$v"; break }
}
if ($effective -in 'Restricted', 'AllSigned') {
    try {
        Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force -ErrorAction Stop
        Ok 'Allowed PowerShell to load your profile (RemoteSigned, for your user only)'
    } catch {
        Warn "Couldn't allow profile scripts: $($_.Exception.Message)"
        Warn 'Your company may control this setting. Ask IT, or the "claude" command will not auto-switch accounts.'
    }
}

# ---------------------------------------------------------------- Step 7
Step 7 'All done'
Info 'Your accounts:'
foreach ($e in $map) { Info "  $($e.Folder)  ->  GitHub: $($e.User)" }
$firstFolder = $map[0].Folder
Info ''
Info 'What to do now:'
Info '1. Close this window and open a NEW PowerShell window.'
Info '2. Put repos inside the matching folder, for example:'
Info "     cd `"$firstFolder`""
Info '     git clone https://github.com/OWNER/REPO.git'
Info '3. Go into the repo and type:  claude'
Info '   You will see "GitHub account: <name>". The first time, Claude asks you to log in.'
Info '4. To double-check, ask Claude to run:  gh api user --jq .login'
Info ''
Info 'Repos outside these folders keep working exactly as before.'
Info 'Run this script again any time to add an account or change a folder.'
