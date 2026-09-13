$procs = Get-Process terminal64, metaeditor64 -ErrorAction SilentlyContinue
foreach ($p in $procs) {
    Write-Host "Process: $($p.Name) PID: $($p.Id) MainTitle: '$($p.MainWindowTitle)' Handle: $($p.MainWindowHandle)"
}
