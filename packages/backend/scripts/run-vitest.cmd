@echo off
setlocal

set SCRIPT_DIR=%~dp0
set BACKEND_DIR=%SCRIPT_DIR%..

call "%BACKEND_DIR%\node_modules\.bin\vitest.cmd" run --pool=threads %*
