<#
.SYNOPSIS
    Sourceable helper for Windows: ensure Node.js is available.
.DESCRIPTION
    Mirrors scripts/lib/node-bootstrap.sh for Windows environments.
#>

$HermesNodeMinVersion = if ($env:HERMES_NODE_MIN_VERSION) { $env:HERMES_NODE_MIN_VERSION } else { "20" }
$HermesNodeTargetMajor = if ($env:HERMES_NODE_TARGET_MAJOR) { $env:HERMES_NODE_TARGET_MAJOR } else { "22" }
$HermesHome = if ($env:HERMES_HOME) { $env:HERMES_HOME } else { Join-Path $env:USERPROFILE ".hermes" }
$global:HERMES_NODE_AVAILABLE = $false

function _nb_log($msg) { Write-Output "→ $msg" }
function _nb_ok($msg) { Write-Output "✓ $msg" }
function _nb_warn($msg) { Write-Warning "⚠ $msg" }

function _nb_node_major {
    if (Get-Command node -ErrorAction SilentlyContinue) {
        $v = (node --version 2>$null) -replace '^v',''
        if ($v -match '^\d+') {
            return [int]($v -split '\.')[0]
        }
    }
    return 0
}

function _nb_have_modern_node {
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) { return $false }
    $major = _nb_node_major
    return $major -ge [int]$HermesNodeMinVersion
}

function _nb_try_fnm {
    if (-not (Get-Command fnm -ErrorAction SilentlyContinue)) { return $false }
    _nb_log "fnm detected — installing Node $HermesNodeTargetMajor..."
    # fnm env logic translates directly via standard invocation if set up
    fnm install $HermesNodeTargetMajor | Out-Null
    fnm use $HermesNodeTargetMajor | Out-Null
    if (-not (_nb_have_modern_node)) { return $false }
    $ver = node --version
    _nb_ok "Node $ver activated via fnm"
    return $true
}

function _nb_try_nvm {
    if (-not (Get-Command nvm -ErrorAction SilentlyContinue)) { return $false }
    _nb_log "nvm detected — installing Node $HermesNodeTargetMajor..."
    nvm install $HermesNodeTargetMajor | Out-Null
    nvm use $HermesNodeTargetMajor | Out-Null
    if (-not (_nb_have_modern_node)) { return $false }
    $ver = node --version
    _nb_ok "Node $ver activated via nvm"
    return $true
}

function _nb_install_bundled_node {
    # On Windows, we download the official zip and extract it
    $node_arch = if ([System.Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" }

    $index_url = "https://nodejs.org/dist/latest-v$($HermesNodeTargetMajor).x/"
    # Get directory listing
    try {
        $html = Invoke-WebRequest -Uri $index_url -UseBasicParsing | Select-Object -ExpandProperty Content
        $regex = "node-v$HermesNodeTargetMajor\.\d+\.\d+-win-$node_arch\.zip"
        $match = [regex]::Match($html, $regex)
        if (-not $match.Success) {
            _nb_warn "Could not resolve Node $HermesNodeTargetMajor binary for win-$node_arch"
            return $false
        }
        $zipball = $match.Value

        $tmp = Join-Path $env:TEMP "node_tmp_$(Get-Random)"
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null

        _nb_log "Downloading $zipball..."
        $zip_path = Join-Path $tmp $zipball
        Invoke-WebRequest -Uri "$index_url$zipball" -OutFile $zip_path

        _nb_log "Extracting to $HermesHome\node\..."
        Expand-Archive -Path $zip_path -DestinationPath $tmp -Force

        $extracted = Get-ChildItem -Path $tmp -Directory -Filter "node-v*" | Select-Object -First 1
        if (-not $extracted) {
            _nb_warn "Extraction produced no directory"
            Remove-Item -Recurse -Force $tmp
            return $false
        }

        $node_dest = Join-Path $HermesHome "node"
        if (Test-Path $node_dest) { Remove-Item -Recurse -Force $node_dest }
        New-Item -ItemType Directory -Force -Path $HermesHome | Out-Null
        Move-Item -Path $extracted.FullName -Destination $node_dest

        Remove-Item -Recurse -Force $tmp

        # Add to PATH temporarily for this session
        $env:PATH = "$node_dest;$env:PATH"

        if (-not (_nb_have_modern_node)) { return $false }
        $ver = node --version
        _nb_ok "Node $ver installed to $node_dest"
        return $true

    } catch {
        _nb_warn "Download or extraction failed: $_"
        return $false
    }
}

function ensure_node {
    $global:HERMES_NODE_AVAILABLE = $false

    if (_nb_have_modern_node) {
        $ver = node --version
        _nb_ok "Node $ver found"
        $global:HERMES_NODE_AVAILABLE = $true
        return $true
    }

    $bundled_node = Join-Path $HermesHome "node\node.exe"
    if (Test-Path $bundled_node) {
        $env:PATH = "$(Join-Path $HermesHome 'node');$env:PATH"
        if (_nb_have_modern_node) {
            $ver = node --version
            _nb_ok "Node $ver found (Hermes-managed)"
            $global:HERMES_NODE_AVAILABLE = $true
            return $true
        }
    }

    if (_nb_try_fnm) { $global:HERMES_NODE_AVAILABLE = $true; return $true }
    if (_nb_try_nvm) { $global:HERMES_NODE_AVAILABLE = $true; return $true }

    if (_nb_install_bundled_node) { $global:HERMES_NODE_AVAILABLE = $true; return $true }

    _nb_warn "Node.js install failed — TUI and browser tools will be unavailable."
    _nb_warn "Install manually: https://nodejs.org/en/download/"
    return $false
}
