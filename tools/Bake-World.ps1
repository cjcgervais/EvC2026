<#
.SYNOPSIS  Bake the WorldGen terrain in real Studio -> assets/BakedTerrain.rbxm.
.DESCRIPTION
    The automated driver for the terrain-bake pipeline (twin of tools/Capture-World.ps1: same
    bootstrap, launch, stdout-tail, and Win32 window patterns). A prior spike proved the three legs
    exist; this script is the missing link that wires them together:
      (1) Rojo 7.6.1 $path-maps a .rbxm containing Workspace.Terrain (with SmoothGrid bytes) into
          `rojo build` output perfectly.
      (2) Lune can deserializePlace a saved .rbxlx, extract Workspace.Terrain, and serializeModel it
          to .rbxm — SmoothGrid round-trips as raw opaque bytes, Lune never has to understand it.
      (3) Only real Studio can PRODUCE valid SmoothGrid (WorldGen.build's Terrain:Fill* calls) — this
          is why a bake step exists at all instead of a headless generator.

    Steps:
      a. rojo build -> EaglesVsCrows.rbxlx (the LIVE, non-baked project as it sits on disk right now —
         default.project.json always $path-maps assets/BakedTerrain.rbxm, but the INJECTED bake script
         re-sculpts unconditionally, so which artifact is currently wired in doesn't matter here).
      b. Launch run-in-roblox with tests/capture/world.bake.luau injected: it WorldGen.build()s the
         live valley (Clear + full sculpt, ignoring any baked shortcut), settles ~5s for the async
         mesher/voxel commit, prints BAKEREADY, then task.wait(40) to hold the process open.
      c. On seeing BAKEREADY: bring Studio's MainWindow to the foreground and send Ctrl+S via
         SendKeys("^s"). run-in-roblox opened the place from a temp .rbxlx path (named in the window
         title AND the newest run-in-roblox-place.rbxlx under $env:TEMP — this script checks the title
         first, falls back to the newest-file glob), so Ctrl+S saves IN PLACE with no dialog. Poll the
         file's LastWriteTime for up to 30s to detect save-complete, then copy it to a scratch path.
      d. Run tools/Extract-Terrain.luau via Lune: deserializePlace the saved copy, find
         Workspace.Terrain, stamp BakedByWorldGen=true, serializeModel it, write assets/BakedTerrain.rbxm.
      e. Report artifact size + a PASS/FAIL/UNAVAILABLE contract, same shape as Capture-World.ps1.

    S51 ORPHAN LESSON (memory: reference-m2-eyes-working.md): a prior capture session left orphaned
    Studio windows + stale AutoSaves that silently corrupted results. This script Stop-Process'es any
    existing RobloxStudio* process and clears %LOCALAPPDATA%\Roblox\AutoSaves before launching, so a
    bake never races a leftover window or gets its Ctrl+S caught by an autosave-recovery dialog.

    Degrades to UNAVAILABLE (never a hard FAIL) if Studio / run-in-roblox / Lune can't be obtained,
    mirroring Capture-World.ps1 / Smoke-Boot.ps1's degrade contract. FAILs (not UNAVAILABLE) if Studio
    ran but the save-detect or extract step itself errors — that's a real bug in this pipeline, not an
    environment gap.

    Exit codes:  0 = PASS (assets/BakedTerrain.rbxm written, non-empty, contains a Terrain)
                 1 = FAIL (injected script errored, save never detected, or extraction failed)
                 2 = UNAVAILABLE (Studio / run-in-roblox / Lune unobtainable on this machine)
.PARAMETER TimeoutSec  Hard wall for the Studio run (default 120s: cold-open + 5s settle + 40s dwell + slack).
.PARAMETER NoBuild     Reuse the existing EaglesVsCrows.rbxlx instead of rebuilding.
#>
[CmdletBinding()]
param([int]$TimeoutSec = 120, [switch]$NoBuild)

$root       = Split-Path $PSScriptRoot -Parent
$proj       = Join-Path $root 'default.project.json'
$place      = Join-Path $root 'EaglesVsCrows.rbxlx'
$bakeScript = Join-Path $root 'tests\capture\world.bake.luau'
$extractLua = Join-Path $root 'tools\Extract-Terrain.luau'
$assetsDir  = Join-Path $root 'assets'
$outRbxm    = Join-Path $assetsDir 'BakedTerrain.rbxm'
$scratch    = Join-Path $env:TEMP ("bake-terrain-" + [Guid]::NewGuid().ToString('N') + '.rbxlx')

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }

if (-not (Test-Path $bakeScript)) { Say "UNAVAILABLE: bake script missing ($bakeScript)" Yellow; exit 2 }
if (-not (Test-Path $extractLua)) { Say "UNAVAILABLE: extract script missing ($extractLua)" Yellow; exit 2 }
New-Item -ItemType Directory -Force -Path $assetsDir | Out-Null

Add-Type -AssemblyName System.Windows.Forms
if (-not ("EvcBake.Native" -as [type])) {
    Add-Type -Namespace EvcBake -Name Native -MemberDefinition @'
        [System.Runtime.InteropServices.DllImport("user32.dll")]
        public static extern bool SetForegroundWindow(System.IntPtr hWnd);
'@ | Out-Null
}

Say "`n=== Bake-World: terrain-bake pipeline ===" Cyan

# --- S51 orphan lesson: kill any leftover Studio + clear AutoSaves before we launch, so this run
# --     never races a stale window or gets its Ctrl+S swallowed by an autosave-recovery dialog. ---
try {
    $orphans = Get-Process -Name 'RobloxStudioBeta' -ErrorAction SilentlyContinue
    if ($orphans) {
        Say ("Preflight: stopping {0} orphaned RobloxStudioBeta process(es)..." -f $orphans.Count) Yellow
        $orphans | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
    }
} catch {}
try {
    $autoSaves = Join-Path $env:LOCALAPPDATA 'Roblox\AutoSaves'
    if (Test-Path $autoSaves) {
        Say "Preflight: clearing $autoSaves" DarkGray
        Get-ChildItem $autoSaves -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    }
} catch {}

# --- 1. Build the place (bake always re-sculpts from source; which artifact is currently wired into
# --     the place doesn't matter — the injected script Clears+rebuilds unconditionally). ---
try {
    $rojo = & (Join-Path $PSScriptRoot 'Bootstrap-Rojo.ps1')
    if (-not $NoBuild -or -not (Test-Path $place)) {
        Say "Building place -> $place" Cyan
        & $rojo build $proj -o $place
        if ($LASTEXITCODE -ne 0) { Say "UNAVAILABLE: rojo build failed (fix the build first)" Yellow; exit 2 }
    }
} catch { Say "UNAVAILABLE: rojo bootstrap/build error: $($_.Exception.Message)" Yellow; exit 2 }

# --- 2. Bootstrap run-in-roblox + Lune (needs Studio installed, and Lune for the extract step). ---
try {
    $rir = & (Join-Path $PSScriptRoot 'Bootstrap-RunInRoblox.ps1')
} catch { Say "UNAVAILABLE: run-in-roblox bootstrap failed: $($_.Exception.Message)" Yellow; exit 2 }
if (-not (Test-Path $rir)) { Say "UNAVAILABLE: run-in-roblox.exe missing" Yellow; exit 2 }
try {
    $lune = & (Join-Path $PSScriptRoot 'Bootstrap-Lune.ps1')
} catch { Say "UNAVAILABLE: lune bootstrap failed: $($_.Exception.Message)" Yellow; exit 2 }
if (-not (Test-Path $lune)) { Say "UNAVAILABLE: lune.exe missing" Yellow; exit 2 }

# --- Locate the temp place run-in-roblox opened: title first (visible in Studio's MainWindowTitle,
# --     e.g. "...\Temp\tmpXXXX\run-in-roblox-place.rbxlx - Roblox Studio"), newest-file-under-$env:TEMP
# --     glob as the fallback (title format isn't a documented contract, so don't depend on it alone). ---
function Find-RunInRobloxPlace {
    try {
        $proc = Get-Process -Name 'RobloxStudioBeta' -ErrorAction SilentlyContinue |
                Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
        if ($proc -and $proc.MainWindowTitle -match '([A-Za-z]:\\[^"]*?run-in-roblox-place\.rbxlx)') {
            $p = $Matches[1]
            if (Test-Path $p) { return $p }
        }
    } catch {}
    try {
        $hit = Get-ChildItem -Path $env:TEMP -Filter 'run-in-roblox-place.rbxlx' -Recurse -ErrorAction SilentlyContinue |
               Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($hit) { return $hit.FullName }
    } catch {}
    return $null
}

# --- 3. Launch run-in-roblox ASYNC, tail stdout for BAKEREADY, then Ctrl+S + copy the saved place. ---
Say "Launching Studio headlessly (up to ${TimeoutSec}s); tailing for BAKEREADY..." DarkGray
$outFile = [IO.Path]::GetTempFileName()
$errFile = [IO.Path]::GetTempFileName()
$sawReady = $false
$failed   = $false
$reason   = ""
$savedCopy = $null
try {
    $p = Start-Process -FilePath $rir `
        -ArgumentList @('--place', $place, '--script', $bakeScript) `
        -NoNewWindow -PassThru -RedirectStandardOutput $outFile -RedirectStandardError $errFile

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $cursor = 0
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 200
        $lines = @()
        try {
            $fs = [IO.File]::Open($outFile, 'Open', 'Read', 'ReadWrite')
            $fs.Seek($cursor, 'Begin') | Out-Null
            $sr = New-Object IO.StreamReader($fs)
            $text = $sr.ReadToEnd()
            $cursor = $fs.Position
            $sr.Close(); $fs.Close()
            if ($text) { $lines = $text -split "`r?`n" }
        } catch {}

        foreach ($line in $lines) {
            if ($line -match '^\s*BAKEREADY\s*$' -and -not $sawReady) {
                $sawReady = $true
                Say "  BAKEREADY seen -> saving in Studio (Ctrl+S)..." Green

                # Bring Studio foreground, find the temp place, Ctrl+S, poll for LastWriteTime change.
                $srcPlace = $null
                try {
                    $studioProc = Get-Process -Name 'RobloxStudioBeta' -ErrorAction SilentlyContinue |
                                  Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
                    if ($studioProc) { [EvcBake.Native]::SetForegroundWindow($studioProc.MainWindowHandle) | Out-Null }
                } catch {}
                Start-Sleep -Milliseconds 300
                $srcPlace = Find-RunInRobloxPlace
                if (-not $srcPlace) {
                    $failed = $true; $reason = "could not locate the run-in-roblox temp place (title + glob both failed)"
                    break
                }
                $before = (Get-Item $srcPlace).LastWriteTimeUtc
                [System.Windows.Forms.SendKeys]::SendWait('^s')

                $saveDeadline = (Get-Date).AddSeconds(30)
                $saved = $false
                while ((Get-Date) -lt $saveDeadline) {
                    Start-Sleep -Milliseconds 300
                    try {
                        $after = (Get-Item $srcPlace).LastWriteTimeUtc
                        if ($after -gt $before) { $saved = $true; break }
                    } catch {}
                }
                if (-not $saved) {
                    $failed = $true; $reason = "save-detect timed out (LastWriteTime never changed on $srcPlace within 30s)"
                    break
                }
                Say "  save detected -> copying" DarkGray
                try {
                    Copy-Item -Path $srcPlace -Destination $scratch -Force
                    $savedCopy = $scratch
                } catch {
                    $failed = $true; $reason = "could not copy saved place: $($_.Exception.Message)"
                }
                break
            } elseif ($line -match '\[BAKE\] FAIL') {
                $failed = $true; $reason = $line.Trim()
            } elseif ($line -match '^\s*BAKEDONE') {
                # informational only; we already acted on BAKEREADY
            }
        }

        if ($sawReady -or $failed) { break }
        if ($p.HasExited) { break }
    }

    if (-not ($p.HasExited)) { try { $p.Kill() } catch {}; Start-Sleep -Milliseconds 300 }
    if (-not $sawReady -and -not $failed) {
        $reason = "timed out / Studio produced no BAKEREADY sentinel"
    }
} catch {
    Say "UNAVAILABLE: could not launch run-in-roblox: $($_.Exception.Message)" Yellow
    Remove-Item $outFile, $errFile -Force -ErrorAction SilentlyContinue
    exit 2
}

$out = (Get-Content $outFile, $errFile -ErrorAction SilentlyContinue) -join "`n"
Remove-Item $outFile, $errFile -Force -ErrorAction SilentlyContinue
if ($out) { Say "`n--- injected stdout/stderr ---`n$out`n------------------------------" DarkGray }

if ($failed -or -not $savedCopy) {
    Say "`n[BAKE] FAIL: $reason" Red
    exit 1
}
if (-not $sawReady) {
    Say "`nBAKE: UNAVAILABLE - $reason" Yellow
    exit 2
}

# --- 4. Extract: Lune deserializes the saved place, pulls Workspace.Terrain, stamps the marker,
# --     serializes just that instance to assets/BakedTerrain.rbxm. ---
Say "Extracting Terrain -> $outRbxm" Cyan
& $lune run $extractLua $savedCopy $outRbxm
$extractExit = $LASTEXITCODE
Remove-Item $savedCopy -Force -ErrorAction SilentlyContinue
if ($extractExit -ne 0) {
    Say "`n[BAKE] FAIL: Extract-Terrain.luau exited $extractExit" Red
    exit 1
}

# --- 5. Result contract. ---
if ((Test-Path $outRbxm) -and (Get-Item $outRbxm).Length -gt 0) {
    $size = (Get-Item $outRbxm).Length
    Say ("`n[BAKE] PASS: {0} ({1:N0} bytes)" -f $outRbxm, $size) Green
    exit 0
}
Say "`n[BAKE] FAIL: $outRbxm missing or empty after extraction" Red
exit 1
