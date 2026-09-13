$path = "C:\Users\dmnde\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\config\common.ini"
$content = Get-Content $path -Encoding Unicode
$hasExperts = $false
foreach ($line in $content) {
    if ($line -match "\[Experts\]") {
        $hasExperts = $true
        break
    }
}

if (-not $hasExperts) {
    $newLines = @(
        "",
        "[Experts]",
        "AllowDllImport=0",
        "Enabled=1",
        "Account=0",
        "Profile=0"
    )
    $content += $newLines
    Set-Content -Path $path -Value $content -Encoding Unicode
    Write-Host "[Experts] section added successfully to common.ini!"
} else {
    Write-Host "[Experts] section already present in common.ini."
}

Get-Content $path -Encoding Unicode -Tail 10
