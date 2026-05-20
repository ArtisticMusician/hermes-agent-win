# tools/environments/terminal_backends.py
"""Terminal Backends for Cross-Platform Execution (Windows Native Priority)

Provides clean abstraction so the rest of Hermes doesn't need to know
about Windows vs POSIX differences.
"""

import os
import subprocess
from abc import ABC, abstractmethod
from typing import Optional, Tuple

from core.utils.platform import (
    IS_WINDOWS,
    get_subprocess_kwargs,
    to_native_path,
    to_git_bash_path,
)


class TerminalBackend(ABC):
    """Abstract base class for terminal execution."""

    @abstractmethod
    def run_command(
        self, cmd: str, timeout: Optional[float] = None, **kwargs
    ) -> Tuple[int, str, str]:
        """Run a command and return (returncode, stdout, stderr)."""
        pass


class WindowsTerminalBackend(TerminalBackend):
    """Windows-native implementation - no console popups, reliable output."""

    def __init__(self):
        # TODO: Make this configurable (PowerShell vs Git Bash)
        self.prefer_powershell = True

    def run_command(
        self, cmd: str, timeout: Optional[float] = None, **kwargs
    ) -> Tuple[int, str, str]:
        """Run command on Windows with hidden console and proper path handling."""

        # Convert paths inside command if needed
        if IS_WINDOWS:
            # Simple replacement for common cases - can be enhanced later
            cmd = to_native_path(cmd) if "\\" not in cmd else cmd

        # Choose shell
        if self.prefer_powershell:
            full_cmd = ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", cmd]
            shell = False
        else:
            # Git Bash support
            bash_path = subprocess.which("bash") or r"C:\Program Files\Git\bin\bash.exe"
            full_cmd = [bash_path, "-c", cmd]
            shell = False

        try:
            proc = subprocess.Popen(
                full_cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                shell=shell,
                **get_subprocess_kwargs(hidden=True, detached=False),  # hidden but keep stdio
            )

            stdout, stderr = proc.communicate(timeout=timeout)

            return proc.returncode, stdout or "", stderr or ""

        except subprocess.TimeoutExpired:
            proc.kill()
            return -1, "", "Command timed out"
        except FileNotFoundError:
            return -1, "", f"Command not found: {cmd.split()[0] if cmd else 'empty'}"
        except Exception as e:
            return -1, "", f"Execution error: {str(e)}"


class PosixTerminalBackend(TerminalBackend):
    """Standard POSIX implementation (Linux/macOS)."""

    def run_command(
        self, cmd: str, timeout: Optional[float] = None, **kwargs
    ) -> Tuple[int, str, str]:
        try:
            proc = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                shell=True,
            )
            stdout, stderr = proc.communicate(timeout=timeout)
            return proc.returncode, stdout or "", stderr or ""
        except Exception as e:
            return -1, "", str(e)


def get_terminal_backend() -> TerminalBackend:
    """Factory to get the correct backend."""
    if IS_WINDOWS:
        return WindowsTerminalBackend()
    return PosixTerminalBackend()