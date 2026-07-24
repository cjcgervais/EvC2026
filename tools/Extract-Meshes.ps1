<#
.SYNOPSIS  Extract every AssetManifest meshId's real geometry from Studio -> assets/MeshTemplates.rbxm.
.DESCRIPTION
    The automated driver for the committed-mesh pipeline (VISUAL-QUALITY-BAR.md §1.5): the runtime
    InsertService:CreateMeshPartAsync path is permission-fragile and network-dependent, so this bakes
    the fetched templates ONCE into a committed .rbxm that MeshFactory clones offline thereafter. Twin
    of tools/Bake-World.ps1 (same bootstrap, launch, stdout-tail, Ctrl+S-save, Lune-extract pattern):
      (1) Rojo 7.6.1 $path-maps a .rbxm into ReplicatedStorage.MeshTemplates at build time (same
          mechanism BakedTerrain.rbxm already proves for Workspace.Terrain).
      (2) Lune can deserializePlace a saved .rbxlx, extract a Folder subtree, and serializeModel it to
          .rbxm — MeshPart geometry (unlike Terrain SmoothGrid) is ordinary instance data, but the
          FETCH itself (InsertService:CreateMeshPartAsync) only works in real Studio, plugin security,
          with network access — hence a bake step instead of a headless generator.

    Steps:
      a. rojo build -> EaglesVsCrows.rbxlx (the live project as it sits on disk; default.project.json
         always $path-maps assets/MeshTemplates.rbxm, but the injected extractor script builds its own
         Workspace.MeshTemplates folder unconditionally, so which artifact is currently wired in
         doesn't matter here).
      b. Launch run-in-roblox with tests/capture/meshes.extract.luau injected: it enumerates every
         unique meshId across AssetManifest.props (via MeshFactory.uniqueMeshIds), fetches each via
         InsertService:CreateMeshPartAsync (SpecialMesh fallback on failure, mirroring MeshFactory's
         own getTemplate), names each template by its meshId, parents them all under a Folder
         "MeshTemplates" in Workspace, prints EXTRACTREADY, then dwells.
      c. On seeing EXTRACTREADY: bring Studio's MainWindow to the foreground and send Ctrl+S via
         SendKeys("^s"). Same temp-place-location + LastWriteTime-poll dance as Bake-World.ps1.
      d. Run tools/Extract-Meshes.luau via Lune: deserializePlace the saved copy, find
         Workspace.MeshTemplates, serializeModel it, write assets/MeshTemplates.rbxm.
      e. Report artifact size + a PASS/FAIL/UNAVAILABLE contract, same shape as Bake-World.ps1.

    RETRY: a known run-in-roblox first-launch panic (Studio's first-ever run-in-roblox invocation on a
    machine can hang/crash before ever printing anything, distinct from a real script error) has
    historically required a human to notice and re-run by hand. This script now builds that retry IN:
    if the first attempt produces no EXTRACTREADY sentinel and no explicit [MESHEXTRACT] FAIL line
    (i.e. it looks like a hang, not a real error), it kills any leftover RobloxStudioBeta/
    run-in-roblox processes, sleeps 5s, and retries ONCE automatically before giving up.

    Also carries the S51 orphan lesson (reference-m2-eyes-working.md): stop any pre-existing
    RobloxStudioBeta process and clear %LOCALAPPDATA%\Roblox\AutoSaves before launching, so a run
    never races a leftover window or gets its Ctrl+S swallowed by an autosave-recovery dialog.

    Degrades to UNAVAILABLE (never a hard FAIL) if Studio / run-in-roblox / Lune can't be obtained.
    FAILs (not UNAVAILABLE) if Studio ran but the save-detect or extract step itself errors, or if the
    injected script itself reported [MESHEXTRACT] FAIL — those are real bugs in this pipeline, not an
    environment gap.

    NOT RUN as part of this commit — extraction needs a human-attended Studio session (network access,
    first-launch dialogs). Run it yourself when ready:  .\tools\Extract-Meshes.ps1
.PARAMETER TimeoutSec  Hard wall PER ATTEMPT for the Studio run (default 180s: cold-open + N CDN
                       round-trips for each unique meshId + 40s dwell + slack).
.PARAMETER NoBuild     Reuse the existing EaglesVsCrows.rbxlx instead of rebuilding.
#>
[CmdletBinding()]
param([int]$TimeoutSec = 180, [switch]$NoBuild)

$root        = Split-Path $PSScriptRoot -Parent
$proj        = Join-Path $root 'default.project.json'
$place       = Join-Path $root 'EaglesVsCrows.rbxlx'
$extractScript = Join-Path $root 'tests\capture\meshes.extract.luau'
$extractLua  = Join-Path $root 'tools\Extract-Meshes.luau'
$assetsDir   = Join-Path $root 'assets'
$outRbxm     = Join-Path $assetsDir 'MeshTemplates.rbxm'

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }

if (-not (Test-Path $extractScript)) { Say "UNAVAILABLE: extractor script missing ($extractScript)" Yellow; exit 2 }
if (-not (Test-Path $extractLua)) { Say "UNAVAILABLE: extract script missing ($extractLua)" Yellow; exit 2 }
New-Item -ItemType Directory -Force -Path $assetsDir | Out-Null

Add-Type -AssemblyName System.Windows.Forms
if (-not ("EvcMeshExtract.Native" -as [type])) {
    Add-Type -Namespace EvcMeshExtract -Name Native -MemberDefinition @'
        [System.Runtime.InteropServices.DllImport("user32.dll")]
        public static extern bool SetForegroundWindow(System.IntPtr hWnd);
'@ | Out-Null
}

Say "`n=== Extract-Meshes: committed mesh-template pipeline (bar sec 1.5) ===" Cyan

function Clear-Orphans {
    try {
        $orphans = Get-Process -Name 'RobloxStudioBeta', 'run-in-roblox' -ErrorAction SilentlyContinue
        if ($orphans) {
            Say ("Preflight: stopping {0} orphaned process(es)..." -f $orphans.Count) Yellow
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
}

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

# --- Runs ONE attempt: launch run-in-roblox, tail stdout for EXTRACTREADY, Ctrl+S, copy the save.
# --  Returns a hashtable: SawReady, Failed, Reason, SavedCopy. ---
function Invoke-ExtractAttempt {
    param([string]$Label, [string]$RunInRoblox, [int]$Timeout)

    Say "`nLaunching Studio headlessly ($Label, up to ${Timeout}s); tailing for EXTRACTREADY..." DarkGray
    $outFile = [IO.Path]::GetTempFileName()
    $errFile = [IO.Path]::GetTempFileName()
    $sawReady = $false
    $failed   = $false
    $reason   = ""
    $savedCopy = $null
    $scratch = Join-Path $env:TEMP ("extract-meshes-" + [Guid]::NewGuid().ToString('N') + '.rbxlx')

    try {
        $p = Start-Process -FilePath $RunInRoblox `
            -ArgumentList @('--place', $place, '--script', $extractScript) `
            -NoNewWindow -PassThru -RedirectStandardOutput $outFile -RedirectStandardError $errFile

        $deadline = (Get-Date).AddSeconds($Timeout)
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
                if ($line -match '^\s*EXTRACTREADY\s*$' -and -not $sawReady) {
                    $sawReady = $true
                    Say "  EXTRACTREADY seen -> saving in Studio (Ctrl+S)..." Green

                    $srcPlace = $null
                    try {
                        $studioProc = Get-Process -Name 'RobloxStudioBeta' -ErrorAction SilentlyContinue |
                                      Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
                        if ($studioProc) { [EvcMeshExtract.Native]::SetForegroundWindow($studioProc.MainWindowHandle) | Out-Null }
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
                } elseif ($line -match '\[MESHEXTRACT\] FAIL') {
                    $failed = $true; $reason = $line.Trim()
                }
            }

            if ($sawReady -or $failed) { break }
            if ($p.HasExited) { break }
        }

        if (-not ($p.HasExited)) { try { $p.Kill() } catch {}; Start-Sleep -Milliseconds 300 }
        if (-not $sawReady -and -not $failed) {
            $reason = "timed out / Studio produced no EXTRACTREADY sentinel (possible first-launch panic)"
        }
    } catch {
        $out = ""
        try { $out = (Get-Content $outFile, $errFile -ErrorAction SilentlyContinue) -join "`n" } catch {}
        Remove-Item $outFile, $errFile -Force -ErrorAction SilentlyContinue
        return @{ SawReady = $false; Failed = $true; Reason = "could not launch run-in-roblox: $($_.Exception.Message)"; SavedCopy = $null; Output = $out; LaunchError = $true }
    }

    $out = (Get-Content $outFile, $errFile -ErrorAction SilentlyContinue) -join "`n"
    Remove-Item $outFile, $errFile -Force -ErrorAction SilentlyContinue

    return @{ SawReady = $sawReady; Failed = $failed; Reason = $reason; SavedCopy = $savedCopy; Output = $out; LaunchError = $false }
}

# --- 1. Build the place. ---
try {
    $rojo = & (Join-Path $PSScriptRoot 'Bootstrap-Rojo.ps1')
    if (-not $NoBuild -or -not (Test-Path $place)) {
        Say "Building place -> $place" Cyan
        & $rojo build $proj -o $place
        if ($LASTEXITCODE -ne 0) { Say "UNAVAILABLE: rojo build failed (fix the build first)" Yellow; exit 2 }
    }
} catch { Say "UNAVAILABLE: rojo bootstrap/build error: $($_.Exception.Message)" Yellow; exit 2 }

# --- 2. Bootstrap run-in-roblox + Lune. ---
try {
    $rir = & (Join-Path $PSScriptRoot 'Bootstrap-RunInRoblox.ps1')
} catch { Say "UNAVAILABLE: run-in-roblox bootstrap failed: $($_.Exception.Message)" Yellow; exit 2 }
if (-not (Test-Path $rir)) { Say "UNAVAILABLE: run-in-roblox.exe missing" Yellow; exit 2 }
try {
    $lune = & (Join-Path $PSScriptRoot 'Bootstrap-Lune.ps1')
} catch { Say "UNAVAILABLE: lune bootstrap failed: $($_.Exception.Message)" Yellow; exit 2 }
if (-not (Test-Path $lune)) { Say "UNAVAILABLE: lune.exe missing" Yellow; exit 2 }

# --- 3. Preflight (S51 orphan lesson) + attempt #1. ---
Clear-Orphans
$result = Invoke-ExtractAttempt -Label "attempt 1" -RunInRoblox $rir -Timeout $TimeoutSec
if ($result.Output) { Say "`n--- injected stdout/stderr (attempt 1) ---`n$($result.Output)`n------------------------------" DarkGray }

# --- 4. Retry ONCE, automatically, if attempt 1 looked like a hang (no sentinel, no explicit FAIL) —
# --     the known run-in-roblox first-launch panic on a fresh machine. A real [MESHEXTRACT] FAIL is
# --     NOT retried; that's a genuine bug worth surfacing, not a launch flake. ---
if (-not $result.SawReady -and -not $result.Failed) {
    Say "`nAttempt 1 produced no sentinel (looks like a first-launch panic/hang) -> retrying once..." Yellow
    Clear-Orphans
    Start-Sleep -Seconds 5
    $result = Invoke-ExtractAttempt -Label "attempt 2 (retry)" -RunInRoblox $rir -Timeout $TimeoutSec
    if ($result.Output) { Say "`n--- injected stdout/stderr (attempt 2) ---`n$($result.Output)`n------------------------------" DarkGray }
}

if ($result.Failed -or -not $result.SavedCopy) {
    Say "`n[MESHEXTRACT] FAIL: $($result.Reason)" Red
    exit 1
}
if (-not $result.SawReady) {
    Say "`nMESHEXTRACT: UNAVAILABLE - $($result.Reason)" Yellow
    exit 2
}

# --- 5. Extract: Lune deserializes the saved place, pulls Workspace.MeshTemplates, serializes it to
# --     assets/MeshTemplates.rbxm. ---
Say "`nExtracting MeshTemplates -> $outRbxm" Cyan
& $lune run $extractLua $result.SavedCopy $outRbxm
$extractExit = $LASTEXITCODE
Remove-Item $result.SavedCopy -Force -ErrorAction SilentlyContinue
if ($extractExit -ne 0) {
    Say "`n[MESHEXTRACT] FAIL: Extract-Meshes.luau exited $extractExit" Red
    exit 1
}

# --- 6. Result contract. ---
if ((Test-Path $outRbxm) -and (Get-Item $outRbxm).Length -gt 0) {
    $size = (Get-Item $outRbxm).Length
    Say ("`n[MESHEXTRACT] PASS: {0} ({1:N0} bytes)" -f $outRbxm, $size) Green
    exit 0
}
Say "`n[MESHEXTRACT] FAIL: $outRbxm missing or empty after extraction" Red
exit 1
