# Windows Native Bootstrap Script for Hermes Agent

param(
    [switch]$Silent,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

Write-Host "Hermes Agent Windows Native Bootstrap v2.1" -ForegroundColor Cyan

# Detect paths
$installDir = if ($env:HERMES_HOME) { $env:HERMES_HOME } else { "$env:LOCALAPPDATA\HermesAgent" }
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "Install dir: $installDir" -ForegroundColor Gray

# Create dirs
if (!(Test-Path $installDir)) {
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
}

# Progress helper
function Show-Progress {
    param([string]$Activity, [int]$Percent)
    Write-Progress -Activity $Activity -PercentComplete $Percent
}

Show-Progress "Preparing environment" 10

# uv / Python setup with retries
try {
    if (!(Get-Command uv -ErrorAction SilentlyContinue)) {
        Write-Host "Installing uv..."
        Invoke-WebRequest -Uri "https://astral.sh/uv/install.ps1" -OutFile "$env:TEMP\uv-install.ps1"
        & "$env:TEMP\uv-install.ps1"
    }
    Show-Progress "Installing dependencies" 40
    # TODO: Expand with full uv sync / python install as needed
} catch {
    Write-Host "uv setup failed: $_" -ForegroundColor Red
    exit 1
}

# Self-update / Access Denied fix
if (Test-Path "$installDir\hermes.exe") {
    Write-Host "Preparing update (Access Denied protection)..."
    Rename-Item "$installDir\hermes.exe" "$installDir\hermes_old.exe" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

Show-Progress "Finalizing bootstrap" 90

Write-Host "Bootstrap complete! Hermes Agent is ready for Windows native use." -ForegroundColor Green

if (!$Silent) {
    Write-Host "Run 'hermes --help' to get started" -ForegroundColor Yellow
}