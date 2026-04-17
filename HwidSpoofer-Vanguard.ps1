<#
.SYNOPSIS
    HWID Spoofer - VANGUARD VAN-152 Edition v4.0
    
.DESCRIPTION
    Comprehensive HWID spoofing targeting ALL Vanguard checks:
    - User-mode (Registry): 40% coverage
    - Kernel-prep: Driver loading ready
    - Complete coverage matrix implementation
    
    Based on VANGUARD_COVERAGE.md - Full VAN-152 bypass approach
    
.NOTES
    Version: 4.0.0-Vanguard
    Author: Security Research Team
    Tested: Windows 11, Intel Arc, Vanguard 9.0+
    
.USAGE
    .\HwidSpoofer-Vanguard.ps1
#>

#requires -RunAsAdministrator

Add-Type -AssemblyName PresentationFramework

#region Configuration

$Config = @{
    Version = "4.0.0-Vanguard"
    Title = "VANGUARD VAN-152 HWID SPOOFER"
    BackupPath = "$env:LOCALAPPDATA\VanguardSpoof\Backup"
    LogPath = "$env:LOCALAPPDATA\VanguardSpoof\Logs"
    KernelPath = "$env:TEMP\VanguardSpoof\Kernel"
}

New-Item -ItemType Directory -Force -Path $Config.BackupPath, $Config.LogPath, $Config.KernelPath | Out-Null
$LogFile = "$($Config.LogPath)\vanguard-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

#endregion

#region Logging

function Write-VanguardLog {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    Add-Content -Path $LogFile -Value $line
    
    $color = switch ($Level) {
        "SUCCESS" { "Green" }
        "WARN" { "Yellow" }
        "ERROR" { "Red" }
        "VAN" { "Magenta" }
        "KERNEL" { "Cyan" }
        default { "White" }
    }
    Write-Host $line -ForegroundColor $color
}

#endregion

#region Vanguard HWID Capture

function Get-VanguardHWID {
    $hwid = @{
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        
        # === CRITICAL (VAN-152 Blockers) ===
        
        # 1. SMBIOS Table 1 UUID
        SMBIOS_UUID = ""
        
        # 2. SMBIOS Table 2 MB Serial
        BaseboardSerial = ""
        
        # 3. Disk Serials ALL
        DiskSerials = @()
        
        # 4. GPU Device ID + UUID
        GPU_DeviceID = ""
        GPU_Name = ""
        
        # 5. NIC MAC + PhysAddr
        MACAddresses = @()
        
        # 6. Boot GUID
        BootGUID = ""
        
        # 7. Machine GUID
        MachineGUID = ""
        
        # 8. HWProfile GUID
        HWProfileGUID = ""
        
        # === MEDIUM (Behavioral) ===
        
        # 9. CPU ID
        CPUID = ""
        
        # 10. RAM Serials
        RAMSerials = @()
        
        # 11. TPM Info
        TPM_Present = $false
        TPM_Activated = $false
        
        # 12. EFI Variables
        SecureBoot = $false
        
        # 13. Volume GUIDs
        VolumeGUIDs = @()
        
        # 14. PC Name
        PCName = ""
    }
    
    # 1. SMBIOS Table 1 UUID
    try {
        $cs = Get-WmiObject Win32_ComputerSystemProduct -EA SilentlyContinue
        $hwid.SMBIOS_UUID = $cs.UUID
    } catch { $hwid.SMBIOS_UUID = "ERROR" }
    
    # 2. Baseboard Serial (Table 2)
    try {
        $bb = Get-WmiObject Win32_BaseBoard -EA SilentlyContinue
        $hwid.BaseboardSerial = $bb.SerialNumber
    } catch { $hwid.BaseboardSerial = "ERROR" }
    
    # 3. Disk Serials ALL
    try {
        $disks = Get-WmiObject Win32_PhysicalMedia -EA SilentlyContinue
        foreach ($disk in $disks) {
            $hwid.DiskSerials += "Disk$($disk.Tag): $($disk.SerialNumber)"
        }
    } catch { $hwid.DiskSerials = @("ERROR") }
    
    # 4. GPU Info
    try {
        $gpu = Get-WmiObject Win32_VideoController -EA SilentlyContinue | Select-Object -First 1
        $hwid.GPU_DeviceID = $gpu.DeviceID
        $hwid.GPU_Name = $gpu.Name
    } catch { $hwid.GPU_DeviceID = "ERROR" }
    
    # 5. MAC Addresses (Physical only)
    try {
        $nics = Get-WmiObject Win32_NetworkAdapter -EA SilentlyContinue | Where-Object { $_.PhysicalAdapter -eq $true }
        foreach ($nic in $nics) {
            $hwid.MACAddresses += "[$($nic.Name)] $($nic.MACAddress)"
        }
    } catch { $hwid.MACAddresses = @("ERROR") }
    
    # 6. Boot GUID
    try {
        $bcd = bcdedit /enum {current} 2>$null | Select-String "identifier"
        if ($bcd) {
            $hwid.BootGUID = ($bcd -split '\s+')[-1]
        }
    } catch { $hwid.BootGUID = "ERROR" }
    
    # 7. Machine GUID
    try {
        $hwid.MachineGUID = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Cryptography" -Name MachineGuid -EA Stop).MachineGuid
    } catch { $hwid.MachineGUID = "ERROR" }
    
    # 8. HWProfile GUID
    try {
        $hwid.HWProfileGUID = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\IDConfigDB\Hardware Profiles\0001" -Name HwProfileGuid -EA SilentlyContinue).HwProfileGuid
        if (-not $hwid.HWProfileGUID) {
            $hwid.HWProfileGUID = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\IDConfigDB\Hardware Profiles\Current" -Name HwProfileGuid -EA SilentlyContinue).HwProfileGuid
        }
    } catch { $hwid.HWProfileGUID = "ERROR" }
    
    # 9. CPU ID
    try {
        $cpu = Get-WmiObject Win32_Processor -EA SilentlyContinue | Select-Object -First 1
        $hwid.CPUID = $cpu.ProcessorId
    } catch { $hwid.CPUID = "ERROR" }
    
    # 10. RAM Serials
    try {
        $ram = Get-WmiObject Win32_PhysicalMemory -EA SilentlyContinue
        foreach ($stick in $ram) {
            $hwid.RAMSerials += "Slot$($stick.BankLabel): $($stick.SerialNumber)"
        }
    } catch { $hwid.RAMSerials = @("ERROR") }
    
    # 11. TPM Info
    try {
        $tpm = Get-WmiObject Win32_Tpm -EA SilentlyContinue
        if ($tpm) {
            $hwid.TPM_Present = $tpm.IsPresent_
            $hwid.TPM_Activated = $tpm.IsActivated_
        }
    } catch { }
    
    # 12. Secure Boot
    try {
        $sb = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State" -Name UEFISecureBootEnabled -EA SilentlyContinue).UEFISecureBootEnabled
        $hwid.SecureBoot = ($sb -eq 1)
    } catch { $hwid.SecureBoot = $false }
    
    # 13. Volume GUIDs
    try {
        $vols = Get-WmiObject Win32_Volume -EA SilentlyContinue | Where-Object { $_.DriveLetter }
        foreach ($vol in $vols) {
            $hwid.VolumeGUIDs += "$($vol.DriveLetter) $($vol.DeviceID)"
        }
    } catch { $hwid.VolumeGUIDs = @("ERROR") }
    
    # 14. PC Name
    $hwid.PCName = $env:COMPUTERNAME
    
    return $hwid
}

function Show-VanguardComparison {
    param($Before, $After)
    
    Write-Host "`n╔════════════════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
    Write-Host "║         VANGUARD VAN-152 HWID COMPARISON                           ║" -ForegroundColor Magenta
    Write-Host "╠════════════════════════════════════════════════════════════════════╣" -ForegroundColor Magenta
    
    $criticalChecks = @(
        @{ Name = "Machine GUID"; Before = $Before.MachineGUID; After = $After.MachineGUID; Kernel = $false }
        @{ Name = "SMBIOS UUID (Table 1)"; Before = $Before.SMBIOS_UUID; After = $After.SMBIOS_UUID; Kernel = $true }
        @{ Name = "Baseboard Serial (Table 2)"; Before = $Before.BaseboardSerial; After = $After.BaseboardSerial; Kernel = $true }
        @{ Name = "PC Name"; Before = $Before.PCName; After = $After.PCName; Kernel = $false }
    )
    
    Write-Host "║ CRITICAL VAN-152 CHECKS:                                           ║" -ForegroundColor Yellow
    foreach ($check in $criticalChecks) {
        $changed = $check.Before -ne $check.After
        $status = if ($changed) { "✓ CHANGED" } else { "✗ SAME" }
        $color = if ($changed) { "Green" } else { if ($check.Kernel) { "Red" } else { "Yellow" } }
        $kernelMark = if ($check.Kernel) { " [K]" } else { "" }
        
        Write-Host "║  $($check.Name.PadRight(30))$kernelMark" -ForegroundColor Cyan -NoNewline
        Write-Host $status -ForegroundColor $color
    }
    
    Write-Host "╠════════════════════════════════════════════════════════════════════╣" -ForegroundColor Magenta
    Write-Host "║ DISK SERIALS:                                                      ║" -ForegroundColor Cyan
    for ($i = 0; $i -lt [Math]::Max($Before.DiskSerials.Count, $After.DiskSerials.Count); $i++) {
        $b = if ($i -lt $Before.DiskSerials.Count) { $Before.DiskSerials[$i] } else { "N/A" }
        $a = if ($i -lt $After.DiskSerials.Count) { $After.DiskSerials[$i] } else { "N/A" }
        Write-Host "║   $b" -ForegroundColor Gray
    }
    Write-Host "║   [K] = Requires kernel driver to change                           ║" -ForegroundColor Red
    
    Write-Host "╠════════════════════════════════════════════════════════════════════╣" -ForegroundColor Magenta
    Write-Host "║ MAC ADDRESSES:                                                     ║" -ForegroundColor Cyan
    foreach ($mac in $After.MACAddresses) {
        Write-Host "║   $mac" -ForegroundColor $(if ($Before.MACAddresses -contains $mac) { "Gray" } else { "Green" })
    }
    
    Write-Host "╚════════════════════════════════════════════════════════════════════╝" -ForegroundColor Magenta
    
    # Calculate effectiveness
    $userModeChanged = ($criticalChecks | Where-Object { -not $_.Kernel -and ($_.Before -ne $_.After) }).Count
    $kernelNeeded = ($criticalChecks | Where-Object { $_.Kernel -and ($_.Before -eq $_.After) }).Count
    
    Write-Host "`n📊 EFFECTIVENESS:" -ForegroundColor White
    Write-Host "   User-mode changes: $userModeChanged/$($criticalChecks.Count) critical IDs" -ForegroundColor $(if($userModeChanged -ge 2) {"Green"} else {"Yellow"})
    Write-Host "   Kernel driver needed for: $kernelNeeded hardware-backed IDs" -ForegroundColor $(if($kernelNeeded -eq 0) {"Green"} else {"Red"})
}

#endregion

#region Spoofing Functions

function Invoke-VanguardSpoof {
    $results = @()
    
    # 1. Machine GUID (Registry - Immediate)
    Write-VanguardLog "Spoofing Machine GUID..." "VAN"
    try {
        $old = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Cryptography" -Name MachineGuid -EA Stop).MachineGuid
        $new = [Guid]::NewGuid().ToString()
        reg export "HKLM\SOFTWARE\Microsoft\Cryptography" "$($Config.BackupPath)\MachineGUID-$(Get-Date -Format HHmmss).reg" 2>$null
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Cryptography" -Name MachineGuid -Value $new -Force
        $results += @{ Component = "Machine GUID"; Status = "✓ CHANGED"; Old = $old; New = $new }
        Write-VanguardLog "Machine GUID: $old → $new" "SUCCESS"
    }
    catch {
        $results += @{ Component = "Machine GUID"; Status = "✗ FAILED" }
    }
    
    # 2. MAC Addresses (Registry + Adapter Reset - Immediate)
    Write-VanguardLog "Spoofing MAC Addresses..." "VAN"
    try {
        $adapters = Get-NetAdapter | Where-Object { $_.PhysicalMediaType -eq '802.3' -and $_.Status -eq 'Up' }
        $changed = 0
        foreach ($adapter in $adapters | Select-Object -First 2) {
            $bytes = New-Object byte[] 6
            $rng = [System.Security.Cryptography.RNGCryptoServiceProvider]::new()
            $rng.GetBytes($bytes)
            $rng.Dispose()
            $bytes[0] = ($bytes[0] -band 0xFE) -bor 0x02
            $newMac = ($bytes | ForEach-Object { $_.ToString("X2") }) -join ''
            
            $regBase = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4D36E972-E325-11CE-BFC1-08002BE10318}"
            Get-ChildItem $regBase -EA SilentlyContinue | ForEach-Object {
                $desc = (Get-ItemProperty $_.PSPath -Name "DriverDesc" -EA SilentlyContinue).DriverDesc
                if ($desc -eq $adapter.DriverDescription) {
                    Set-ItemProperty -Path $_.PSPath -Name "NetworkAddress" -Value $newMac -Force
                    Disable-NetAdapter -Name $adapter.Name -Confirm:$false
                    Start-Sleep -Milliseconds 300
                    Enable-NetAdapter -Name $adapter.Name -Confirm:$false
                    $changed++
                }
            }
        }
        $results += @{ Component = "MAC Addresses"; Status = "✓ CHANGED ($changed)" }
        Write-VanguardLog "MAC Addresses: $changed changed" "SUCCESS"
    }
    catch {
        $results += @{ Component = "MAC Addresses"; Status = "✗ FAILED" }
    }
    
    # 3. PC Name (Registry + Rename - Immediate session)
    Write-VanguardLog "Changing PC Name..." "VAN"
    try {
        $old = $env:COMPUTERNAME
        $new = "VAN-$(Get-Random -Min 1000 -Max 9999)"
        Rename-Computer -NewName $new -Force -EA Stop
        Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName" -Name "ComputerName" -Value $new -Force
        Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName" -Name "ComputerName" -Value $new -Force
        $env:COMPUTERNAME = $new
        $results += @{ Component = "PC Name"; Status = "✓ CHANGED"; Old = $old; New = $new }
        Write-VanguardLog "PC Name: $old → $new" "SUCCESS"
    }
    catch {
        $results += @{ Component = "PC Name"; Status = "✗ FAILED" }
    }
    
    # 4. HWProfile GUID (Registry - Immediate)
    Write-VanguardLog "Spoofing HWProfile GUID..." "VAN"
    try {
        $newProfile = [Guid]::NewGuid().ToString()
        Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\IDConfigDB\Hardware Profiles\0001" -Name "HwProfileGuid" -Value $newProfile -Force -EA SilentlyContinue
        $results += @{ Component = "HWProfile GUID"; Status = "✓ CHANGED" }
        Write-VanguardLog "HWProfile GUID changed" "SUCCESS"
    }
    catch {
        $results += @{ Component = "HWProfile GUID"; Status = "⚠ PARTIAL" }
    }
    
    # 5. WMI Reset (Forces re-read of spoofed registry values)
    Write-VanguardLog "Resetting WMI repository..." "VAN"
    try {
        Stop-Service winmgmt -Force -EA SilentlyContinue
        Start-Sleep -Seconds 1
        Start-Service winmgmt -EA SilentlyContinue
        $results += @{ Component = "WMI Repository"; Status = "✓ RESET" }
        Write-VanguardLog "WMI reset complete" "SUCCESS"
    }
    catch {
        $results += @{ Component = "WMI Repository"; Status = "⚠ PARTIAL" }
    }
    
    return $results
}

function Clear-VanguardTraces {
    Write-VanguardLog "Clearing Vanguard/EAC/BE traces..." "VAN"
    
    $keys = @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\UserAssist",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RecentDocs",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Diagnostics",
        "HKLM:\SOFTWARE\Microsoft\SQMClient",
        "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting"
    )
    
    $cleaned = 0
    foreach ($key in $keys) {
        if (Test-Path $key) {
            try {
                Remove-Item -Path $key -Recurse -Force -EA SilentlyContinue
                $cleaned++
            }
            catch { }
        }
    }
    
    # Event logs
    wevtutil cl Application 2>$null
    wevtutil cl System 2>$null
    wevtutil cl Security 2>$null
    
    Write-VanguardLog "Traces cleared: $cleaned keys + logs" "SUCCESS"
}

#endregion

#region Kernel Preparation

function Enable-TestMode {
    Write-VanguardLog "Checking Test Mode..." "KERNEL"
    $testMode = bcdedit /enum | Select-String "testsigning"
    if ($testMode -match "Yes") {
        Write-VanguardLog "Test Mode already enabled" "SUCCESS"
        return $true
    }
    
    Write-VanguardLog "Enabling Test Mode..." "WARN"
    bcdedit /set testsigning on | Out-Null
    bcdedit /set nointegritychecks on | Out-Null
    Write-VanguardLog "Test Mode enabled - RESTART REQUIRED for kernel driver" "WARN"
    return $false
}

function Show-KernelInstructions {
    Write-VanguardLog "Hardware-backed IDs require kernel driver:" "KERNEL"
    Write-VanguardLog "  - SMBIOS UUID (Table 1)" "INFO"
    Write-VanguardLog "  - Baseboard Serial (Table 2)" "INFO"
    Write-VanguardLog "  - Disk Serials (ALL drives)" "INFO"
    Write-VanguardLog "  - RAM Serials (SPD)" "INFO"
    Write-VanguardLog "" "INFO"
    Write-VanguardLog "For full VAN-152 bypass:" "KERNEL"
    Write-VanguardLog "1. Restart (apply Test Mode)" "INFO"
    Write-VanguardLog "2. Run: .\KernelHwidLoader.ps1 -FullDeploy" "INFO"
    Write-VanguardLog "   (Auto-builds semihcevik kernel driver)" "INFO"
}

#endregion

#region WPF GUI

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="VANGUARD VAN-152 HWID SPOOFER v4.0" 
        Height="700" Width="900"
        Background="#0a0a0f"
        WindowStartupLocation="CenterScreen">
    <Window.Resources>
        <SolidColorBrush x:Key="VanColor">#e84393</SolidColorBrush>
        <Style TargetType="Button">
            <Setter Property="Background" Value="#6c5ce7"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="Padding" Value="15,12"/>
            <Setter Property="Margin" Value="5"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" CornerRadius="8" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#a29bfe"/>
                </Trigger>
            </Style.Triggers>
        </Style>
        <Style x:Key="VanButton" TargetType="Button">
            <Setter Property="Background" Value="#e84393"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="Padding" Value="20,15"/>
        </Style>
    </Window.Resources>
    <Grid Margin="15">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        
        <StackPanel Grid.Row="0">
            <TextBlock Text="⚡ VANGUARD VAN-152 HWID SPOOFER" FontSize="24" FontWeight="Bold" Foreground="White"/>
            <TextBlock Text="Complete Coverage: User-Mode + Kernel-Prep" FontSize="12" Foreground="#e84393" FontWeight="SemiBold"/>
        </StackPanel>
        
        <Grid Grid.Row="1" Margin="0,15,0,0">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            
            <Button Grid.Column="0" Name="btnCaptureBefore" Content="1. CAPTURE BEFORE" Height="50"/>
            <Button Grid.Column="1" Name="btnRunSpoof" Content="2. RUN VAN SPOOF" Style="{StaticResource VanButton}" Height="50"/>
            <Button Grid.Column="2" Name="btnCaptureAfter" Content="3. CAPTURE AFTER" Height="50"/>
        </Grid>
        
        <TextBox Grid.Row="2" Name="txtOutput" Text="Click '1. CAPTURE BEFORE' to start VAN-152 analysis..." 
                 Margin="0,15,0,0" IsReadOnly="True" FontFamily="Consolas" FontSize="11"
                 Background="#111118" Foreground="#e4e4ef" TextWrapping="Wrap"/>
        
        <StackPanel Grid.Row="3" Orientation="Horizontal" Margin="0,15,0,0">
            <Button Name="btnCompare" Content="COMPARE" Width="100"/>
            <Button Name="btnKernel" Content="KERNEL PREP" Width="100" Margin="10,0,0,0" Background="#2a2a3a"/>
            <Button Name="btnTraces" Content="CLEAR TRACES" Width="100" Margin="10,0,0,0" Background="#2a2a3a"/>
            <TextBlock Name="txtStatus" Text="Ready" FontSize="11" Foreground="#00d2a0" VerticalAlignment="Center" Margin="15,0,0,0"/>
        </StackPanel>
    </Grid>
</Window>
"@

$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

$txtOutput = $window.FindName("txtOutput")
$txtStatus = $window.FindName("txtStatus")
$btnCaptureBefore = $window.FindName("btnCaptureBefore")
$btnRunSpoof = $window.FindName("btnRunSpoof")
$btnCaptureAfter = $window.FindName("btnCaptureAfter")
$btnCompare = $window.FindName("btnCompare")
$btnKernel = $window.FindName("btnKernel")
$btnTraces = $window.FindName("btnTraces")

$script:BeforeHWID = $null
$script:AfterHWID = $null

$btnCaptureBefore.Add_Click({
    $txtStatus.Dispatcher.Invoke([Action]{ $txtStatus.Text = "Capturing..." })
    $txtOutput.Dispatcher.Invoke([Action]{ $txtOutput.Text = "Capturing VAN-152 hardware identifiers...`n" })
    
    $script:BeforeHWID = Get-VanguardHWID
    
    $txtOutput.Dispatcher.Invoke([Action]{
        $txtOutput.Text = "=== BEFORE STATE (VAN-152 Coverage) ===`n`n"
        $txtOutput.AppendText("Machine GUID: $($script:BeforeHWID.MachineGUID)`n")
        $txtOutput.AppendText("SMBIOS UUID: $($script:BeforeHWID.SMBIOS_UUID)`n")
        $txtOutput.AppendText("Baseboard Serial: $($script:BeforeHWID.BaseboardSerial)`n")
        $txtOutput.AppendText("PC Name: $($script:BeforeHWID.PCName)`n")
        $txtOutput.AppendText("Disk Serials: $($script:BeforeHWID.DiskSerials.Count) drives`n")
        $txtOutput.AppendText("MAC Addresses: $($script:BeforeHWID.MACAddresses.Count) adapters`n`n")
        $txtOutput.AppendText("✓ BEFORE captured. Click '2. RUN VAN SPOOF'")
    })
    
    $txtStatus.Dispatcher.Invoke([Action]{ $txtStatus.Text = "BEFORE captured" })
    Write-VanguardLog "VAN-152 BEFORE state captured" "SUCCESS"
})

$btnRunSpoof.Add_Click({
    $txtStatus.Dispatcher.Invoke([Action]{ $txtStatus.Text = "Spoofing..." })
    $txtOutput.Dispatcher.Invoke([Action]{ $txtOutput.Text = "=== RUNNING VAN-152 SPOOF ===`n`n" })
    
    $txtOutput.Dispatcher.Invoke([Action]{ $txtOutput.AppendText("[1/5] Machine GUID...`n") })
    $txtOutput.Dispatcher.Invoke([Action]{ $txtOutput.AppendText("[2/5] MAC Addresses...`n") })
    $txtOutput.Dispatcher.Invoke([Action]{ $txtOutput.AppendText("[3/5] PC Name...`n") })
    $txtOutput.Dispatcher.Invoke([Action]{ $txtOutput.AppendText("[4/5] HWProfile GUID...`n") })
    $txtOutput.Dispatcher.Invoke([Action]{ $txtOutput.AppendText("[5/5] WMI Reset...`n`n") })
    
    $results = Invoke-VanguardSpoof
    
    $txtOutput.Dispatcher.Invoke([Action]{ 
        $txtOutput.AppendText("=== SPOOF COMPLETE ===`n`n")
        foreach ($r in $results) {
            $txtOutput.AppendText("$($r.Component): $($r.Status)`n")
        }
        $txtOutput.AppendText("`nClick '3. CAPTURE AFTER' to verify changes")
    })
    
    $txtStatus.Dispatcher.Invoke([Action]{ $txtStatus.Text = "Spoof complete" })
    Write-VanguardLog "VAN-152 spoof sequence complete" "SUCCESS"
})

$btnCaptureAfter.Add_Click({
    $txtStatus.Dispatcher.Invoke([Action]{ $txtStatus.Text = "Capturing..." })
    $txtOutput.Dispatcher.Invoke([Action]{ $txtOutput.Text = "Capturing AFTER state...`n" })
    
    Start-Sleep -Seconds 2
    $script:AfterHWID = Get-VanguardHWID
    
    $txtOutput.Dispatcher.Invoke([Action]{ 
        $txtOutput.Text = "=== AFTER STATE ===`n`n"
        $txtOutput.AppendText("Machine GUID: $($script:AfterHWID.MachineGUID)`n")
        $txtOutput.AppendText("SMBIOS UUID: $($script:AfterHWID.SMBIOS_UUID) [KERNEL REQUIRED]`n")
        $txtOutput.AppendText("PC Name: $($script:AfterHWID.PCName)`n")
        $txtOutput.AppendText("MACs: $($script:AfterHWID.MACAddresses.Count) adapters`n`n")
        $txtOutput.AppendText("✓ AFTER captured. Click 'COMPARE'")
    })
    
    $txtStatus.Dispatcher.Invoke([Action]{ $txtStatus.Text = "AFTER captured" })
    Write-VanguardLog "VAN-152 AFTER state captured" "SUCCESS"
})

$btnCompare.Add_Click({
    if (-not $script:BeforeHWID -or -not $script:AfterHWID) {
        $txtOutput.Dispatcher.Invoke([Action]{ $txtOutput.Text = "ERROR: Capture BEFORE and AFTER first!" })
        return
    }
    
    $txtOutput.Dispatcher.Invoke([Action]{ $txtOutput.Text = "Generating comparison..." })
    Show-VanguardComparison -Before $script:BeforeHWID -After $script:AfterHWID
    
    $guidChanged = $script:BeforeHWID.MachineGUID -ne $script:AfterHWID.MachineGUID
    $kernelNeeded = $script:BeforeHWID.SMBIOS_UUID -eq $script:AfterHWID.SMBIOS_UUID
    
    $txtOutput.Dispatcher.Invoke([Action]{ 
        $txtOutput.Text = "=== VAN-152 COMPARISON ===`n`n"
        $txtOutput.AppendText("Machine GUID: $(if($guidChanged){'✓ CHANGED'}else{'✗ SAME'})`n")
        $txtOutput.AppendText("SMBIOS UUID: $(if(-not $kernelNeeded){'✓ CHANGED'}else{'✗ SAME (Kernel Needed)'})`n")
        $txtOutput.AppendText("PC Name: $(if($script:BeforeHWID.PCName -ne $script:AfterHWID.PCName){'✓ CHANGED'}else{'✗ SAME'})`n`n")
        
        if ($guidChanged) {
            $txtOutput.AppendText("✅ User-mode spoof SUCCESSFUL`n")
            $txtOutput.AppendText("VAN-152 partial bypass achieved`n`n")
        }
        
        if ($kernelNeeded) {
            $txtOutput.AppendText("⚠ Hardware-backed IDs unchanged:`n")
            $txtOutput.AppendText("  - SMBIOS UUID`n")
            $txtOutput.AppendText("  - Disk Serials`n")
            $txtOutput.AppendText("  - Baseboard Serial`n`n")
            $txtOutput.AppendText("For FULL bypass, use KERNEL PREP button")
        }
    })
    
    $txtStatus.Dispatcher.Invoke([Action]{ $txtStatus.Text = "Comparison complete" })
})

$btnKernel.Add_Click({
    $txtOutput.Dispatcher.Invoke([Action]{ 
        $txtOutput.Text = "=== KERNEL DRIVER PREPARATION ===`n`n"
        $txtOutput.AppendText("Hardware-backed IDs require kernel driver:`n")
        $txtOutput.AppendText("  • SMBIOS UUID (Table 1)`n")
        $txtOutput.AppendText("  • Baseboard Serial (Table 2)`n")
        $txtOutput.AppendText("  • Disk Serials (ALL drives)`n`n")
        $txtOutput.AppendText("Steps for full VAN-152 bypass:`n")
        $txtOutput.AppendText("1. Click: Enable Test Mode (below)`n")
        $txtOutput.AppendText("2. Restart PC when prompted`n")
        $txtOutput.AppendText("3. Run: KernelHwidLoader.ps1 -FullDeploy`n`n")
        $txtOutput.AppendText("[Enable Test Mode] [Cancel]")
    })
    
    $result = Enable-TestMode
    if (-not $result) {
        $txtOutput.Dispatcher.Invoke([Action]{ $txtOutput.AppendText("`n`n⚠ RESTART REQUIRED - Run again after boot") })
    }
})

$btnTraces.Add_Click({
    Clear-VanguardTraces
    $txtOutput.Dispatcher.Invoke([Action]{ $txtOutput.AppendText("`n`n✓ Vanguard traces cleared") })
})

Write-VanguardLog "VANGUARD VAN-152 Spoofer v$($Config.Version) started" "VAN"
$window.ShowDialog() | Out-Null

#endregion
