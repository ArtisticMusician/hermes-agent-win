from hermes_cli import gateway_windows


def _patch_windows_status(monkeypatch, tmp_path, *, task=False, startup=False, pids=None):
    monkeypatch.setattr(gateway_windows.sys, "platform", "win32")
    monkeypatch.setattr(gateway_windows, "get_task_name", lambda: "Hermes_Gateway")
    monkeypatch.setattr(gateway_windows, "is_task_registered", lambda: task)
    monkeypatch.setattr(gateway_windows, "is_startup_entry_installed", lambda: startup)
    monkeypatch.setattr(gateway_windows, "_gateway_pids", lambda: list(pids or []))
    monkeypatch.setattr(gateway_windows, "query_task_status", lambda: {})
    monkeypatch.setattr(
        gateway_windows,
        "get_task_script_path",
        lambda: tmp_path / "gateway-service" / "Hermes_Gateway.cmd",
    )
    monkeypatch.setattr(
        gateway_windows,
        "get_startup_entry_path",
        lambda: tmp_path / "Startup" / "Hermes_Gateway.cmd",
    )
    monkeypatch.setattr(
        gateway_windows,
        "_gateway_log_paths",
        lambda: (tmp_path / "logs" / "gateway.log", tmp_path / "logs" / "gateway-stdio.log"),
    )


def test_windows_status_installed_but_stopped_prints_start_and_logs(monkeypatch, tmp_path, capsys):
    _patch_windows_status(monkeypatch, tmp_path, task=True, pids=[])

    gateway_windows.status()

    out = capsys.readouterr().out
    assert "Scheduled Task registered: Hermes_Gateway" in out
    assert "Backend: Scheduled Task" in out
    assert "service is installed but no gateway process is running" in out
    assert "hermes gateway start" in out
    assert "gateway.log" in out
    assert "gateway-stdio.log" in out


def test_windows_status_manual_process_suggests_install(monkeypatch, tmp_path, capsys):
    _patch_windows_status(monkeypatch, tmp_path, pids=[1234])

    gateway_windows.status()

    out = capsys.readouterr().out
    assert "Gateway service not installed" in out
    assert "Gateway process running (PID: 1234)" in out
    assert "running manually" in out
    assert "hermes gateway install" in out


def test_windows_status_absent_prints_install_command(monkeypatch, tmp_path, capsys):
    _patch_windows_status(monkeypatch, tmp_path)

    gateway_windows.status()

    out = capsys.readouterr().out
    assert "Gateway service not installed" in out
    assert "No gateway process detected" in out
    assert "To install:" in out
    assert "hermes gateway install" in out
