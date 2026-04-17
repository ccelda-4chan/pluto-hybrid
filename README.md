# 🔱 Pluto Hybrid HWID Spoofer v2.0

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-blue.svg)](https://microsoft.com/powershell)
[![Windows](https://img.shields.io/badge/Windows-10%2F11-blue.svg)](https://microsoft.com/windows)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](../LICENSE)
[![Architecture](https://img.shields.io/badge/architecture-hybrid-purple.svg)]()

> **The most comprehensive documented HWID spoofing toolkit.** Combines user-mode registry operations with documented kernel-mode driver architecture for complete system identity modification.

---

## 🎯 Why Hybrid?

Most spoofers fall into two categories:

| Type | Effectiveness | Safety | Complexity |
|------|--------------|--------|------------|
| **Registry-Only** | ⚠️ Partial | ✅ Safe | ✅ Easy |
| **Kernel Drivers** | ✅ Complete | ⚠️ Risky | ❌ Complex |
| **Pluto Hybrid** | ✅ Complete | ✅ Documented | 📚 Educational |

**Pluto Hybrid** bridges the gap by providing:
1. **Working user-mode spoofing** (immediate results)
2. **Documented kernel architecture** (educational pathway)
3. **Safety-first approach** (backups, validation, reversibility)

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Pluto Hybrid v2.0                     │
├──────────────────────────┬──────────────────────────────┤
│    LAYER 1: User-Mode   │     LAYER 2: Kernel-Mode     │
│     (PowerShell)        │     (Driver Architecture)    │
├──────────────────────────┼──────────────────────────────┤
│ • Machine GUID           │ • WMI Query Hooking          │
│ • MAC Addresses          │ • Disk Serial Spoofing       │
│ • Windows Update ID      │ • SMBIOS Data Hook           │
│ • PC Name / Hostname     │ • PCI Device Masking         │
│ • Registry Trace Cleanup │ • Anti-Detection Layer       │
├──────────────────────────┴──────────────────────────────┤
│                    Safety Layer                         │
│  • Registry Backup • Driver Documentation • Logging     │
└─────────────────────────────────────────────────────────┘
```

---

## 🚀 Quick Start

### Requirements
- Windows 10/11 (64-bit)
- PowerShell 5.1 or 7.x
- **Administrator privileges**

### One-Liner Installation

```powershell
# Console Version
irm https://raw.githubusercontent.com/YOURUSERNAME/pluto-hybrid/main/PlutoHybrid.ps1 | iex

# GUI Version
irm https://raw.githubusercontent.com/YOURUSERNAME/pluto-hybrid/main/PlutoHybrid-GUI.ps1 | iex
```

### Local Installation

```powershell
# Clone the repository
git clone https://github.com/YOURUSERNAME/pluto-hybrid.git
cd pluto-hybrid

# Run console version
.\PlutoHybrid.ps1

# Or run GUI version
.\PlutoHybrid-GUI.ps1
```

---

## 📊 Feature Matrix

### Layer 1: User-Mode (Always Works)

| Feature | Target | Method | Reversible | Restart Required |
|---------|--------|--------|------------|------------------|
| **Machine GUID** | `HKLM\SOFTWARE\Microsoft\Cryptography\MachineGuid` | Registry Write | ✅ Yes | ❌ No |
| **MAC Address** | `HKLM\SYSTEM\CurrentControlSet\Control\Class\{4D36E972...}` | Registry + Adapter Reset | ✅ Yes | ⚠️ Adapter Reset |
| **Windows Update ID** | `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate` | Service Stop/Start | ✅ Yes | ❌ No |
| **PC Name** | `ComputerName` system property | WMI Rename | ✅ Yes | ✅ Yes |
| **Trace Cleanup** | Various registry locations | Key Deletion | ✅ (with backup) | ❌ No |

### Layer 2: Kernel-Mode (Requires Setup)

| Feature | Target | Method | Prerequisites |
|---------|--------|--------|---------------|
| **WMI Query Hooking** | `Win32_*` classes | Filter Driver | Test Mode + Driver |
| **Disk Serial Spoofing** | `IOCTL_STORAGE_QUERY_PROPERTY` | Driver Hook | Test Mode + Driver |
| **SMBIOS Spoofing** | `GetSystemFirmwareTable` | Memory Hook | Test Mode + Driver |
| **PCI Device Masking** | `SetupAPI` enumeration | Config Space Filter | Test Mode + Driver |

---

## 🛡️ Safety Features

### Automatic Backups
Every registry change is backed up before modification:
```
%LOCALAPPDATA%\PlutoHybrid\Backup\
├── MachineGuid-20240115-143022.reg
├── MAC-Adapter1-20240115-143025.reg
└── MountedDevices-20240115-143028.reg
```

### Restore Procedure
```powershell
# Restore Machine GUID
reg import "%LOCALAPPDATA%\PlutoHybrid\Backup\MachineGuid-*.reg"

# Restore all
Get-ChildItem "$env:LOCALAPPDATA\PlutoHybrid\Backup\*.reg" | ForEach-Object { reg import $_.FullName }
```

### Comprehensive Logging
```
%LOCALAPPDATA%\PlutoHybrid\logs\
├── pluto-20240115.log
└── pluto-20240116.log
```

Log format:
```
[2024-01-15 14:30:22.123] [INFO] Starting hybrid spoof sequence...
[2024-01-15 14:30:22.456] [SUCCESS] Machine GUID: {old-guid} -> {new-guid}
[2024-01-15 14:30:25.789] [SUCCESS] MAC [Ethernet]: A1:B2:C3:D4:E5:F6 -> 02:5A:7C:9E:3F:4B
```

---

## ⚙️ Kernel-Mode Preparation

### Prerequisites Check

Run `PlutoHybrid.ps1` or click "Check System Status" in GUI:

| Check | Required For | How to Enable |
|-------|--------------|---------------|
| **Test Mode** | Unsigned drivers | `bcdedit /set testsigning on` |
| **Secure Boot OFF** | Driver loading | Disable in UEFI/BIOS |
| **Driver Signature Override** | KDMApper | `bcdedit /set nointegritychecks on` |
| **HVCI OFF** | Memory integrity | Windows Security → Device Security |

### Enable Test Mode

```powershell
# As Administrator:
bcdedit /set testsigning on
bcdedit /set nointegritychecks on

# Restart required
shutdown /r /t 0
```

**Note:** Test Mode shows a watermark on desktop. This is normal and required for kernel-mode spoofing.

---

## 📚 Kernel Driver Documentation

The kernel-mode layer is **documented architecture only** (no compiled drivers provided).

### Why?

1. **Driver Signing**: Requires expensive EV certificate (~$500/year) or test mode
2. **Anti-Cheat Detection**: Unsigned drivers are flagged; need evasion techniques
3. **System Stability**: Kernel bugs = Blue Screen of Death (BSOD)
4. **Legal**: Providing pre-built kernel drivers for spoofing is legally gray

### What's Provided

```
pluto-hybrid/
├── PlutoHybrid.ps1          # Console orchestrator
├── PlutoHybrid-GUI.ps1       # WPF GUI
└── Drivers/
    ├── DRIVER_ARCHITECTURE.md     # Complete driver architecture docs
    └── driver-manifest.json       # Component manifest
```

### DRIVER_ARCHITECTURE.md Contents

- **WMI Filter Driver** - How to hook WMI queries
- **Disk Filter Driver** - IOCTL interception techniques
- **SMBIOS Hook Driver** - Firmware table modification
- **PCI Config Filter** - Device ID masking
- **Driver Loaders** - KDMApper, GDRV exploitation
- **Anti-Detection** - Evasion techniques
- **Building Guide** - WDK setup and compilation

---

## 🎓 Building Kernel Drivers

### Requirements

- Windows 11 SDK
- Windows Driver Kit (WDK)
- Visual Studio 2022 with "Desktop development with C++" workload
- Certificate (for signing) OR Test Mode enabled

### Build Steps

1. **Install WDK**: Download from [Microsoft](https://docs.microsoft.com/en-us/windows-hardware/drivers/download-the-wdk)

2. **Open Solution**: `PlutoDrivers.sln` (would be created from docs)

3. **Build**:
   ```batch
   msbuild PlutoDrivers.sln /p:Configuration=Release /p:Platform=x64
   ```

4. **Sign** (with certificate):
   ```batch
   signtool sign /f certificate.pfx /p password PlutoWmi.sys
   ```

5. **Load** (Test Mode):
   ```powershell
   .\kdmapper.exe PlutoWmi.sys
   ```

---

## 🔍 How It Works

### User-Mode Registry Spoofing

```powershell
# Machine GUID
$original = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Cryptography" MachineGuid).MachineGuid
$new = [Guid]::NewGuid().ToString()
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Cryptography" -Name MachineGuid -Value $new
```

### MAC Address Spoofing

```powershell
# Generate locally-administered MAC
$bytes = New-Object byte[] 6
$rng = [System.Security.Cryptography.RNGCryptoServiceProvider]::new()
$rng.GetBytes($bytes)
$bytes[0] = ($bytes[0] -band 0xFE) -bor 0x02  # Local admin bit
$newMac = ($bytes | ForEach-Object { $_.ToString("X2") }) -join ':'

# Apply via registry
Set-ItemProperty -Path "HKLM:\...\{4D36E972...}\0001" -Name "NetworkAddress" -Value ($newMac -replace ':','')
```

### Kernel-Mode WMI Hooking (Conceptual)

```c
// Filter driver attaches to WMI stack
NTSTATUS DriverEntry(PDRIVER_OBJECT DriverObject, PUNICODE_STRING RegistryPath) {
    // Register as WMI filter
    IoWMIRegistrationControl(DeviceObject, WMIREG_ACTION_REGISTER);
    
    // Hook IRP_MJ_DEVICE_CONTROL
    DriverObject->MajorFunction[IRP_MJ_DEVICE_CONTROL] = PlutoWmiDispatch;
}

NTSTATUS PlutoWmiDispatch(PDEVICE_OBJECT DeviceObject, PIRP Irp) {
    // Check if WMI query for hardware info
    if (IsHardwareQuery(Irp)) {
        // Modify response with spoofed data
        SpoofWmiResponse(Irp);
    }
    return IoCallDriver(NextLowerDriver, Irp);
}
```

---

## ⚠️ Important Considerations

### Anti-Cheat Detection

Modern anti-cheat (EAC, BattlEye, Vanguard) checks:

1. **Driver Signatures** - Unsigned drivers = immediate flag
2. **Memory Integrity** - Look for hooks in kernel memory
3. **Cross-Validation** - Compare multiple identifier sources
4. **Timing Analysis** - Detect unnatural query response times
5. **TPM Attestation** - Hardware-backed integrity measurements

### Recommendations

| Use Case | Recommended Mode |
|----------|------------------|
| Privacy/Testing | User-Mode Only ✅ |
| Game Anti-Cheat | VM with GPU Passthrough ✅ |
| Educational | Kernel Documentation ✅ |
| Production | Signed Driver + Evasion ❌ (Not provided) |

---

## 📁 Project Structure

```
pluto-hybrid/
├── PlutoHybrid.ps1              # Console orchestrator (13 KB)
├── PlutoHybrid-GUI.ps1          # WPF GUI (10 KB)
├── README.md                    # This file
├── Drivers/                     # Kernel architecture docs
│   ├── DRIVER_ARCHITECTURE.md   # Technical documentation
│   └── driver-manifest.json     # Component list
└── LICENSE                      # MIT License
```

---

## 🤝 Contributing

Contributions welcome! Areas of interest:

- Additional user-mode spoofing targets
- Kernel driver implementations (with appropriate warnings)
- GUI improvements
- Documentation
- Safety enhancements

### Submitting Changes

1. Fork the repository
2. Create feature branch: `git checkout -b feature/amazing-feature`
3. Commit: `git commit -m 'Add amazing feature'`
4. Push: `git push origin feature/amazing-feature`
5. Open Pull Request

---

## 📜 License

MIT License - See [LICENSE](../LICENSE)

**Disclaimer**: This tool is for educational and privacy purposes. Users are responsible for complying with applicable laws and terms of service.

---

## 🙏 Acknowledgments

- Windows Driver Kit documentation
- Windows Internals books (Russinovich, Solomon, Ionescu)
- Sysinternals tools reference
- Security research community

---

<div align="center">

**[⬆ Back to Top](#-pluto-hybrid-hwid-spoofer-v20)**

Built with 🔱 PowerShell and documented kernel architecture

</div>
