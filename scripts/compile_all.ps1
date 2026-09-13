$metaeditor = "C:\Program Files\MetaTrader 5\metaeditor64.exe"
if (-not (Test-Path $metaeditor)) {
    Write-Error "MetaEditor not found at $metaeditor"
    exit 1
}

$files = Get-ChildItem "C:\Projetos\eddytrader\research\w05\*.mq5"
foreach ($f in $files) {
    $mq5Path = $f.FullName
    $logPath = [System.IO.Path]::ChangeExtension($mq5Path, ".log")
    Write-Host "Compiling: $($f.Name)..."
    
    $proc = Start-Process -FilePath $metaeditor -ArgumentList "/compile:`"$mq5Path`" /log:`"$logPath`"" -Wait -PassThru -NoNewWindow
    
    Start-Sleep -Milliseconds 300
    if (Test-Path $logPath) {
        $logContent = Get-Content $logPath -Encoding Unicode
        $resultLine = $logContent | Where-Object { $_ -match "Result:" }
        if ($resultLine) {
            Write-Host "  -> $resultLine"
        } else {
            Write-Host "  -> Log generated but no Result line:"
            $logContent | Select-Object -Last 5 | ForEach-Object { Write-Host "     $_" }
        }
    } else {
        Write-Warning "  -> No log produced for $($f.Name)"
    }
}
