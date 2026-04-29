<#
.SYNOPSIS
    Manim Video Skill — Setup Check for Windows
#>

$ErrorActionPreference = "Stop"

$policy = Get-ExecutionPolicy
if ($policy -eq 'Restricted') {
    Write-Warning "Your current Execution Policy is $policy."
    Write-Warning "This script might not run successfully."
    Write-Warning "If you encounter errors, please run the following command in PowerShell:"
    Write-Warning "Set-ExecutionPolicy RemoteSigned -Scope CurrentUser"
}

function ok($msg) { Write-Host "  + $msg" -ForegroundColor Green }
function fail($msg) { Write-Host "  x $msg" -ForegroundColor Red }

Write-Host "`nManim Video Skill — Setup Check`n"

$errors = 0

if (Get-Command python -ErrorAction SilentlyContinue) {
    $pyVer = & python --version 2>&1
    ok "Python $pyVer"
} else {
    fail "Python not found"
    $errors++
}

if (Get-Command python -ErrorAction SilentlyContinue) {
    $manimCheck = & python -c "import manim" 2>$null
    if ($LASTEXITCODE -eq 0) {
        $manimVer = & manim --version 2>&1 | Select-Object -First 1
        ok "Manim $manimVer"
    } else {
        fail "Manim not installed: pip install manim"
        $errors++
    }
} else {
    fail "Manim not installed: pip install manim (python missing)"
    $errors++
}

if (Get-Command pdflatex -ErrorAction SilentlyContinue) {
    ok "LaTeX (pdflatex)"
} else {
    fail "LaTeX not found (Windows: install MiKTeX or TeX Live)"
    $errors++
}

if (Get-Command ffmpeg -ErrorAction SilentlyContinue) {
    ok "ffmpeg"
} else {
    fail "ffmpeg not found"
    $errors++
}

Write-Host ""
if ($errors -eq 0) {
    Write-Host "All prerequisites satisfied." -ForegroundColor Green
} else {
    Write-Host "$errors prerequisite(s) missing." -ForegroundColor Red
}
Write-Host ""
