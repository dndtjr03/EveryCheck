@echo off
REM ============================================================================
REM EveryCheck 백그라운드 실행 (창 없음, 자동 시작용)
REM
REM 동작:
REM   1. PostgreSQL (Docker) 백그라운드 시작
REM   2. 백엔드 (uvicorn) 최소화된 창에서 실행 — 작업표시줄에서 클릭하면 로그 보임
REM   3. adb reverse 워처 최소화된 창
REM
REM 부팅 후 한 번만 호출되도록 install-autostart.bat 에서 시작프로그램 등록함.
REM ============================================================================

setlocal
set ROOT=%~dp0
set ROOT=%ROOT:~0,-1%

REM PostgreSQL (Docker Desktop 이 켜져 있어야 동작)
pushd "%ROOT%"
docker-compose up -d db >nul 2>&1
popd

REM 백엔드 — 최소화된 PowerShell 창 (작업표시줄에서 클릭하면 로그 확인 가능)
start "EveryCheck Backend" /MIN powershell -NoExit -WindowStyle Minimized -Command ^
  "cd '%ROOT%'; .\.venv\Scripts\Activate.ps1; cd backend; python -m uvicorn main:app --host 0.0.0.0 --port 8000"

REM adb reverse 워처 — 최소화된 PowerShell 창
start "adb reverse watcher" /MIN powershell -NoExit -WindowStyle Minimized -Command ^
  "& '%ROOT%\Flutter\scripts\keep-adb-reverse.ps1'"

endlocal
