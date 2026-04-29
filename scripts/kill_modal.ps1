$ErrorActionPreference = "Stop"

$policy = Get-ExecutionPolicy
if ($policy -eq 'Restricted') {
    Write-Warning "Your current Execution Policy is $policy."
    Write-Warning "This script might not run successfully."
    Write-Warning "If you encounter errors, please run the following command in PowerShell:"
    Write-Warning "Set-ExecutionPolicy RemoteSigned -Scope CurrentUser"
}

Write-Output "Fetching Modal app list..."
$AppList = modal app list 2>$null

if ($args.Count -gt 0 -and $args[0] -eq "--all") {
    Write-Output "Stopping ALL Modal apps..."
    if ($AppList) {
        $Matches = [regex]::Matches($AppList, "ap-[A-Za-z0-9]+")
        $AppIds = $Matches | ForEach-Object { $_.Value } | Select-Object -Unique
        foreach ($AppId in $AppIds) {
            Write-Output "  Stopping $AppId"
            modal app stop $AppId 2>$null
        }
    }
} else {
    Write-Output "Stopping hermes-agent sandboxes..."
    if ($AppList) {
        $HermesApps = $AppList -split "`n" | Where-Object { $_ -match "hermes-agent" }
        if ($null -eq $HermesApps -or $HermesApps.Count -eq 0) {
            Write-Output "  No hermes-agent apps found."
        } else {
            $Matches = [regex]::Matches($HermesApps -join "`n", "ap-[A-Za-z0-9]+")
            $AppIds = $Matches | ForEach-Object { $_.Value } | Select-Object -Unique
            foreach ($AppId in $AppIds) {
                Write-Output "  Stopping $AppId"
                modal app stop $AppId 2>$null
            }
        }
    } else {
        Write-Output "  No hermes-agent apps found."
    }
}

Write-Output ""
Write-Output "Current hermes-agent status:"
$CurrentList = modal app list 2>$null
if ($CurrentList) {
    $FilteredList = $CurrentList -split "`n" | Where-Object { $_ -match "State|hermes-agent" }
    if ($FilteredList) {
        $FilteredList | ForEach-Object { Write-Output $_ }
    } else {
        Write-Output "  (none)"
    }
} else {
    Write-Output "  (none)"
}
