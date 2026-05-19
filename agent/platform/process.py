"""
Process management abstraction.
"""
import os
import signal
import subprocess
import logging
from agent.platform.platform_info import platform_info

logger = logging.getLogger(__name__)

class ProcessManager:
    @staticmethod
    def kill_process_group(proc: subprocess.Popen, escalate: bool = False):
        """Kill the child and its entire process group."""
        try:
            if platform_info.is_windows:
                proc.terminate()
            else:
                os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
        except (ProcessLookupError, PermissionError) as e:
            logger.debug("Could not kill process group: %s", e, exc_info=True)
            try:
                proc.kill()
            except Exception as e2:
                logger.debug("Could not kill process: %s", e2, exc_info=True)

        if escalate:
            # Give the process 5s to exit after SIGTERM, then SIGKILL
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                try:
                    if platform_info.is_windows:
                        proc.kill()
                    else:
                        os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
                except (ProcessLookupError, PermissionError) as e:
                    logger.debug("Could not kill process group with SIGKILL: %s", e, exc_info=True)
                    try:
                        proc.kill()
                    except Exception as e2:
                        logger.debug("Could not kill process: %s", e2, exc_info=True)

    @staticmethod
    def kill_pid(pid: int, force: bool = False):
        """Kills a given pid."""
        if platform_info.is_windows:
            import subprocess
            if force:
                subprocess.run(["taskkill", "/F", "/T", "/PID", str(pid)], capture_output=True)
            else:
                subprocess.run(["taskkill", "/T", "/PID", str(pid)], capture_output=True)
        else:
            sig = signal.SIGKILL if force else signal.SIGTERM
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                pass

    @staticmethod
    def is_process_alive(pid: int) -> bool:
        """Check if a process is alive."""
        if platform_info.is_windows:
            import ctypes
            # Get process handle
            kernel32 = ctypes.windll.kernel32
            SYNCHRONIZE = 0x00100000
            process = kernel32.OpenProcess(SYNCHRONIZE, False, pid)
            if not process:
                return False
            # Check if it has exited
            WAIT_TIMEOUT = 258
            status = kernel32.WaitForSingleObject(process, 0)
            kernel32.CloseHandle(process)
            return status == WAIT_TIMEOUT
        else:
            try:
                os.kill(pid, 0)
                return True
            except ProcessLookupError:
                return False
            except PermissionError:
                return True

    @staticmethod
    def setup_new_process_group():
        """Returns the preexec_fn needed to start a new process group."""
        if platform_info.is_windows:
            return None
        return os.setsid