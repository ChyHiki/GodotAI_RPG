## ============================================================
## Run this project's regression probes (Windows / PowerShell).
## ============================================================
## WHY THIS SCRIPT EXISTS
##   The probes are `extends Node`, so they MUST be launched as .tscn.
##   Running the .gd directly (or via `--script`) produces two misleading errors:
##     1. Can't load the script "..." as it doesn't inherit from SceneTree or MainLoop.
##     2. Identifier not found: EventBus   (autoloads are NOT registered under --script,
##                                          and that failure happens at COMPILE time)
##   Neither message mentions "you should run the .tscn", so the correct command has to be
##   rediscovered every time. This script pins it down: just run `.\tools\run_probes.ps1`.
##
## USAGE
##   .\tools\run_probes.ps1               # all four probes
##   .\tools\run_probes.ps1 -Only m1      # one probe: m1 | quest | lock | possess
##   .\tools\run_probes.ps1 -Verbose      # print log tails for unhealthy probes
##
## EXIT CODE: 0 = all passed; 1 = something failed; 3 = Godot binary not found.
##
## NOTE: kept pure ASCII on purpose. Windows PowerShell 5.1 reads .ps1 as ANSI when there is
##       no BOM, so non-ASCII characters in this file would be mangled into parse errors.
## ============================================================

param(
    [string]$Only = "",
    [switch]$Verbose
)

$ErrorActionPreference = "Stop"

$Godot = "D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
# This script lives in <project>\tools\, so the project root is one level up.
$Project = Split-Path -Parent $PSScriptRoot

if (-not (Test-Path $Godot)) {
    Write-Host "[x] Godot binary not found: $Godot" -ForegroundColor Red
    exit 3
}

# Probe manifest: short name -> scene path + expected assertion count.
# WARNING: Expect is the regression BASELINE. If you change a probe, update this number too --
#          a mismatch means assertions were silently added or dropped.
$Probes = @(
    @{ Name = "m1";      Scene = "res://tools/autotest/m1_autotest.tscn";       Expect = 339 },
    @{ Name = "quest";   Scene = "res://tools/autotest/quest_probe.tscn";       Expect = 113 },
    @{ Name = "lock";    Scene = "res://tools/autotest/lock_toggle_probe.tscn"; Expect = 62  },
    @{ Name = "possess"; Scene = "res://tools/autotest/possess_probe.tscn";     Expect = 36  }
)

$failed = @()
$mismatch = @()

foreach ($p in $Probes) {
    if ($Only -ne "" -and $p.Name -ne $Only) { continue }

    $log = Join-Path $Project ".tmp_probe_$($p.Name).log"
    # KEY: the argument after --path is the SCENE PATH, not --script.
    & $Godot --headless --path $Project $p.Scene *> $log
    $code = $LASTEXITCODE

    # Godot console output may be UTF-16 or UTF-8; try both.
    $text = Get-Content $log -Encoding Unicode -ErrorAction SilentlyContinue
    if (-not $text) { $text = Get-Content $log -Encoding UTF8 -ErrorAction SilentlyContinue }
    $joined = ($text -join "`n")

    $pass = ([regex]::Matches($joined, 'AUTOTEST OK|\[PASS\]')).Count
    $fail = ([regex]::Matches($joined, 'AUTOTEST FAIL|\[FAIL\]|PROBE FAIL')).Count

    $status = "OK"
    $color = "Green"
    if ($code -ne 0 -or $fail -gt 0) {
        $status = "FAIL"; $color = "Red"; $failed += $p.Name
    } elseif ($pass -ne $p.Expect) {
        $status = "COUNT?"; $color = "Yellow"; $mismatch += $p.Name
    }

    Write-Host ("[{0,-6}] {1,-8} asserts {2}/{3}  failed {4}  exit={5}" -f `
        $status, $p.Name, $pass, $p.Expect, $fail, $code) -ForegroundColor $color

    # On anything unhealthy, show the evidence instead of just a summary line.
    if ($status -ne "OK" -or $Verbose) {
        Write-Host "  -- log tail ($log) --" -ForegroundColor DarkGray
        $text | Select-Object -Last 12 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
    }

    # Compile-time failures (the signature of a wrong launch command) get an explicit hint.
    if ($joined -match "doesn't inherit from SceneTree|Identifier not found: EventBus") {
        Write-Host "  [!] This looks like a WRONG LAUNCH COMMAND: probes must run as .tscn, not --script." -ForegroundColor Yellow
    }

    Remove-Item $log -Force -ErrorAction SilentlyContinue
}

if ($failed.Count -gt 0) {
    Write-Host ""
    Write-Host "[x] Failed probes: $($failed -join ', ')" -ForegroundColor Red
    exit 1
}
if ($mismatch.Count -gt 0) {
    Write-Host ""
    Write-Host "[!] Assertion count changed for: $($mismatch -join ', ')  (update Expect in this script if intended)" -ForegroundColor Yellow
}
Write-Host ""
Write-Host "[OK] All probes passed." -ForegroundColor Green
exit 0
