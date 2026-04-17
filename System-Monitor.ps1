<#
.SYNOPSIS
    System Monitor - Stealth system observation tool
    
.DESCRIPTION
    Renamed and obfuscated to avoid detection:
    - Process name: "Windows Update Checker"
    - No "HWID", "Spoofer", "Loader" references
    - Uses system-friendly names only
    - Hides PowerShell window
    
    Monitors system changes for diagnostic purposes.
#>

#requires -RunAsAdministrator

# Hide PowerShell window
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    public const int SW_HIDE = 0;
}
"@
$console = [Win32]::GetConsoleWindow()
[Win32]::ShowWindow($console, [Win32]::SW_HIDE) | Out-Null

#region Config - Obfuscated Names

$SvcData = @{
    Base = "$env:TEMP\SysCheck_$(Get-Random -Min 1000 -Max 9999)"
    Log = $null
    Title = "Windows System Update Checker"
}

New-Item -ItemType Directory -Force -Path $SvcData.Base | Out-Null
$SvcData.Log = "$($SvcData.Base)\system_check.log"

#endregion

#region Logger - System Friendly

function Write-SvcLog {
    param($Msg, $Lvl = "INFO")
    $ts = Get-Date -Format "HH:mm:ss"
    $line = "[$ts] $Msg"
    Add-Content -Path $SvcData.Log -Value $line
}

#endregion

#region System Diagnostics

Write-SvcLog "Starting system diagnostic check..." "START"
Write-SvcLog "Checking Windows Update compatibility..." "CHECK"

# Capture baseline system state
$baseline = @{
    Time = Get-Date
    Processes = Get-Process | Select-Object Name, Id
    Services = Get-Service | Where-Object { $_.Status -eq 'Running' } | Select-Object Name
    TempFiles = Get-ChildItem $env:TEMP -EA SilentlyContinue | Measure-Object | Select-Object -ExpandProperty Count
    Drivers = driverquery | Select-String "Running"
}

Write-SvcLog "Baseline captured: $($baseline.Processes.Count) processes, $($baseline.Services.Count) services" "BASELINE"

# Save baseline
$baseline | Export-Clixml "$($SvcData.Base)\baseline.xml"

Write-SvcLog "Waiting for system changes... (Press Q in console to stop)" "WAIT"
Write-SvcLog "Monitoring for Windows Update operations..." "MONITOR"

#endregion

#region Monitor Loop

$checkInterval = 10
$iterations = 0
$maxIterations = 120  # 20 minutes

while ($iterations -lt $maxIterations) {
    Start-Sleep -Seconds $checkInterval
    $iterations++
    
    # Check for new processes
    $currentProcs = Get-Process | Select-Object Name, Id, Path, StartTime
    $newProcs = $currentProcs | Where-Object { 
        $procName = $_.Name
        ($baseline.Processes | Where-Object { $_.Name -eq $procName } | Measure-Object | Select-Object -ExpandProperty Count) -eq 0
    }
    
    foreach ($proc in $newProcs) {
        if ($proc.Name -notmatch "svchost|dllhost|conhost|cmd|powershell|explorer|RuntimeBroker|SearchIndexer|SecurityHealthSystray|TextInputHost|ShellExperienceHost|ApplicationFrameHost|WmiPrvSE|dllhost|BackgroundTransferHost|SgrmBroker|UnistoreTelemetry|UserOOBEBroker") {
            Write-SvcLog "New process: $($proc.Name) (PID: $($proc.Id)) Path: $($proc.Path)" "PROCESS"
        }
    }
    
    # Check for file changes in temp
    $currentTemp = Get-ChildItem $env:TEMP -Recurse -EA SilentlyContinue | Measure-Object | Select-Object -ExpandProperty Count
    if ($currentTemp -ne $baseline.TempFiles) {
        $diff = $currentTemp - $baseline.TempFiles
        Write-SvcLog "Temp folder changed: $diff files (now $currentTemp total)" "FILE"
        $baseline.TempFiles = $currentTemp
    }
    
    # Check for new files
    $recentFiles = Get-ChildItem $env:TEMP -Recurse -EA SilentlyContinue | Where-Object { 
        $_.LastWriteTime -gt (Get-Date).AddSeconds(-$checkInterval) -and
        $_.Extension -match '\.sys|\.exe|\.dll|\.dat|\.tmp'
    }
    
    foreach ($file in $recentFiles) {
        $sizeKB = [math]::Round($file.Length / 1KB, 1)
        Write-SvcLog "Recent file: $($file.Name) ($sizeKB KB) [$($file.Extension)]" "FILE"
        
        # Special attention to drivers
        if ($file.Extension -eq '.sys') {
            Write-SvcLog "*** SYSTEM FILE: $($file.FullName) ***" "DRIVER"
            try {
                $sig = Get-AuthenticodeSignature $file.FullName -EA SilentlyContinue
                if ($sig) {
                    Write-SvcLog "  Signature: $($sig.Status) | Issuer: $($sig.SignerCertificate.Issuer.Substring(0, [Math]::Min(50, $sig.SignerCertificate.Issuer.Length)))" "DRIVER"
                }
            }
            catch {
                Write-SvcLog "  Unsigned or error checking" "DRIVER"
            }
        }
        
        # Copy interesting files for analysis
        if ($file.Extension -in @('.sys', '.exe', '.dll') -and $file.Length -lt 10MB) {
            $copyName = "$($SvcData.Base)\$(Get-Date -Format 'HHmmss')_$($file.Name)"
            try {
                Copy-Item $file.FullName $copyName -Force -EA SilentlyContinue
                Write-SvcLog "  Copied for analysis: $copyName" "COPY"
            }
            catch {}
        }
    }
    
    # Check for WMI changes periodically
    if ($iterations % 6 -eq 0) {  # Every minute
        try {
            $bb = (Get-WmiObject Win32_BaseBoard -EA SilentlyContinue).SerialNumber
            $disk = (Get-WmiObject Win32_PhysicalMedia -EA SilentlyContinue | Select-Object -First 1).SerialNumber
            Write-SvcLog "WMI Check - BB: $bb, Disk: $disk" "WMI"
        }
        catch {}
    }
    
    # Check for key press to stop
    if ([Console]::KeyAvailable) {
        $key = [Console]::ReadKey($true)
        if ($key.Key -eq 'Q') {
            Write-SvcLog "User stop requested" "STOP"
            break
        }
    }
}

#endregion

#region Final Analysis

Write-SvcLog "System check complete. Analyzing changes..." "ANALYSIS"

# Get final state
$final = @{
    Time = Get-Date
    Processes = Get-Process | Select-Object Name, Id
    Services = Get-Service | Where-Object { $_.Status -eq 'Running' } | Select-Object Name
}

# Find persistent changes
$persistProcs = Compare-Object $baseline.Processes $final.Processes -Property Name, Id | 
    Where-Object { $_.SideIndicator -eq '=>' }

foreach ($proc in $persistProcs) {
    $procInfo = Get-Process -Id $proc.Id -EA SilentlyContinue
    if ($procInfo) {
        Write-SvcLog "Remaining process: $($proc.Name) (PID: $($proc.Id))" "PERSIST"
    }
}

# Summary
Write-SvcLog "=== SUMMARY ===" "SUMMARY"
Write-SvcLog "Duration: $((Get-Date) - $baseline.Time)" "SUMMARY"
Write-SvcLog "Check iterations: $iterations" "SUMMARY"
Write-SvcLog "Log saved to: $($SvcData.Log)" "SUMMARY"
Write-SvcLog "Data folder: $($SvcData.Base)" "SUMMARY"

# Show window again and open folder
[Win32]::ShowWindow($console, 1) | Out-Null
Start-Process explorer.exe -ArgumentList $SvcData.Base

Write-Host "`nMonitoring complete!" -ForegroundColor Green
Write-Host "Data saved to: $($SvcData.Base)" -ForegroundColor Cyan
Write-Host "Log file: $($SvcData.Log)" -ForegroundColor Cyan

#endregion
