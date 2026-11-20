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
Set-Content (Join-Path $bin 'claude.cmd') '@echo GH_TOKEN=%GH_TOKEN%' -Encoding ascii
Set-Content (Join-Path $bin 'gh.cmd') '@if "%4"=="nobody" (exit /b 1) else (echo TOKEN-for-%4)' -Encoding ascii
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
        try { return (claude 6>$null | Select-Object -Last 1) } finally { Pop-Location }
    }
    Check 'repo inside folder uses its account'  'GH_TOKEN=TOKEN-for-alice' (Invoke-At 'code\work\repo')
    Check 'similar folder name is not confused'  'GH_TOKEN=TOKEN-for-bob'   (Invoke-At 'code\workshop')
    Check 'nested folder: longest match wins'    'GH_TOKEN=TOKEN-for-carol' (Invoke-At 'code\work\client\x')
    Check 'not logged in: runs without a token'  'GH_TOKEN='               (Invoke-At 'code\ghost')
    Check 'outside all folders: no token'        'GH_TOKEN='               (Invoke-At 'elsewhere')
    Check 'GH_TOKEN is restored afterwards'      $null                      $env:GH_TOKEN
} finally {
    Set-Variable -Name HOME -Value $oldHome -Force -Scope Global
    $env:Path = $oldPath
    Remove-Item -Recurse -Force $T -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host "$script:pass passed, $script:failed failed"
if ($script:failed) { exit 1 }
