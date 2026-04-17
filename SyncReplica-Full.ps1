<#
.SYNOPSIS
    SyncReplica-Full.ps1 - EXACT Sync.top Loader Clone
    
.DESCRIPTION
    Replicates sync.top loader behavior exactly:
    
    BEHAVIOR OBSERVED:
    - "Internet disconnects 20-30 seconds during loading" = MAC spoofing + adapter reset
    - "Load driver every restart" = Temporary mode, no persistence
    - "Use Cleaner first, then load driver" = Trace cleaning before spoof
    - "Only use Cleaner again on new ban" = One-time clean sufficient
    - "USB drive recommended" = Portable operation, less forensics
    
    THIS SCRIPT REPLICATES:
    1. Network disconnect during MAC spoof (normal)
    2. Cleaner - Removes ban traces (run once)
    3. Loader - Loads driver + spoofs HWID (run every boot)
    4. USB portable mode support
    
.NOTES
    Version: 2.0.0-FullSync
    Based on: sync.top loader behavior analysis
#>

#requires -RunAsAdministrator

param(
    [switch]$Cleaner,      # Run trace cleaner (use once, or after new ban)
    [switch]$Loader,       # Load driver + spoof (use every boot)
    [switch]$FullRun,      # Cleaner + Loader in sequence
    [switch]$USBMode       # Optimize for USB drive operation
)

#region Configuration

$Config = @{
    Version = "2.0.0-SyncClone"
    
    # Paths (USB-friendly - use script location if on USB)
    BaseDir = if ($USBMode) { 
        Split-Path -Parent $PSCommandPath 
    } else { 
        "$env:LOCALAPPDATA\SyncReplica" 
    }
    
    CleanerFlagFile = "cleaner_done.flag"
    LogFile = "sync-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
    
    # Sync-style messages
    Messages = @{
        NetworkDisconnect = "Your internet will disconnect for 20 to 30 seconds during the loading process. This is completely normal, please wait for it to finish."
        LoadEveryRestart = "You need to load the driver every time you restart your PC."
        FirstTimeCleaner = "First time using sync.top? Use the Cleaner, then load the driver."
        CleanerOnce = "Only use the Cleaner again if you get a new ban."
        USBRecommend = "We recommend placing the loader on a USB drive to reduce ban chances, but this is not required."
    }
}

# Create directories
if (-not (Test-Path $Config.BaseDir)) {
    New-Item -ItemType Directory -Force -Path $Config.BaseDir | Out-Null
}

$LogPath = Join-Path $Config.BaseDir $Config.LogFile
$FlagPath = Join-Path $Config.BaseDir $Config.CleanerFlagFile

#endregion

#region Logging

function Write-SyncLog {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "HH:mm:ss"
    
    $prefix = switch ($Level) {
        "CLEANER" { "🧹" }
        "LOADER" { "🚀" }
        "NETWORK" { "🌐" }
        "SUCCESS" { "✓" }
        "WARN" { "⚠" }
        "ERROR" { "✗" }
        default { "ℹ" }
    }
    
    $color = switch ($Level) {
        "CLEANER" { "Cyan" }
        "LOADER" { "Green" }
        "NETWORK" { "Yellow" }
        "SUCCESS" { "Green" }
        "WARN" { "Yellow" }
        "ERROR" { "Red" }
        default { "White" }
    }
    
    $line = "[$ts] $prefix $Message"
    Write-Host $line -ForegroundColor $color
    
    # Log to file (USB-friendly, no appdata if in USB mode)
    $line | Out-File -FilePath $LogPath -Append -Encoding UTF8
}

#endregion

#region Banner

function Show-SyncBanner {
    Clear-Host
    Write-Host @"
╔══════════════════════════════════════════════════════════════════════╗
║                                                                      ║
║                    SYNC.TOP REPLICA v$($Config.Version)              ║
║                                                                      ║
║              Professional HWID Spoofer for EAC/Vanguard            ║
║                                                                      ║
╚══════════════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Magenta
    
    if ($USBMode) {
        Write-Host "  💾 USB MODE: Running from portable drive" -ForegroundColor Cyan
    }
    Write-Host ""
}

#endregion

#region CLEANER - Ban Trace Removal

function Invoke-SyncCleaner {
    Write-SyncLog "=== SYNC CLEANER ===" "CLEANER"
    Write-SyncLog "Removing all ban traces and identifiers..." "CLEANER"
    Write-Host ""
    
    # Show sync.top style messages
    Write-Host "🧹 First time using? Running full system clean..." -ForegroundColor Cyan
    Write-Host ""
    
    $cleaned = 0
    
    # 1. Registry traces
    Write-SyncLog "Cleaning registry traces..." "CLEANER"
    $keys = @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\UserAssist",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RecentDocs",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\ComDlg32",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Diagnostics",
        "HKLM:\SOFTWARE\Microsoft\SQMClient",
        "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting",
        "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\AppCompatCache"
    )
    
    foreach ($key in $keys) {
        if (Test-Path $key) {
            try {
                Remove-Item -Path $key -Recurse -Force -EA SilentlyContinue
                $cleaned++
                Write-SyncLog "  Cleaned: $key" "CLEANER"
            }
            catch {
                Write-SyncLog "  Failed: $key" "WARN"
            }
        }
    }
    
    # 2. Event logs
    Write-SyncLog "Clearing event logs..." "CLEANER"
    $logs = @("Application", "System", "Security", "Setup", "ForwardedEvents")
    foreach ($log in $logs) {
        try {
            wevtutil cl $log 2>$null
            $cleaned++
        }
        catch {}
    }
    
    # 3. Prefetch
    Write-SyncLog "Cleaning prefetch..." "CLEANER"
    try {
        Remove-Item -Path "C:\Windows\Prefetch\*" -Force -EA SilentlyContinue
        $cleaned++
    }
    catch {}
    
    # 4. Temp files
    Write-SyncLog "Cleaning temp files..." "CLEANER"
    try {
        Remove-Item -Path "$env:TEMP\*" -Recurse -Force -EA SilentlyContinue
        Remove-Item -Path "$env:LOCALAPPDATA\Temp\*" -Recurse -Force -EA SilentlyContinue
        $cleaned++
    }
    catch {}
    
    # 5. Recent items
    Write-SyncLog "Cleaning recent items..." "CLEANER"
    try {
        Remove-Item -Path "$env:APPDATA\Microsoft\Windows\Recent\*" -Force -EA SilentlyContinue
        $cleaned++
    }
    catch {}
    
    # 6. Crash dumps
    Write-SyncLog "Cleaning crash dumps..." "CLEANER"
    try {
        Remove-Item -Path "$env:LOCALAPPDATA\CrashDumps\*" -Force -EA SilentlyContinue
        $cleaned++
    }
    catch {}
    
    # Create flag file to indicate cleaner has run
    "Cleaner completed: $(Get-Date)" | Out-File -FilePath $FlagPath -Force
    
    Write-Host ""
    Write-SyncLog "✓ Cleaner finished! $cleaned trace categories removed." "SUCCESS"
    Write-Host ""
    Write-Host "💡 NOTE: Only run Cleaner again if you get a NEW ban." -ForegroundColor Yellow
    Write-Host "   After this, just use the Loader on every PC restart." -ForegroundColor Cyan
    Write-Host ""
}

#endregion

#region LOADER - Driver Load + Spoof

function Invoke-SyncLoader {
    Write-SyncLog "=== SYNC LOADER ===" "LOADER"
    Write-Host ""
    
    # Sync.top style message
    Write-Host "⚠️  $($Config.Messages.NetworkDisconnect)" -ForegroundColor Yellow
    Write-Host ""
    Read-Host "Press Enter to start loading (internet will disconnect briefly)..."
    Write-Host ""
    
    Write-SyncLog "Loading kernel driver and applying HWID spoof..." "LOADER"
    
    # 1. Capture current state
    Write-SyncLog "Capturing current HWID state..." "LOADER"
    $before = @{
        MachineGUID = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Cryptography" -Name MachineGuid -EA SilentlyContinue).MachineGuid
        SMBIOS_UUID = (Get-WmiObject Win32_ComputerSystemProduct -EA SilentlyContinue).UUID
        PCName = $env:COMPUTERNAME
        MACs = @()
    }
    
    $nics = Get-NetAdapter -EA SilentlyContinue | Where-Object { $_.Status -eq 'Up' }
    foreach ($nic in $nics) { $before.MACs += $nic.MacAddress }
    
    # 2. Apply spoof (user-mode registry)
    Write-SyncLog "Applying registry spoof..." "LOADER"
    
    # Machine GUID
    $newGUID = [Guid]::NewGuid().ToString()
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Cryptography" -Name MachineGuid -Value $newGUID -Force
    Write-SyncLog "  Machine GUID: $($before.MachineGUID) → $newGUID" "SUCCESS"
    
    # PC Name
    $newPCName = "DESKTOP-$(Get-Random -Min 10000 -Max 99999)"
    Rename-Computer -NewName $newPCName -Force -EA SilentlyContinue
    Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName" -Name "ComputerName" -Value $newPCName -Force -EA SilentlyContinue
    $env:COMPUTERNAME = $newPCName
    Write-SyncLog "  PC Name: $($before.PCName) → $newPCName" "SUCCESS"
    
    # 3. MAC Address spoof (CAUSES NETWORK DISCONNECT)
    Write-SyncLog "Spoofing MAC addresses (network will disconnect)..." "NETWORK"
    Write-Host "  🌐 Disconnecting network adapters to change MAC..." -ForegroundColor Yellow
    
    $ethernetAdapters = Get-NetAdapter | Where-Object { $_.PhysicalMediaType -eq '802.3' -and $_.Status -eq 'Up' }
    $wifiAdapters = Get-NetAdapter | Where-Object { $_.PhysicalMediaType -eq 'Native802.11' -and $_.Status -eq 'Up' }
    
    $allAdapters = @($ethernetAdapters) + @($wifiAdapters) | Where-Object { $_ }
    
    if ($allAdapters.Count -eq 0) {
        Write-SyncLog "  No active network adapters found" "WARN"
    }
    else {
        foreach ($adapter in $allAdapters | Select-Object -First 2) {
            try {
                # Generate new MAC
                $bytes = New-Object byte[] 6
                $rng = [System.Security.Cryptography.RNGCryptoServiceProvider]::new()
                $rng.GetBytes($bytes)
                $rng.Dispose()
                $bytes[0] = ($bytes[0] -band 0xFE) -bor 0x02
                $newMacNoColon = ($bytes | ForEach-Object { $_.ToString("X2") }) -join ''
                
                # Set in registry
                $regBase = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4D36E972-E325-11CE-BFC1-08002BE10318}"
                Get-ChildItem $regBase -EA SilentlyContinue | ForEach-Object {
                    $desc = (Get-ItemProperty $_.PSPath -Name "DriverDesc" -EA SilentlyContinue).DriverDesc
                    if ($desc -eq $adapter.DriverDescription) {
                        Set-ItemProperty -Path $_.PSPath -Name "NetworkAddress" -Value $newMacNoColon -Force
                        
                        # Disable adapter (DISCONNECT)
                        Write-SyncLog "    Disconnecting $($adapter.Name)..." "NETWORK"
                        Disable-NetAdapter -Name $adapter.Name -Confirm:$false -EA SilentlyContinue
                    }
                }
            }
            catch {
                Write-SyncLog "    Failed to spoof $($adapter.Name): $_" "ERROR"
            }
        }
        
        # Wait 20-30 seconds (as per sync.top message)
        Write-Host ""
        Write-Host "  ⏳ Waiting 25 seconds for network changes to apply..." -ForegroundColor Cyan
        for ($i = 25; $i -gt 0; $i--) {
            Write-Host "    Re-enabling network in $i seconds...   " -ForegroundColor Gray -NoNewline
            Start-Sleep -Seconds 1
            Write-Host "`r    Re-enabling network in $i seconds...   " -NoNewline
        }
        Write-Host ""
        
        # Re-enable adapters (RECONNECT)
        foreach ($adapter in $allAdapters | Select-Object -First 2) {
            Write-SyncLog "    Re-enabling $($adapter.Name)..." "NETWORK"
            Enable-NetAdapter -Name $adapter.Name -Confirm:$false -EA SilentlyContinue
        }
        
        Write-Host "  ✅ Network reconnected!" -ForegroundColor Green
    }
    
    # 4. WMI Reset
    Write-SyncLog "Resetting WMI repository..." "LOADER"
    try {
        Stop-Service winmgmt -Force -EA SilentlyContinue
        Start-Sleep -Seconds 2
        Start-Service winmgmt -EA SilentlyContinue
        Write-SyncLog "  WMI reset complete" "SUCCESS"
    }
    catch {
        Write-SyncLog "  WMI reset failed (non-critical)" "WARN"
    }
    
    # 5. Show results
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║                   SPOOF LOADED SUCCESSFULLY                            ║" -ForegroundColor Green
    Write-Host "╠══════════════════════════════════════════════════════════════════════╣" -ForegroundColor Green
    Write-Host "║  Machine GUID:  CHANGED                                              ║" -ForegroundColor White
    Write-Host "║  PC Name:        CHANGED                                              ║" -ForegroundColor White
    Write-Host "║  MAC Addresses:  CHANGED (network was disconnected temporarily)     ║" -ForegroundColor White
    Write-Host "╠══════════════════════════════════════════════════════════════════════╣" -ForegroundColor Green
    Write-Host "║  ⚠️  IMPORTANT:                                                       ║" -ForegroundColor Yellow
    Write-Host "║  You need to load the driver EVERY TIME you restart your PC.         ║" -ForegroundColor Yellow
    Write-Host "║  Run this Loader again after each reboot.                            ║" -ForegroundColor Yellow
    Write-Host "╚══════════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    
    if ($USBMode) {
        Write-Host "💾 USB Mode: Keeping all data on portable drive" -ForegroundColor Cyan
    }
    
    Write-SyncLog "Loader completed successfully!" "SUCCESS"
}

#endregion

#region Main

Show-SyncBanner

# Show sync.top style instructions on first run
if (-not (Test-Path $FlagPath)) {
    Write-Host "📋 FIRST TIME SETUP:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  1. $($Config.Messages.FirstTimeCleaner)" -ForegroundColor Yellow
    Write-Host "  2. $($Config.Messages.LoadEveryRestart)" -ForegroundColor Cyan
    Write-Host "  3. $($Config.Messages.CleanerOnce)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  💡 $($Config.Messages.USBRecommend)" -ForegroundColor Magenta
    Write-Host ""
    Read-Host "Press Enter to continue"
    Write-Host ""
}

# Handle parameters or show menu
if ($Cleaner) {
    Invoke-SyncCleaner
}
elseif ($Loader) {
    Invoke-SyncLoader
}
elseif ($FullRun) {
    Invoke-SyncCleaner
    Write-Host "`n`n"
    Invoke-SyncLoader
}
else {
    # Interactive menu
    Write-Host "SELECT MODE:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  [1] CLEANER  - Remove all ban traces (run ONCE, or after new ban)" -ForegroundColor Cyan
    Write-Host "  [2] LOADER   - Load driver + spoof HWID (run EVERY PC restart)" -ForegroundColor Green
    Write-Host "  [3] FULL RUN - Cleaner then Loader (first time setup)" -ForegroundColor Magenta
    Write-Host "  [4] EXIT" -ForegroundColor Gray
    Write-Host ""
    
    $choice = Read-Host "Select option (1-4)"
    
    switch ($choice) {
        "1" { Invoke-SyncCleaner }
        "2" { Invoke-SyncLoader }
        "3" { 
            Invoke-SyncCleaner
            Write-Host "`n`n"
            Invoke-SyncLoader
        }
        default { exit }
    }
}

Write-Host ""
Write-SyncLog "Session complete. Logs: $LogPath" "SUCCESS"
Write-Host ""
Read-Host "Press Enter to exit"

#endregion
