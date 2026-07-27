@echo off
REM One-click launcher: leave teamclaude mode, restore the direct connection.
REM Double-click me. The window stays open so you can read the instructions.
title Exit TeamClaude Mode
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0exit-teamclaude.ps1"
echo.
pause
