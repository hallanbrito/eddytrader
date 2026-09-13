$metaeditor = "C:\Program Files\MetaTrader 5\metaeditor64.exe"
$termData = "C:\Users\dmnde\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"
$outFile = "$termData\MQL5\Files\probe_env_w07.txt"
if (Test-Path $outFile) { Remove-Item $outFile -Force }

Write-Host "Invoking metaeditor64 /run:probe_env_w07..."
Start-Process $metaeditor -ArgumentList "/run:probe_env_w07" -NoNewWindow
Start-Sleep -Seconds 5

if (Test-Path $outFile) {
    Write-Host "SUCCESS! probe_env_w07.txt found!"
    Get-Content $outFile
} else {
    Write-Host "Not created with probe_env_w07. Trying with Scripts\probe_env_w07..."
    Start-Process $metaeditor -ArgumentList "/run:Scripts\probe_env_w07" -NoNewWindow
    Start-Sleep -Seconds 5
    if (Test-Path $outFile) {
        Write-Host "SUCCESS with Scripts\probe_env_w07!"
        Get-Content $outFile
    } else {
        Write-Host "Trying with Experts\probe_env_w07..."
        Start-Process $metaeditor -ArgumentList "/run:Experts\probe_env_w07" -NoNewWindow
        Start-Sleep -Seconds 5
        if (Test-Path $outFile) {
            Write-Host "SUCCESS with Experts\probe_env_w07!"
            Get-Content $outFile
        } else {
            Write-Warning "probe_env_w07.txt still not created."
            $logs = Get-ChildItem "$termData\MQL5\logs\*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
            if ($logs) {
                Write-Host "Last lines of MQL5 log:"
                Get-Content $logs[0].FullName -Encoding Unicode -Tail 20
            }
        }
    }
}
