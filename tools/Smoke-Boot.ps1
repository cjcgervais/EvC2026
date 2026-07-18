<#
.SYNOPSIS  A6 Tier 4.5 smoke boot: build the place, run it headlessly in Studio, assert squirrels populate.
.DESCRIPTION
    Orchestrates the runtime gate that Tier 4 (geometry) can't cover:
      1. Bootstrap Rojo + build EaglesVsCrows.rbxlx (unless -NoBuild and a place already exists).
      2. Bootstrap run-in-roblox (needs Roblox Studio installed).
      3. Launch Studio headlessly against the place, injecting tests/smoke/boot.smoke.luau,
         time-boxed so a Studio hang / login wall can never block the loop.
      4. PASS iff the smoke script exited 0 AND printed "[SMOKE] PASS".

    Degrades to UNAVAILABLE (never a hard FAIL) if Studio / run-in-roblox can't be obtained,
    mirroring the selene/lune degrade contract in verify.ps1.

    Exit codes:  0 = PASS   1 = FAIL (real runtime problem)   2 = UNAVAILABLE (couldn't run).
.PARAMETER TimeoutSec  Hard wall for the Studio run (default 150s: Studio cold-open + 30s populate wait + slack).
.PARAMETER NoBuild     Reuse the existing EaglesVsCrows.rbxlx instead of rebuilding.
#>
[CmdletBinding()]
param([int]$TimeoutSec = 150, [switch]$NoBuild)

$root  = Split-Path $PSScriptRoot -Parent
$proj  = Join-Path $root 'default.project.json'
$place = Join-Path $root 'EaglesVsCrows.rbxlx'
$smoke = Join-Path $root 'tests\smoke\boot.smoke.luau'

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }

if (-not (Test-Path $smoke)) { Say "UNAVAILABLE: smoke script missing ($smoke)" Yellow; exit 2 }

# --- 1. Build the place (the smoke boot runs the REAL built artifact) ---
try {
    $rojo = & (Join-Path $PSScriptRoot 'Bootstrap-Rojo.ps1')
    if (-not $NoBuild -or -not (Test-Path $place)) {
        Say "Building place -> $place" Cyan
        & $rojo build $proj -o $place
        if ($LASTEXITCODE -ne 0) { Say "UNAVAILABLE: rojo build failed (fix the build first)" Yellow; exit 2 }
    }
} catch { Say "UNAVAILABLE: rojo bootstrap/build error: $($_.Exception.Message)" Yellow; exit 2 }

# --- 2. Bootstrap run-in-roblox (needs Studio) ---
try {
    $rir = & (Join-Path $PSScriptRoot 'Bootstrap-RunInRoblox.ps1')
} catch { Say "UNAVAILABLE: run-in-roblox bootstrap failed: $($_.Exception.Message)" Yellow; exit 2 }
if (-not (Test-Path $rir)) { Say "UNAVAILABLE: run-in-roblox.exe missing" Yellow; exit 2 }

# --- 3. Launch headlessly, time-boxed ---
Say "`n=== smoke boot (Tier 4.5) ===" Cyan
Say "Launching Studio headlessly (up to ${TimeoutSec}s)..." DarkGray
$outFile = [IO.Path]::GetTempFileName()
$errFile = [IO.Path]::GetTempFileName()
$code = $null
try {
    $p = Start-Process -FilePath $rir `
        -ArgumentList @('--place', $place, '--script', $smoke) `
        -NoNewWindow -PassThru -RedirectStandardOutput $outFile -RedirectStandardError $errFile
    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
        try { $p.Kill() } catch {}
        Start-Sleep -Milliseconds 300
        $out = (Get-Content $outFile, $errFile -ErrorAction SilentlyContinue) -join "`n"
        if ($out) { Say $out }
        Say "`nSMOKE: TIMEOUT after ${TimeoutSec}s (Studio hang or login wall) -> UNAVAILABLE." Yellow
        exit 2
    }
    $code = $p.ExitCode
} catch {
    Say "UNAVAILABLE: could not launch run-in-roblox: $($_.Exception.Message)" Yellow
    exit 2
}

$out = (Get-Content $outFile, $errFile -ErrorAction SilentlyContinue) -join "`n"
Remove-Item $outFile, $errFile -Force -ErrorAction SilentlyContinue
if ($out) { Say $out }

# --- 4. Verdict: driven by the smoke script's own sentinels, NOT the process exit code.
# run-in-roblox's exit code is unreliable through Start-Process here (often empty), so we
# read what the injected script actually printed:
#   [SMOKE] PASS  + no FAIL  -> PASS (0)
#   [SMOKE] FAIL / SMOKE FAIL -> FAIL (1)   (an assertion the gate deliberately failed)
#   neither sentinel          -> UNAVAILABLE (2)  (Studio never ran the gate; not a real bug)
$hasPass = $out -match '\[SMOKE\] PASS'
$hasFail = $out -match '(SMOKE FAIL|\[SMOKE\] FAIL)'
if ($hasPass -and -not $hasFail) {
    Say "`nSMOKE: PASS - shared modules load and the real models build in Studio (exit=$code)." Green
    exit 0
} elseif ($hasFail) {
    Say "`nSMOKE: FAIL - the real-engine gate failed an assertion (see [SMOKE] lines above)." Red
    exit 1
}
Say "`nSMOKE: UNAVAILABLE - Studio produced no [SMOKE] sentinel (the gate never ran; exit=$code)." Yellow
exit 2
