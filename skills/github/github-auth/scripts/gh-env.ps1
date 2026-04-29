<#
.SYNOPSIS
    GitHub environment detection helper for Hermes Agent skills on Windows.
#>

$policy = Get-ExecutionPolicy
if ($policy -eq 'Restricted') {
    Write-Warning "Your current Execution Policy is $policy."
    Write-Warning "This script might not run successfully."
    Write-Warning "If you encounter errors, please run the following command in PowerShell:"
    Write-Warning "Set-ExecutionPolicy RemoteSigned -Scope CurrentUser"
}

$global:GH_AUTH_METHOD = "none"
if ($null -eq $global:GITHUB_TOKEN) { $global:GITHUB_TOKEN = "" }
$global:GH_USER = ""

if (Get-Command gh -ErrorAction SilentlyContinue) {
    $ghAuthStatus = & gh auth status 2>&1
    if ($LASTEXITCODE -eq 0) {
        $global:GH_AUTH_METHOD = "gh"
        $global:GH_USER = & gh api user --jq '.login' 2>$null
    }
}

if ($global:GH_AUTH_METHOD -eq "none" -and -not [string]::IsNullOrWhiteSpace($global:GITHUB_TOKEN)) {
    $global:GH_AUTH_METHOD = "curl"
}

$HermesEnv = Join-Path $env:USERPROFILE ".hermes\.env"
if ($global:GH_AUTH_METHOD -eq "none" -and (Test-Path $HermesEnv)) {
    $tokenLine = Get-Content $HermesEnv | Where-Object { $_ -match "^GITHUB_TOKEN=" } | Select-Object -First 1
    if ($tokenLine) {
        $global:GITHUB_TOKEN = ($tokenLine -split "=", 2)[1].Trim()
        if (-not [string]::IsNullOrWhiteSpace($global:GITHUB_TOKEN)) {
            $global:GH_AUTH_METHOD = "curl"
        }
    }
}

$GitCreds = Join-Path $env:USERPROFILE ".git-credentials"
if ($global:GH_AUTH_METHOD -eq "none" -and (Test-Path $GitCreds)) {
    $credLine = Get-Content $GitCreds | Where-Object { $_ -match "github.com" } | Select-Object -First 1
    if ($credLine) {
        $match = [regex]::Match($credLine, "https://[^:]+:([^@]+)@.*")
        if ($match.Success) {
            $global:GITHUB_TOKEN = $match.Groups[1].Value
            if (-not [string]::IsNullOrWhiteSpace($global:GITHUB_TOKEN)) {
                $global:GH_AUTH_METHOD = "curl"
            }
        }
    }
}

if ($global:GH_AUTH_METHOD -eq "curl" -and [string]::IsNullOrWhiteSpace($global:GH_USER)) {
    try {
        $resp = Invoke-RestMethod -Uri "https://api.github.com/user" -Headers @{ "Authorization" = "token $($global:GITHUB_TOKEN)" } -ErrorAction Stop
        $global:GH_USER = $resp.login
    } catch {
        # ignore
    }
}

$global:GH_OWNER = ""
$global:GH_REPO = ""
$global:GH_OWNER_REPO = ""

if (Get-Command git -ErrorAction SilentlyContinue) {
    $remoteUrl = & git remote get-url origin 2>$null
    if ($remoteUrl -match "github.com") {
        $cleanUrl = $remoteUrl -replace '.*github\.com[:/]', '' -replace '\.git$', ''
        $global:GH_OWNER_REPO = $cleanUrl
        $parts = $cleanUrl -split '/'
        if ($parts.Count -ge 2) {
            $global:GH_OWNER = $parts[0]
            $global:GH_REPO = $parts[1]
        }
    }
}

Write-Output "GitHub Auth: $($global:GH_AUTH_METHOD)"
if (-not [string]::IsNullOrWhiteSpace($global:GH_USER)) { Write-Output "User: $($global:GH_USER)" }
if (-not [string]::IsNullOrWhiteSpace($global:GH_OWNER_REPO)) { Write-Output "Repo: $($global:GH_OWNER_REPO)" }
if ($global:GH_AUTH_METHOD -eq "none") { Write-Output "⚠ Not authenticated — see github-auth skill" }
