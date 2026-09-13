Stop-Process -Name terminal64 -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

$termData = "C:\Users\dmnde\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"
$chartPath = "$termData\MQL5\Profiles\Charts\Default\chart01.chr"
$chartBak = "$termData\MQL5\Profiles\Charts\Default\chart01.chr.clean"

if (-not (Test-Path $chartBak)) {
    Copy-Item $chartPath $chartBak -Force
}

Copy-Item "C:\Projetos\eddytrader\tests\probe_env_w07.ex5" "$termData\MQL5\Experts\probe_env_w07.ex5" -Force

$content = Get-Content $chartBak -Encoding Unicode
$expertBlock = @"
<expert>
name=probe_env_w07
flags=339
window_num=0
<inputs>
</inputs>
</expert>
<window>
"@

$joined = $content -join "`r`n"
$newContent = $joined.Replace("<window>", $expertBlock)
Set-Content -Path $chartPath -Value $newContent -Encoding Unicode

$outFile = "$termData\MQL5\Files\probe_env_w07.txt"
if (Test-Path $outFile) { Remove-Item $outFile -Force }

$terminal = "C:\Program Files\MetaTrader 5\terminal64.exe"
Write-Host "Starting terminal with expert attached before <window>..."
$proc = Start-Process $terminal -PassThru

$found = $false
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 1
    if (Test-Path $outFile) {
        Write-Host "FOUND $outFile at second $i!"
        $found = $true
        break
    }
}

Start-Sleep -Seconds 2
Stop-Process -Name terminal64 -Force -ErrorAction SilentlyContinue
Copy-Item $chartBak $chartPath -Force

if ($found) {
    Write-Host "=== CONTENT OF $outFile ==="
    Get-Content $outFile
} else {
    Write-Warning "Not found."
    $mqlLogs = Get-ChildItem "$termData\MQL5\logs\*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
    if ($mqlLogs) {
        Write-Host "=== MQL5 Log ($($mqlLogs[0].Name)) ==="
        Get-Content $mqlLogs[0].FullName -Encoding Unicode -Tail 25
    }
    $termLogs = Get-ChildItem "$termData\logs\20260913.log" -ErrorAction SilentlyContinue
    if ($termLogs) {
        Write-Host "=== Terminal Log ==="
        Get-Content $termLogs.FullName -Encoding Unicode -Tail 25
    }
}
