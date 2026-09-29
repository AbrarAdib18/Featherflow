@echo off
REM ===========================================================================
REM  Featherflow - start the backend (Django + uvicorn ASGI, dev mode)
REM  Double-click this file, or run it from a terminal.
REM  Stop the server with Ctrl+C.
REM ===========================================================================

cd /d "%~dp0backend"

if not exist "venv\Scripts\python.exe" (
    echo.
    echo [ERROR] Python virtualenv not found at backend\venv
    echo         Expected: %CD%\venv\Scripts\python.exe
    echo.
    pause
    exit /b 1
)

echo.
echo === Django system check ===
venv\Scripts\python.exe manage.py check
if errorlevel 1 (
    echo.
    echo [ERROR] Django check failed - not starting the server.
    echo.
    pause
    exit /b 1
)

echo.
echo === Starting backend on http://127.0.0.1:8000/ ===
echo     (auto-reloads on code changes - press Ctrl+C to stop)
echo.

venv\Scripts\python.exe -m uvicorn featherflow_backend.asgi:application --host 0.0.0.0 --port 8000 --reload

echo.
echo === Backend stopped ===
pause
