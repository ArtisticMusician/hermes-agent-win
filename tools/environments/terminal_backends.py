# Terminal Backends for Cross-Platform (Windows Native Priority)

import os
import subprocess
import time
from abc import ABC, abstractmethod
from typing import Optional, Tuple

from core.utils.platform import IS_WINDOWS, get_subprocess_kwargs, to_native_path

class TerminalBackend(ABC):
    @abstractmethod
    def run_command(self, cmd: str, timeout: Optional[float] = None, **kwargs) -> Tuple[int, str, str]:
        pass

class WindowsTerminalBackend(TerminalBackend):
    def __init__(self):
        self.use_powershell = True  # or detect Git Bash

    def run_command(self, cmd: str, timeout: Optional[float] = None, **kwargs) -> Tuple[int, str, str]:
        # Normalize command for Windows
        cmd = to_native_path(cmd) if 'cd ' not in cmd else cmd
        
        startup_kwargs = get_subprocess_kwargs(hidden=True)
        
        # Use PowerShell for better output handling
        full_cmd = f'powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "{cmd}"'
        
        try:
            proc = subprocess.Popen(
                full_cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                shell=True,
                **startup_kwargs
            )
            
            # Windows-compatible output drain (no select.select)
            stdout, stderr = proc.communicate(timeout=timeout)
            return proc.returncode, stdout or '', stderr or ''
            
        except subprocess.TimeoutExpired:
            proc.kill()
            return -1, '', 'Command timed out'
        except Exception as e:
            return -1, '', str(e)

class PosixTerminalBackend(TerminalBackend):
    def run_command(self, cmd: str, timeout: Optional[float] = None, **kwargs) -> Tuple[int, str, str]:
        try:
            proc = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                shell=True
            )
            stdout, stderr = proc.communicate(timeout=timeout)
            return proc.returncode, stdout or '', stderr or ''
        except Exception as e:
            return -1, '', str(e)


def get_terminal_backend():
    if IS_WINDOWS:
        return WindowsTerminalBackend()
    return PosixTerminalBackend()