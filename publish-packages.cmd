@echo off
call powershell -ExecutionPolicy ByPass -NoProfile -command "& """%~dp0eng\common\build.ps1""" -pack -c Release -warnAsError 0"
call powershell -ExecutionPolicy ByPass -NoProfile -command "& """%~dp0eng\common\publish-packages.ps1""" %*"
exit /b %ErrorLevel%
