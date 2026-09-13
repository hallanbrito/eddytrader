$p = Get-Process terminal64 -ErrorAction SilentlyContinue
if ($null -eq $p) {
    Write-Host "terminal64 is not running"
    exit
}

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public class WinUtil {
    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);
}
"@

$procId = $p.Id
Write-Host "Checking windows for PID: $procId"

[WinUtil]::EnumWindows([WinUtil+EnumWindowsProc]{
    param([IntPtr]$hwnd, [IntPtr]$lparam)
    $pidOut = 0
    [WinUtil]::GetWindowThreadProcessId($hwnd, [ref]$pidOut)
    if ($pidOut -eq $procId) {
        $sb = New-Object System.Text.StringBuilder 256
        [WinUtil]::GetWindowText($hwnd, $sb, 256) | Out-Null
        $title = $sb.ToString()
        $vis = [WinUtil]::IsWindowVisible($hwnd)
        if ($title -or $vis) {
            Write-Host "HWND: $hwnd Visible: $vis Title: '$title'"
        }
    }
    return $true
}, [IntPtr]::Zero) | Out-Null
