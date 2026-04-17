<#
    Pluto Hybrid HWID Spoofer
    =========================
    
    Architecture: PowerShell (User-Mode) + Documented Kernel Techniques
    
    User-Mode Layer (This Script):
    - Registry spoofing
    - MAC address changes
    - Windows Update ID reset
    - Trace cleanup
    - Driver orchestration
    
    Kernel-Mode Layer (Documented/Integrated):
    - WMI query hooking
    - Disk serial interception
    - SMBIOS data spoofing
    - PCI device ID masking
    
    WARNING: Kernel components require driver signing or test mode.
    This implementation documents the architecture for educational purposes.
#>

#region Configuration & Setup

$PlutoConfig = @{
    Version = "2.0.0-Hybrid"
    Mode = "Hybrid"  # UserMode, KernelMode, FullHybrid
    BackupPath = "$env:LOCALAPPDATA\PlutoHybrid\Backup"
    DriverPath = "$env:LOCALAPPDATA\PlutoHybrid\Drivers"
    LogPath = "$env:LOCALAPPDATA\PlutoHybrid\logs"
    ConfigPath = "$env:LOCALAPPDATA\PlutoHybrid\config.json"
    
    # Kernel component settings
    UseWMIHook = $true
    UseDiskSpoof = $true
    UseSMBIOSSpoof = $true
    UsePCISpoof = $false  # Most complex
    
    # Driver settings
    DriverLoader = "kdmapper"  # Options: kdmapper, gdrv, manual
    RequireTestMode = $true
    RequireSecureBootOff = $true
}

# Ensure admin privileges
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Administrator privileges required for kernel-mode operations"
    exit 1
}

# Create directories
$PlutoConfig.BackupPath, $PlutoConfig.DriverPath, $PlutoConfig.LogPath | ForEach-Object {
    New-Item -ItemType Directory -Force -Path $_ | Out-Null
}

#endregion

#region Logging System

function Write-PlutoLog {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS", "KERNEL")]
        [string]$Level = "INFO",
        
        [switch]$NoConsole
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Write to file
    Add-Content -Path "$($PlutoConfig.LogPath)\pluto-$(Get-Date -Format yyyyMMdd).log" -Value $logEntry
    
    # Console output with colors
    if (-not $NoConsole) {
        switch ($Level) {
            "INFO" { Write-Host $Message -ForegroundColor Cyan }
            "WARN" { Write-Host $Message -ForegroundColor Yellow }
            "ERROR" { Write-Host $Message -ForegroundColor Red }
            "SUCCESS" { Write-Host $Message -ForegroundColor Green }
            "KERNEL" { Write-Host $Message -ForegroundColor Magenta }
        }
    }
}

#endregion

#region Kernel Mode Preparation

function Test-KernelModePrerequisites {
    Write-PlutoLog "Checking kernel-mode prerequisites..." "INFO"
    
    $results = @{
        TestMode = $false
        SecureBoot = $false
        DriverSignature = $false
        HVCI = $false
        TotalOK = 0
    }
    
    # Check Test Mode
    $bcdedit = bcdedit /enum | Select-String "testsigning"
    $results.TestMode = ($bcdedit -match "Yes")
    Write-PlutoLog "Test Mode: $(if($results.TestMode){'ENABLED ✓'}else{'DISABLED ✗'})" $(if($results.TestMode){"SUCCESS"}else{"WARN"})
    
    # Check Secure Boot (via registry)
    try {
        $sb = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State" -Name UEFISecureBootEnabled -EA SilentlyContinue).UEFISecureBootEnabled
        $results.SecureBoot = ($sb -eq 0)
        Write-PlutoLog "Secure Boot: $(if($results.SecureBoot){'OFF ✓'}else{'ON ✗'})" $(if($results.SecureBoot){"SUCCESS"}else{"WARN"})
    }
    catch {
        Write-PlutoLog "Secure Boot: Unable to detect (may be off)" "WARN"
        $results.SecureBoot = $true  # Assume OK if can't detect
    }
    
    # Check Driver Signature Enforcement (bcdedit)
    $dse = bcdedit /enum | Select-String "nointegritychecks"
    $results.DriverSignature = ($dse -match "Yes")
    Write-PlutoLog "Driver Signature Override: $(if($results.DriverSignature){'ENABLED ✓'}else{'DISABLED ✗'})" $(if($results.DriverSignature){"SUCCESS"}else{"WARN"})
    
    # Check HVCI (Hypervisor-protected Code Integrity / Memory Integrity)
    try {
        $hvci = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard" -Name EnableVirtualizationBasedSecurity -EA SilentlyContinue).EnableVirtualizationBasedSecurity
        $results.HVCI = ($hvci -eq 0 -or $null -eq $hvci)
        Write-PlutoLog "HVCI/Memory Integrity: $(if($results.HVCI){'OFF ✓'}else{'ON ✗'})" $(if($results.HVCI){"SUCCESS"}else{"WARN"})
    }
    catch {
        Write-PlutoLog "HVCI: Unable to detect" "WARN"
        $results.HVCI = $true
    }
    
    $results.TotalOK = ($results.TestMode, $results.SecureBoot, $results.DriverSignature, $results.HVCI | Where-Object { $_ }).Count
    
    Write-PlutoLog "Prerequisites passed: $($results.TotalOK)/4" $(if($results.TotalOK -ge 3){"SUCCESS"}else{"WARN"})
    
    return $results
}

function Enable-TestMode {
    Write-PlutoLog "Enabling Windows Test Mode for unsigned driver loading..." "KERNEL"
    
    try {
        bcdedit /set testsigning on | Out-Null
        bcdedit /set nointegritychecks on | Out-Null
        Write-PlutoLog "Test Mode enabled - RESTART REQUIRED" "SUCCESS"
        return $true
    }
    catch {
        Write-PlutoLog "Failed to enable Test Mode: $_" "ERROR"
        return $false
    }
}

#endregion

#region User-Mode Spoofing (Layer 1)

function Invoke-UserModeSpoof {
    Write-PlutoLog "=== LAYER 1: User-Mode Spoofing ===" "INFO"
    
    $results = @{
        MachineGUID = $false
        MACAddresses = @()
        WindowsUpdateID = $false
        PCName = $false
        Hostname = $false
        TracesCleaned = 0
    }
    
    # 1. Machine GUID
    try {
        $originalGUID = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Cryptography" -Name MachineGuid -EA Stop).MachineGuid
        $newGUID = [Guid]::NewGuid().ToString()
        
        # Backup
        reg export "HKLM\SOFTWARE\Microsoft\Cryptography" "$($PlutoConfig.BackupPath)\MachineGuid-$(Get-Date -Format yyyyMMdd-HHmmss).reg" 2>$null
        
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Cryptography" -Name MachineGuid -Value $newGUID -Force
        $results.MachineGUID = $true
        Write-PlutoLog "Machine GUID: $originalGUID -> $newGUID" "SUCCESS"
    }
    catch {
        Write-PlutoLog "Failed to spoof Machine GUID: $_" "ERROR"
    }
    
    # 2. MAC Addresses
    try {
        $adapters = Get-NetAdapter | Where-Object { $_.PhysicalMediaType -eq '802.3' }
        
        foreach ($adapter in $adapters) {
            $originalMAC = $adapter.MacAddress
            
            # Generate random MAC (locally administered)
            $bytes = New-Object byte[] 6
            $rng = [System.Security.Cryptography.RNGCryptoServiceProvider]::new()
            $rng.GetBytes($bytes)
            $rng.Dispose()
            $bytes[0] = ($bytes[0] -band 0xFE) -bor 0x02
            $newMAC = ($bytes | ForEach-Object { $_.ToString("X2") }) -join ':'
            
            # Find registry path
            $regBase = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4D36E972-E325-11CE-BFC1-08002BE10318}"
            $subKeys = Get-ChildItem $regBase -ErrorAction SilentlyContinue
            
            foreach ($key in $subKeys) {
                $driverDesc = (Get-ItemProperty $key.PSPath -Name "DriverDesc" -EA SilentlyContinue).DriverDesc
                if ($driverDesc -eq $adapter.DriverDescription) {
                    Set-ItemProperty -Path $key.PSPath -Name "NetworkAddress" -Value ($newMAC -replace ':', '') -Force
                    
                    # Disable/enable adapter
                    Disable-NetAdapter -Name $adapter.Name -Confirm:$false
                    Start-Sleep -Milliseconds 500
                    Enable-NetAdapter -Name $adapter.Name -Confirm:$false
                    
                    $results.MACAddresses += "$originalMAC -> $newMAC"
                    Write-PlutoLog "MAC [$($adapter.Name)]: $originalMAC -> $newMAC" "SUCCESS"
                    break
                }
            }
        }
    }
    catch {
        Write-PlutoLog "Failed to spoof MAC addresses: $_" "ERROR"
    }
    
    # 3. Windows Update ID
    try {
        Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
        
        $wuPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate"
        if (Test-Path $wuPath) {
            Remove-ItemProperty $wuPath "SusClientId" -Force -ErrorAction SilentlyContinue
            Remove-ItemProperty $wuPath "SusClientIdValidation" -Force -ErrorAction SilentlyContinue
        }
        
        Start-Service wuauserv -ErrorAction SilentlyContinue
        $results.WindowsUpdateID = $true
        Write-PlutoLog "Windows Update ID: Regenerated" "SUCCESS"
    }
    catch {
        Write-PlutoLog "Failed to reset Windows Update ID: $_" "ERROR"
    }
    
    # 4. PC Name / Hostname
    try {
        $originalName = $env:COMPUTERNAME
        $newName = "PC-" + (Get-Random -Minimum 1000 -Maximum 9999)
        
        Rename-Computer -NewName $newName -Force -ErrorAction Stop
        $results.PCName = $true
        $results.Hostname = $true
        Write-PlutoLog "PC Name: $originalName -> $newName (restart required)" "SUCCESS"
    }
    catch {
        Write-PlutoLog "Failed to rename PC: $_" "ERROR"
    }
    
    # 5. Trace Cleanup
    $traces = @(
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\UserAssist"; Recursive = $true },
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RecentDocs"; Recursive = $true },
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU"; Recursive = $false },
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\ComDlg32\OpenSavePidlMRU"; Recursive = $true },
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\ComDlg32\LastVisitedPidlMRU"; Recursive = $true }
    )
    
    foreach ($trace in $traces) {
        try {
            if (Test-Path $trace.Path) {
                Remove-Item -Path $trace.Path -Recurse:$trace.Recursive -Force -ErrorAction SilentlyContinue
                $results.TracesCleaned++
            }
        }
        catch {
            # Silently continue
        }
    }
    
    Write-PlutoLog "Traces cleaned: $($results.TracesCleaned) locations" "SUCCESS"
    
    # Clear Event Logs
    try {
        wevtutil cl Application 2>$null
        wevtutil cl System 2>$null
        wevtutil cl Security 2>$null
        wevtutil cl Setup 2>$null
        Write-PlutoLog "Event logs cleared" "SUCCESS"
    }
    catch {
        Write-PlutoLog "Some event logs could not be cleared" "WARN"
    }
    
    return $results
}

#endregion

#region Kernel-Mode Layer (Layer 2) - Documented Architecture

function Invoke-KernelModePreparation {
    Write-PlutoLog "=== LAYER 2: Kernel-Mode Preparation ===" "KERNEL"
    
    # Check prerequisites
    $prereqs = Test-KernelModePrerequisites
    
    if ($prereqs.TotalOK -lt 3) {
        Write-PlutoLog "Kernel-mode prerequisites not met" "WARN"
        Write-PlutoLog "Attempting to enable Test Mode..." "WARN"
        
        if (Enable-TestMode) {
            Write-PlutoLog "Please restart your computer and run this script again" "WARN"
            return @{ Status = "RESTART_REQUIRED"; CanProceed = $false }
        }
        else {
            return @{ Status = "PREREQ_FAILED"; CanProceed = $false }
        }
    }
    
    Write-PlutoLog "Kernel-mode prerequisites satisfied" "SUCCESS"
    
    return @{ Status = "READY"; CanProceed = $true }
}

function New-PlutoDriverPackage {
    Write-PlutoLog "Creating driver package documentation..." "KERNEL"
    
    # Since we can't provide signed drivers, we document the architecture
    $driverDoc = @"
# Pluto Hybrid - Kernel Driver Architecture

## Driver Components

### 1. WMI Filter Driver (PlutoWmi.sys)
**Purpose:** Hook WMI queries to return spoofed hardware data

**Technique:**
- Register as WMI filter driver using IoRegisterFsRegistrationChange
- Intercept IRP_MJ_DEVICE_CONTROL for WMI IOCTLs
- Hook WMIDataDevice and WMIMountDevice
- Modify query results in-flight

**Target WMI Classes:**
- Win32_ComputerSystemProduct (UUID)
- Win32_BIOS (SerialNumber, Version)
- Win32_BaseBoard (SerialNumber, Product)
- Win32_DiskDrive (SerialNumber, Model)
- Win32_PhysicalMedia (SerialNumber)

### 2. Disk Filter Driver (PlutoDisk.sys)
**Purpose:** Intercept disk serial number queries

**Technique:**
- Attach to disk stack using IoAttachDeviceToDeviceStack
- Filter IOCTL_DISK_GET_DRIVE_GEOMETRY_EX
- Filter IOCTL_STORAGE_QUERY_PROPERTY (StorageDeviceProperty)
- Return modified STORAGE_DEVICE_DESCRIPTOR

**IOCTLs Hooked:**
- IOCTL_DISK_GET_DRIVE_GEOMETRY
- IOCTL_DISK_GET_DRIVE_GEOMETRY_EX
- IOCTL_STORAGE_QUERY_PROPERTY
- IOCTL_SCSI_PASS_THROUGH
- IOCTL_SCSI_PASS_THROUGH_DIRECT
- SMART_RCV_DRIVE_DATA

### 3. SMBIOS Hook Driver (PlutoDMI.sys)
**Purpose:** Modify SMBIOS table in memory

**Technique:**
- Map physical memory where SMBIOS lives (0xF0000-0xFFFFF typically)
- Hook System Firmware Tables (GetSystemFirmwareTable API at kernel level)
- Modify cached SMBIOS data

**Alternative Approach:**
- Use DmiEdit (AMI tool) if AMI BIOS
- Use flashrom + patched firmware (advanced)

### 4. PCI Configuration Filter (PlutoPCI.sys)
**Purpose:** Modify PCI device IDs (GPU spoofing)

**Technique:**
- Filter IRP_MJ_PNP for PCI devices
- Hook PCI config space reads
- Modify DeviceID/VendorID in PCI_COMMON_CONFIG

## Driver Loading Strategy

### Option 1: KDMApper (Recommended for testing)
```batch
kdmapper.exe PlutoWmi.sys
```
Uses legitimate driver vulnerability to load unsigned code.

### Option 2: GDRV Loader
Exploit ASUS Aura Sync driver to load arbitrary code.

### Option 3: Manual Mapping (Educational)
Manually map driver without Windows loader:
1. Allocate kernel memory
2. Resolve imports
3. Call DriverEntry manually
4. Set up IRP handlers

## Anti-Detection Techniques

### 1. Timing Randomization
- Random delays between operations
- Jitter in hook response times

### 2. Pattern Obfuscation
- Polymorphic code (change signature each load)
- Junk code insertion
- Control flow flattening

### 3. Rootkit Techniques (Advanced)
- DKOM (Direct Kernel Object Manipulation)
- SSDT hooking (classic but detectable)
- IRP hooking (more stealthy)
- Mini-filter registration (legitimate-looking)

## Building the Driver

### Requirements:
- Windows Driver Kit (WDK)
- Visual Studio 2022
- Certificate for signing (or test mode)

### Build Steps:
```batch
msbuild PlutoDriver.sln /p:Configuration=Release /p:Platform=x64
signtool sign /f certificate.pfx /p password PlutoWmi.sys
```

### Installation:
```powershell
# Test mode
sc create PlutoWmi type= kernel binPath= C:\Path\To\PlutoWmi.sys
sc start PlutoWmi

# Or use loader
.\kdmapper.exe PlutoWmi.sys
```

## Safety Considerations

⚠️ Kernel driver bugs = SYSTEM CRASH (BSOD)
⚠️ Anti-cheat detects unsigned drivers
⚠️ Requires Test Mode or stolen/leaked certificates
⚠️ Permanent damage to hardware possible with wrong writes

## Detection Vectors

1. Driver signature check (EasyAntiCheat, Vanguard)
2. Memory scan for hooks
3. Timing analysis
4. Cross-validation of identifiers
5. TPM attestation

## Recommended Approach for Production

1. Use hypervisor-based spoofing (VM with GPU passthrough)
2. Or use signed driver with legitimate purpose
3. Or target only user-mode checks (limited effectiveness)

"@
    
    $docPath = "$($PlutoConfig.DriverPath)\DRIVER_ARCHITECTURE.md"
    Set-Content -Path $docPath -Value $driverDoc
    
    Write-PlutoLog "Driver architecture documented: $docPath" "SUCCESS"
    Write-PlutoLog "Note: Kernel driver source code not included - requires WDK and signing" "WARN"
    
    # Create placeholder driver info
    $driverInfo = @{
        Components = @(
            @{ Name = "PlutoWmi.sys"; Purpose = "WMI Query Hooking"; Status = "DOCUMENTED" }
            @{ Name = "PlutoDisk.sys"; Purpose = "Disk Serial Spoofing"; Status = "DOCUMENTED" }
            @{ Name = "PlutoDMI.sys"; Purpose = "SMBIOS Spoofing"; Status = "DOCUMENTED" }
            @{ Name = "PlutoPCI.sys"; Purpose = "PCI Device Masking"; Status = "DOCUMENTED" }
        )
        Loaders = @(
            @{ Name = "kdmapper"; Purpose = "Exploit-based loading"; Status = "AVAILABLE" }
            @{ Name = "gdrv"; Purpose = "ASUS driver exploit"; Status = "AVAILABLE" }
        )
        Documentation = $docPath
    }
    
    $driverInfo | ConvertTo-Json -Depth 10 | Set-Content "$($PlutoConfig.DriverPath)\driver-manifest.json"
    
    return $driverInfo
}

#endregion

#region WMI Query Hooking (User-Mode Alternative)

function Install-WMIHookUserMode {
    Write-PlutoLog "Installing user-mode WMI hook layer..." "INFO"
    
    # User-mode can't truly hook WMI, but we can:
    # 1. Create a WMI proxy
    # 2. Override COM objects
    # 3. Use DLL injection (advanced)
    
    Write-PlutoLog "User-mode WMI hook: LIMITED EFFECTIVENESS" "WARN"
    Write-PlutoLog "Kernel driver required for complete WMI spoofing" "WARN"
    
    # Document the limitation
    $wmiDoc = @"
# WMI Hooking - User-Mode vs Kernel-Mode

## User-Mode Limitations:
- Can only hook processes we control
- Can't hook system/anti-cheat processes
- WMI service (winmgmt.exe) runs as SYSTEM

## Kernel-Mode Approach (Required):
- Filter driver in WMI stack
- Hook WmipDataDevice, WmipMountDevice
- Modify IRP_MJ_DEVICE_CONTROL responses

## Alternative: COM Hooking
1. Hook CoCreateInstance
2. Redirect WMI queries to our proxy
3. Return spoofed IWbemServices

Limitation: Only affects current process
"@
    
    Set-Content -Path "$($PlutoConfig.DriverPath)\WMI_HOOKING.md" -Value $wmiDoc
}

#endregion

#region Full Hybrid Execution

function Invoke-PlutoHybridSpoof {
    param([switch]$SkipKernelMode)
    
    Write-Host @"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║        PLUTO HYBRID HWID SPOOFER v$($PlutoConfig.Version)               ║
║                                                           ║
║        User-Mode + Kernel-Mode Architecture               ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan
    
    Write-PlutoLog "Starting hybrid spoof sequence..." "INFO"
    
    # Phase 1: User-Mode (Always works)
    $userResults = Invoke-UserModeSpoof
    
    # Phase 2: Kernel-Mode (If enabled and prerequisites met)
    if (-not $SkipKernelMode) {
        $kernelStatus = Invoke-KernelModePreparation
        
        if ($kernelStatus.CanProceed) {
            Write-PlutoLog "Kernel-mode layer ready" "SUCCESS"
            
            # Document the driver architecture
            $driverInfo = New-PlutoDriverPackage
            
            Write-PlutoLog "Kernel driver status check..." "INFO"
            Write-PlutoLog "=== KERNEL DRIVER STATUS ===" "KERNEL"
            Write-PlutoLog "Components documented: $($driverInfo.Components.Count)" "KERNEL"
            foreach ($comp in $driverInfo.Components) {
                Write-PlutoLog "  - $($comp.Name): $($comp.Purpose) [$($comp.Status)]" "KERNEL"
            }
            
            Write-PlutoLog "Kernel-mode setup instructions:" "INFO"
            Write-PlutoLog "To complete kernel-mode spoofing:" "WARN"
            Write-PlutoLog "1. Review: $($driverInfo.Documentation)" "INFO"
            Write-PlutoLog "2. Build drivers using Windows Driver Kit (WDK)" "INFO"
            Write-PlutoLog "3. Sign drivers or use Test Mode + kdmapper" "INFO"
            Write-PlutoLog "4. Load drivers with documented loader" "INFO"
        }
        elseif ($kernelStatus.Status -eq "RESTART_REQUIRED") {
            Write-PlutoLog "Restart needed for kernel-mode" "WARN"
            Write-PlutoLog "=== ACTION REQUIRED ===" "WARN"
            Write-PlutoLog "Kernel-mode preparation incomplete" "WARN"
            Write-PlutoLog "Restart your computer to enable Test Mode" "WARN"
            Write-PlutoLog "Then run this script again" "WARN"
        }
        else {
            Write-PlutoLog "Kernel-mode layer unavailable - continuing with user-mode only" "WARN"
        }
    }
    
    # Summary
    Write-PlutoLog "Generating spoof summary..." "INFO"
    Write-PlutoLog "=== SPOOF SUMMARY ===" "SUCCESS"
    Write-PlutoLog "User-Mode Changes:" "INFO"
    Write-PlutoLog "  Machine GUID: $(if($userResults.MachineGUID){'CHANGED ✓'}else{'FAILED ✗'})" $(if($userResults.MachineGUID){"SUCCESS"}else{"ERROR"})
    Write-PlutoLog "  MAC Addresses: $($userResults.MACAddresses.Count) changed" "INFO"
    Write-PlutoLog "  Windows Update ID: $(if($userResults.WindowsUpdateID){'REGENERATED ✓'}else{'FAILED ✗'})" $(if($userResults.WindowsUpdateID){"SUCCESS"}else{"ERROR"})
    Write-PlutoLog "  PC Name: $(if($userResults.PCName){'CHANGED ✓ (restart req)'}else{'FAILED ✗'})" $(if($userResults.PCName){"SUCCESS"}else{"ERROR"})
    Write-PlutoLog "  Traces Cleaned: $($userResults.TracesCleaned)" "INFO"
    Write-PlutoLog "Kernel-mode layer status check..." "INFO"
    Write-PlutoLog "Kernel-Mode Layer: $(if($kernelStatus.CanProceed){'READY (drivers need building)'}else{'PENDING (restart or manual setup)'})" "INFO"
    Write-PlutoLog "Spoofing operation complete" "INFO"
    Write-PlutoLog "Log file: $($PlutoConfig.LogPath)\pluto-$(Get-Date -Format yyyyMMdd).log" "INFO"
    
    if (-not $userResults.PCName) {
        Write-PlutoLog "RESTART REQUIRED to complete PC name change" "WARN"
    }
}

#endregion

#region Execution

# Run the hybrid spoofer
Invoke-PlutoHybridSpoof

#endregion
