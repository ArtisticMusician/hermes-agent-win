
import os
import platform
import tempfile
import pytest
from unittest.mock import MagicMock, patch

def test_local_environment_temp_dir_windows(monkeypatch):
    """Verify get_temp_dir handles Windows paths correctly when mocked."""
    # We must mock platform.system in the module where LocalEnvironment is defined
    # but also where it's imported if it uses a module-level constant.

    with patch("tools.environments.local._IS_WINDOWS", True), \
         patch("platform.system", return_value="Windows"):

        from tools.environments.local import LocalEnvironment

        # Mock env to return a Windows-style TMPDIR
        env = LocalEnvironment(cwd="C:\\test")
        env.env = {"TMPDIR": "C:\\Windows\\Temp"}

        assert env.get_temp_dir() == "C:\\Windows\\Temp"

        # Test fallback to tempfile.gettempdir()
        env.env = {}
        with patch("tempfile.gettempdir", return_value="C:\\Users\\Test\\AppData\\Local\\Temp"):
            assert env.get_temp_dir() == "C:\\Users\\Test\\AppData\\Local\\Temp"

def test_tool_result_storage_dir_windows():
    """Verify STORAGE_DIR is platform-appropriate."""
    with patch("platform.system", return_value="Windows"), \
         patch("tempfile.gettempdir", return_value="C:\\Temp"):

        # Reloading module to test top-level assignment
        import importlib
        import tools.tool_result_storage
        importlib.reload(tools.tool_result_storage)

        assert "C:\\Temp" in tools.tool_result_storage.STORAGE_DIR
        assert tools.tool_result_storage.STORAGE_DIR.endswith("hermes-results")

def test_file_operations_expand_path_windows():
    """Verify _expand_path handles $USERPROFILE on Windows."""
    from tools.file_operations import ShellFileOperations

    mock_env = MagicMock()
    # Mock return values for $HOME and $USERPROFILE
    # Git Bash often sets $HOME even on Windows, but our logic handles the fallback.
    mock_env.execute.side_effect = lambda cmd, **kwargs: {
        "output": "C:\\Users\\Test" if "USERPROFILE" in cmd else "",
        "returncode": 0
    }

    file_ops = ShellFileOperations(mock_env)

    with patch("platform.system", return_value="Windows"):
        expanded = file_ops._expand_path("~/test.txt")
        assert expanded == "C:\\Users\\Test/test.txt"

def test_file_tools_windows_guards():
    """Verify Windows-specific device and path guards."""
    import tools.file_tools

    # Check device paths
    assert tools.file_tools._is_blocked_device("NUL")
    assert tools.file_tools._is_blocked_device("COM1")

    # Check sensitive paths
    assert tools.file_tools._check_sensitive_path("C:\\Windows\\System32\\config") is not None
    assert tools.file_tools._check_sensitive_path("C:\\Program Files\\SomeApp") is not None
