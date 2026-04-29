<#
.SYNOPSIS
    p5.js Skill — Headless Render Pipeline for Windows
.DESCRIPTION
    Renders a p5.js sketch to MP4 video via Puppeteer + ffmpeg
#>

$ErrorActionPreference = "Stop"

$policy = Get-ExecutionPolicy
if ($policy -eq 'Restricted') {
    Write-Warning "Your current Execution Policy is $policy."
    Write-Warning "This script might not run successfully."
    Write-Warning "If you encounter errors, please run the following command in PowerShell:"
    Write-Warning "Set-ExecutionPolicy RemoteSigned -Scope CurrentUser"
}

$Width = 1920
$Height = 1080
$Fps = 30
$Duration = 10
$Crf = 18
$FramesOnly = $false

$InputFile = ""
$OutputFile = ""

$i = 0
while ($i -lt $args.Count) {
    if ($i -eq 0 -and (-not $args[$i].StartsWith("--"))) {
        $InputFile = $args[$i]
        $i++
        if ($i -lt $args.Count -and (-not $args[$i].StartsWith("--"))) {
            $OutputFile = $args[$i]
            $i++
        }
        continue
    }

    switch ($args[$i]) {
        "--width" { $Width = $args[$i+1]; $i += 2 }
        "--height" { $Height = $args[$i+1]; $i += 2 }
        "--fps" { $Fps = $args[$i+1]; $i += 2 }
        "--duration" { $Duration = $args[$i+1]; $i += 2 }
        "--quality" { $Crf = $args[$i+1]; $i += 2 }
        "--frames-only" { $FramesOnly = $true; $i += 1 }
        default { Write-Error "Unknown option: $($args[$i])"; Exit 1 }
    }
}

if ([string]::IsNullOrWhiteSpace($InputFile) -or ([string]::IsNullOrWhiteSpace($OutputFile) -and -not $FramesOnly)) {
    Write-Error "Usage: .\render.ps1 <input.html> <output.mp4> [options]"
    Exit 1
}

$TotalFrames = [int]$Fps * [int]$Duration
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$FrameDir = Join-Path $env:TEMP "p5js_frames_$(Get-Random)"
New-Item -ItemType Directory -Force -Path $FrameDir | Out-Null

Write-Output "=== p5.js Render Pipeline ==="
Write-Output "Input:      $InputFile"
Write-Output "Output:     $OutputFile"
Write-Output "Resolution: ${Width}x${Height}"
Write-Output "FPS:        $Fps"
Write-Output "Duration:   ${Duration}s (${TotalFrames} frames)"
Write-Output "Quality:    CRF $Crf"
Write-Output "Frame dir:  $FrameDir`n"

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Error "Error: Node.js required"
    Exit 1
}

if (-not $FramesOnly -and -not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    Write-Error "Error: ffmpeg required for MP4"
    Exit 1
}

Write-Output "Step 1/2: Capturing ${TotalFrames} frames..."
& node "$(Join-Path $ScriptDir 'export-frames.js')" $InputFile --output $FrameDir --width $Width --height $Height --frames $TotalFrames --fps $Fps

Write-Output "Frames captured to $FrameDir"

if ($FramesOnly) {
    Write-Output "Frames saved to: $FrameDir"
    Write-Output "To encode manually:"
    Write-Output "  ffmpeg -framerate $Fps -i ""$FrameDir\frame-%04d.png"" -c:v libx264 -crf $Crf -pix_fmt yuv420p ""$OutputFile"""
    Exit 0
}

Write-Output "Step 2/2: Encoding MP4..."
& ffmpeg -y -framerate $Fps -i "$FrameDir\frame-%04d.png" -c:v libx264 -preset slow -crf $Crf -pix_fmt yuv420p -movflags +faststart $OutputFile 2> "$FrameDir\ffmpeg.log"

Remove-Item -Recurse -Force $FrameDir

$FileSize = (Get-Item $OutputFile).Length
$FileSizeFormatted = "{0:N2} MB" -f ($FileSize / 1MB)

Write-Output "`n=== Done ==="
Write-Output "Output: $OutputFile ($FileSizeFormatted)"
Write-Output "Duration: ${Duration}s at ${Fps}fps, ${Width}x${Height}"
