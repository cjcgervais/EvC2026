<#
.SYNOPSIS  Headless verify ladder for Eagles vs Crows: static analysis + Rojo build.
.DESCRIPTION
    The optional Tier-1 gate described in the evc-loop skill. Runs, best-effort:
      1. luau-lsp analyze   (types / broken requires / contract mismatches)
      2. selene             (lint / correctness smells)
      3. lune tests (Tier 4)(headless pure-logic specs, exit-code gated — tests/run.luau)
      4. rojo build         (the guaranteed wiring floor — same as build.ps1)

    Each analysis tier is BEST-EFFORT: if its binary can't be bootstrapped on this
    machine (offline / moved release asset), that tier is reported UNAVAILABLE and
    the run continues. The rojo build floor always executes. Exit code is 0 only if
    the build passed AND no *available* analysis tier reported errors.

    NOTE: authored to mirror the proven Bootstrap-Rojo pattern but not yet run on a
    live machine — if a bootstrap URL has drifted, fall back to .\build.ps1 and
    bump the pinned version/asset name in tools\Bootstrap-Verify.ps1.
.PARAMETER SkipAnalysis  Only run the rojo build floor (fast path).
.PARAMETER Smoke         Also run Tier 4.5: the headless run-in-roblox SMOKE BOOT (A6) — launches
                         Studio against the built place and asserts squirrels populate at RUNTIME
                         (catches the "machine-green but empty map" class Tier 4 can't see). Heavy
                         (Studio cold-open ~1-2 min), so it is opt-in, not part of the default ladder.
#>
[CmdletBinding()]
param([switch]$SkipAnalysis, [switch]$Smoke)

$root = $PSScriptRoot
$src  = Join-Path $root 'src'
$proj = Join-Path $root 'default.project.json'
$results = [ordered]@{}      # tier -> 'PASS' | 'FAIL' | 'UNAVAILABLE'

function Write-Head($t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }
# Windows PowerShell 5.1 has no ternary operator — use this helper for pass/fail.
function PassFail($code) { if ($code -eq 0) { 'PASS' } else { 'FAIL' } }

# --- Bootstrap Rojo (proven) up front; used for sourcemap + build. ---
$rojo = & (Join-Path $root 'tools\Bootstrap-Rojo.ps1')

if (-not $SkipAnalysis) {
    # --- Tier 1a: luau-lsp analyze ---
    Write-Head 'luau-lsp analyze'
    try {
        $luau = & (Join-Path $root 'tools\Bootstrap-Verify.ps1') -Tool luau-lsp
        $smap = Join-Path $root 'sourcemap.json'
        & $rojo sourcemap $proj -o $smap | Out-Null

        # Roblox API type defs are optional; fetch once, best-effort, into tools/bin (gitignored).
        $defs = Join-Path $root 'tools\bin\globalTypes.d.luau'
        if (-not (Test-Path $defs)) {
            try {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                $op = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
                $iwr = @{
                    # PINNED to the luau-lsp release (keep in lockstep with Bootstrap-Verify.ps1's Version).
                    # Fetching from 'main' shipped defs a year newer than the 1.32.1 binary -> the parser
                    # DIED SILENTLY (exit 0xC0000409/127, no output) = the "pre-existing luau-lsp crash"
                    # every session since S25 misattributed to PowerShell. Version-matched defs analyze fine.
                    Uri             = 'https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/1.32.1/scripts/globalTypes.d.luau'
                    OutFile         = $defs
                    UseBasicParsing = $true
                    Headers         = @{ 'User-Agent' = 'evc-verify' }
                }
                Invoke-WebRequest @iwr
                $ProgressPreference = $op
            } catch { Write-Host "  (Roblox API defs unavailable - analyzing without them)" -ForegroundColor DarkGray }
        }

        $laArgs = @('analyze', "--sourcemap=$smap")
        if (Test-Path $defs) { $laArgs += "--definitions=$defs" }
        $laArgs += $src
        & $luau @laArgs
        $results['luau-lsp'] = PassFail $LASTEXITCODE
    } catch {
        Write-Host "  UNAVAILABLE: $($_.Exception.Message)" -ForegroundColor Yellow
        $results['luau-lsp'] = 'UNAVAILABLE'
    }

    # --- Tier 1b: selene ---
    Write-Head 'selene'
    try {
        $selene = & (Join-Path $root 'tools\Bootstrap-Verify.ps1') -Tool selene
        & $selene $src
        $results['selene'] = PassFail $LASTEXITCODE
    } catch {
        Write-Host "  UNAVAILABLE: $($_.Exception.Message)" -ForegroundColor Yellow
        $results['selene'] = 'UNAVAILABLE'
    }

    # --- Tier 4: lune headless logic tests (exit-code gated) ---
    # Runs the pure modules OUTSIDE Roblox (tests/run.luau discovers *.spec.luau).
    # Unlike luau-lsp (judged by NEW findings), Tier 4 is authoritative on its exit
    # code: a failing spec = FAIL. Degrades to UNAVAILABLE if lune can't be fetched.
    Write-Head 'lune tests (Tier 4)'
    $runner = Join-Path $root 'tests\run.luau'
    if (-not (Test-Path $runner)) {
        Write-Host "  UNAVAILABLE: tests/run.luau not present (pre-A1)" -ForegroundColor Yellow
        $results['lune-tests'] = 'UNAVAILABLE'
    } else {
        try {
            $lune = & (Join-Path $root 'tools\Bootstrap-Lune.ps1')
            & $lune run $runner
            $results['lune-tests'] = PassFail $LASTEXITCODE
        } catch {
            Write-Host "  UNAVAILABLE: $($_.Exception.Message)" -ForegroundColor Yellow
            $results['lune-tests'] = 'UNAVAILABLE'
        }
    }
}

# --- Tier 0: rojo build (guaranteed floor) ---
Write-Head 'rojo build'
$out = Join-Path $root 'EaglesVsCrows.rbxlx'
& $rojo build $proj -o $out
$results['rojo-build'] = PassFail $LASTEXITCODE

# --- Tier 4.5: smoke boot (A6, opt-in) — runs the built place headlessly in Studio. ---
# Only meaningful if the build passed. Degrades to UNAVAILABLE (never FAIL) if Studio /
# run-in-roblox can't run, mirroring the analysis-tier contract.
if ($Smoke) {
    Write-Head 'smoke boot (Tier 4.5)'
    if ($results['rojo-build'] -ne 'PASS') {
        Write-Host "  SKIPPED: build failed, nothing to boot" -ForegroundColor Yellow
        $results['smoke-boot'] = 'UNAVAILABLE'
    } else {
        & (Join-Path $root 'tools\Smoke-Boot.ps1') -NoBuild
        switch ($LASTEXITCODE) {
            0       { $results['smoke-boot'] = 'PASS' }
            1       { $results['smoke-boot'] = 'FAIL' }
            default { $results['smoke-boot'] = 'UNAVAILABLE' }
        }
    }
}

# --- Summary + exit ---
Write-Head 'verify summary'
foreach ($k in $results.Keys) {
    $c = switch ($results[$k]) { 'PASS' { 'Green' } 'FAIL' { 'Red' } default { 'Yellow' } }
    Write-Host ("  {0,-12} {1}" -f $k, $results[$k]) -ForegroundColor $c
}
$failed = @($results.Values | Where-Object { $_ -eq 'FAIL' }).Count
if ($failed -gt 0) { Write-Host "`nVERIFY: $failed tier(s) FAILED." -ForegroundColor Red; exit 1 }
Write-Host "`nVERIFY: green (no available tier failed)." -ForegroundColor Green
exit 0
