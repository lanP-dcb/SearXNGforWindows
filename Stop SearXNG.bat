@echo off
title SearXNG for Windows - Stop
cd /d "%~dp0"

:: 检查是否有进程监听 8888（即 SearXNG 是否在运行）
netstat -ano | findstr ":8888" | findstr "LISTENING" >nul 2>&1
if errorlevel 1 (
    echo SearXNG is not running.
    pause
    exit /b
)

:: 终止监听 8888 的 python 进程（SearXNG 服务）
for /f "tokens=5" %%p in ('netstat -ano ^| findstr ":8888" ^| findstr "LISTENING"') do (
    for /f "tokens=1" %%i in ('tasklist /FI "PID eq %%p" /NH ^| findstr /i "python"') do (
        taskkill /PID %%p /F >nul 2>&1 && echo SearXNG stopped ^(PID %%p^).
    )
)

pause