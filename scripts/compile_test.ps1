$metaeditor = "C:\Program Files\MetaTrader 5\metaeditor64.exe"
if (-not (Test-Path $metaeditor)) {
    Write-Error "MetaEditor not found at $metaeditor"
    exit 1
}

$mq5Path = "C:\Projetos\eddytrader\tests\test_fsm_w06.mq5"
$logPath = "C:\Projetos\eddytrader\tests\test_fsm_w06.log"

Write-Host "Compiling $mq5Path..."
$proc = Start-Process -FilePath $metaeditor -ArgumentList "/compile:`"$mq5Path`" /log:`"$logPath`"" -Wait -PassThru -NoNewWindow
Start-Sleep -Milliseconds 500

if (Test-Path $logPath) {
    $logContent = Get-Content $logPath -Encoding Unicode
    $logContent | ForEach-Object { Write-Host $_ }
} else {
    Write-Warning "No log file produced."
}
