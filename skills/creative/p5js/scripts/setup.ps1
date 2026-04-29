<#
.SYNOPSIS
    p5.js Skill — Dependency Verification for Windows
#>

$ErrorActionPreference = "Stop"

$policy = Get-ExecutionPolicy
if ($policy -eq 'Restricted') {
    Write-Warning "Your current Execution Policy is $policy."
    Write-Warning "This script might not run successfully."
    Write-Warning "If you encounter errors, please run the following command in PowerShell:"
    Write-Warning "Set-ExecutionPolicy RemoteSigned -Scope CurrentUser"
}

function ok($msg) { Write-Host "[OK] $msg" -ForegroundColor Green }
function warn($msg) { Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function fail($msg) { Write-Host "[FAIL] $msg" -ForegroundColor Red }

Write-Host "=== p5.js Skill — Setup Check ===`n"

if (Get-Command node -ErrorAction SilentlyContinue) {
    $nodeVer = & node -v
    ok "Node.js $nodeVer"
} else {
    warn "Node.js not found — optional, needed for headless export"
    Write-Host "  Install: https://nodejs.org/"
}

if (Get-Command npm -ErrorAction SilentlyContinue) {
    $npmVer = & npm -v
    ok "npm $npmVer"
} else {
    warn "npm not found — optional, needed for headless export"
}

if (Get-Command node -ErrorAction SilentlyContinue) {
    $pupCheck = & node -e "require('puppeteer')" 2>$null
    if ($LASTEXITCODE -eq 0) {
        ok "Puppeteer installed"
    } else {
        warn "Puppeteer not installed — needed for headless export"
        Write-Host "  Install: npm install puppeteer"
    }
}

if (Get-Command ffmpeg -ErrorAction SilentlyContinue) {
    $ffmpegVerInfo = & ffmpeg -version 2>&1
    $ffmpegVer = ($ffmpegVerInfo | Select-Object -First 1) -split " " | Select-Object -Index 2
    ok "ffmpeg $ffmpegVer"
} else {
    warn "ffmpeg not found — needed for MP4 export"
    Write-Host "  Install: https://ffmpeg.org/download.html"
}

if (Get-Command python -ErrorAction SilentlyContinue) {
    $pyVer = & python --version 2>&1
    ok "Python $pyVer (for local server: python -m http.server)"
} else {
    warn "Python not found — needed for local file serving"
}

Write-Host "`n=== Core Requirements ==="
Write-Host "  A modern browser (Chrome/Firefox/Safari/Edge)"
Write-Host "  p5.js loaded via CDN — no local install needed`n"

Write-Host "=== Optional (for export) ==="
Write-Host "  Node.js + Puppeteer — headless frame capture"
Write-Host "  ffmpeg — frame sequence to MP4"
Write-Host "  Python — local development server`n"

Write-Host "=== Quick Start ==="
Write-Host "  1. Create an HTML file with inline p5.js sketch"
Write-Host "  2. Open in browser"
Write-Host "  3. Press 's' to save PNG, 'g' to save GIF`n"

Write-Host "Setup check complete."
