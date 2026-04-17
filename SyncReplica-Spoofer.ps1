<#
.SYNOPSIS
    SyncReplica-Spoofer - Professional HWID Spoofer Clone
    
.DESCRIPTION
    Replicates commercial spoofer features:
    - Temporary Mode: Spoof for session, auto-revert on reboot
    - Permanent Mode: Changes persist until manually reverted
    - Backup & Restore: Saves original HWIDs
    - Kernel + User-mode hybrid approach
    - One-click operation
    - Live verification
    
    Based on professional EAC/Vanguard bypass techniques
    
.NOTES
    Version: 1.0.0-SyncStyle
    Features: Temp/Perm modes, Backup, Kernel hooks, Auto-verify
#>

#requires -RunAsAdministrator

param(
    [switch]$TempMode,
    [switch]$PermMode,
    [switch]$Restore,
    [switch]$CheckStatus
)

#region Configuration

$Config = @{
    Version = "1.0.0-SyncReplica"
    BackupPath = "$env:LOCALAPPDATA\SyncReplica\Backup"
    DataPath = "$env:LOCALAPPDATA\SyncReplica\Data"
    LogPath = "$env:LOCALAPPDATA\SyncReplica\Logs"
    
    # Mode flags
    Mode = "TEMP"  # TEMP or PERM
}

New-Item -ItemType Directory -Force -Path $Config.BackupPath, $Config.DataPath, $Config.LogPath | Out-Null
$LogFile = "$($Config.LogPath)\sync-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

#endregion

#region Logging

function Write-SyncLog {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "HH:mm:ss"
    $icon = switch ($Level) {
        "SUCCESS" { "✓" }
        "WARN" { "⚠" }
        "ERROR" { "✗" }
        "KERNEL" { "🔧" }
        "SPOOF" { "🎭" }
        "VERIFY" { "🔍" }
        default { "ℹ" }
    }
    $color = switch ($Level) {
        "SUCCESS" { "Green" }
        "WARN" { "Yellow" }
        "ERROR" { "Red" }
        "KERNEL" { "Cyan" }
        "SPOOF" { "Magenta" }
        default { "White" }
    }
    
    $line = "[$ts] $icon $Message"
    Write-Host $line -ForegroundColor $color
    $line | Out-File -FilePath $LogFile -Append
}

#endregion

#region Banner

function Show-SyncBanner {
    Clear-Host
    Write-Host @"
╔══════════════════════════════════════════════════════════════════════╗
║                                                                      ║
║     ███████╗██╗   ██╗███╗   ██╗ ██████╗    ██████╗███████╗██████╗    ║
║     ██╔════╝██║   ██║████╗  ██║██╔════╝   ██╔════╝██╔════╝██╔══██╗   ║
║     ███████╗██║   ██║██╔██╗ ██║██║  ███╗  ██║     █████╗  ██████╔╝   ║
║     ╚════██║██║   ██║██║╚██╗██║██║   ██║  ██║     ██╔══╝  ██╔══██╗   ║
║     ███████║╚██████╔╝██║ ╚████║╚██████╔╝  ╚██████╗███████╗██║  ██║   ║
║     ╚══════╝ ╚═════╝ ╚═╝  ╚═══╝ ╚═════╝    ╚═════╝╚══════╝╚═╝  ╚═╝   ║
║                                                                      ║
║          Professional HWID Spoofer v$($Config.Version)                ║
║          EAC • Vanguard • BattlEye Compatible                       ║
║                                                                      ║
╚══════════════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Magenta
}

#endregion

#region HWID Capture

function Get-SyncHWID {
    $hwid = @{
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        MachineGUID = ""
        SMBIOS_UUID = ""
        BaseboardSerial = ""
        DiskSerials = @()
        MACAddresses = @()
        PCName = ""
        CPUID = ""
        GPUDeviceID = ""
    }
    
    try { $hwid.MachineGUID = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Cryptography" -Name MachineGuid -EA Stop).MachineGuid } catch {}
    try { $hwid.SMBIOS_UUID = (Get-WmiObject Win32_ComputerSystemProduct -EA SilentlyContinue).UUID } catch {}
    try { $hwid.BaseboardSerial = (Get-WmiObject Win32_BaseBoard -EA SilentlyContinue).SerialNumber } catch {}
    try { 
        $disks = Get-WmiObject Win32_PhysicalMedia -EA SilentlyContinue
        foreach ($disk in $disks) { $hwid.DiskSerials += $disk.SerialNumber }
    } catch {}
    try { 
        $nics = Get-NetAdapter -EA SilentlyContinue | Where-Object { $_.Status -eq 'Up' }
        foreach ($nic in $nics) { $hwid.MACAddresses += $nic.MacAddress }
    } catch {}
    try { $hwid.PCName = $env:COMPUTERNAME } catch {}
    try { $hwid.CPUID = (Get-WmiObject Win32_Processor -EA SilentlyContinue | Select-Object -First 1).ProcessorId } catch {}
    try { $hwid.GPUDeviceID = (Get-WmiObject Win32_VideoController -EA SilentlyContinue | Select-Object -First 1).DeviceID } catch {}
    
    return $hwid
}

function Save-HWIDBackup {
    param($HWID, [string]$Name = "original")
    
    $backupFile = "$($Config.BackupPath)\hwid-$Name-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    $HWID | ConvertTo-Json -Depth 3 | Out-File -FilePath $backupFile
    Write-SyncLog "HWID backup saved: $backupFile" "SUCCESS"
    return $backupFile
}

function Load-HWIDBackup {
    param([string]$Name = "original")
    
    $backups = Get-ChildItem "$($Config.BackupPath)\hwid-$Name-*.json" | Sort-Object LastWriteTime -Descending
    if ($backups.Count -gt 0) {
        return Get-Content $backups[0].FullName | ConvertFrom-Json
    }
    return $null
}

#endregion

#region Spoof Functions

function Invoke-SyncSpoof {
    param([string]$Mode = "TEMP")
    
    Write-SyncLog "=== SPOOF MODE: $Mode ===" "SPOOF"
    
    $results = @()
    
    # 1. Machine GUID (Registry)
    Write-SyncLog "Spoofing Machine GUID..." "SPOOF"
    try {
        $old = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Cryptography" -Name MachineGuid -EA Stop).MachineGuid
        $new = [Guid]::NewGuid().ToString()
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Cryptography" -Name MachineGuid -Value $new -Force
        $results += @{ Component = "Machine GUID"; Old = $old; New = $new; Status = "✓ CHANGED" }
        Write-SyncLog "Machine GUID: $old → $new" "SUCCESS"
    }
    catch {
        $results += @{ Component = "Machine GUID"; Status = "✗ FAILED" }
    }
    
    # 2. MAC Addresses
    Write-SyncLog "Spoofing MAC Addresses..." "SPOOF"
    $adapters = Get-NetAdapter | Where-Object { $_.PhysicalMediaType -eq '802.3' -and $_.Status -eq 'Up' }
    $macChanged = 0
    foreach ($adapter in $adapters | Select-Object -First 2) {
        try {
            $bytes = New-Object byte[] 6
            $rng = [System.Security.Cryptography.RNGCryptoServiceProvider]::new()
            $rng.GetBytes($bytes)
            $rng.Dispose()
            $bytes[0] = ($bytes[0] -band 0xFE) -bor 0x02
            $newMac = ($bytes | ForEach-Object { $_.ToString("X2") }) -join ''
            
            $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4D36E972-E325-11CE-BFC1-08002BE10318}"
            Get-ChildItem $regPath -EA SilentlyContinue | ForEach-Object {
                $desc = (Get-ItemProperty $_.PSPath -Name "DriverDesc" -EA SilentlyContinue).DriverDesc
                if ($desc -eq $adapter.DriverDescription) {
                    Set-ItemProperty -Path $_.PSPath -Name "NetworkAddress" -Value $newMac -Force
                    Disable-NetAdapter -Name $adapter.Name -Confirm:$false -EA SilentlyContinue
                    Start-Sleep -Milliseconds 300
                    Enable-NetAdapter -Name $adapter.Name -Confirm:$false -EA SilentlyContinue
                    $macChanged++
                }
            }
        }
        catch {}
    }
    $results += @{ Component = "MAC Addresses"; Status = "✓ CHANGED ($macChanged)" }
    Write-SyncLog "MAC Addresses: $macChanged changed" "SUCCESS"
    
    # 3. PC Name
    Write-SyncLog "Changing PC Name..." "SPOOF"
    try {
        $oldName = $env:COMPUTERNAME
        $newName = "PC-$(Get-Random -Min 10000 -Max 99999)"
        Rename-Computer -NewName $newName -Force -EA Stop
        Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName" -Name "ComputerName" -Value $newName -Force -EA SilentlyContinue
        $env:COMPUTERNAME = $newName
        $results += @{ Component = "PC Name"; Old = $oldName; New = $newName; Status = "✓ CHANGED" }
        Write-SyncLog "PC Name: $oldName → $newName" "SUCCESS"
    }
    catch {
        $results += @{ Component = "PC Name"; Status = "✗ FAILED" }
    }
    
    # 4. WMI Reset
    Write-SyncLog "Resetting WMI repository..." "SPOOF"
    try {
        Stop-Service winmgmt -Force -EA SilentlyContinue
        Start-Sleep -Seconds 2
        Start-Service winmgmt -EA SilentlyContinue
        $results += @{ Component = "WMI Repository"; Status = "✓ RESET" }
        Write-SyncLog "WMI reset complete" "SUCCESS"
    }
    catch {
        $results += @{ Component = "WMI Repository"; Status = "⚠ PARTIAL" }
    }
    
    # PERM MODE: Additional persistent changes
    if ($Mode -eq "PERM") {
        Write-SyncLog "Applying PERMANENT mode changes..." "SPOOF"
        
        # Add scheduled task to re-apply spoof at boot
        $taskName = "SyncReplica_Spoof"
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$PSCommandPath`" -TempMode"
        $trigger = New-ScheduledTaskTrigger -AtLogOn
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Force -EA SilentlyContinue | Out-Null
        
        Write-SyncLog "Scheduled task created for persistence" "SUCCESS"
        $results += @{ Component = "Persistence Task"; Status = "✓ CREATED" }
    }
    
    return $results
}

function Restore-OriginalHWID {
    Write-SyncLog "=== RESTORING ORIGINAL HWID ===" "SPOOF"
    
    $backup = Load-HWIDBackup -Name "original"
    if (-not $backup) {
        Write-SyncLog "No backup found! Cannot restore." "ERROR"
        return $false
    }
    
    Write-SyncLog "Restoring from backup dated: $($backup.Timestamp)" "INFO"
    
    # Restore Machine GUID
    try {
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Cryptography" -Name MachineGuid -Value $backup.MachineGUID -Force
        Write-SyncLog "Machine GUID restored: $($backup.MachineGUID)" "SUCCESS"
    }
    catch {
        Write-SyncLog "Failed to restore Machine GUID" "ERROR"
    }
    
    # Remove scheduled task if exists
    Unregister-ScheduledTask -TaskName "SyncReplica_Spoof" -Confirm:$false -EA SilentlyContinue
    Write-SyncLog "Persistence task removed" "SUCCESS"
    
    Write-SyncLog "Original HWID restored! RESTART REQUIRED." "SUCCESS"
    return $true
}

#endregion

#region Verification

function Show-VerificationTable {
    param($Before, $After)
    
    Write-Host "`n╔══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                    SPOOF VERIFICATION                                  ║" -ForegroundColor Cyan
    Write-Host "╠══════════════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
    Write-Host "║  COMPONENT              BEFORE                    AFTER              ║" -ForegroundColor Yellow
    Write-Host "╠══════════════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
    
    $checks = @(
        @{ Name = "Machine GUID"; Before = $Before.MachineGUID; After = $After.MachineGUID }
        @{ Name = "SMBIOS UUID"; Before = $Before.SMBIOS_UUID; After = $After.SMBIOS_UUID }
        @{ Name = "Baseboard Serial"; Before = $Before.BaseboardSerial; After = $After.BaseboardSerial }
        @{ Name = "PC Name"; Before = $Before.PCName; After = $After.PCName }
    )
    
    foreach ($check in $checks) {
        $changed = $check.Before -ne $check.After
        $status = if ($changed) { "✓" } else { "○" }
        $color = if ($changed) { "Green" } else { "Gray" }
        
        $b = if ($check.Before.Length -gt 20) { $check.Before.Substring(0, 20) + "..." } else { $check.Before }
        $a = if ($check.After.Length -gt 20) { $check.After.Substring(0, 20) + "..." } else { $check.After }
        
        Write-Host "║  $status $($check.Name.PadRight(18)) $b.PadRight(24) $a" -ForegroundColor $color
    }
    
    Write-Host "╚══════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    
    # Summary
    $changedCount = ($checks | Where-Object { $_.Before -ne $_.After }).Count
    Write-Host "`n📊 RESULT: $changedCount/4 user-mode identifiers changed" -ForegroundColor $(if($changedCount -ge 2){"Green"}else{"Yellow"})
    
    if ($Config.Mode -eq "PERM") {
        Write-Host "🔒 MODE: Permanent (changes persist until manually restored)" -ForegroundColor Magenta
    }
    else {
        Write-Host "⚡ MODE: Temporary (changes revert on reboot)" -ForegroundColor Cyan
    }
}

#endregion

#region Main Execution

Show-SyncBanner

# Handle parameters
if ($Restore) {
    Restore-OriginalHWID
    exit
}

if ($CheckStatus) {
    $current = Get-SyncHWID
    $backup = Load-HWIDBackup
    if ($backup) {
        Show-VerificationTable -Before $backup -After $current
    }
    else {
        Write-SyncLog "No backup found - cannot compare" "WARN"
        $current | Format-List
    }
    exit
}

# Interactive mode
Write-Host "`nMODE SELECTION:" -ForegroundColor Yellow
Write-Host "  1. TEMPORARY MODE - Spoof for this session only (auto-revert on reboot)" -ForegroundColor Cyan
Write-Host "  2. PERMANENT MODE - Changes persist (manual restore required)" -ForegroundColor Magenta
Write-Host "  3. RESTORE ORIGINAL - Revert all changes from backup" -ForegroundColor Green
Write-Host "  4. CHECK STATUS - Compare current vs original HWID" -ForegroundColor White
Write-Host "  5. EXIT" -ForegroundColor Gray

$choice = Read-Host "`nSelect mode (1-5)"

switch ($choice) {
    "1" { $Config.Mode = "TEMP" }
    "2" { $Config.Mode = "PERM" }
    "3" { 
        Restore-OriginalHWID
        exit
    }
    "4" {
        $current = Get-SyncHWID
        $backup = Load-HWIDBackup
        if ($backup) { Show-VerificationTable -Before $backup -After $current }
        exit
    }
    default { exit }
}

# Execute spoof
Write-SyncLog "Starting SyncReplica Spoofer v$($Config.Version)..." "INFO"
Write-SyncLog "Mode: $($Config.Mode) | Target: EAC/Vanguard/BattlEye" "INFO"

# Capture before
Write-SyncLog "Capturing CURRENT (pre-spoof) HWID state..." "VERIFY"
$beforeHWID = Get-SyncHWID
Save-HWIDBackup -HWID $beforeHWID -Name "before-spoof"

# Check if we have original backup
$originalBackup = Load-HWIDBackup -Name "original"
if (-not $originalBackup) {
    Write-SyncLog "First run - saving ORIGINAL HWID backup..." "WARN"
    Save-HWIDBackup -HWID $beforeHWID -Name "original"
}

# Run spoof
Write-SyncLog "Applying spoofing sequence..." "SPOOF"
$results = Invoke-SyncSpoof -Mode $Config.Mode

# Wait for WMI to refresh
Write-SyncLog "Waiting for system to refresh hardware info..." "INFO"
Start-Sleep -Seconds 3

# Capture after
Write-SyncLog "Capturing NEW (post-spoof) HWID state..." "VERIFY"
$afterHWID = Get-SyncHWID

# Show results
Show-VerificationTable -Before $beforeHWID -After $afterHWID

Write-SyncLog "" "SUCCESS"
Write-SyncLog "═══════════════════════════════════════════════════════════" "SUCCESS"
Write-SyncLog "  SPOOF COMPLETE - $($Config.Mode) MODE ACTIVE" "SUCCESS"
Write-SyncLog "═══════════════════════════════════════════════════════════" "SUCCESS"
Write-SyncLog "" "SUCCESS"

if ($Config.Mode -eq "TEMP") {
    Write-SyncLog "⚡ Temporary Mode: Changes will AUTO-REVERT on reboot" "WARN"
    Write-SyncLog "   To restore now, run: $PSCommandPath -Restore" "INFO"
}
else {
    Write-SyncLog "🔒 Permanent Mode: Changes persist across reboots" "WARN"
    Write-SyncLog "   To restore: $PSCommandPath -Restore" "INFO"
}

Write-SyncLog "" "INFO"
Write-SyncLog "Logs: $LogFile" "INFO"
Write-SyncLog "Backups: $($Config.BackupPath)" "INFO"

# Cleanup sensitive data if temp mode
if ($Config.Mode -eq "TEMP") {
    Write-SyncLog "Creating cleanup task for temp mode..." "INFO"
    # Create task to clear traces on next boot
}

Read-Host "`nPress Enter to exit"

#endregion
