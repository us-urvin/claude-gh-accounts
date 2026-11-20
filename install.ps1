# claude-gh-accounts: use several GitHub accounts with Claude Code (Windows)
# https://github.com/us-urvin/claude-gh-accounts
#
# Run:   powershell -ExecutionPolicy Bypass -File .\install.ps1
#   or:  irm https://github.com/us-urvin/claude-gh-accounts/releases/latest/download/install.ps1 | iex
# Safe to run again any time to add accounts or change folders.
#
# Note for contributors: keep this file pure ASCII. Windows PowerShell 5.1 misreads other
# characters in files without a BOM, so symbols are built from character codes below.

$ErrorActionPreference = 'Continue'
$RepoUrl    = 'https://github.com/us-urvin/claude-gh-accounts'
$MapFile    = Join-Path $HOME '.claude-gh-accounts'
$BlockStart = '# >>> claude-gh-accounts >>>'
$BlockEnd   = '# <<< claude-gh-accounts <<<'
$TotalSteps = 6
# Holds the claude.cmd helper that makes "claude" switch accounts in Command Prompt too
$ShimDir    = Join-Path $env:LOCALAPPDATA 'claude-gh-accounts\bin'

# ================================================================ Look & feel
function U([int[]]$codes) { return -join ($codes | ForEach-Object { [char]$_ }) }
# Windows Terminal and VS Code show every symbol; the classic console gets look-alikes that always render
$fancy = [bool]($env:WT_SESSION -or $env:TERM_PROGRAM -eq 'vscode')
if ($fancy) {
    $S = @{ Ok = U 0x2714; X = U 0x2718; Warn = U 0x25B2; Arrow = U 0x279C; In = U 0x203A; Heart = U 0x2665; Dot = U 0x25CF
            On = U 0x25A0; Off = U 0x25A1; TL = U 0x256D; TR = U 0x256E; BL = U 0x2570; BR = U 0x256F; H = U 0x2500; V = U 0x2502 }
} else {
    $S = @{ Ok = U 0x221A; X = U 0x00D7; Warn = U 0x25B2; Arrow = U 0x2192; In = U 0x00BB; Heart = U 0x2665; Dot = U 0x2022
            On = U 0x25A0; Off = U 0x25A1; TL = U 0x250C; TR = U 0x2510; BL = U 0x2514; BR = U 0x2518; H = U 0x2500; V = U 0x2502 }
}
$C = @{ G1 = 'Magenta'; G2 = 'Magenta'; G3 = 'Blue'; G4 = 'Cyan'; G5 = 'Cyan'; Ok = 'Green'; Warn = 'Yellow'; Bad = 'Red'
        Accent = 'Cyan'; Q = 'Magenta'; Dim = 'DarkGray'; Bold = 'White'; Card = 'DarkCyan' }
if ($env:NO_COLOR) { foreach ($k in @($C.Keys)) { $C[$k] = '' } }

# Say 'text' 'Color' 'more text' 'Color' ...   (one line, several colors; '' = default color)
function Say {
    for ($i = 0; $i -lt $args.Count; $i += 2) {
        $t = "$($args[$i])"; $col = if ($i + 1 -lt $args.Count) { $args[$i + 1] } else { '' }
        if ($col) { Write-Host $t -NoNewline -ForegroundColor $col } else { Write-Host $t -NoNewline }
    }
    Write-Host ''
}
function Rep($s, $n) { if ($n -le 0) { return '' }; return ($s * $n) }
function Ok($m)   { Say '  ' '' $S.Ok $C.Ok " $m" '' }
function Info($m) { Say "    $m" '' }
function Dim($m)  { Say "    $m" $C.Dim }
function Warn($m) { Say '  ' '' $S.Warn $C.Warn " $m" '' }
function Doing($m) { Say '  ' '' $S.Arrow $C.Accent " $m" '' }
function Fail($m) {
    Write-Host ''
    Say "  $($S.X) $m" $C.Bad
    Say '    Nothing was broken. Fix the problem above, then run the installer again.' $C.Dim
    Write-Host ''
    throw 'Setup stopped.'
}
function Has($c)  { [bool](Get-Command $c -CommandType Application -ErrorAction SilentlyContinue) }
function Pretty($p) {
    $h = $HOME.TrimEnd('\')
    if ($p -and $p.StartsWith($h, [StringComparison]::OrdinalIgnoreCase)) { return '~' + $p.Substring($h.Length) }
    return $p
}
function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
}

# Step header:  [progress]  STEP 3 OF 6 / Title / plain-words explanation
function Step($n, $title, $why) {
    Write-Host ''; Write-Host ''
    Write-Host '  ' -NoNewline
    for ($i = 1; $i -le $TotalSteps; $i++) {
        if ($i -le $n) { Say2 $S.On $C.G2 } else { Say2 $S.Off $C.Dim }
    }
    Say "  STEP $n OF $TotalSteps" $C.Dim
    Say "  $title" $C.Bold
    if ($why) { Say "  $why" $C.Dim }
    Write-Host ''
}
function Say2($t, $col) { if ($col) { Write-Host $t -NoNewline -ForegroundColor $col } else { Write-Host $t -NoNewline } }

# Cards: a title and a left border (no right border, so long text never breaks it)
function CardTop($title) { Say "  $($S.TL)$($S.H) " $C.Card $title $C.Bold (' ' + (Rep $S.H (40 - $title.Length))) $C.Card }
function CardLine { Say2 "  $($S.V)  " $C.Card; Say @args }
function CardBottom { Say "  $($S.BL)$(Rep $S.H 43)" $C.Card }

# A closed box for short, fixed text
function Box($col, [string[]]$lines) {
    $w = 52
    Say "  $($S.TL)$(Rep $S.H $w)$($S.TR)" $col
    foreach ($l in $lines) {
        Say2 "  $($S.V) " $col; Say2 $l $C.Bold; Say2 (' ' * [Math]::Max(0, $w - 1 - $l.Length)) ''; Say $S.V $col
    }
    Say "  $($S.BL)$(Rep $S.H $w)$($S.BR)" $col
}

# Questions
function Ask($q, $def, $hint) {
    Write-Host ''
    Say '  ' '' '?' $C.Q " $q" $C.Bold
    if ($hint) { Say "    $hint" $C.Dim }
    Say2 "    $($S.In) " $C.Accent
    if ($def) { Say2 "[$def] " $C.Dim }
    $a = Read-Host
    if ([string]::IsNullOrWhiteSpace($a)) { return $def } else { return $a.Trim() }
}
function AskYes($q, $def = 'y') {
    $hint = if ($def -eq 'n') { '(y/N)' } else { '(Y/n)' }
    Write-Host ''
    Say2 '  ' ''; Say2 '?' $C.Q; Say2 " $q " $C.Bold; Say2 "$hint " $C.Dim; Say2 "$($S.In) " $C.Accent
    $a = Read-Host
    if ([string]::IsNullOrWhiteSpace($a)) { $a = $def }
    return ($a.Trim() -match '^(y|yes)$')
}

function GitQuote($s) { return '"' + (("$s" -replace '\\', '\\') -replace '"', '\"') + '"' }
function Winget-Install($id, $name) {
    if (-not (Has winget)) { Fail "$name is missing and winget isn't available. Install $name yourself, then run the installer again." }
    Doing "Installing $name (a permission window may pop up - click Yes)"
    winget install --id $id -e --source winget --accept-package-agreements --accept-source-agreements
    Refresh-Path
}

# A token in the environment would hide the accounts gh stores, and blocks "gh auth login".
# (This happens if you run the setup from inside a "claude" session.)
Remove-Item Env:GH_TOKEN, Env:GITHUB_TOKEN -ErrorAction SilentlyContinue

# ================================================================ Welcome
# Logo drawn with half blocks: T = upper half, L = lower half, # = full block
$logo = @(
    @('LTT #   LTL # # #TL ##T    LT  #L#', $C.G1),
    @('TLL #LL #T# TL# #LT #LL TT TL# # #', $C.G2),
    @('LTL LTT LTT LTL # # #L # T#T LTT',   $C.G4),
    @('#T# TLL TLL TLT TL# # T#  #  L##',   $C.G5)
)
Write-Host ''
foreach ($row in $logo) {
    Say ('   ' + ($row[0].Replace('T', (U 0x2580)).Replace('L', (U 0x2584)).Replace('#', (U 0x2588)))) $row[1]
}
Write-Host ''
Say '   One computer. Many GitHub accounts. Zero mix-ups.' $C.Bold
Write-Host ''
Dim 'This sets things up so each of your GitHub accounts (work, personal, ...)'
Dim 'gets its own folder. Work inside a folder and everything - commits, pushes'
Dim 'and Claude Code - automatically uses the right account.'
Write-Host ''
Dim 'Takes about 3 minutes. Just answer the questions; press Enter to accept'
Dim 'the suggestion in [brackets]. Stop any time with Ctrl+C - nothing breaks.'

# ================================================================ Step 1
Step 1 'Checking your computer' "Making sure we know what we're working with."
$arch = $env:PROCESSOR_ARCHITECTURE
try {
    $cpu = (Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1).Architecture
    if ($cpu -eq 12) { $arch = 'ARM64' } elseif ($cpu -eq 9) { $arch = 'x64' }
} catch { }
Ok "Windows on $arch, PowerShell $($PSVersionTable.PSVersion)"

if (-not (Has git)) { Winget-Install 'Git.Git' 'Git' }
if (-not (Has git)) { Fail 'Git still not found. Close this window, open a new PowerShell window and run the installer again.' }
Say '  ' '' $S.Ok $C.Ok ' Git is ready ' '' "($((git --version) -replace '^git version ', ''))" $C.Dim

# ================================================================ Step 2
Step 2 'GitHub CLI' "GitHub's official tool. It logs you in and keeps your passwords safe."
function Gh-Version {
    $line = gh --version 2>$null | Select-Object -First 1
    if ($line -match '(\d+)\.(\d+)\.(\d+)') { return [version]"$($Matches[1]).$($Matches[2]).$($Matches[3])" }
    return [version]'0.0.0'
}
if (-not (Has gh)) { Winget-Install 'GitHub.cli' 'GitHub CLI' }
if (-not (Has gh)) { Fail 'GitHub CLI still not found. Close this window, open a new PowerShell window and run the installer again.' }
if ((Gh-Version) -lt [version]'2.40.0') {
    Warn 'Your GitHub CLI is too old for multiple accounts (needs 2.40+). Updating it.'
    winget upgrade --id GitHub.cli -e --source winget --accept-package-agreements --accept-source-agreements
    Refresh-Path
}
if ((Gh-Version) -lt [version]'2.40.0') { Fail 'GitHub CLI 2.40 or newer is needed. Get it from https://cli.github.com' }
Say '  ' '' $S.Ok $C.Ok ' GitHub CLI is ready ' '' "($(Gh-Version))" $C.Dim

# ================================================================ Step 3
Step 3 'Claude Code' "Your AI coding assistant, installed with Anthropic's official installer."
$localBin = Join-Path $HOME '.local\bin'
function First-Claude {
    # The real Claude Code, not our own Command Prompt helper
    Get-Command claude -CommandType Application -ErrorAction SilentlyContinue |
        Where-Object { (Split-Path -Parent $_.Source) -ne $ShimDir } | Select-Object -First 1
}
function Test-Claude($path) {
    try { & $path --version *> $null; return ($LASTEXITCODE -eq 0) } catch { return $false }
}
function Claude-Version($path) { try { return "$(& $path --version 2>$null | Select-Object -First 1)" } catch { return '' } }
$c = First-Claude
if ($c -and (Test-Claude $c.Source)) {
    Say '  ' '' $S.Ok $C.Ok ' Claude Code is ready ' '' "($(Claude-Version $c.Source))" $C.Dim
} else {
    if ($c) { Warn "Found a Claude Code install that doesn't start ($($c.Source)). Reinstalling it." }
    if (Has npm) {
        $npmHas = npm ls -g @anthropic-ai/claude-code 2>$null | Out-String
        if ($npmHas -match 'claude-code') {
            Doing 'Removing an old copy installed with npm'
            npm uninstall -g @anthropic-ai/claude-code 2>$null | Out-Null
        }
    }
    Doing 'Installing Claude Code'
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
        Fail "A broken Claude Code file is in the way: $($c.Source). Delete it (as Administrator), then run the installer again."
    }
    Say '  ' '' $S.Ok $C.Ok ' Claude Code installed ' '' "($(Claude-Version $c.Source))" $C.Dim
}

# ================================================================ Step 4
Step 4 'Your GitHub accounts' "Each account gets its own folder. That's the whole trick."
CardTop 'How it works'
CardLine '~\code\work       ' '' $S.Arrow $C.Accent '  your work account' ''
CardLine '~\code\personal   ' '' $S.Arrow $C.Accent '  your personal account' ''
CardLine ''
CardLine "Every project inside a folder uses that folder's account." $C.Dim
CardBottom
Write-Host ''
Say '  ' '' $S.Warn $C.Warn ' Heads-up:' $C.Bold " when your browser opens to log in, make sure it's signed in to" ''
Say '    the ' '' 'right' $C.Bold ' GitHub account. If not, sign out on github.com first, or paste' ''
Info 'the link into a private/incognito window.'

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
function Show-Accounts($title, $bullet) {
    CardTop $title
    foreach ($e in $map) {
        $lbl = if ($e.Label) { $e.Label } else { '?' }
        CardLine "$bullet " $C.Ok ('{0,-10} {1,-20} ' -f $lbl, $e.User) '' (Pretty $e.Folder) $C.Dim
    }
    CardBottom
}
$firstRun = ($map.Count -eq 0)
if ($map.Count) { Write-Host ''; Show-Accounts 'Already set up' $S.Arrow }

# gh's own login can point all of github.com at gh's *active* account. Git reads settings top to
# bottom and the last one wins, so if that setting sits below the per-folder ones it overrides
# them. Move the per-folder entries to the end of ~/.gitconfig. gh's setting stays in place, so
# repos outside the account folders keep working exactly as before.
function Put-AccountsLast {
    foreach ($e in $map) {
        $key = "includeIf.gitdir/i:$(GitDir $e.Folder)"
        $path = git config --global --get "$key.path" 2>$null
        if (-not $path) { continue }
        git config --global --remove-section $key 2>$null
        git config --global "$key.path" "$path"
    }
}

# ---- SSH (only for accounts whose projects use git@github.com: addresses)
# Prefer Git for Windows' own ssh tools: they are the ones git uses.
function Find-SshTool($name) {
    $git = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($git) {
        $dir = Split-Path -Parent $git.Source
        for ($i = 0; $i -lt 3 -and $dir; $i++) {
            $dir = Split-Path -Parent $dir
            if ($dir) { $p = Join-Path $dir "usr\bin\$name.exe"; if (Test-Path $p) { return $p } }
        }
    }
    $c = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($c) { return $c.Source }
    return $null
}
# Which GitHub account does this key log in as? (empty if none)
function Ssh-WhoAmI($ssh, $keyFwd) {
    $out = & $ssh -i $keyFwd -o IdentitiesOnly=yes -o ConnectTimeout=15 -T git@github.com 2>&1 | ForEach-Object { "$_" }
    foreach ($l in $out) { if ($l -match '^Hi ([^!]+)!') { return $Matches[1] } }
    return ''
}
# Trust GitHub's SSH servers using the fingerprints from GitHub's API (fetched over HTTPS),
# so there is no "authenticity of host can't be established" question.
function Trust-GitHubHost($keygen) {
    $kh = Join-Path $HOME '.ssh\known_hosts'
    if (Test-Path $kh) { & $keygen -F github.com -f ($kh -replace '\\', '/') *> $null; if ($LASTEXITCODE -eq 0) { return } }
    $keys = @(gh api meta --jq '.ssh_keys[]' 2>$null | Where-Object { $_ })
    if (-not $keys.Count) { return }
    $text = (($keys | ForEach-Object { "github.com $_" }) -join "`n") + "`n"
    if ((Test-Path $kh) -and (Get-Item $kh).Length -gt 0 -and -not ((Get-Content $kh -Raw).EndsWith("`n"))) { $text = "`n" + $text }
    [IO.File]::AppendAllText($kh, $text, (New-Object Text.ASCIIEncoding))
    Ok "Added GitHub's official SSH fingerprints"
}
# Returns the path of a working key for this account, or '' (HTTPS only).
function Setup-Ssh($label, $u) {
    $ssh = Find-SshTool 'ssh'; $keygen = Find-SshTool 'ssh-keygen'
    if (-not $ssh -or -not $keygen) { Warn "SSH isn't installed on this computer, so this account will use HTTPS only."; return '' }
    New-Item -ItemType Directory -Force -Path (Join-Path $HOME '.ssh') | Out-Null
    $key = Join-Path $HOME ".ssh\claude-gh-$label"
    if (Test-Path $key) {
        Ok "Using the SSH key made earlier: $(Pretty $key)"
    } else {
        $custom = Ask "Already have an SSH key for '$u'? Type its path, or just press Enter to create one" '' 'For example  ~\.ssh\id_ed25519_work   (the private key, not the .pub file)'
        if ($custom) {
            if ($custom.StartsWith('~')) { $custom = $HOME + $custom.Substring(1) }
            $key = $custom
            if (-not (Test-Path $key) -or -not (Test-Path "$key.pub")) {
                Warn "Couldn't find both $(Pretty $key) and $(Pretty $key).pub - this account will use HTTPS only."; return ''
            }
        } else {
            # Start-Process passes the command line as-is, so the empty passphrase ("") survives
            # on both Windows PowerShell 5.1 and PowerShell 7
            $argLine = "-q -t ed25519 -N `"`" -C `"claude-gh-accounts $label`" -f `"$($key -replace '\\', '/')`""
            $p = Start-Process -FilePath $keygen -ArgumentList $argLine -NoNewWindow -Wait -PassThru
            if ($p.ExitCode -ne 0 -or -not (Test-Path $key)) { Warn "Couldn't create an SSH key - this account will use HTTPS only."; return '' }
            Ok "Created a new SSH key: $(Pretty $key)"
        }
    }
    $keyFwd = $key -replace '\\', '/'
    Trust-GitHubHost $keygen

    $who = Ssh-WhoAmI $ssh $keyFwd
    if ($who -and $who -ne $u) {
        Warn "That key is already linked to GitHub account '$who', not '$u'."
        Info 'GitHub allows each key on one account only. Run the installer again and pick another key.'
        return ''
    }
    if (-not $who) {
        Doing "Adding the key to GitHub account $u"
        $title = "claude-gh-accounts ($env:COMPUTERNAME)"
        $saved = $env:GH_TOKEN
        try {
            $env:GH_TOKEN = "$(gh auth token --user $u 2>$null)".Trim()
            $out = gh ssh-key add "$key.pub" --title $title 2>&1 | Out-String
            $failed = ($LASTEXITCODE -ne 0)
        } finally { $env:GH_TOKEN = $saved }
        if ($failed -and $out -match 'scope|403|404') {
            Info "GitHub needs your OK to add SSH keys for $u. One more browser step:"
            gh auth switch --hostname github.com --user $u *> $null
            gh auth refresh --hostname github.com --scopes admin:public_key
            try {
                $env:GH_TOKEN = "$(gh auth token --user $u 2>$null)".Trim()
                gh ssh-key add "$key.pub" --title $title *> $null
            } finally { $env:GH_TOKEN = $saved }
        }
        $who = Ssh-WhoAmI $ssh $keyFwd
    }
    if ($who -and $who -eq $u) { Ok "SSH works for $u"; return $keyFwd }
    Warn "GitHub didn't accept the key yet. Add it by hand, then run the installer again:"
    Info "1. Open  https://github.com/settings/ssh/new  (signed in as $u)"
    Info '2. Paste this key and save:'
    Dim "   $((Get-Content "$key.pub" -Raw).Trim())"
    return ''
}

# Pushes that change GitHub Actions files (.github/workflows) need the "workflow" permission.
# Logins made without it get "refusing to allow an OAuth App to create or update workflow".
function Ensure-WorkflowScope($u) {
    $tok = gh auth token --user $u 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $tok) { return }
    $saved = $env:GH_TOKEN
    try { $env:GH_TOKEN = "$tok".Trim(); $headers = gh api -i user 2>$null } finally { $env:GH_TOKEN = $saved }
    $scopes = ''
    foreach ($h in @($headers)) { if ("$h" -match '^x-oauth-scopes:\s*(.*)$') { $scopes = $Matches[1].Trim() } }
    if (-not $scopes) { return }  # couldn't check (offline, or a token type without scopes): don't nag
    if ((($scopes -split ',') | ForEach-Object { $_.Trim() }) -contains 'workflow') { return }
    Warn "The login for $u can't change GitHub Actions files (.github/workflows),"
    Info 'so pushes that touch them would be refused. One more browser step fixes it.'
    if (AskYes 'Fix it now?' 'y') {
        gh auth switch --hostname github.com --user $u *> $null
        gh auth refresh --hostname github.com --scopes workflow
        if ($LASTEXITCODE -eq 0) { Ok "$u can now push GitHub Actions changes" }
        else { Warn "Couldn't add it. Later, run:  gh auth switch --user $u  then  gh auth refresh -s workflow" }
    } else {
        Dim "Later, run:  gh auth switch --user $u  then  gh auth refresh -s workflow"
    }
}

# ---- Smart defaults, so re-runs and new accounts are mostly "press Enter"
# GitHub accounts already logged in to gh on this computer
function Get-LoggedInUsers {
    $out = gh auth status --hostname github.com 2>&1 | ForEach-Object { "$_" }
    foreach ($l in $out) { if ($l -match 'Logged in to github\.com account ([A-Za-z0-9-]+)') { $Matches[1] } }
}
# Name and email from the GitHub profile. When the email is private, use the account's
# no-reply address (<id>+<login>@users.noreply.github.com), which GitHub always accepts.
function Get-GitHubProfile($u) {
    $result = @{ Name = ''; Email = '' }
    $tok = gh auth token --user $u 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $tok) { return $result }
    $saved = $env:GH_TOKEN
    # Parse the JSON here (no --jq): PowerShell 5.1 and 7 pass quotes to programs differently
    try { $env:GH_TOKEN = "$tok".Trim(); $json = gh api user 2>$null | Out-String } finally { $env:GH_TOKEN = $saved }
    try { $o = $json | ConvertFrom-Json } catch { return $result }
    if (-not $o) { return $result }
    if ($o.name) { $result.Name = "$($o.name)" }
    if ($o.email) { $result.Email = "$($o.email)" }
    elseif ($o.id -and $o.login) { $result.Email = "$($o.id)+$($o.login)@users.noreply.github.com" }
    return $result
}
# What's already saved for this GitHub user?
function Get-ExistingAccount($u) {
    $ex = @{ Label = ''; Folder = ''; Name = ''; Email = ''; Ssh = '' }
    $e = $map | Where-Object { $_.User -eq $u } | Select-Object -First 1
    if (-not $e) { return $ex }
    $ex.Folder = $e.Folder; $ex.Label = $e.Label
    $cfgp = git config --global --get "includeIf.gitdir/i:$(GitDir $e.Folder).path" 2>$null
    if (-not $ex.Label -and $cfgp) { $ex.Label = ($cfgp -split '\.gitconfig-')[-1] }
    if (-not $cfgp) { $cfgp = Join-Path $HOME ".gitconfig-$($ex.Label)" }
    $ex.Name  = "$(git config --file $cfgp user.name 2>$null)"
    $ex.Email = "$(git config --file $cfgp user.email 2>$null)"
    $ex.Ssh   = "$(git config --file $cfgp core.sshCommand 2>$null)"
    return $ex
}

$defaultName = git config --global user.name 2>$null
$another = if ($map.Count) { AskYes 'Add or change an account now?' 'n' } else { $true }
$count = 0

while ($another) {
    $count++
    Write-Host ''
    Say "  $(Rep $S.H 3) ACCOUNT $count $(Rep $S.H 40)" $C.G3

    # Suggest an account that's logged in on this computer but not set up yet
    $loggedIn = @(Get-LoggedInUsers)
    $suggest = ''
    foreach ($u in $loggedIn) { if (-not (Get-ExistingAccount $u).Folder) { $suggest = $u; break } }
    $hint = if ($loggedIn.Count) { "Logged in on this computer: $($loggedIn -join ', ')" } else { 'The name you log in with, shown at github.com/<username>' }
    $user = Ask 'Which GitHub account?' $suggest $hint
    if ("$user" -notmatch '^[A-Za-z0-9][A-Za-z0-9-]{0,38}$') { Warn "That doesn't look like a GitHub username (letters, numbers and dashes only)."; $count--; continue }
    $ex = Get-ExistingAccount $user
    if ($ex.Folder) { Ok "'$user' is already set up - press Enter to keep each answer." }

    $defLabel = if ($ex.Label) { $ex.Label } else { $user.ToLower() -replace '[^a-z0-9-]', '' }
    $label = ((Ask 'Give this account a nickname' $defLabel 'One word, e.g.  work,  personal,  client1') + '').ToLower() -replace '[^a-z0-9-]', ''
    if (-not $label) { Warn 'Please use letters or numbers.'; $count--; continue }
    Write-Host ''

    gh auth token --user $user *> $null
    if ($LASTEXITCODE -eq 0) {
        Ok "Already logged in to GitHub as $user"
    } else {
        while ($true) {
            Doing "Logging in as $user. A browser window will open - follow the steps there."
            Dim '(Choose "Login with a web browser" and copy the one-time code it shows.)'
            gh auth login --hostname github.com --git-protocol https --web --scopes workflow
            gh auth token --user $user *> $null
            if ($LASTEXITCODE -eq 0) { Ok "Logged in as $user"; break }
            $who = gh api user --jq .login 2>$null
            # GitHub usernames aren't case sensitive, but gh stores them exactly as GitHub spells them
            if ($who -and ("$who".Trim() -eq $user)) { $user = "$who".Trim(); Ok "Logged in as $user"; break }
            if (-not $who) { $who = 'unknown' }
            Warn "That login was for '$who', not '$user'. The browser was signed in to a different account."
            if ($who -ne 'unknown') { Dim "(To remove that login later: gh auth logout --user $who)" }
            if (-not (AskYes 'Try logging in again?' 'y')) { Warn "Skipped. Run the installer again to finish logging in as $user."; break }
        }
    }
    Ensure-WorkflowScope $user
    $gp = Get-GitHubProfile $user

    $defFolder = if ($ex.Folder) { $ex.Folder } else { Join-Path $HOME "code\$label" }
    $folder = Ask "Which folder should hold the '$label' projects?" $defFolder "It will be created if it doesn't exist yet"
    if ($folder.StartsWith('~')) { $folder = $HOME + $folder.Substring(1) }
    if ($folder.Contains('|')) { Warn "The folder name can't contain '|'."; $count--; continue }
    try {
        $folder = [IO.Path]::GetFullPath($folder).TrimEnd('\')
    } catch { Warn "That folder name isn't valid: $($_.Exception.Message)"; $count--; continue }
    if ($folder.Length -le 3 -or $folder -eq $HOME.TrimEnd('\')) { Warn "Please pick a folder of its own, not $folder itself."; $count--; continue }
    try {
        New-Item -ItemType Directory -Force -Path $folder -ErrorAction Stop | Out-Null
    } catch { Warn "Couldn't create that folder: $($_.Exception.Message)"; $count--; continue }

    $defName = if ($ex.Name) { $ex.Name } elseif ($gp.Name) { $gp.Name } else { $defaultName }
    $name = Ask 'Your name, as it should appear on your work' $defName 'Shown next to every change you save (a "commit")'
    if (-not $name) { Warn "A name is needed - Git won't save changes without one."; $count--; continue }

    $defEmail = if ($ex.Email) { $ex.Email } else { $gp.Email }
    $emailHint = if ($defEmail -like '*@users.noreply.github.com') { 'Suggested: your private GitHub address - it keeps your real email hidden' } else { 'Use an email added to this GitHub account (github.com/settings/emails)' }
    $email = Ask 'Email for this account' $defEmail $emailHint
    if ("$email" -notmatch '^\S+@\S+$') { Warn 'Please enter a valid email address.'; $count--; continue }

    Write-Host ''
    CardTop 'Quick check'
    CardLine ('{0,-10}' -f 'Nickname') $C.Dim $label $C.Bold
    CardLine ('{0,-10}' -f 'GitHub')   $C.Dim $user $C.Bold
    CardLine ('{0,-10}' -f 'Folder')   $C.Dim (Pretty $folder) $C.Bold
    CardLine ('{0,-10}' -f 'Commits')  $C.Dim $name $C.Bold " <$email>" $C.Dim
    CardBottom
    if (-not (AskYes 'Does this look right?' 'y')) { Info "No problem - let's try that account again."; $count--; continue }

    $sshKey = ''
    $sshDefault = if ($ex.Ssh -or (Test-Path (Join-Path $HOME ".ssh\claude-gh-$label"))) { 'y' } else { 'n' }
    Write-Host ''
    Dim 'Project addresses look like  https://github.com/...  or  git@github.com:...  (SSH).'
    Dim "HTTPS always works. If you're not sure, answer no - you can add SSH later."
    if (AskYes "Do your '$label' projects use SSH addresses (git@github.com:...)?" $sshDefault) {
        $sshKey = Setup-Ssh $label $user
    }

    # Per-folder git settings: commit identity + which account git uses for github.com
    # The helper hands git this account's token, and prints a hint if GitHub ever rejects it.
    # With SSH, core.sshCommand picks this account's key for git@github.com: addresses.
    # Written directly (not via "git config") because Windows PowerShell mangles quotes and empty values passed to programs
    $cfg = Join-Path $HOME ".gitconfig-$label"
    $helper = '!f() { case "$1" in get) echo "username=' + $user + '"; echo "password=$(gh auth token --user ' + $user + ')" ;; ' +
              'erase) echo "claude-gh-accounts: GitHub did not accept the saved login for ' + $user + '. Log in again with: gh auth login   Help: ' +
              $RepoUrl + '#-troubleshooting" >&2 ;; esac; }; f'
    $cfgText = "[user]`n`tname = $(GitQuote $name)`n`temail = $(GitQuote $email)`n" +
               "[credential `"https://github.com`"]`n`thelper =`n`thelper = $(GitQuote $helper)`n"
    if ($sshKey) { $cfgText += "[core]`n`tsshCommand = $(GitQuote "ssh -i '$sshKey' -o IdentitiesOnly=yes")`n" }
    [IO.File]::WriteAllText($cfg, $cfgText, (New-Object Text.UTF8Encoding($false)))
    $cfgFwd = $cfg -replace '\\', '/'

    # Forget earlier entries for this folder or this label (e.g. the label moved to a new folder)
    foreach ($e in @($map)) {
        if ($e.Folder -eq $folder) { [void]$map.Remove($e); continue }
        $oldCfg = git config --global --get "includeIf.gitdir/i:$(GitDir $e.Folder).path" 2>$null
        if ($e.Label -eq $label -or "$oldCfg" -eq $cfgFwd) {
            git config --global --unset-all "includeIf.gitdir/i:$(GitDir $e.Folder).path" 2>$null
            Info "$($e.Folder) no longer uses '$label'"
            [void]$map.Remove($e)
        }
    }
    git config --global --replace-all "includeIf.gitdir/i:$(GitDir $folder).path" $cfgFwd
    [void]$map.Add([pscustomobject]@{ Folder = $folder; User = $user; Label = $label })
    Save-Map
    Ok "Repos in $(Pretty $folder) will now use $user"

    Put-AccountsLast
    $another = AskYes 'Add another GitHub account?' 'n'
}
if ($map.Count -eq 0) { Fail "No accounts are set up yet. Run the installer again when you're ready." }
Put-AccountsLast

# ================================================================ Step 5
Step 5 'Turning on auto-switching' 'Teaching the claude command to pick the right account by itself.'
$launcher = @'
# >>> claude-gh-accounts >>>
# Starts Claude Code with the GitHub account that matches the current folder.
# Managed by claude-gh-accounts (https://github.com/us-urvin/claude-gh-accounts):
# run the installer again to change accounts.
function claude {
    $exe = Get-Command claude -CommandType Application -ErrorAction SilentlyContinue |
        Where-Object { $_.Source -notlike '*\claude-gh-accounts\bin\*' } | Select-Object -First 1
    if (-not $exe) { Write-Host 'Claude Code was not found. Run the claude-gh-accounts installer again.' -ForegroundColor Red; return }
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
    Ok "Added the smart claude command to $(Pretty $p)"
}

# Command Prompt (cmd.exe) doesn't read PowerShell profiles, so it gets a small claude.cmd
# in its own folder at the front of your PATH. It looks up the account (claude-gh-lookup.ps1)
# and then starts the real Claude Code with that account's token.
$cmdShim = @'
@echo off
rem Starts Claude Code with the GitHub account that matches the current folder.
rem Managed by claude-gh-accounts (https://github.com/us-urvin/claude-gh-accounts):
rem run the installer again to change accounts.
setlocal
set "CGA_EXE="
set "CGA_USER="
set "CGA_TOKEN="
for /f "usebackq tokens=1-3 delims=|" %%A in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0claude-gh-lookup.ps1"`) do (
  set "CGA_EXE=%%A"
  set "CGA_USER=%%B"
  set "CGA_TOKEN=%%C"
)
if not defined CGA_EXE for /f "delims=" %%P in ('where claude.exe 2^>nul') do if not defined CGA_EXE set "CGA_EXE=%%P"
if not defined CGA_EXE (
  echo Claude Code was not found. Run the claude-gh-accounts installer again.
  exit /b 1
)
if defined CGA_TOKEN (
  echo GitHub account: %CGA_USER%
  set "GH_TOKEN=%CGA_TOKEN%"
) else if defined CGA_USER (
  echo Not logged in to GitHub as %CGA_USER%. Run: gh auth login
)
call "%CGA_EXE%" %*
exit /b %ERRORLEVEL%
'@
$cmdLookup = @'
# Used by claude.cmd: prints "<real claude path>|<github user>|<token>" for the current folder.
# Managed by claude-gh-accounts (https://github.com/us-urvin/claude-gh-accounts).
$bin = Split-Path -Parent $MyInvocation.MyCommand.Path
$exe = Get-Command claude -CommandType Application -ErrorAction SilentlyContinue |
    Where-Object { (Split-Path -Parent $_.Source) -ne $bin } | Select-Object -First 1
if (-not $exe) { exit 1 }
$map  = Join-Path $HOME '.claude-gh-accounts'
$here = (Get-Location).ProviderPath.TrimEnd('\') + '\'
$user = ''; $best = 0
if (Test-Path $map) {
    foreach ($line in Get-Content $map) {
        $p = $line -split '\|'
        if ($p.Count -lt 2 -or -not $p[0] -or -not $p[1]) { continue }
        $f = $p[0].TrimEnd('\') + '\'
        if ($here.StartsWith($f, [StringComparison]::OrdinalIgnoreCase) -and $f.Length -gt $best) { $user = $p[1]; $best = $f.Length }
    }
}
$tok = ''
if ($user) {
    $t = gh auth token --user $user 2>$null
    if ($LASTEXITCODE -eq 0 -and $t) { $tok = "$t".Trim() }
}
"$($exe.Source)|$user|$tok"
'@
try {
    New-Item -ItemType Directory -Force -Path $ShimDir -ErrorAction Stop | Out-Null
    $ascii = New-Object Text.ASCIIEncoding
    [IO.File]::WriteAllText((Join-Path $ShimDir 'claude.cmd'), ($cmdShim -replace "`r?`n", "`r`n") + "`r`n", $ascii)
    [IO.File]::WriteAllText((Join-Path $ShimDir 'claude-gh-lookup.ps1'), ($cmdLookup -replace "`r?`n", "`r`n") + "`r`n", $ascii)
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not $userPath) { $userPath = '' }
    $rest = @($userPath -split ';' | Where-Object { $_ -and ($_.TrimEnd('\') -ne $ShimDir) })
    [Environment]::SetEnvironmentVariable('Path', ((@($ShimDir) + $rest) -join ';'), 'User')
    Refresh-Path
    Ok 'Added the smart claude command to Command Prompt'
    $real = First-Claude
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine') -split ';' | ForEach-Object { $_.TrimEnd('\') }
    if ($real -and ($machinePath -contains (Split-Path -Parent $real.Source))) {
        Warn 'Claude Code is installed for all users, so Command Prompt finds it first and skips account switching.'
        Info 'PowerShell switches accounts as normal. Git switches accounts everywhere.'
    }
} catch {
    Warn "Couldn't set up Command Prompt: $($_.Exception.Message)"
    Info 'PowerShell switches accounts as normal. Git switches accounts everywhere.'
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
        Ok 'Allowed PowerShell to load the smart command (for your user only)'
    } catch {
        Warn "Couldn't allow PowerShell to load the smart command: $($_.Exception.Message)"
        Warn 'Your company may control this setting. Ask IT - until then "claude" will not switch accounts by itself.'
    }
}

# ================================================================ Step 6
Step 6 'All done!' ''
Box $C.Ok @('', "  $($S.Ok)  You're all set! Nice work.", '')
Write-Host ''
Show-Accounts 'Your accounts' $S.Dot

$first = $map[0]
Write-Host ''
CardTop 'What to do now'
CardLine '1' $C.G2 '  Close this window and open a ' '' 'new' $C.Bold ' PowerShell or Command Prompt window.' ''
CardLine "   (This one doesn't know about the new setup yet.)" $C.Dim
CardLine '2' $C.G2 '  Go to an account folder:   ' '' "cd $(Pretty $first.Folder)" $C.Accent
CardLine '3' $C.G2 '  Download a project:        ' '' 'git clone https://github.com/OWNER/REPO.git' $C.Accent
CardLine '   (or  git clone git@github.com:OWNER/REPO.git  if you set up SSH)' $C.Dim
CardLine '4' $C.G2 '  Go into it and type:       ' '' 'claude' $C.Accent
CardLine "   You'll see " '' "GitHub account: $($first.User)" $C.Accent " - that's it working!" ''
CardBottom
Write-Host ''
Dim 'Projects outside these folders keep working exactly as before.'
Dim 'Run the installer again any time to add or change an account.'
Dim "Push not working? Common errors and fixes: $RepoUrl#-troubleshooting"

# ================================================================ Star
Write-Host ''
Say '  ' '' $S.Heart $C.Bad '  Enjoying it? A star on GitHub helps other people find it.' $C.Bold
Say "     $RepoUrl" $C.Accent
if ($firstRun -and (AskYes 'Open it in your browser now?' 'y')) {
    try { Start-Process $RepoUrl -ErrorAction Stop; Ok 'Thank you!' } catch { Info "Couldn't open a browser here. Copy the link above instead." }
}
Write-Host ''
