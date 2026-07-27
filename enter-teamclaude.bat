@echo off
REM One-click launcher: enter teamclaude auto-switch mode.
REM Double-click me. The window stays open so you can read the instructions.
title Enter TeamClaude Mode
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0enter-teamclaude.ps1"
echo.
pause
