@echo off
REM ============================================================================
REM Windows 자동 시작 등록 해제
REM ============================================================================

setlocal
set STARTUP=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup
set LINK=%STARTUP%\EveryCheck-Dev.lnk

if exist "%LINK%" (
    del "%LINK%"
    echo [autostart] 등록 해제 완료. 다음 부팅부터는 자동 실행 안 됩니다.
) else (
    echo [autostart] 등록된 시작프로그램이 없습니다.
)

echo.
echo 현재 실행 중인 백엔드/adb 워처도 종료하려면:
echo   stop-dev.bat 실행

echo.
pause
endlocal
