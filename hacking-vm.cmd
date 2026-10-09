@echo off
rem Windows launcher: passes everything to hacking-vm.ps1 without needing to change execution policy.
rem Double-clicking this file boots the LiveCD.
if "%~1"=="" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0hacking-vm.ps1" run
  pause
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0hacking-vm.ps1" %*
)
