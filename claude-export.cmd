@echo off
rem Runs claude-export from PowerShell or Command Prompt through Git for Windows' bash.
rem If Git is installed somewhere else, edit the path below.
"%ProgramFiles%\Git\bin\bash.exe" "%~dp0claude-export.sh" %*
