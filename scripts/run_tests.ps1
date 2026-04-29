<#
.SYNOPSIS
    Canonical test runner for hermes-agent on Windows.
.DESCRIPTION
    Mirrors scripts/run_tests.sh for Windows.
    Enforces determinism, hermetic credentials, correct worker count, and venv setup.
#>

$ErrorActionPreference = "Stop"

$policy = Get-ExecutionPolicy
if ($policy -eq 'Restricted') {
    Write-Warning "Your current Execution Policy is $policy."
    Write-Warning "This script might not run successfully."
    Write-Warning "If you encounter errors, please run the following command in PowerShell:"
    Write-Warning "Set-ExecutionPolicy RemoteSigned -Scope CurrentUser"
}

# ── Locate repo root ────────────────────────────────────────────────────────
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RepoRoot = Split-Path -Parent $ScriptDir

# ── Activate venv ───────────────────────────────────────────────────────────
$VenvCandidates = @(
    Join-Path $RepoRoot ".venv"
    Join-Path $RepoRoot "venv"
    Join-Path $env:USERPROFILE ".hermes\hermes-agent\venv"
)

$Venv = $null
foreach ($Candidate in $VenvCandidates) {
    if (Test-Path (Join-Path $Candidate "Scripts\activate.ps1")) {
        $Venv = $Candidate
        break
    }
}

if (-not $Venv) {
    Write-Error "error: no virtualenv found in $RepoRoot\.venv or $RepoRoot\venv"
    Exit 1
}

$PythonExe = Join-Path $Venv "Scripts\python.exe"

# ── Ensure pytest-split is installed (required for shard-equivalent runs) ──
$PytestSplitCheck = & $PythonExe -c "import pytest_split" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Output "→ installing pytest-split into $Venv"
    & $PythonExe -m pip install --quiet "pytest-split>=0.9,<1"
}

# ── Hermetic environment ────────────────────────────────────────────────────
$EnvVars = Get-ChildItem Env:
foreach ($Var in $EnvVars) {
    $Name = $Var.Name
    if ($Name -match "(?i)_API_KEY$|_TOKEN$|_SECRET$|_PASSWORD$|_CREDENTIALS$|_ACCESS_KEY$|_SECRET_ACCESS_KEY$|_PRIVATE_KEY$|_OAUTH_TOKEN$|_WEBHOOK_SECRET$|_ENCRYPT_KEY$|_APP_SECRET$|_CLIENT_SECRET$|_CORP_SECRET$|_AES_KEY$|^AWS_ACCESS_KEY_ID$|^AWS_SECRET_ACCESS_KEY$|^AWS_SESSION_TOKEN$|^FAL_KEY$|^GH_TOKEN$|^GITHUB_TOKEN$") {
        Remove-Item -Path "Env:\$Name"
    }
}

$HermesVars = @(
    "HERMES_YOLO_MODE", "HERMES_INTERACTIVE", "HERMES_QUIET", "HERMES_TOOL_PROGRESS",
    "HERMES_TOOL_PROGRESS_MODE", "HERMES_MAX_ITERATIONS", "HERMES_SESSION_PLATFORM",
    "HERMES_SESSION_CHAT_ID", "HERMES_SESSION_CHAT_NAME", "HERMES_SESSION_THREAD_ID",
    "HERMES_SESSION_SOURCE", "HERMES_SESSION_KEY", "HERMES_GATEWAY_SESSION",
    "HERMES_PLATFORM", "HERMES_INFERENCE_PROVIDER", "HERMES_MANAGED", "HERMES_DEV",
    "HERMES_CONTAINER", "HERMES_EPHEMERAL_SYSTEM_PROMPT", "HERMES_TIMEZONE",
    "HERMES_REDACT_SECRETS", "HERMES_BACKGROUND_NOTIFICATIONS", "HERMES_EXEC_ASK",
    "HERMES_HOME_MODE"
)
foreach ($Var in $HermesVars) {
    if (Test-Path "Env:\$Var") {
        Remove-Item -Path "Env:\$Var"
    }
}

$env:TZ = "UTC"
$env:LANG = "C.UTF-8"
$env:LC_ALL = "C.UTF-8"
$env:PYTHONHASHSEED = "0"

# ── Worker count ────────────────────────────────────────────────────────────
$Workers = $env:HERMES_TEST_WORKERS
if ([string]::IsNullOrWhiteSpace($Workers)) {
    $Workers = "4"
}

# ── Run pytest ──────────────────────────────────────────────────────────────
Set-Location $RepoRoot

Write-Output "▶ running pytest with $Workers workers, hermetic env, in $RepoRoot"
Write-Output "  (TZ=UTC LANG=C.UTF-8 PYTHONHASHSEED=0; all credential env vars unset)"

$PytestArgs = @("-m", "pytest", "-o", "addopts=", "-n", "$Workers", "--ignore=tests/integration", "--ignore=tests/e2e", "-m", "not integration")
if ($args.Count -gt 0) {
    $PytestArgs += $args
}

& $PythonExe $PytestArgs
if ($LASTEXITCODE -ne 0) {
    Throw "pytest failed with exit code $LASTEXITCODE"
}
