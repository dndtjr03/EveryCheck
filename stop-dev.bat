@echo off
REM ============================================================================
REM 백엔드 + adb 워처 강제 종료
REM ============================================================================

echo [stop] uvicorn 프로세스 종료...
taskkill /F /FI "WINDOWTITLE eq EveryCheck Backend*" >nul 2>&1
taskkill /F /IM python.exe /FI "WINDOWTITLE eq EveryCheck Backend*" >nul 2>&1

echo [stop] adb 워처 종료...
taskkill /F /FI "WINDOWTITLE eq adb reverse watcher*" >nul 2>&1

echo [stop] (선택) PostgreSQL 컨테이너 중지하려면 별도로:
echo         docker-compose down
echo.
pause
