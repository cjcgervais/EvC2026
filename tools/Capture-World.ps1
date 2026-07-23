<#
.SYNOPSIS  M2 "THE EYES": build the worldV2 valley in EDIT mode and screenshot 8 fixed vantages.
.DESCRIPTION
    Phase V, packet M2. Produces the contact sheet Fable audits against VISUAL-QUALITY-BAR.md §2:
      1. Bootstrap Rojo + build EaglesVsCrows.rbxlx (unless -NoBuild and a place already exists).
      2. Bootstrap run-in-roblox (needs Roblox Studio installed).
      3. Launch Studio headlessly against the place, injecting tests/capture/world.capture.luau,
         which builds the NEW WorldGen valley in edit mode and steps the camera through 8 poses.
      4. Tail the injected script's stdout; on each `M2READY <i> <name>` line, settle briefly then
         screenshot the Studio window into captures/$Session/NN_name.png. Optionally montage them.

    ═══ THE HARD CONSTRAINT (deviation from the MASTER-PLAN M2 "sentinel-FILE handshake") ═══
    run-in-roblox is a ONE-WAY channel: Studio→here via stdout `print`. Luau at plugin security
    CANNOT read a file or receive stdin, so the plan's ideal bidirectional per-shot ACK is
    impossible. Instead the injected script HOLDS each pose for a fixed DWELL (2.5s) after printing
    M2READY; this script tails stdout and captures within that window. run-in-roblox closes Studio
    the instant the injected script returns, so the script's total dwell exceeds the capture time
    by construction. The dwell IS the sync budget — there is no blind cross-process timer here; a
    capture is only ever taken in response to a real M2READY line.

    SCOPE: edit-mode .server scripts are dormant, so the sheet is the WorldGen TERRAIN + LIGHTING
    only (no groves/waterfall/critters). That is exactly what M1/M3 look-dev iterates.

    Degrades to UNAVAILABLE (never a hard FAIL) if Studio / run-in-roblox can't be obtained,
    mirroring Smoke-Boot.ps1 and verify.ps1's degrade contract.

    Exit codes:  0 = PASS (>=1 non-empty PNG saved)   1 = FAIL (injected script errored)   2 = UNAVAILABLE.
.PARAMETER TimeoutSec  Hard wall for the Studio run (default 180s: cold-open + 8 * 2.5s dwell + slack).
.PARAMETER NoBuild     Reuse the existing EaglesVsCrows.rbxlx instead of rebuilding.
.PARAMETER Session     Capture folder tag; images land in captures/<Session>/ (default S49).
#>
[CmdletBinding()]
param([int]$TimeoutSec = 180, [switch]$NoBuild, [string]$Session = "S49")

$root    = Split-Path $PSScriptRoot -Parent
$proj    = Join-Path $root 'default.project.json'
$place   = Join-Path $root 'EaglesVsCrows.rbxlx'
$capture = Join-Path $root 'tests\capture\world.capture.luau'
$outDir  = Join-Path $root ("captures\{0}" -f $Session)

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }

if (-not (Test-Path $capture)) { Say "UNAVAILABLE: capture script missing ($capture)" Yellow; exit 2 }
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

# --- Screen-capture + Win32 helpers (loaded once) ---
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
if (-not ("EvcNative" -as [type])) {
    Add-Type -Namespace Evc -Name Native -MemberDefinition @'
        [System.Runtime.InteropServices.DllImport("user32.dll")]
        public static extern bool SetProcessDPIAware();
        [System.Runtime.InteropServices.DllImport("user32.dll")]
        public static extern bool GetWindowRect(System.IntPtr hWnd, out RECT lpRect);
        [System.Runtime.InteropServices.DllImport("user32.dll")]
        public static extern bool SetForegroundWindow(System.IntPtr hWnd);
        public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
'@ -Name Native -Namespace Evc | Out-Null
}

# --- DPI / display preflight (hardening ②) ---
try { [Evc.Native]::SetProcessDPIAware() | Out-Null } catch {}
$screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
Say "`n=== M2 capture (edit-mode WorldGen valley) ===" Cyan
Say ("Preflight: primary screen {0}x{1} @ ({2},{3})." -f $screen.Width, $screen.Height, $screen.X, $screen.Y) DarkGray
try {
    $g   = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
    $dpi = $g.DpiX; $g.Dispose()
    if ([math]::Round($dpi) -ne 96) {
        Say ("Preflight WARNING: display DPI is {0} (scaling {1}%). Capture coords assume 1:1 (100%); a scaled desktop may crop/offset shots. Set Display scale to 100% for a clean sheet." -f $dpi, [math]::Round($dpi / 96 * 100)) Yellow
    }
} catch {}
Say "Preflight: bring Studio to the FOREGROUND and keep occluding dialogs (login/update) closed while this runs — a covered window captures whatever is on top of it." DarkGray

# --- 1. Build the place (the capture builds the REAL built artifact) ---
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

# --- Studio-window capture: RobloxStudioBeta's MainWindowHandle -> GetWindowRect; fall back to the
#     full primary screen if the handle can't be found (a covered/minimised window still yields a shot).
function Capture-Studio($path) {
    $rect = $null
    try {
        $proc = Get-Process -Name 'RobloxStudioBeta' -ErrorAction SilentlyContinue |
                Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
        if ($proc) {
            $r = New-Object Evc.Native+RECT
            if ([Evc.Native]::GetWindowRect($proc.MainWindowHandle, [ref]$r)) {
                try { [Evc.Native]::SetForegroundWindow($proc.MainWindowHandle) | Out-Null } catch {}
                $w = $r.Right - $r.Left; $h = $r.Bottom - $r.Top
                if ($w -gt 0 -and $h -gt 0) {
                    $rect = New-Object System.Drawing.Rectangle $r.Left, $r.Top, $w, $h
                }
            }
        }
    } catch {}
    if (-not $rect) { $rect = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds }
    $bmp = New-Object System.Drawing.Bitmap $rect.Width, $rect.Height
    $gfx = [System.Drawing.Graphics]::FromImage($bmp)
    $gfx.CopyFromScreen($rect.Location, [System.Drawing.Point]::Empty, $rect.Size)
    $gfx.Dispose()
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}

# --- 3. Launch run-in-roblox ASYNC, tail its stdout, capture on each M2READY ---
Say "Launching Studio headlessly (up to ${TimeoutSec}s); tailing for M2READY sentinels..." DarkGray
$outFile = [IO.Path]::GetTempFileName()
$errFile = [IO.Path]::GetTempFileName()
$saved = @()
$sawDone = $false
$failed  = $false
$reason  = ""
try {
    $p = Start-Process -FilePath $rir `
        -ArgumentList @('--place', $place, '--script', $capture) `
        -NoNewWindow -PassThru -RedirectStandardOutput $outFile -RedirectStandardError $errFile

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $cursor = 0        # bytes of $outFile already consumed
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
            if ($line -match '^\s*M2READY\s+(\d+)\s+(\S+)') {
                $idx = [int]$Matches[1]; $name = $Matches[2]
                Start-Sleep -Milliseconds 500          # settle: let the pose finish drawing
                $png = Join-Path $outDir ("{0:D2}_{1}.png" -f $idx, $name)
                try {
                    Capture-Studio $png
                    if ((Test-Path $png) -and (Get-Item $png).Length -gt 0) {
                        $saved += $png
                        Say ("  captured [{0:D2}] {1} -> {2}" -f $idx, $name, (Split-Path $png -Leaf)) Green
                    }
                } catch { Say "  capture error at ${name}: $($_.Exception.Message)" Yellow }
            } elseif ($line -match '^\s*M2DONE') {
                $sawDone = $true
            } elseif ($line -match '\[CAPTURE\] FAIL') {
                $failed = $true; $reason = $line.Trim()
            }
        }

        if ($sawDone -or $failed) { break }
        if ($p.HasExited) { break }
    }

    if (-not ($p.HasExited)) { try { $p.Kill() } catch {}; Start-Sleep -Milliseconds 300 }
    if (-not ($sawDone -or $failed) -and $saved.Count -eq 0) {
        $reason = "timed out / Studio produced no M2READY sentinel"
    }
} catch {
    Say "UNAVAILABLE: could not launch run-in-roblox: $($_.Exception.Message)" Yellow
    Remove-Item $outFile, $errFile -Force -ErrorAction SilentlyContinue
    exit 2
}

# Echo the injected script's stdout/stderr for the record.
$out = (Get-Content $outFile, $errFile -ErrorAction SilentlyContinue) -join "`n"
Remove-Item $outFile, $errFile -Force -ErrorAction SilentlyContinue
if ($out) { Say "`n--- injected stdout/stderr ---`n$out`n------------------------------" DarkGray }

# --- Optional contact sheet: grid montage of the individual PNGs (best-effort; individuals suffice). ---
if ($saved.Count -ge 1) {
    try {
        $cols = [math]::Min(3, $saved.Count)
        $rows = [math]::Ceiling($saved.Count / $cols)
        $cw, $ch = 640, 360   # per-tile size in the sheet
        $sheet = New-Object System.Drawing.Bitmap ($cols * $cw), ($rows * $ch)
        $sg = [System.Drawing.Graphics]::FromImage($sheet)
        $sg.Clear([System.Drawing.Color]::FromArgb(20, 20, 24))
        for ($k = 0; $k -lt $saved.Count; $k++) {
            $img = [System.Drawing.Image]::FromFile($saved[$k])
            $cx = ($k % $cols) * $cw; $cy = [math]::Floor($k / $cols) * $ch
            $sg.DrawImage($img, $cx, $cy, $cw, $ch)
            $img.Dispose()
        }
        $sg.Dispose()
        $sheetPath = Join-Path $outDir "_contactsheet.png"
        $sheet.Save($sheetPath, [System.Drawing.Imaging.ImageFormat]::Png)
        $sheet.Dispose()
        Say "Contact sheet -> $sheetPath" DarkGray
    } catch { Say "  (contact sheet skipped: $($_.Exception.Message))" DarkGray }
}

# --- 4. Result contract ---
if ($failed) {
    Say "`nCAPTURE: FAIL - the injected script errored: $reason" Red
    exit 1
}
if ($saved.Count -ge 1) {
    Say "`n[CAPTURE] PASS: $($saved.Count) images -> $outDir" Green
    exit 0
}
Say "`nCAPTURE: UNAVAILABLE - $reason (0 images)." Yellow
Say "FALLBACK (hardening ⑤): if capture defeats repeated attempts, Chad records ONE flythrough of the worldV2 valley as the look-dev record — the strategy never silently depends on this tool." Yellow
exit 2
