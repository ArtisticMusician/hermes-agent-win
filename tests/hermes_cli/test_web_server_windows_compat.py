"""Tests for Windows compatibility in hermes_cli.web_server."""

import os
import sys
import mimetypes
from pathlib import Path
from unittest.mock import patch, MagicMock

import pytest
from fastapi.testclient import TestClient
from fastapi import FastAPI

def test_mime_types_registered():
    """Verify that common web MIME types are explicitly registered."""
    # These should be registered in hermes_cli.web_server at module level
    import hermes_cli.web_server as web_server

    # Check if they are in the mimetypes module
    assert mimetypes.guess_type("test.js")[0] == "application/javascript"
    assert mimetypes.guess_type("test.mjs")[0] == "application/javascript"
    assert mimetypes.guess_type("test.css")[0] == "text/css"

def test_web_dist_is_absolute():
    """Verify that WEB_DIST is an absolute path."""
    import hermes_cli.web_server as web_server
    assert web_server.WEB_DIST.is_absolute()

def test_serve_index_encoding(tmp_path, monkeypatch):
    """Verify that _serve_index reads index.html with utf-8 encoding."""
    # Set up a fake WEB_DIST
    web_dist = tmp_path / "web_dist"
    web_dist.mkdir()
    (web_dist / "assets").mkdir()
    index_html = web_dist / "index.html"
    content = "<html><head></head><body>Hermes ⚕</body></html>"
    index_html.write_text(content, encoding="utf-8")

    monkeypatch.setattr("hermes_cli.web_server.WEB_DIST", web_dist)

    from hermes_cli.web_server import mount_spa

    # We want to verify that _index_path.read_text(encoding="utf-8") is called.
    test_app = FastAPI()

    # We patch Path.read_text to capture the encoding argument
    with patch("pathlib.Path.read_text") as mock_read:
        mock_read.return_value = content

        mount_spa(test_app)
        client = TestClient(test_app)

        # Trigger the SPA fallback
        resp = client.get("/some-random-route")
        assert resp.status_code == 200

        # Verify read_text was called with encoding="utf-8"
        found_utf8 = False
        for call in mock_read.call_args_list:
            if call.kwargs.get("encoding") == "utf-8":
                found_utf8 = True
                break
        assert found_utf8, "Path.read_text(encoding='utf-8') was not called"

def test_staticfiles_directory_is_string(monkeypatch, tmp_path):
    """Verify that StaticFiles is initialized with a string directory."""
    import fastapi.staticfiles

    # Create a dummy assets dir
    web_dist = tmp_path / "web_dist"
    web_dist.mkdir()
    (web_dist / "assets").mkdir()
    (web_dist / "index.html").write_text("dummy")

    monkeypatch.setattr("hermes_cli.web_server.WEB_DIST", web_dist)

    from hermes_cli.web_server import mount_spa

    with patch("fastapi.staticfiles.StaticFiles.__init__", return_value=None) as mock_init:
        test_app = FastAPI()
        mount_spa(test_app)

        # Find the call to StaticFiles
        assert mock_init.called
        # directory is usually the first positional arg or a kwarg
        kwargs = mock_init.call_args.kwargs
        args = mock_init.call_args.args

        directory = kwargs.get("directory") or (args[1] if len(args) > 1 else None)
        assert isinstance(directory, str), f"StaticFiles directory should be str, got {type(directory)}"

def test_windows_shell_build_logic():
    """Verify build command uses shell=True logic."""
    import subprocess
    from hermes_cli.main import _build_web_ui

    # Mock sys.platform to be win32
    with patch("sys.platform", "win32"):
        with patch("subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(returncode=0)
            with patch("shutil.which", return_value="npm"):
                # Mock Path.exists for package.json
                with patch("pathlib.Path.exists", return_value=True):
                    _build_web_ui(Path("fake_dir"))
                    # Should be called twice (install and build)
                    assert mock_run.call_count >= 2
                    for call in mock_run.call_args_list:
                        assert call.kwargs.get("shell") is True

    # Mock sys.platform to be linux
    with patch("sys.platform", "linux"):
        with patch("subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(returncode=0)
            with patch("shutil.which", return_value="npm"):
                with patch("pathlib.Path.exists", return_value=True):
                    _build_web_ui(Path("fake_dir"))
                    assert mock_run.call_count >= 2
                    for call in mock_run.call_args_list:
                        assert call.kwargs.get("shell") is False
