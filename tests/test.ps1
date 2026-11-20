# Tests for the "claude" launcher that install.ps1 adds to the PowerShell profile.
# Uses fake "gh" and "claude" commands and a throwaway HOME. Nothing real is touched.
# Usage: powershell -ExecutionPolicy Bypass -File tests\test.ps1
$ErrorActionPreference = 'Stop'
$script:pass = 0; $script:failed = 0
function Check($desc, $expected, $actual) {
    if ("$expected" -eq "$actual") { $script:pass++; Write-Host "  ok   $desc" }
    else { $script:failed++; Write-Host "  FAIL $desc`n       expected: $expected`n       actual:   $actual" -ForegroundColor Red }
}

$root = Split-Path -Parent $PSScriptRoot
$src  = Get-Content (Join-Path $root 'install.ps1') -Raw

Write-Host 'Syntax'
$errs = $null
$null = [System.Management.Automation.Language.Parser]::ParseInput($src, [ref]$null, [ref]$errs)
Check 'install.ps1 parses' 0 @($errs).Count
$m = [regex]::Match($src, "(?s)\`$launcher = @'\r?\n(.*?)\r?\n'@")
Check 'launcher block found' $true $m.Success

Write-Host 'Launcher'
$T = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid())
$bin = Join-Path $T 'bin'
New-Item -ItemType Directory -Force $bin | Out-Null
Set-Content (Join-Path $bin 'claude.cmd') @('@echo GH_TOKEN=%GH_TOKEN%', '@echo ARGS=%*') -Encoding ascii
Set-Content (Join-Path $bin 'gh.cmd') '@if "%4"=="nobody" (exit /b 1) else (echo TOKEN-for-%4)' -Encoding ascii
# Same fake for git's credential helper, which runs in Git for Windows' sh (it can't run .cmd files)
[IO.File]::WriteAllText((Join-Path $bin 'gh'), "#!/bin/sh`necho `"TOKEN-for-`$4`"`n")
$oldHome = $HOME; $oldPath = $env:Path
try {
    Set-Variable -Name HOME -Value $T -Force -Scope Global
    $env:Path = "$bin;$env:Path"
    $env:GH_TOKEN = $null
    foreach ($d in 'code\work\repo', 'code\workshop', 'code\work\client\x', 'code\ghost', 'elsewhere') {
        New-Item -ItemType Directory -Force (Join-Path $T $d) | Out-Null
    }
    @(
        "$T\code\work|alice|work",
        "$T\code\workshop|bob",
        "$T\code\work\client|carol|client",
        "$T\code\ghost|nobody|ghost"
    ) -join "`n" | Set-Content (Join-Path $T '.claude-gh-accounts') -Encoding ascii

    . ([scriptblock]::Create($m.Groups[1].Value))
    function Invoke-At($dir) {
        Push-Location (Join-Path $T $dir)
        try { return (claude 6>$null | Where-Object { $_ -match '^GH_TOKEN=' } | Select-Object -First 1) } finally { Pop-Location }
    }
    Check 'repo inside folder uses its account'  'GH_TOKEN=TOKEN-for-alice' (Invoke-At 'code\work\repo')
    Check 'similar folder name is not confused'  'GH_TOKEN=TOKEN-for-bob'   (Invoke-At 'code\workshop')
    Check 'nested folder: longest match wins'    'GH_TOKEN=TOKEN-for-carol' (Invoke-At 'code\work\client\x')
    Check 'not logged in: runs without a token'  'GH_TOKEN='               (Invoke-At 'code\ghost')
    Check 'outside all folders: no token'        'GH_TOKEN='               (Invoke-At 'elsewhere')
    Check 'GH_TOKEN is restored afterwards'      $null                      $env:GH_TOKEN

    Write-Host 'Command Prompt (claude.cmd)'
    $shim = Join-Path $T 'shim'
    New-Item -ItemType Directory -Force $shim | Out-Null
    foreach ($pair in @(@('cmdShim', 'claude.cmd'), @('cmdLookup', 'claude-gh-lookup.ps1'))) {
        $mm = [regex]::Match($src, "(?s)\`$$($pair[0]) = @'\r?\n(.*?)\r?\n'@")
        Check "$($pair[1]) block found" $true $mm.Success
        Set-Content (Join-Path $shim $pair[1]) ($mm.Groups[1].Value -replace "`r?`n", "`r`n") -Encoding ascii
    }
    # The lookup runs in a new PowerShell, which takes HOME from these variables
    $oldProfile = $env:USERPROFILE; $oldDrive = $env:HOMEDRIVE; $oldHPath = $env:HOMEPATH
    $env:USERPROFILE = $T; $env:HOMEDRIVE = $T.Substring(0, 2); $env:HOMEPATH = $T.Substring(2)
    function Invoke-Cmd($dir, $cmdArgs) {
        $out = cmd /c "cd /d `"$(Join-Path $T $dir)`" && `"$shim\claude.cmd`" $cmdArgs"
        return @($out)
    }
    try {
        $out = Invoke-Cmd 'code\work\repo' '--model opus "two words"'
        Check 'cmd: shows the account'               'GitHub account: alice'       ($out | Where-Object { $_ -like 'GitHub account:*' } | Select-Object -First 1)
        Check 'cmd: repo inside folder uses its account' 'GH_TOKEN=TOKEN-for-alice' ($out | Where-Object { $_ -match '^GH_TOKEN=' })
        Check 'cmd: arguments are passed through'    'ARGS=--model opus "two words"' ($out | Where-Object { $_ -match '^ARGS=' })
        Check 'cmd: nested folder: longest match wins' 'GH_TOKEN=TOKEN-for-carol' ((Invoke-Cmd 'code\work\client\x' '') | Where-Object { $_ -match '^GH_TOKEN=' })
        Check 'cmd: outside all folders: no token'   'GH_TOKEN='                    ((Invoke-Cmd 'elsewhere' '') | Where-Object { $_ -match '^GH_TOKEN=' })
    } finally {
        $env:USERPROFILE = $oldProfile; $env:HOMEDRIVE = $oldDrive; $env:HOMEPATH = $oldHPath
    }

    Write-Host 'Git config written by install.ps1'
    # Run the installer's own lines that build ~/.gitconfig-<label>, then ask real git for credentials
    $gq  = [regex]::Match($src, '(?m)^function GitQuote.*$').Value
    $hlp = [regex]::Match($src, '(?s)    \$helper = .*?f''\r?\n').Value
    $txt = [regex]::Match($src, '(?s)    \$cfgText = .*?`n"\r?\n').Value
    Check 'config-building lines found' $true ([bool]($gq -and $hlp -and $txt))
    $user = 'alice'; $name = 'Alice "Al" A'; $email = 'alice@example.com'; $RepoUrl = 'https://github.com/us-urvin/claude-gh-accounts'
    . ([scriptblock]::Create("$gq`n$hlp`n$txt"))
    $cfgFile = Join-Path $T '.gitconfig-work'
    [IO.File]::WriteAllText($cfgFile, $cfgText, (New-Object Text.UTF8Encoding($false)))
    $repo = Join-Path $T 'code\work\repo'
    # Keep the real global/system git config (and its credential helpers) out of the test
    $oldGlobal = $env:GIT_CONFIG_GLOBAL; $oldNoSys = $env:GIT_CONFIG_NOSYSTEM
    $env:GIT_CONFIG_GLOBAL = Join-Path $T 'empty-gitconfig'; $env:GIT_CONFIG_NOSYSTEM = '1'
    New-Item -ItemType File -Force $env:GIT_CONFIG_GLOBAL | Out-Null
    try {
        git -C $repo init -q
        git -C $repo config include.path ($cfgFile -replace '\\', '/')
        Check 'commit name (with quotes) survives' 'Alice "Al" A' (git -C $repo config user.name)
        # Feed git from files with LF line endings (Windows PowerShell pipes CRLF)
        $q = Join-Path $T 'query.txt'; $r = Join-Path $T 'reject.txt'
        [IO.File]::WriteAllText($q, "protocol=https`nhost=github.com`n`n")
        [IO.File]::WriteAllText($r, "protocol=https`nhost=github.com`nusername=alice`npassword=bad`n`n")
        $fill = cmd /c "git -C `"$repo`" credential fill < `"$q`" 2>nul"
        Check 'credentials come from gh' 'username=alice password=TOKEN-for-alice' ((@($fill) | Where-Object { $_ -match '^(username|password)=' }) -join ' ')
        $hint = cmd /c "git -C `"$repo`" credential reject < `"$r`" 2>&1" | Out-String
        Check 'rejected login prints a helpful hint' $true ($hint -match 'did not accept the saved login for alice.*#-troubleshooting')
    } finally {
        $env:GIT_CONFIG_GLOBAL = $oldGlobal; $env:GIT_CONFIG_NOSYSTEM = $oldNoSys
    }
} finally {
    Set-Variable -Name HOME -Value $oldHome -Force -Scope Global
    $env:Path = $oldPath
    Remove-Item -Recurse -Force $T -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host "$script:pass passed, $script:failed failed"
if ($script:failed) { exit 1 }
