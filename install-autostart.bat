@echo off
REM ============================================================================
REM Windows 시작 시 EveryCheck 백엔드+adb 워처 자동 실행 등록
REM
REM 사용법: 이 파일을 한 번만 더블클릭. 다음 부팅부터 자동 실행됨.
REM 해제: uninstall-autostart.bat 더블클릭.
REM ============================================================================

setlocal
set ROOT=%~dp0
set ROOT=%ROOT:~0,-1%
set STARTUP=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup
set LINK=%STARTUP%\EveryCheck-Dev.lnk
set TARGET=%ROOT%\start-dev-silent.bat

echo.
echo [autostart] 시작프로그램 등록 중...
echo   대상: %TARGET%
echo   바로가기: %LINK%
echo.

REM PowerShell 한 줄로 바로가기(.lnk) 생성 — 콘솔 숨김(WindowStyle=7)
powershell -NoProfile -Command ^
  "$s = (New-Object -ComObject WScript.Shell).CreateShortcut('%LINK%'); $s.TargetPath = '%TARGET%'; $s.WorkingDirectory = '%ROOT%'; $s.WindowStyle = 7; $s.Save()"

if exist "%LINK%" (
    echo   OK - 다음 로그인부터 자동 실행됩니다.
    echo.
    echo 지금 바로 시작하려면 아래 명령을 실행하거나 PC를 재부팅하세요:
    echo   "%TARGET%"
) else (
    echo   ! 바로가기 생성 실패. 권한 또는 경로 확인 필요.
)

echo.
pause
endlocal
