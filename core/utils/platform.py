# Windows Native Platform Utilities for Hermes Agent

import os
import platform
import subprocess
from pathlib import Path
from typing import Dict, Any

IS_WINDOWS = os.name == 'nt'
IS_LINUX = os.name == 'posix' and platform.system() == 'Linux'


def to_native_path(path: str) -> str:
    """Convert paths for Windows compatibility (Git Bash vs PowerShell/cmd)."""
    if not IS_WINDOWS:
        return path
    p = Path(path)
    if str(p).startswith('/c/') or str(p).startswith('/C/'):
        # Git Bash style -> Windows
        return str(p).replace('/c/', 'C:\\', 1).replace('/', '\\')
    return str(p).replace('/', '\\')

def to_git_bash_path(path: str) -> str:
    """Convert Windows path to Git Bash /c/ style."""
    if not IS_WINDOWS:
        return path
    p = Path(path)
    if p.drive:
        drive = p.drive.lower().replace(':', '')
        return f'/{drive}{p.as_posix()[2:]}'
    return str(p).replace('\\', '/')

def get_subprocess_kwargs(hidden: bool = True) -> Dict[str, Any]:
    """Return kwargs for subprocess to hide console on Windows."""
    if not IS_WINDOWS:
        return {}
    startupinfo = subprocess.STARTUPINFO()
    startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startupinfo.wShowWindow = 0  # SW_HIDE
    return {
        'startupinfo': startupinfo,
        'creationflags': subprocess.CREATE_NO_WINDOW | subprocess.DETACHED_PROCESS,
    }
