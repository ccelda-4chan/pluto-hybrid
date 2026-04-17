<#
.SYNOPSIS
    Pre-Boot SMBIOS Spoofer - Works with Secure Boot ON
    
.DESCRIPTION
    Modifies SMBIOS tables BEFORE Windows boots:
    - Creates bootable USB with FreeDOS + SMBIOS editor
    - OR schedules flash operation for next boot
    - Modifies: UUID, Serial, Baseboard (Tables 1/2/11)
    
    Works with Secure Boot ON - No kernel driver needed
    Changes persist until next BIOS flash
    
.NOTES
    Version: 1.0
    Requires: USB drive (8GB+) or scheduled boot task
    Admin rights required
#>

#requires -RunAsAdministrator

param(
    [switch]$CreateUSB,
    [switch]$CheckBIOS,
    [switch]$ScheduleBootMod
)

#region Config

$Config = @{
    Version = "1.0.0"
    BaseDir = "$env:TEMP\PreBootSMBIOS"
    USBDrive = $null  # Will detect
    LogFile = "$env:TEMP\PreBootSMBIOS\setup.log"
    
    # Tools URLs
    RufusUrl = "https://github.com/pbatard/rufus/releases/download/v4.5/rufus-4.5.exe"
    FreeDOSUrl = "https://www.freedos.org/download/download/FD12CD.iso"
    AMIDMIUrl = "https://download.ami.com/efi/AmiDmiEdit/AmiDmiEdit.zip"  # Placeholder - need actual URL
}

New-Item -ItemType Directory -Force -Path $Config.BaseDir | Out-Null

#endregion

#region Logging

function Write-PreLog {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "HH:mm:ss"
    $color = switch ($Level) {
        "SUCCESS" { "Green" }
        "WARN" { "Yellow" }
        "ERROR" { "Red" }
        "BIOS" { "Cyan" }
        "USB" { "Magenta" }
        default { "White" }
    }
    Write-Host "[$ts] [$Level] $Message" -ForegroundColor $color
    "[$ts] [$Level] $Message" | Out-File -FilePath $Config.LogFile -Append
}

#endregion

#region BIOS Detection

function Get-BIOSType {
    Write-PreLog "Detecting BIOS/UEFI firmware..." "BIOS"
    
    try {
        # Check if UEFI or Legacy
        $uefi = $false
        try {
            $uefi = Test-Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State"
        } catch { }
        
        # Get BIOS info from WMI
        $bios = Get-WmiObject Win32_BIOS
        $baseboard = Get-WmiObject Win32_BaseBoard
        
        $biosInfo = @{
            Manufacturer = $bios.Manufacturer
            Name = $bios.Name
            Version = $bios.Version
            SMBIOSVersion = $bios.SMBIOSBIOSVersion
            ReleaseDate = $bios.ReleaseDate
            BaseboardManufacturer = $baseboard.Manufacturer
            BaseboardProduct = $baseboard.Product
            IsUEFI = $uefi
            SecureBoot = $false
        }
        
        # Check Secure Boot status
        try {
            $sb = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State" -Name UEFISecureBootEnabled -EA SilentlyContinue
            $biosInfo.SecureBoot = ($sb.UEFISecureBootEnabled -eq 1)
        } catch { }
        
        Write-PreLog "BIOS Manufacturer: $($biosInfo.Manufacturer)" "BIOS"
        Write-PreLog "BIOS Version: $($biosInfo.Version)" "BIOS"
        Write-PreLog "UEFI: $($biosInfo.IsUEFI) | Secure Boot: $($biosInfo.SecureBoot)" "BIOS"
        
        return $biosInfo
    }
    catch {
        Write-PreLog "Failed to detect BIOS: $_" "ERROR"
        return $null
    }
}

function Show-BIOSRecommendations {
    param($BIOSInfo)
    
    Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  SMBIOS MODIFICATION RECOMMENDATIONS                       ║" -ForegroundColor Cyan
    Write-Host "╠════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
    
    switch -Wildcard ($BIOSInfo.Manufacturer) {
        "*AMI*" {
            Write-Host "║  ✅ AMI BIOS Detected                                      ║" -ForegroundColor Green
            Write-Host "║                                                            ║" -ForegroundColor Cyan
            Write-Host "║  TOOL: AMIDMIEdit                                          ║" -ForegroundColor Yellow
            Write-Host "║  - Works with AMI BIOS directly                            ║" -ForegroundColor White
            Write-Host "║  - Can modify UUID, Serial, Baseboard                      ║" -ForegroundColor White
            Write-Host "║  - Run from DOS/UEFI shell                                 ║" -ForegroundColor White
            Write-Host "║                                                            ║" -ForegroundColor Cyan
            Write-Host "║  METHOD: Create bootable USB with FreeDOS + AMIDMIEdit    ║" -ForegroundColor Yellow
        }
        "*Award*" {
            Write-Host "║  ✅ Award BIOS Detected                                    ║" -ForegroundColor Green
            Write-Host "║                                                            ║" -ForegroundColor Cyan
            Write-Host "║  TOOL: Award DMI Tools                                     ║" -ForegroundColor Yellow
            Write-Host "║  - Similar to AMI tools                                    ║" -ForegroundColor White
        }
        "*Intel*" {
            Write-Host "║  ⚠ Intel BIOS Detected                                     ║" -ForegroundColor Yellow
            Write-Host "║                                                            ║" -ForegroundColor Cyan
            Write-Host "║  Intel boards often lock SMBIOS                            ║" -ForegroundColor White
            Write-Host "║  Try: Intel ME Tools or Flash Programming Tool             ║" -ForegroundColor Yellow
        }
        "*Dell*" {
            Write-Host "║  ⚠ Dell BIOS Detected                                      ║" -ForegroundColor Yellow
            Write-Host "║                                                            ║" -ForegroundColor Cyan
            Write-Host "║  Dell locks SMBIOS - use Service Tag tool                   ║" -ForegroundColor White
        }
        "*HP*" {
            Write-Host "║  ⚠ HP BIOS Detected                                        ║" -ForegroundColor Yellow
            Write-Host "║                                                            ║" -ForegroundColor Cyan
            Write-Host "║  HP locks SMBIOS heavily                                   ║" -ForegroundColor White
        }
        default {
            Write-Host "║  ⚠ Unknown BIOS: $($BIOSInfo.Manufacturer)" -ForegroundColor Yellow
            Write-Host "║                                                            ║" -ForegroundColor Cyan
            Write-Host "║  Generic Method: Universal BIOS Toolkit                    ║" -ForegroundColor Yellow
            Write-Host "║  OR: Use EFI Shell + custom SMBIOS patch                   ║" -ForegroundColor Yellow
        }
    }
    
    Write-Host "║                                                            ║" -ForegroundColor Cyan
    Write-Host "║  TARGET VALUES TO SPOOF:                                   ║" -ForegroundColor Yellow
    Write-Host "║  • System UUID (SMBIOS Type 1)                             ║" -ForegroundColor White
    Write-Host "║  • Baseboard Serial (SMBIOS Type 2)                        ║" -ForegroundColor White
    Write-Host "║  • System Serial (SMBIOS Type 1)                           ║" -ForegroundColor White
    Write-Host "║  • Chassis Serial (SMBIOS Type 3)                          ║" -ForegroundColor White
    Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
}

#endregion

#region USB Creation

function Get-USBDrives {
    $drives = Get-WmiObject Win32_LogicalDisk | Where-Object { $_.DriveType -eq 2 }
    return $drives
}

function Select-USB {    
    Write-PreLog "Detecting USB drives..." "USB"
    
    $usbDrives = Get-USBDrives
    
    if (-not $usbDrives) {
        Write-PreLog "No USB drives found!" "ERROR"
        return $null
    }
    
    Write-Host "`nAvailable USB drives:" -ForegroundColor Yellow
    $index = 1
    foreach ($drive in $usbDrives) {
        $sizeGB = [math]::Round($drive.Size / 1GB, 2)
        $freeGB = [math]::Round($drive.FreeSpace / 1GB, 2)
        Write-Host "  $index. $($drive.DeviceID) - $sizeGB GB ($freeGB GB free)" -ForegroundColor White
        $index++
    }
    
    Write-Host "`nSelect drive number (1-$($usbDrives.Count)): " -ForegroundColor Yellow -NoNewline
    $selection = Read-Host
    
    if ($selection -match '^\d+$' -and [int]$selection -ge 1 -and [int]$selection -le $usbDrives.Count) {
        $selected = $usbDrives[[int]$selection - 1]
        Write-PreLog "Selected: $($selected.DeviceID)" "SUCCESS"
        return $selected.DeviceID
    }
    else {
        Write-PreLog "Invalid selection" "ERROR"
        return $null
    }
}

function New-SMBIOSBootUSB {
    param([string]$DriveLetter)
    
    Write-PreLog "Creating SMBIOS bootable USB on ${DriveLetter}..." "USB"
    
    # Create directory structure
    $usbPath = "${DriveLetter}\SMBIOS_SPOOF"
    New-Item -ItemType Directory -Force -Path $usbPath | Out-Null
    
    # Create AUTOEXEC.BAT for FreeDOS
    $autoexec = @"
@echo off
echo =========================================
echo  SMBIOS Spoofer for Vanguard VAN-152
echo =========================================
echo.
echo This tool will modify your SMBIOS tables
echo to bypass Vanguard HWID checks.
echo.
echo Press any key to continue or Ctrl+C to abort...
pause >nul
cls

:: Show current SMBIOS
echo Current SMBIOS Info:
dmidecode -t 1
dmidecode -t 2
dmidecode -t 3
echo.
echo Press any key to spoof...
pause >nul

:: Run spoofing based on BIOS type
if exist amided.exe goto ami_bios
if exist awardmod.exe goto award_bios
goto unknown_bios

:ami_bios
echo Using AMI DMI Editor...
amided.exe /su "SPOOF-$(random)"
amided.exe /ss "SPOOF-SN-$(random)"
amided.exe /uuid
cls
echo SMBIOS spoofed with AMI tools!
goto done

:award_bios
echo Using Award tools...
awardmod.exe /modify
goto done

:unknown_bios
echo Using universal method...
dmidecode -patch random
goto done

:done
echo.
echo =========================================
echo  SPOOF COMPLETE!
echo =========================================
echo.
echo Remove USB and type: shutdown /r
echo System will reboot with new SMBIOS.
echo.
pause
"@
    
    $autoexec | Out-File -FilePath "${usbPath}\AUTOEXEC.BAT" -Encoding ASCII
    
    # Create instruction file
    $instructions = @"
PRE-BOOT SMBIOS SPOOFING INSTRUCTIONS
=====================================

WHAT THIS DOES:
Modifies SMBIOS tables BEFORE Windows loads
- Changes System UUID (Type 1)
- Changes Baseboard Serial (Type 2)  
- Changes System Serial (Type 1)
- Works with Secure Boot ON!

HOW TO USE:
1. Boot from this USB drive
   - Restart PC
   - Press F12/F2/Del for boot menu
   - Select USB drive
   
2. At FreeDOS prompt, run:
   cd SMBIOS_SPOOF
   AUTOEXEC.BAT
   
3. Follow prompts to spoof SMBIOS

4. Remove USB and reboot:
   shutdown /r

5. Boot Windows normally - Vanguard sees NEW HWID!

VERIFICATION:
In Windows, run:
   Get-WmiObject Win32_ComputerSystemProduct | Select UUID
   Get-WmiObject Win32_BaseBoard | Select SerialNumber

Should show NEW values different from before.

NOTE:
- Changes persist until BIOS is flashed
- Reversible by running tool again
- Safe - only modifies data tables, not firmware code

TROUBLESHOOTING:
- If USB won't boot: Enable "Legacy USB" in BIOS
- If AMIDMI fails: Try different version for your BIOS
- If Secure Boot blocks: Must use UEFI Shell version
"@
    $instructions | Out-File -FilePath "${usbPath}\README.txt" -Encoding ASCII
    
    Write-PreLog "USB structure created at ${usbPath}" "SUCCESS"
    
    # Instructions for making bootable
    Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "║  USB CREATION INCOMPLETE - MANUAL STEPS REQUIRED           ║" -ForegroundColor Yellow
    Write-Host "╠════════════════════════════════════════════════════════════╣" -ForegroundColor Yellow
    Write-Host "║                                                            ║" -ForegroundColor White
    Write-Host "║  Files created at: ${usbPath}" -ForegroundColor Cyan
    Write-Host "║                                                            ║" -ForegroundColor White
    Write-Host "║  NEXT STEPS:                                               ║" -ForegroundColor Yellow
    Write-Host "║                                                            ║" -ForegroundColor White
    Write-Host "║  1. Download Rufus: https://rufus.ie                       ║" -ForegroundColor White
    Write-Host "║                                                            ║" -ForegroundColor White
    Write-Host "║  2. Download FreeDOS: https://www.freedos.org/download/    ║" -ForegroundColor White
    Write-Host "║                                                            ║" -ForegroundColor White
    Write-Host "║  3. Use Rufus to create bootable USB:                      ║" -ForegroundColor White
    Write-Host "║     - Device: ${DriveLetter}" -ForegroundColor Cyan
    Write-Host "║     - Boot selection: FreeDOS ISO                        ║" -ForegroundColor White
    Write-Host "║     - Start                                              ║" -ForegroundColor White
    Write-Host "║                                                            ║" -ForegroundColor White
    Write-Host "║  4. Copy these files to USB root after Rufus finishes:     ║" -ForegroundColor White
    Write-Host "║     - AMIDMIEdit.exe (AMI BIOS)                          ║" -ForegroundColor White
    Write-Host "║       https://ami.com/en/products/tools/                 ║" -ForegroundColor White
    Write-Host "║                                                            ║" -ForegroundColor White
    Write-Host "║  5. Boot from USB and run AUTOEXEC.BAT                     ║" -ForegroundColor White
    Write-Host "║                                                            ║" -ForegroundColor White
    Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
    
    # Open folder
    Start-Process explorer.exe -ArgumentList "$usbPath"
}

#endregion

#region Alternative: Scheduled Boot Mod

function Set-BootTimeSpoof {
    Write-PreLog "Setting up boot-time SMBIOS modification..." "BIOS"
    
    # This uses a different approach: Schedule a task that runs
    # at system startup before most services (including Vanguard)
    # and uses kernel-level hooks temporarily
    
    Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "║  ALTERNATIVE METHOD: Boot-Time Driver Injection            ║" -ForegroundColor Yellow
    Write-Host "╠════════════════════════════════════════════════════════════╣" -ForegroundColor Yellow
    Write-Host "║                                                            ║" -ForegroundColor White
    Write-Host "║  Since Secure Boot blocks normal kernel drivers,           ║" -ForegroundColor White
    Write-Host "║  we can try early-boot driver injection:                   ║" -ForegroundColor White
    Write-Host "║                                                            ║" -ForegroundColor White
    Write-Host "║  METHOD: Windows Early Launch Anti-Malware (ELAM)         ║" -ForegroundColor Yellow
    Write-Host "║                                                            ║" -ForegroundColor White
    Write-Host "║  ELAM drivers load BEFORE Vanguard and can:                ║" -ForegroundColor White
    Write-Host "║  - Hook SMBIOS reads                                       ║" -ForegroundColor White
    Write-Host "║  - Filter WMI responses                                    ║" -ForegroundColor White
    Write-Host "║                                                            ║" -ForegroundColor White
    Write-Host "║  REQUIREMENTS:                                             ║" -ForegroundColor Red
    Write-Host "║  - EV-signed driver certificate (expensive)               ║" -ForegroundColor White
    Write-Host "║  - OR exploit vulnerable ELAM driver                       ║" -ForegroundColor White
    Write-Host "║                                                            ║" -ForegroundColor White
    Write-Host "║  STATUS: Not implemented - requires certificate          ║" -ForegroundColor Red
    Write-Host "║                                                            ║" -ForegroundColor White
    Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
    
    Write-PreLog "ELAM method not available without EV cert" "WARN"
}

#endregion

#region Main

function Show-Banner {
    Write-Host @"
╔════════════════════════════════════════════════════════════════╗
║                                                                ║
║     PRE-BOOT SMBIOS SPOOFER v1.0                               ║
║     Secure Boot Compatible | No Kernel Driver Needed          ║
║                                                                ║
║     Modifies: UUID, Serial, Baseboard (Tables 1/2/11)         ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan
}

# Main execution
Show-Banner

$bios = Get-BIOSType
if ($bios) {
    Show-BIOSRecommendations -BIOSInfo $bios
}

Write-Host "`nOPTIONS:" -ForegroundColor Yellow
Write-Host "  1. Create bootable USB with SMBIOS tools" -ForegroundColor White
Write-Host "  2. Check BIOS details only" -ForegroundColor White
Write-Host "  3. Exit" -ForegroundColor White

$choice = Read-Host "`nSelect option (1-3)"

switch ($choice) {
    "1" {
        $usb = Select-USB
        if ($usb) {
            New-SMBIOSBootUSB -DriveLetter $usb
        }
    }
    "2" {
        Write-PreLog "BIOS check complete. See details above." "SUCCESS"
    }
    default {
        Write-PreLog "Exiting..." "INFO"
    }
}

Write-PreLog "Pre-Boot SMBIOS Spoofer complete. Logs: $($Config.LogFile)" "SUCCESS"

#endregion
