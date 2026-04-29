<#
.SYNOPSIS
    DuckDuckGo Search Helper Script for Windows
.DESCRIPTION
    Wrapper around ddgs CLI with sensible defaults
#>

$ErrorActionPreference = "Stop"

$policy = Get-ExecutionPolicy
if ($policy -eq 'Restricted') {
    Write-Warning "Your current Execution Policy is $policy."
    Write-Warning "This script might not run successfully."
    Write-Warning "If you encounter errors, please run the following command in PowerShell:"
    Write-Warning "Set-ExecutionPolicy RemoteSigned -Scope CurrentUser"
}

$Query = $args[0]
$MaxResults = if ($args.Count -gt 1) { $args[1] } else { "5" }

if ([string]::IsNullOrWhiteSpace($Query)) {
    Write-Output "Usage: .\duckduckgo.ps1 <query> [max_results]"
    Write-Output ""
    Write-Output "Examples:"
    Write-Output "  .\duckduckgo.ps1 'python async programming' 5"
    Write-Output "  .\duckduckgo.ps1 'latest AI news' 10"
    Write-Output ""
    Write-Output "Requires: pip install ddgs"
    Exit 1
}

if (-not (Get-Command ddgs -ErrorAction SilentlyContinue)) {
    Write-Error "Error: ddgs not found. Install with: pip install ddgs"
    Exit 1
}

ddgs text -q "$Query" -m "$MaxResults"
