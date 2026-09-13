$terminal = "C:\Program Files\MetaTrader 5\terminal64.exe"
$termData = "C:\Users\dmnde\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"

Copy-Item "C:\Projetos\eddytrader\tests\probe_env_w07.ex5" -Destination "$termData\MQL5\Experts\probe_env_w07.ex5" -Force
Copy-Item "C:\Projetos\eddytrader\tests\probe_env_w07.ex5" -Destination "$termData\MQL5\Scripts\probe_env_w07.ex5" -Force

$outFile = "$termData\MQL5\Files\probe_env_w07.txt"
if (Test-Path $outFile) { Remove-Item $outFile -Force }

$iniPath = "$termData\run_probe.ini"
$iniContent = @"
[Common]
Login=6272676
Server=ActivTradesCorp-Server

[Start]
Expert=Experts\probe_env_w07.ex5
Symbol=EURUSD
Period=M1
"@
Set-Content -Path $iniPath -Value $iniContent -Encoding Ascii

Write-Host "Killing any running terminal64..."
Stop-Process -Name "terminal64" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

Write-Host "Starting terminal with config: $iniPath..."
$proc = Start-Process -FilePath $terminal -ArgumentList "/config:`"$iniPath`"" -PassThru -NoNewWindow

$timeout = 25
$waited = 0
while ($waited -lt $timeout) {
    Start-Sleep -Seconds 2
    $waited += 2
    if (Test-Path $outFile) {
        Write-Host "Output file detected after $waited seconds!"
        break
    }
}

Start-Sleep -Seconds 2
Stop-Process -Name "terminal64" -Force -ErrorAction SilentlyContinue

if (Test-Path $outFile) {
    Write-Host "=== CONTENT OF probe_env_w07.txt ==="
    Get-Content $outFile
} else {
    Write-Warning "probe_env_w07.txt not created. Checking terminal logs..."
    $termLogs = Get-ChildItem "$termData\logs\20260913.log" -ErrorAction SilentlyContinue
    if ($termLogs) {
        Get-Content $termLogs.FullName -Encoding Unicode -Tail 25
    }
}
