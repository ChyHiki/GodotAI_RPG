## ============================================================
## Run this project's regression probes AND asset validators (Windows / PowerShell).
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
## WHAT IT RUNS
##   1) Four gameplay probes (.tscn, from the autotest suite) -- with a hard assertion baseline.
##   2) Seven asset validators -- added in T05 so they stop rotting in `tools/`:
##        --script class : verify_enemy_model.gd, verify_enemy_wolf.gd
##        .tscn   class : verify_wolf_hitbox.tscn, verify_wolf_death.tscn, verify_brute_death.tscn,
##                          verify_qa_negative.tscn, verify_qa_death_states.tscn
##      The two classes run differently (see the manifests below) -- do NOT mix them up:
##        * `--script res://...gd`  -> only works for scripts that `extends SceneTree`.
##        * `res://...tscn`         -> for `extends Node` scripts (need a scene + autoloads).
##
## USAGE
##   .\tools\run_probes.ps1               # probes + validators (default)
##   .\tools\run_probes.ps1 -Only m1      # one probe: m1 | quest | lock | possess
##   .\tools\run_probes.ps1 -Verify       # only the 7 validators (skip the 4 probes)
##   .\tools\run_probes.ps1 -Verbose      # print log tails for unhealthy entries
##
## EXIT CODE: 0 = everything passed; 1 = something failed; 3 = Godot binary not found.
##
## NOTE: kept pure ASCII on purpose. Windows PowerShell 5.1 reads .ps1 as ANSI when there is
##       no BOM, so non-ASCII characters in this file would be mangled into parse errors.
## ============================================================

param(
    [string]$Only = "",
    [switch]$Verbose,
    [switch]$Verify
)

$ErrorActionPreference = "Stop"

## Godot prints benign diagnostics to stderr (e.g. "ERROR: N RID allocations ... were leaked at
## exit" from the dummy renderer). With $ErrorActionPreference = "Stop" plus the "*>" redirection
## below, Windows PowerShell 5.1 promotes each stderr line to a TERMINATING NativeCommandError and
## this script would abort mid-run (symptom: output stops right after a validator that leaks).
## So native calls run with the preference temporarily relaxed -- their output still lands in $log,
## and we read the real status from the exit code as before. Everything else keeps EAP = Stop.
function Invoke-Native([scriptblock]$Block) {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try { & $Block } finally { $ErrorActionPreference = $prev }
    return $global:LASTEXITCODE
}

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
# NOTE (T05): this section's behavior and baselines are UNCHANGED. Validators are handled separately.
$Probes = @(
    @{ Name = "m1";      Scene = "res://tools/autotest/m1_autotest.tscn";       Expect = 339 },
    @{ Name = "quest";   Scene = "res://tools/autotest/quest_probe.tscn";       Expect = 113 },
    @{ Name = "lock";    Scene = "res://tools/autotest/lock_toggle_probe.tscn"; Expect = 62  },
    @{ Name = "possess"; Scene = "res://tools/autotest/possess_probe.tscn";     Expect = 36  }
)

# Validator manifests. Pass/fail is decided by EXIT CODE (each validator quit(1) on any
# failed assertion), which is simpler and more robust than parsing its output markers.
# Two classes, run differently -- see the header.
$ScriptValidators = @(
    @{ Name = "verify_enemy_model"; Path = "res://tools/verify_enemy_model.gd" },
    @{ Name = "verify_enemy_wolf";  Path = "res://tools/verify_enemy_wolf.gd"  }
)
$SceneValidators = @(
    @{ Name = "verify_wolf_hitbox"; Path = "res://tools/verify_wolf_hitbox.tscn" },
    @{ Name = "verify_wolf_death";  Path = "res://tools/verify_wolf_death.tscn"  },
    @{ Name = "verify_brute_death"; Path = "res://tools/verify_brute_death.tscn" },
    @{ Name = "verify_qa_negative"; Path = "res://tools/verify_qa_negative.tscn" },
    @{ Name = "verify_qa_death_states"; Path = "res://tools/verify_qa_death_states.tscn" },
    @{ Name = "verify_playback_invariant"; Path = "res://tools/verify_playback_invariant.tscn" }
)

$failed = @()
$mismatch = @()
$vfailed = @()

if (-not $Verify) {
    Write-Host "== gameplay probes ==" -ForegroundColor Cyan
    foreach ($p in $Probes) {
        if ($Only -ne "" -and $p.Name -ne $Only) { continue }

        $log = Join-Path $Project ".tmp_probe_$($p.Name).log"
        # KEY: the argument after --path is the SCENE PATH, not --script.
        $code = Invoke-Native { & $Godot --headless --path $Project $p.Scene *> $log }

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
}

# ------------------------------------------------------------------
# Asset validators (T05): --script class then .tscn class.
# ------------------------------------------------------------------
Write-Host "== asset validators ==" -ForegroundColor Cyan

$validatorRuns = @()
foreach ($v in $ScriptValidators) {
    $validatorRuns += @{ Name = $v.Name; Mode = "script"; Path = $v.Path }
}
foreach ($v in $SceneValidators) {
    $validatorRuns += @{ Name = $v.Name; Mode = "scene"; Path = $v.Path }
}

foreach ($v in $validatorRuns) {
    $log = Join-Path $Project ".tmp_verify_$($v.Name).log"
    if ($v.Mode -eq "script") {
        # extends SceneTree -> launched with --script.
        $code = Invoke-Native { & $Godot --headless --path $Project --script $v.Path *> $log }
    } else {
        # extends Node -> launched as a scene.
        $code = Invoke-Native { & $Godot --headless --path $Project $v.Path *> $log }
    }

    $text = Get-Content $log -Encoding Unicode -ErrorAction SilentlyContinue
    if (-not $text) { $text = Get-Content $log -Encoding UTF8 -ErrorAction SilentlyContinue }

    $ok = ($code -eq 0)
    $status = "OK"; $color = "Green"
    if (-not $ok) {
        $status = "FAIL"; $color = "Red"; $vfailed += $v.Name
    }
    Write-Host ("[{0,-6}] {1,-22} exit={2}" -f $status, $v.Name, $code) -ForegroundColor $color

    if (-not $ok -or $Verbose) {
        Write-Host "  -- log tail ($log) --" -ForegroundColor DarkGray
        $text | Select-Object -Last 12 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
    }
    Remove-Item $log -Force -ErrorAction SilentlyContinue
}

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------
Write-Host ""
if ($failed.Count -gt 0) {
    Write-Host "[x] Failed probes: $($failed -join ', ')" -ForegroundColor Red
}
if ($vfailed.Count -gt 0) {
    Write-Host "[x] Failed validators: $($vfailed -join ', ')" -ForegroundColor Red
}
if ($failed.Count -gt 0 -or $vfailed.Count -gt 0) {
    exit 1
}
if ($mismatch.Count -gt 0) {
    Write-Host "[!] Assertion count changed for: $($mismatch -join ', ')  (update Expect in this script if intended)" -ForegroundColor Yellow
}
Write-Host "[OK] All probes + validators passed." -ForegroundColor Green
exit 0
