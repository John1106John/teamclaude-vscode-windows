@echo off
REM One-click launcher: start VS Code with teamclaude in forward-proxy mode.
REM Double-click me. The window stays open so you can read the notes.
title Launch VS Code with TeamClaude
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0launch-teamclaude-vscode.ps1"
echo.
pause
