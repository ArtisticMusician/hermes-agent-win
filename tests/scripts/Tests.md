# Testing PowerShell Scripts

Since this environment doesn't have `pwsh` installed by default to run Pester tests directly in the CI/Sandbox, we've structured basic Pester tests in `.Tests.ps1` files.
These tests use standard Pester v5 mocking and assertion structures.

The tests can be executed on a Windows machine by running:
```powershell
Invoke-Pester .\tests\scripts\
```
