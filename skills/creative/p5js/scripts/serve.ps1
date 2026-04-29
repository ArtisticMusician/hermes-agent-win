<#
.SYNOPSIS
    p5.js Skill — Local Development Server for Windows
.DESCRIPTION
    Serves the current directory over HTTP for loading local assets (fonts, images)
#>

$ErrorActionPreference = "Stop"

$policy = Get-ExecutionPolicy
if ($policy -eq 'Restricted') {
    Write-Warning "Your current Execution Policy is $policy."
    Write-Warning "This script might not run successfully."
    Write-Warning "If you encounter errors, please run the following command in PowerShell:"
    Write-Warning "Set-ExecutionPolicy RemoteSigned -Scope CurrentUser"
}

$Port = if ($args.Count -gt 0) { $args[0] } else { "8080" }
$Dir = if ($args.Count -gt 1) { $args[1] } else { "." }

$AbsDir = (Resolve-Path $Dir).Path

Write-Output "=== p5.js Dev Server ==="
Write-Output "Serving: $AbsDir"
Write-Output "URL:     http://localhost:$Port"
Write-Output "Press Ctrl+C to stop`n"

Set-Location $AbsDir

if (Get-Command python -ErrorAction SilentlyContinue) {
    & python -m http.server $Port
} else {
    Write-Output "Python not found. Trying Node.js..."
    if (Get-Command npx -ErrorAction SilentlyContinue) {
        & npx serve -l $Port $AbsDir
    } else {
        Write-Error "Error: Need python or npx (Node.js) for local server"
        Exit 1
    }
}
