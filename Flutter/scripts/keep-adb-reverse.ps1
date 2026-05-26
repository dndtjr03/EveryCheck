# keep-adb-reverse.ps1
#
# Keeps adb reverse (tcp:8000 -> PC localhost:8000) alive while an Android
# device is connected via USB. Reconnects automatically on cable replug.
#
# Usage:
#   .\Flutter\scripts\keep-adb-reverse.ps1
#   .\Flutter\scripts\keep-adb-reverse.ps1 -Port 8001
#
# Stop with Ctrl+C. Leave this PowerShell window open while debugging.

param(
    [int]$Port = 8000,
    [string]$AdbPath = "C:\Android\platform-tools\adb.exe",
    [int]$IntervalSeconds = 3
)

if (-not (Test-Path $AdbPath)) {
    Write-Host "[ERROR] adb.exe not found: $AdbPath" -ForegroundColor Red
    Write-Host "  Use -AdbPath to override." -ForegroundColor Yellow
    exit 1
}

Write-Host "[adb-reverse-watcher] starting" -ForegroundColor Cyan
Write-Host ("  port     : {0}" -f $Port)
Write-Host ("  adb      : {0}" -f $AdbPath)
Write-Host ("  interval : {0}s" -f $IntervalSeconds)
Write-Host "  press Ctrl+C to stop"
Write-Host ""

$lastState = "init"

while ($true) {
    try {
        $deviceLines = & $AdbPath devices 2>$null | Select-String "device$"

        if ($deviceLines) {
            $serial = ($deviceLines[0].ToString() -split "\s+")[0]
            $reverses = & $AdbPath -s $serial reverse --list 2>$null
            $hasPort = $reverses | Select-String "tcp:$Port\s+tcp:$Port"

            if (-not $hasPort) {
                & $AdbPath -s $serial reverse "tcp:$Port" "tcp:$Port" 2>$null | Out-Null
                $ts = Get-Date -Format 'HH:mm:ss'
                Write-Host ("[{0}] reverse set ({1})" -f $ts, $serial) -ForegroundColor Green
                $lastState = "set"
            } elseif ($lastState -ne ("ok-" + $serial)) {
                $ts = Get-Date -Format 'HH:mm:ss'
                Write-Host ("[{0}] OK ({1})" -f $ts, $serial) -ForegroundColor DarkGray
                $lastState = "ok-" + $serial
            }
        } else {
            if ($lastState -ne "no-device") {
                $ts = Get-Date -Format 'HH:mm:ss'
                Write-Host ("[{0}] no device - waiting..." -f $ts) -ForegroundColor Yellow
                $lastState = "no-device"
            }
        }
    } catch {
        $ts = Get-Date -Format 'HH:mm:ss'
        $msg = $_.Exception.Message
        Write-Host ("[{0}] error: {1}" -f $ts, $msg) -ForegroundColor Red
    }

    Start-Sleep -Seconds $IntervalSeconds
}
