<#
.SYNOPSIS
    Hermes Agent native Windows installer.

.DESCRIPTION
    Installs Hermes Agent without WSL. The script is intentionally staged so
    GUI/bootstrap drivers can run one stage at a time, while humans can run the
    whole installer with:

        irm https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.ps1 | iex

    The installer:
      - uses Python 3.11+ already on PATH, or installs Python through winget
      - installs uv in user scope
      - installs or clones Hermes under %LOCALAPPDATA%\hermes\hermes-agent
      - creates .venv, falling back to venv only for old checkouts
      - installs Python dependencies
      - installs PortableGit when no native Git Bash is available
      - installs user-scoped Node.js, ripgrep, and ffmpeg when missing
      - writes a stable %LOCALAPPDATA%\hermes\bin\hermes.cmd shim
      - sets User HERMES_HOME, HERMES_GIT_BASH_PATH, and PATH entries

    No admin rights are required unless winget itself prompts for a dependency.
#>

[CmdletBinding()]
param(
    [switch]$ProtocolVersion,
    [switch]$Manifest,
    [string]$Stage,
    [string]$InstallRoot,
    [string]$Branch = "main",
    [switch]$NoVenv,
    [switch]$SkipSetup,
    [switch]$SkipGateway,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$script:Protocol = 1
$script:RepoUrl = "https://github.com/NousResearch/hermes-agent.git"
$script:PortableGitVersion = "2.49.0"
$script:PortableGitUrl = "https://github.com/git-for-windows/git/releases/download/v2.49.0.windows.1/PortableGit-2.49.0-64-bit.7z.exe"
$script:NodeVersion = "22.16.0"
$script:NodeUrl = "https://nodejs.org/dist/v22.16.0/node-v22.16.0-win-x64.zip"
$script:RipgrepVersion = "14.1.1"
$script:RipgrepUrl = "https://github.com/BurntSushi/ripgrep/releases/download/14.1.1/ripgrep-14.1.1-x86_64-pc-windows-msvc.zip"

function Get-HermesRoot {
    if ($InstallRoot) {
        return [IO.Path]::GetFullPath($InstallRoot)
    }
    $base = Join-Path $env:LOCALAPPDATA "hermes"
    return Join-Path $base "hermes-agent"
}

function Get-HermesBase {
    return Split-Path -Parent (Get-HermesRoot)
}

function Write-Info([string]$Message) {
    Write-Host "-> $Message"
}

function Write-Ok([string]$Message) {
    Write-Host "  OK $Message"
}

function Write-Warn([string]$Message) {
    Write-Host "  WARN $Message" -ForegroundColor Yellow
}

function Fail([string]$Message) {
    throw $Message
}

function Invoke-External {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments
    )
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        Fail "$FilePath $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
    }
}

function Add-UserPathEntry([string]$PathEntry) {
    if (-not $PathEntry -or -not (Test-Path $PathEntry)) {
        return
    }
    $current = [Environment]::GetEnvironmentVariable("Path", "User")
    $parts = @()
    if ($current) {
        $parts = $current -split ";" | Where-Object { $_ }
    }
    $already = $false
    foreach ($part in $parts) {
        if ($part.TrimEnd("\") -ieq $PathEntry.TrimEnd("\")) {
            $already = $true
            break
        }
    }
    if (-not $already) {
        $newPath = @($PathEntry) + $parts
        [Environment]::SetEnvironmentVariable("Path", ($newPath -join ";"), "User")
    }
    $envParts = @($PathEntry) + (($env:Path -split ";") | Where-Object { $_ -and ($_ -ine $PathEntry) })
    $env:Path = $envParts -join ";"
}

function Set-UserEnv([string]$Name, [string]$Value) {
    [Environment]::SetEnvironmentVariable($Name, $Value, "User")
    Set-Item -Path "Env:$Name" -Value $Value
}

function Download-File([string]$Uri, [string]$OutFile) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutFile) | Out-Null
    Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing
}

function Test-NativeGitBash([string]$BashPath) {
    if (-not $BashPath -or -not (Test-Path $BashPath)) {
        return $false
    }
    $full = [IO.Path]::GetFullPath($BashPath)
    $wslBash = Join-Path $env:SystemRoot "System32\bash.exe"
    if ($full -ieq $wslBash) {
        return $false
    }
    try {
        $out = & $full --version 2>$null
        return ($LASTEXITCODE -eq 0 -and (($out -join "`n") -match "GNU bash"))
    } catch {
        return $false
    }
}

function Find-GitBash {
    $candidates = @()
    if ($env:HERMES_GIT_BASH_PATH) { $candidates += $env:HERMES_GIT_BASH_PATH }
    $base = Get-HermesBase
    $candidates += @(
        (Join-Path $base "git\bin\bash.exe"),
        (Join-Path $base "git\usr\bin\bash.exe")
    )
    $cmd = Get-Command "bash.exe" -ErrorAction SilentlyContinue
    if ($cmd) { $candidates += $cmd.Source }
    $candidates += @(
        "$env:ProgramFiles\Git\bin\bash.exe",
        "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
        "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
    )
    foreach ($candidate in $candidates) {
        if (Test-NativeGitBash $candidate) {
            return [IO.Path]::GetFullPath($candidate)
        }
    }
    return $null
}

function Ensure-Python {
    Write-Info "Checking Python 3.11+"
    $python = Get-Command "python.exe" -ErrorAction SilentlyContinue
    if ($python) {
        $version = & $python.Source -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')"
        if ([version]$version -ge [version]"3.11") {
            Write-Ok "Python $version found at $($python.Source)"
            return $python.Source
        }
    }

    $uv = Get-Command "uv.exe" -ErrorAction SilentlyContinue
    if (-not $uv) {
        try {
            $uvPath = Ensure-Uv
            $uv = Get-Command $uvPath -ErrorAction SilentlyContinue
        } catch {
            Write-Warn "uv is not available yet: $($_.Exception.Message)"
        }
    }
    if ($uv) {
        Write-Info "Installing Python 3.12 with uv"
        & $uv.Source python install 3.12
        if ($LASTEXITCODE -ne 0) {
            Fail "$($uv.Source) python install 3.12 failed with exit code $LASTEXITCODE"
        }
        $managedPython = (& $uv.Source python find 3.12 2>$null | Select-Object -First 1)
        if ($LASTEXITCODE -eq 0 -and $managedPython -and (Test-Path $managedPython)) {
            Write-Ok "Python 3.12 ready at $managedPython"
            return [IO.Path]::GetFullPath($managedPython)
        }
        Write-Warn "uv installed Python, but uv python find 3.12 did not return a usable python.exe"
    }

    $winget = Get-Command "winget.exe" -ErrorAction SilentlyContinue
    if (-not $winget) {
        Fail "Python 3.11+ was not found, uv could not provide managed Python, and winget is unavailable. Install Python from https://www.python.org/downloads/windows/ and rerun."
    }
    Write-Info "Installing Python 3.12 with winget"
    Invoke-External $winget.Source install --id Python.Python.3.12 --source winget --silent --accept-package-agreements --accept-source-agreements
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
    $python = Get-Command "python.exe" -ErrorAction SilentlyContinue
    if (-not $python) {
        Fail "Python install completed but python.exe is not on PATH. Open a new PowerShell window and rerun."
    }
    return $python.Source
}

function Ensure-Uv {
    Write-Info "Checking uv"
    $uv = Get-Command "uv.exe" -ErrorAction SilentlyContinue
    if ($uv) {
        Write-Ok "uv found at $($uv.Source)"
        return $uv.Source
    }

    $tmp = Join-Path ([IO.Path]::GetTempPath()) "hermes-install-uv.ps1"
    Download-File "https://astral.sh/uv/install.ps1" $tmp
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tmp
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue

    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User") + ";$env:USERPROFILE\.local\bin;$env:USERPROFILE\.cargo\bin"
    $uv = Get-Command "uv.exe" -ErrorAction SilentlyContinue
    if (-not $uv) {
        Fail "uv install completed but uv.exe is not on PATH. Open a new PowerShell window and rerun."
    }
    Write-Ok "uv installed at $($uv.Source)"
    return $uv.Source
}

function Ensure-Repo {
    $root = Get-HermesRoot
    $parent = Split-Path -Parent $root
    New-Item -ItemType Directory -Force -Path $parent | Out-Null

    if (Test-Path (Join-Path $root ".git")) {
        Write-Ok "Hermes checkout found at $root"
        return $root
    }

    if (Test-Path (Join-Path (Get-Location) "pyproject.toml")) {
        $current = [IO.Path]::GetFullPath((Get-Location).Path)
        Write-Ok "Using current checkout at $current"
        return $current
    }

    $git = Get-Command "git.exe" -ErrorAction SilentlyContinue
    if (-not $git) {
        Fail "git.exe is required to clone Hermes. Run the git stage first."
    }
    Write-Info "Cloning Hermes Agent to $root"
    Invoke-External $git.Source clone --branch $Branch --depth 1 $script:RepoUrl $root
    return $root
}

function Ensure-Git {
    Write-Info "Checking native Git Bash"
    $bash = Find-GitBash
    if ($bash) {
        Write-Ok "Git Bash found at $bash"
        Set-UserEnv "HERMES_GIT_BASH_PATH" $bash
        Add-UserPathEntry (Split-Path -Parent $bash)
        $gitRoot = Split-Path -Parent (Split-Path -Parent $bash)
        foreach ($entry in @("cmd", "bin", "usr\bin")) {
            Add-UserPathEntry (Join-Path $gitRoot $entry)
        }
        return $bash
    }

    $dest = Join-Path (Get-HermesBase) "git"
    Write-Info "Installing PortableGit to $dest"
    if ($Force -and (Test-Path $dest)) {
        Remove-Item $dest -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    $archive = Join-Path ([IO.Path]::GetTempPath()) "PortableGit-$script:PortableGitVersion.7z.exe"
    Download-File $script:PortableGitUrl $archive
    & $archive -y "-o$dest" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Fail "PortableGit extraction failed with exit code $LASTEXITCODE"
    }
    Remove-Item $archive -Force -ErrorAction SilentlyContinue

    $bash = Find-GitBash
    if (-not $bash) {
        Fail "PortableGit installed but bash.exe was not found under $dest"
    }
    Set-UserEnv "HERMES_GIT_BASH_PATH" $bash
    foreach ($entry in @("cmd", "bin", "usr\bin")) {
        Add-UserPathEntry (Join-Path $dest $entry)
    }
    Write-Ok "PortableGit installed"
    return $bash
}

function Ensure-Node {
    Write-Info "Checking Node.js"
    $node = Get-Command "node.exe" -ErrorAction SilentlyContinue
    if ($node) {
        try {
            $major = (& $node.Source -p "process.versions.node.split('.')[0]").Trim()
            if ([int]$major -ge 20) {
                Write-Ok "Node.js found at $($node.Source)"
                return $node.Source
            }
        } catch {}
    }

    $dest = Join-Path (Get-HermesBase) "node"
    if ($Force -and (Test-Path $dest)) {
        Remove-Item $dest -Recurse -Force
    }
    if (-not (Test-Path (Join-Path $dest "node.exe"))) {
        Write-Info "Installing Node.js $script:NodeVersion to $dest"
        $zip = Join-Path ([IO.Path]::GetTempPath()) "node-v$script:NodeVersion-win-x64.zip"
        $extract = Join-Path ([IO.Path]::GetTempPath()) "hermes-node-$script:NodeVersion"
        Remove-Item $extract -Recurse -Force -ErrorAction SilentlyContinue
        Download-File $script:NodeUrl $zip
        Expand-Archive -Path $zip -DestinationPath $extract -Force
        $inner = Get-ChildItem $extract -Directory | Select-Object -First 1
        if (-not $inner) { Fail "Node archive did not contain a directory" }
        if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
        Move-Item $inner.FullName $dest
        Remove-Item $zip -Force -ErrorAction SilentlyContinue
        Remove-Item $extract -Recurse -Force -ErrorAction SilentlyContinue
    }
    Add-UserPathEntry $dest
    Add-UserPathEntry (Join-Path $dest "node_modules\.bin")
    Write-Ok "Node.js ready at $dest"
    return (Join-Path $dest "node.exe")
}

function Ensure-Ripgrep {
    Write-Info "Checking ripgrep"
    $rg = Get-Command "rg.exe" -ErrorAction SilentlyContinue
    if ($rg) {
        Write-Ok "ripgrep found at $($rg.Source)"
        return $rg.Source
    }

    $bin = Join-Path (Get-HermesBase) "bin"
    New-Item -ItemType Directory -Force -Path $bin | Out-Null
    $target = Join-Path $bin "rg.exe"
    if (-not (Test-Path $target)) {
        $zip = Join-Path ([IO.Path]::GetTempPath()) "ripgrep-$script:RipgrepVersion.zip"
        $extract = Join-Path ([IO.Path]::GetTempPath()) "hermes-ripgrep-$script:RipgrepVersion"
        Remove-Item $extract -Recurse -Force -ErrorAction SilentlyContinue
        Download-File $script:RipgrepUrl $zip
        Expand-Archive -Path $zip -DestinationPath $extract -Force
        $found = Get-ChildItem $extract -Recurse -Filter "rg.exe" | Select-Object -First 1
        if (-not $found) { Fail "ripgrep archive did not contain rg.exe" }
        Copy-Item $found.FullName $target -Force
        Remove-Item $zip -Force -ErrorAction SilentlyContinue
        Remove-Item $extract -Recurse -Force -ErrorAction SilentlyContinue
    }
    Add-UserPathEntry $bin
    Write-Ok "ripgrep ready at $target"
    return $target
}

function Ensure-Ffmpeg {
    Write-Info "Checking ffmpeg"
    $ffmpeg = Get-Command "ffmpeg.exe" -ErrorAction SilentlyContinue
    if ($ffmpeg) {
        Write-Ok "ffmpeg found at $($ffmpeg.Source)"
        return $ffmpeg.Source
    }

    $winget = Get-Command "winget.exe" -ErrorAction SilentlyContinue
    if (-not $winget) {
        Write-Warn "ffmpeg was not found and winget is unavailable. Audio/video conversion features may be limited."
        return $null
    }

    Write-Info "Installing ffmpeg with winget"
    Invoke-External $winget.Source install --id Gyan.FFmpeg --source winget --silent --accept-package-agreements --accept-source-agreements
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
    $ffmpeg = Get-Command "ffmpeg.exe" -ErrorAction SilentlyContinue
    if ($ffmpeg) {
        Write-Ok "ffmpeg installed at $($ffmpeg.Source)"
        return $ffmpeg.Source
    }

    Write-Warn "ffmpeg install completed but ffmpeg.exe is not on PATH yet. Open a new PowerShell window after install."
    return $null
}

function Ensure-Venv {
    if ($NoVenv) {
        Write-Warn "Skipping venv because -NoVenv was specified"
        return
    }
    $root = Ensure-Repo
    $uv = Ensure-Uv
    $python = Ensure-Python
    Push-Location $root
    try {
        $venv = Join-Path $root ".venv"
        Write-Info "Creating virtual environment at $venv"
        Invoke-External $uv "venv" ".venv" "--python" $python
    } finally {
        Pop-Location
    }
}

function Get-VenvPython([string]$Root) {
    $candidate = Join-Path $Root ".venv\Scripts\python.exe"
    if (Test-Path $candidate) { return $candidate }
    $fallback = Join-Path $Root "venv\Scripts\python.exe"
    if (Test-Path $fallback) { return $fallback }
    return $null
}

function Install-Dependencies {
    if ($NoVenv) {
        Write-Warn "Skipping dependencies because -NoVenv was specified"
        return
    }
    $root = Ensure-Repo
    if (-not (Get-VenvPython $root)) {
        Ensure-Venv
    }
    $uv = Ensure-Uv
    Push-Location $root
    try {
        Write-Info "Installing Hermes Python dependencies"
        $venvPython = Get-VenvPython $root
        Invoke-External $uv "pip" "install" "--python" $venvPython "-e" ".[all]"
    } finally {
        Pop-Location
    }
}

function Write-HermesShim {
    $root = Ensure-Repo
    $bin = Join-Path (Get-HermesBase) "bin"
    New-Item -ItemType Directory -Force -Path $bin | Out-Null
    $shim = Join-Path $bin "hermes.cmd"
    $content = @"
@echo off
setlocal
set "HERMES_REPO=$root"
set "VENV_PY=%HERMES_REPO%\.venv\Scripts\python.exe"
if not exist "%VENV_PY%" set "VENV_PY=%HERMES_REPO%\venv\Scripts\python.exe"
if exist "%VENV_PY%" (
  "%VENV_PY%" -m hermes_cli.main %*
) else (
  python -m hermes_cli.main %*
)
endlocal
"@
    Set-Content -Path $shim -Value $content -Encoding ASCII
    Add-UserPathEntry $bin
    Set-UserEnv "HERMES_HOME" (Join-Path $env:USERPROFILE ".hermes")
    Write-Ok "Hermes shim written to $shim"
}

function Invoke-Configure {
    Write-HermesShim
    if ($SkipSetup) {
        Write-Warn "Skipping setup wizard because -SkipSetup was specified"
        return
    }
    $root = Ensure-Repo
    $python = Get-VenvPython $root
    if (-not $python) { $python = (Ensure-Python) }
    Push-Location $root
    try {
        Invoke-External $python "-m" "hermes_cli.main" "setup"
    } finally {
        Pop-Location
    }
}

function Invoke-Gateway {
    if ($SkipGateway) {
        Write-Warn "Skipping gateway install because -SkipGateway was specified"
        return
    }
    $root = Ensure-Repo
    $python = Get-VenvPython $root
    if (-not $python) { $python = (Ensure-Python) }
    Push-Location $root
    try {
        Invoke-External $python "-m" "hermes_cli.main" "gateway" "install"
    } finally {
        Pop-Location
    }
}

function Get-ManifestObject {
    return [ordered]@{
        protocol_version = $script:Protocol
        stages = @(
            [ordered]@{ name = "python"; title = "Install Python 3.11+"; category = "runtime"; needs_user_input = $false },
            [ordered]@{ name = "uv"; title = "Install uv"; category = "runtime"; needs_user_input = $false },
            [ordered]@{ name = "git"; title = "Install Git Bash"; category = "runtime"; needs_user_input = $false },
            [ordered]@{ name = "node"; title = "Install Node.js"; category = "runtime"; needs_user_input = $false },
            [ordered]@{ name = "ripgrep"; title = "Install ripgrep"; category = "runtime"; needs_user_input = $false },
            [ordered]@{ name = "ffmpeg"; title = "Install ffmpeg"; category = "runtime"; needs_user_input = $false },
            [ordered]@{ name = "venv"; title = "Create virtual environment"; category = "python"; needs_user_input = $false },
            [ordered]@{ name = "dependencies"; title = "Install Python dependencies"; category = "python"; needs_user_input = $false },
            [ordered]@{ name = "configure"; title = "Run Hermes setup"; category = "configuration"; needs_user_input = $true },
            [ordered]@{ name = "gateway"; title = "Install gateway service"; category = "configuration"; needs_user_input = $true }
        )
    }
}

function Invoke-Stage([string]$Name) {
    switch ($Name) {
        "python" { Ensure-Python | Out-Null; return }
        "uv" { Ensure-Uv | Out-Null; return }
        "git" { Ensure-Git | Out-Null; return }
        "node" { Ensure-Node | Out-Null; return }
        "ripgrep" { Ensure-Ripgrep | Out-Null; return }
        "ffmpeg" { Ensure-Ffmpeg | Out-Null; return }
        "venv" { Ensure-Venv; return }
        "dependencies" { Install-Dependencies; return }
        "configure" { Invoke-Configure; return }
        "gateway" { Invoke-Gateway; return }
        default {
            [ordered]@{ ok = $false; stage = $Name; reason = "unknown stage '$Name'" } |
                ConvertTo-Json -Compress
            exit 2
        }
    }
}

function Invoke-AllStages {
    Write-Host "============================================================"
    Write-Host "          Hermes Agent Native Windows Installer"
    Write-Host "============================================================"
    Ensure-Uv | Out-Null
    Ensure-Python | Out-Null
    Ensure-Git | Out-Null
    Ensure-Node | Out-Null
    Ensure-Ripgrep | Out-Null
    Ensure-Ffmpeg | Out-Null
    Ensure-Venv
    Install-Dependencies
    Write-HermesShim
    Invoke-Configure
    if (-not $SkipGateway) {
        Invoke-Gateway
    }
    Write-Host ""
    Write-Host "Installation complete."
    Write-Host "Open a new PowerShell window, then run: hermes"
}

if ($ProtocolVersion) {
    Write-Output $script:Protocol
    exit 0
}

if ($Manifest) {
    Get-ManifestObject | ConvertTo-Json -Depth 6
    exit 0
}

if ($Stage) {
    Invoke-Stage $Stage
    exit 0
}

Invoke-AllStages
