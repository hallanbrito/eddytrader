Stop-Process -Name terminal64 -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
$proc = Start-Process "C:\Program Files\MetaTrader 5\terminal64.exe" -PassThru
Start-Sleep -Seconds 8
$p = Get-Process terminal64 -ErrorAction SilentlyContinue
if ($p) {
    Write-Host "Terminal is running! PID: $($p.Id), Title: '$($p.MainWindowTitle)', Handle: $($p.MainWindowHandle)"
} else {
    Write-Host "Terminal is not running."
}
