<#
.SYNOPSIS
    setup.ps1 — Automated setup for twozero MCP plugin for TouchDesigner on Windows
#>

$ErrorActionPreference = "Stop"

$policy = Get-ExecutionPolicy
if ($policy -eq 'Restricted') {
    Write-Warning "Your current Execution Policy is $policy."
    Write-Warning "This script might not run successfully."
    Write-Warning "If you encounter errors, please run the following command in PowerShell:"
    Write-Warning "Set-ExecutionPolicy RemoteSigned -Scope CurrentUser"
}

$TwoZeroUrl = "https://www.404zero.com/pisang/twozero.tox"
$ToxPath = Join-Path (Join-Path $env:USERPROFILE "Downloads") "twozero.tox"
$HermesHomeDir = if ($env:HERMES_HOME) { $env:HERMES_HOME } else { Join-Path $env:USERPROFILE ".hermes" }
$HermesCfg = Join-Path $HermesHomeDir "config.yaml"
$McpPort = 40404
$McpEndpoint = "http://localhost:${McpPort}/mcp"

$ManualSteps = @()

Write-Host "`n═══ twozero MCP for TouchDesigner — Setup ═══`n" -ForegroundColor Cyan

# ── 1. Check if TouchDesigner is running ──
$tdRunning = $false
$tdProc = Get-Process -Name "TouchDesigner", "TouchDesignerFTE" -ErrorAction SilentlyContinue
if ($tdProc) {
    Write-Host " ✔ TouchDesigner is running" -ForegroundColor Green
    $tdRunning = $true
} else {
    Write-Host " ⚠ TouchDesigner is not running" -ForegroundColor Yellow
}

# ── 2. Ensure twozero.tox exists ──
if (Test-Path $ToxPath) {
    Write-Host " ✔ twozero.tox already exists at $ToxPath" -ForegroundColor Green
} else {
    Write-Host " ⚠ twozero.tox not found — downloading..." -ForegroundColor Yellow
    try {
        Invoke-WebRequest -Uri $TwoZeroUrl -OutFile $ToxPath -UseBasicParsing
        Write-Host " ✔ Downloaded twozero.tox to $ToxPath" -ForegroundColor Green
    } catch {
        Write-Host " ✘ Failed to download twozero.tox from $TwoZeroUrl" -ForegroundColor Red
        Write-Host "       Please download manually and place at $ToxPath"
        $ManualSteps += "Download twozero.tox from $TwoZeroUrl to $ToxPath"
    }
}

# ── 3. Ensure Hermes config has twozero_td MCP entry ──
if (-not (Test-Path $HermesCfg)) {
    Write-Host " ✘ Hermes config not found at $HermesCfg" -ForegroundColor Red
    $ManualSteps += "Create $HermesCfg with twozero_td MCP server entry"
} else {
    $configContent = Get-Content $HermesCfg -Raw
    if ($configContent -match "twozero_td") {
        Write-Host " ✔ twozero_td MCP entry exists in Hermes config" -ForegroundColor Green
    } else {
        Write-Host " ⚠ Adding twozero_td MCP entry to Hermes config..." -ForegroundColor Yellow
        $pyScript = @"
import yaml, sys

cfg_path = '$($HermesCfg -replace '\\', '\\')'
try:
    with open(cfg_path, 'r') as f:
        cfg = yaml.safe_load(f) or {}

    if 'mcp_servers' not in cfg:
        cfg['mcp_servers'] = {}

    if 'twozero_td' not in cfg['mcp_servers']:
        cfg['mcp_servers']['twozero_td'] = {
            'url': '$McpEndpoint',
            'timeout': 120,
            'connect_timeout': 60
        }
        with open(cfg_path, 'w') as f:
            yaml.dump(cfg, f, default_flow_style=False, sort_keys=False)
    sys.exit(0)
except Exception as e:
    sys.exit(1)
"@
        $tmpPy = Join-Path $env:TEMP "twozero_cfg_$(Get-Random).py"
        Set-Content -Path $tmpPy -Value $pyScript
        $pyCheck = & python $tmpPy 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host " ✔ twozero_td MCP entry added to config" -ForegroundColor Green
        } else {
            Write-Host " ✘ Could not update config (is PyYAML installed?)" -ForegroundColor Red
            $ManualSteps += "Add twozero_td MCP entry to $HermesCfg manually"
        }
        Remove-Item $tmpPy -Force
        $ManualSteps += "Restart Hermes session to pick up config change"
    }
}

# ── 4. Test if MCP port is responding ──
$portOpen = $false
try {
    $tcpClient = New-Object System.Net.Sockets.TcpClient
    $async = $tcpClient.BeginConnect("127.0.0.1", $McpPort, $null, $null)
    $portOpen = $async.AsyncWaitHandle.WaitOne(1000, $false)
    $tcpClient.Close()
} catch {}

if ($portOpen) {
    Write-Host " ✔ Port $McpPort is open" -ForegroundColor Green

    # ── 5. Verify MCP endpoint responds ──
    try {
        $resp = Invoke-WebRequest -Uri $McpEndpoint -TimeoutSec 3 -UseBasicParsing -ErrorAction Stop
        Write-Host " ✔ MCP endpoint responded at $McpEndpoint" -ForegroundColor Green
    } catch {
        Write-Host " ⚠ Port open but MCP endpoint returned empty response or error" -ForegroundColor Yellow
        $ManualSteps += "Verify MCP is enabled in twozero settings"
    }
} else {
    Write-Host " ⚠ Port $McpPort is not open" -ForegroundColor Yellow
    if ($tdRunning) {
        $ManualSteps += "In TD: drag twozero.tox into network editor -> click Install"
        $ManualSteps += "Enable MCP: twozero icon -> Settings -> mcp -> 'auto start MCP' -> Yes"
    } else {
        $ManualSteps += "Launch TouchDesigner"
        $ManualSteps += "Drag twozero.tox into the TD network editor and click Install"
        $ManualSteps += "Enable MCP: twozero icon -> Settings -> mcp -> 'auto start MCP' -> Yes"
    }
}

# ── Status Report ──
Write-Host "`n═══ Status Report ═══`n" -ForegroundColor Cyan

if ($ManualSteps.Count -eq 0) {
    Write-Host " ✔ Fully configured! twozero MCP is ready to use.`n" -ForegroundColor Green
    Exit 0
} else {
    Write-Host " ⚠ Manual steps remaining:`n" -ForegroundColor Yellow
    for ($i=0; $i -lt $ManualSteps.Count; $i++) {
        $stepNum = $i + 1
        Write-Host "   $stepNum. $($ManualSteps[$i])"
    }
    Write-Host ""
    Exit 1
}
