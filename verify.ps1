<#
.SYNOPSIS  Headless verify ladder for Eagles vs Crows: static analysis + Rojo build.
.DESCRIPTION
    The optional Tier-1 gate described in the evc-loop skill. Runs, best-effort:
      1. luau-lsp analyze   (types / broken requires / contract mismatches)
      2. selene             (lint / correctness smells)
      3. rojo build         (the guaranteed wiring floor — same as build.ps1)

    Each analysis tier is BEST-EFFORT: if its binary can't be bootstrapped on this
    machine (offline / moved release asset), that tier is reported UNAVAILABLE and
    the run continues. The rojo build floor always executes. Exit code is 0 only if
    the build passed AND no *available* analysis tier reported errors.

    NOTE: authored to mirror the proven Bootstrap-Rojo pattern but not yet run on a
    live machine — if a bootstrap URL has drifted, fall back to .\build.ps1 and
    bump the pinned version/asset name in tools\Bootstrap-Verify.ps1.
.PARAMETER SkipAnalysis  Only run the rojo build floor (fast path).
#>
[CmdletBinding()]
param([switch]$SkipAnalysis)

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
                    Uri             = 'https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau'
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
}

# --- Tier 0: rojo build (guaranteed floor) ---
Write-Head 'rojo build'
$out = Join-Path $root 'EaglesVsCrows.rbxlx'
& $rojo build $proj -o $out
$results['rojo-build'] = PassFail $LASTEXITCODE

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
