<#
.SYNOPSIS
    Monitor-Loader.ps1 - Monitor sync.top loader behavior
    
.DESCRIPTION
    Records everything loader.exe does:
    - File creations/modifications
    - Registry changes
    - Driver loads
    - Network connections
    - Process spawns
    
    Run this BEFORE starting loader, let it run during loader execution.
#>

#requires -RunAsAdministrator

$LogDir = "$env:TEMP\LoaderMonitor"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$LogFile = "$LogDir\monitor-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

function Write-MonLog {
    param($Message, $Level = "INFO")
    $ts = Get-Date -Format "HH:mm:ss.fff"
    $line = "[$ts] [$Level] $Message"
    Write-Host $line
    $line | Out-File -FilePath $LogFile -Append -Encoding UTF8
}

Write-MonLog "=== LOADER MONITOR STARTED ===" "START"
Write-MonLog "Log file: $LogFile" "INFO"
Write-MonLog "Press Ctrl+C to stop monitoring" "INFO"
Write-MonLog "Start loader.exe now..." "WARN"
Write-Host "`n`n"

# Initial system state
Write-MonLog "Capturing initial system state..." "INFO"

# 1. List running processes before
$procBefore = Get-Process | Select-Object Name, Id, Path
$procBefore | Export-Clixml "$LogDir\processes_before.xml"
Write-MonLog "Processes before: $($procBefore.Count)" "INFO"

# 2. List loaded drivers before
$driversBefore = Get-WinEvent -FilterHashtable @{LogName='System'; ID=7036} -MaxEvents 100 -EA SilentlyContinue
Write-MonLog "Recent driver events captured" "INFO"

# 3. Registry snapshot - key areas
$regKeys = @(
    "HKLM:\SOFTWARE\Microsoft\Cryptography",
    "HKLM:\SYSTEM\CurrentControlSet\Services",
    "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4D36E972-E325-11CE-BFC1-08002BE10318}"
)

foreach ($key in $regKeys) {
    if (Test-Path $key) {
        $regFile = "$LogDir\reg_$(($key -replace '\\', '_') -replace ':', '').reg"
        reg export $key $regFile 2>$null
    }
}
Write-MonLog "Registry snapshots saved" "INFO"

# 4. List files in temp before
$tempBefore = Get-ChildItem $env:TEMP -Recurse -EA SilentlyContinue | Select-Object FullName, Length, LastWriteTime
$tempBefore | Export-Clixml "$LogDir\temp_before.xml"
Write-MonLog "Temp folder snapshot: $($tempBefore.Count) files" "INFO"

# 5. Network connections before
$netBefore = Get-NetTCPConnection -EA SilentlyContinue | Select-Object LocalAddress, LocalPort, RemoteAddress, RemotePort, State, OwningProcess
$netBefore | Export-Clixml "$LogDir\network_before.xml"
Write-MonLog "Network connections: $($netBefore.Count) active" "INFO"

Write-MonLog "`n=== WAITING FOR LOADER.EXE ===`n" "WAIT"

# Monitoring loop
$loaderSeen = $false
$lastFileCount = $tempBefore.Count
$checkInterval = 5  # seconds

while ($true) {
    Start-Sleep -Seconds $checkInterval
    
    # Check for loader.exe process
    $loader = Get-Process -Name "loader" -EA SilentlyContinue
    if ($loader -and -not $loaderSeen) {
        Write-MonLog "LOADER.EXE DETECTED! PID: $($loader.Id)" "ALERT"
        $loaderSeen = $true
        
        # Log loader details
        Write-MonLog "  Path: $($loader.Path)" "INFO"
        Write-MonLog "  Started: $($loader.StartTime)" "INFO"
        Write-MonLog "  Memory: $([math]::Round($loader.WorkingSet64 / 1MB, 2)) MB" "INFO"
    }
    
    if ($loaderSeen) {
        # Monitor loader's children processes
        $children = Get-CimInstance Win32_Process | Where-Object { $_.ParentProcessId -eq $loader.Id }
        foreach ($child in $children) {
            Write-MonLog "Child process spawned: $($child.Name) (PID: $($child.ProcessId))" "PROCESS"
        }
        
        # Check for new files in temp
        $tempNow = Get-ChildItem $env:TEMP -Recurse -EA SilentlyContinue
        if ($tempNow.Count -ne $lastFileCount) {
            $newFiles = $tempNow | Where-Object { $_.LastWriteTime -gt (Get-Date).AddSeconds(-$checkInterval) }
            foreach ($file in $newFiles) {
                Write-MonLog "New file: $($file.FullName) ($([math]::Round($file.Length/1KB, 1)) KB)" "FILE"
            }
            $lastFileCount = $tempNow.Count
        }
        
        # Check for new drivers
        $newDrivers = Get-WinEvent -FilterHashtable @{LogName='System'; ID=7036; StartTime=(Get-Date).AddSeconds(-$checkInterval)} -EA SilentlyContinue
        foreach ($event in $newDrivers) {
            Write-MonLog "Driver event: $($event.Message)" "DRIVER"
        }
        
        # Check network connections from loader
        $loaderNet = Get-NetTCPConnection -OwningProcess $loader.Id -EA SilentlyContinue
        foreach ($conn in $loaderNet) {
            Write-MonLog "Network: $($conn.LocalAddress):$($conn.LocalPort) -> $($conn.RemoteAddress):$($conn.RemotePort) [$($conn.State)]" "NETWORK"
        }
        
        # Check if loader exited
        if (-not (Get-Process -Id $loader.Id -EA SilentlyContinue)) {
            Write-MonLog "LOADER.EXE EXITED" "ALERT"
            break
        }
    }
    
    # Also check if we should stop (user pressed key)
    if ([Console]::KeyAvailable) {
        $key = [Console]::ReadKey($true)
        if ($key.Key -eq 'Q') {
            Write-MonLog "User requested stop" "STOP"
            break
        }
    }
}

# Post-loader analysis
Write-MonLog "`n=== POST-LOADER ANALYSIS ===" "INFO"

# 1. Final processes
$procAfter = Get-Process | Select-Object Name, Id, Path
$newProcs = Compare-Object $procBefore $procAfter -Property Name, Id | Where-Object { $_.SideIndicator -eq '=>' }
foreach ($proc in $newProcs) {
    Write-MonLog "New process remained: $($proc.Name) (PID: $($proc.Id))" "PROCESS"
}

# 2. Final temp files
$tempAfter = Get-ChildItem $env:TEMP -Recurse -EA SilentlyContinue
$newTemp = Compare-Object $tempBefore $tempAfter -Property FullName | Where-Object { $_.SideIndicator -eq '=>' }
foreach ($file in $newTemp) {
    $f = Get-Item $file.FullName -EA SilentlyContinue
    if ($f) {
        Write-MonLog "New file created: $($f.FullName) ($([math]::Round($f.Length/1KB, 1)) KB)" "FILE"
        
        # If it's a .sys file, very important!
        if ($f.Extension -eq '.sys') {
            Write-MonLog "*** DRIVER FILE DETECTED: $($f.Name) ***" "DRIVER"
            # Try to get file info
            try {
                $sig = Get-AuthenticodeSignature $f.FullName
                Write-MonLog "  Signed: $($sig.Status) | Subject: $($sig.SignerCertificate.Subject)" "DRIVER"
            }
            catch {
                Write-MonLog "  Not signed or error checking signature" "WARN"
            }
        }
    }
}

# 3. Registry changes
Write-MonLog "Checking registry changes..." "INFO"
foreach ($key in $regKeys) {
    if (Test-Path $key) {
        $regFile = "$LogDir\reg_after_$(($key -replace '\\', '_') -replace ':', '').reg"
        reg export $key $regFile 2>$null
        
        $beforeFile = "$LogDir\reg_$(($key -replace '\\', '_') -replace ':', '').reg"
        if (Test-Path $beforeFile) {
            $diff = Compare-Object (Get-Content $beforeFile) (Get-Content $regFile)
            if ($diff) {
                Write-MonLog "REGISTRY CHANGED: $key" "REGISTRY"
                foreach ($line in $diff | Select-Object -First 10) {
                    Write-MonLog "  $($line.InputObject)" "REGISTRY"
                }
            }
        }
    }
}

# 4. WMI changes
Write-MonLog "Checking WMI hardware info..." "INFO"
$wmiAfter = @{
    Baseboard = (Get-WmiObject Win32_BaseBoard -EA SilentlyContinue).SerialNumber
    Disk1 = (Get-WmiObject Win32_PhysicalMedia -EA SilentlyContinue | Select -First 1).SerialNumber
    MAC = (Get-WmiObject Win32_NetworkAdapter -EA SilentlyContinue | Where-Object { $_.PhysicalAdapter } | Select -First 1).MACAddress
}

Write-MonLog "Current WMI values:" "INFO"
Write-MonLog "  Baseboard: $($wmiAfter.Baseboard)" "INFO"
Write-MonLog "  Disk1: $($wmiAfter.Disk1)" "INFO"
Write-MonLog "  MAC: $($wmiAfter.MAC)" "INFO"

# 5. Check for loaded drivers
$driversNow = driverquery /v | Select-String "kernel"
Write-MonLog "Kernel drivers currently loaded: $($driversNow.Count)" "INFO"

Write-MonLog "`n=== MONITORING COMPLETE ===" "COMPLETE"
Write-MonLog "All data saved to: $LogDir" "INFO"
Write-MonLog "Share this folder for analysis" "INFO"

# Open folder
Start-Process explorer.exe -ArgumentList $LogDir
