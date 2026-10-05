@echo off
REM One-click: warm every idle account once, starting its rolling 5h window.
REM Double-click me. The window stays open so you can read the result.
title Warm TeamClaude Accounts
node --no-deprecation "%~dp0warm-teamclaude.mjs"
echo.
pause
