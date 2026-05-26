@echo off
REM ============================================================================
REM EveryCheck 개발 환경 일괄 시작 (Windows)
REM
REM 더블클릭하면:
REM   1. PostgreSQL (Docker) 백그라운드 실행
REM   2. 백엔드 (FastAPI/uvicorn)  - 새 PowerShell 창
REM   3. adb reverse 워처           - 새 PowerShell 창
REM   (Flutter는 VS Code에서 F5 또는 별도 터미널에서 실행)
REM
REM 종료할 때: 각 PowerShell 창에서 Ctrl+C, PostgreSQL은 그대로 둬도 됨
REM ============================================================================

setlocal
set ROOT=%~dp0
set ROOT=%ROOT:~0,-1%

echo.
echo [1/3] PostgreSQL (docker) ...
pushd "%ROOT%"
docker-compose up -d db >nul 2>&1
if errorlevel 1 (
    echo   ! Docker Desktop 이 꺼져있거나 db 컨테이너 시작 실패. Docker Desktop 을 켜고 다시 실행하세요.
) else (
    echo   OK
)
popd

echo.
echo [2/3] backend (uvicorn) - 새 창 ...
start "EveryCheck Backend" powershell -NoExit -Command ^
  "cd '%ROOT%'; .\venv\Scripts\Activate.ps1; cd backend; python -m uvicorn main:app --host 0.0.0.0 --port 8000"

echo.
echo [3/3] adb reverse watcher - 새 창 ...
start "adb reverse watcher" powershell -NoExit -Command ^
  "& '%ROOT%\Flutter\scripts\keep-adb-reverse.ps1'"

echo.
echo ===========================================
echo  완료! 새로 뜬 두 창은 그대로 두세요.
echo
echo  앱 실행은 다음 중 하나:
echo    - VS Code 에서 F5
echo    - 또는 새 PowerShell:  cd "%ROOT%\Flutter" ^&^& flutter run
echo ===========================================
echo.
pause
endlocal
