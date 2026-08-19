@echo off
title SearXNG for Windows
cd /d "%~dp0"

:: 若 SearXNG 已在运行（端口 8888 被占用），只打开页面并退出，避免窗口堆积
netstat -ano | findstr ":8888" | findstr "LISTENING" >nul 2>&1
if not errorlevel 1 (
    start "" "http://localhost:8888"
    exit /b
)

:: 检查随附的 python.exe 和 webapp.py 是否存在
if not exist ".\python\python.exe" (
    echo Error: python.exe not found in the current directory.
    pause
    exit /b
)

if not exist ".\python\Lib\site-packages\searx\webapp.py" (
    echo Error: webapp.py not found in the specified path.
    pause
    exit /b
)

echo Starting SearXNG for Windows...

:: 后台延迟约 5 秒打开浏览器（不影响前台终端日志）
start "" /b cmd /c "ping -n 6 127.0.0.1 >nul & explorer http://localhost:8888"

:: 前台启动服务器，终端窗口保留运行日志
.\python\python.exe .\python\Lib\site-packages\searx\webapp.py

pause