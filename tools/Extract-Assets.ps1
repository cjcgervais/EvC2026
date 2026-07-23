<#
.SYNOPSIS  M4-A asset-extraction runner: regenerate the manifest source jsonl from the live toolbox.
.DESCRIPTION
    Wraps run-in-roblox exactly like tools/Smoke-Boot.ps1 (same bootstrap + time-box + stdout
    capture patterns), but instead of asserting a smoke gate it just captures whatever
    tools/asset-extract/extract-assets.luau prints to tools/asset-extract/extract-latest.jsonl.

    WORKFLOW:
      1. Edit the candidate ID list at the top of tools/asset-extract/extract-assets.luau
         (marked SWAP POINT).
      2. Run:  .\tools\Extract-Assets.ps1
      3. Read tools/asset-extract/extract-latest.jsonl, hand-transform the new/changed
         `[X] OK <id> <role> <json>` lines into src/shared/AssetManifest.luau (see the
         Packet M4-A shape comment at the top of that file), and re-run .\verify.ps1.

    Requires Roblox Studio to be installed locally (run-in-roblox drives it headlessly).
    Degrades to UNAVAILABLE (never a hard FAIL) if Studio / run-in-roblox can't be obtained,
    mirroring the verify.ps1 / Smoke-Boot.ps1 degrade contract — this is a dev tool, not a gate.

    Exit codes:  0 = captured output   1 = FAIL (script errored)   2 = UNAVAILABLE (couldn't run).
.PARAMETER TimeoutSec  Hard wall for the Studio run (default 150s: Studio cold-open + slack).
.PARAMETER NoBuild     Reuse the existing EaglesVsCrows.rbxlx instead of rebuilding.
#>
[CmdletBinding()]
param([int]$TimeoutSec = 150, [switch]$NoBuild)

$root    = Split-Path $PSScriptRoot -Parent
$proj    = Join-Path $root 'default.project.json'
$place   = Join-Path $root 'EaglesVsCrows.rbxlx'
$script  = Join-Path $root 'tools\asset-extract\extract-assets.luau'
$outDir  = Join-Path $root 'tools\asset-extract'
$latest  = Join-Path $outDir 'extract-latest.jsonl'

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }

if (-not (Test-Path $script)) { Say "UNAVAILABLE: extractor script missing ($script)" Yellow; exit 2 }

# --- 1. Build the place (extraction runs against the real built artifact) ---
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
Say "`n=== asset extraction ===" Cyan
Say "Launching Studio headlessly (up to ${TimeoutSec}s)..." DarkGray
$outFile = [IO.Path]::GetTempFileName()
$errFile = [IO.Path]::GetTempFileName()
$code = $null
try {
    $p = Start-Process -FilePath $rir `
        -ArgumentList @('--place', $place, '--script', $script) `
        -NoNewWindow -PassThru -RedirectStandardOutput $outFile -RedirectStandardError $errFile
    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
        try { $p.Kill() } catch {}
        Start-Sleep -Milliseconds 300
        $out = (Get-Content $outFile, $errFile -ErrorAction SilentlyContinue) -join "`n"
        if ($out) { Say $out }
        Say "`nEXTRACT: TIMEOUT after ${TimeoutSec}s (Studio hang or login wall) -> UNAVAILABLE." Yellow
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

# --- 4. Verdict: driven by the extractor's own sentinel, NOT the process exit code
# (run-in-roblox's exit code is unreliable through Start-Process here, mirrors Smoke-Boot.ps1).
$hasDone = $out -match '\[X\] DONE'
if (-not $hasDone) {
    Say "`nEXTRACT: UNAVAILABLE - Studio produced no [X] DONE sentinel (the script never finished; exit=$code)." Yellow
    exit 2
}

# Capture only the extractor's own [X] lines (drop Studio/log noise).
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$lines = $out -split "`r?`n" | Where-Object { $_ -match '^\[X\] ' }
Set-Content -Path $latest -Value $lines -Encoding UTF8
Say "`nEXTRACT: captured $($lines.Count) line(s) -> $latest" Green
exit 0
