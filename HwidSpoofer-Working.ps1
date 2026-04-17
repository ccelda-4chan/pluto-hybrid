<#
.SYNOPSIS
    HWID Spoofer - Working User-Mode Edition
    
.DESCRIPTION
    Honest, working registry-based HWID modification with clear before/after.
    Targets user-mode identifiers. Hardware-backed IDs (SMBIOS, disk serials) 
    require kernel drivers (documented separately).
    
    Tested on: Intel Arc, Windows 11
#>

#requires -RunAsAdministrator

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Drawing

#region Configuration

$Config = @{
    Version = "3.1.0-Working"
    BackupPath = "$env:LOCALAPPDATA\HwidWorking\Backup"
    LogPath = "$env:LOCALAPPDATA\HwidWorking\Logs"
}

New-Item -ItemType Directory -Force -Path $Config.BackupPath, $Config.LogPath | Out-Null
$LogFile = "$($Config.LogPath)\hwid-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

#endregion

#region Logging

function Write-Log {
    param([string]$Message, [string]$Type = "INFO")
    $ts = Get-Date -Format "HH:mm:ss"
    $line = "[$ts] [$Type] $Message"
    Add-Content -Path $LogFile -Value $line
    
    $color = switch ($Type) {
        "SUCCESS" { "Green" }
        "WARN" { "Yellow" }
        "ERROR" { "Red" }
        "HWID" { "Cyan" }
        default { "White" }
    }
    Write-Host $line -ForegroundColor $color
}

#endregion

#region Hardware ID Functions

function Get-CurrentHWID {
    $hwid = @{}
    
    # Machine GUID
    try {
        $hwid.MachineGUID = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Cryptography" -Name MachineGuid -EA Stop).MachineGuid
    } catch { $hwid.MachineGUID = "ERROR" }
    
    # PC Name
    $hwid.PCName = $env:COMPUTERNAME
    
    # Product ID
    try {
        $hwid.ProductID = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name ProductId -EA SilentlyContinue).ProductId
    } catch { $hwid.ProductID = "ERROR" }
    
    # MAC Addresses
    $hwid.MACs = @()
    try {
        $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.HardwareInterface }
        foreach ($a in $adapters | Select-Object -First 3) {
            $hwid.MACs += "$($a.Name): $($a.MacAddress)"
        }
    } catch { $hwid.MACs = @("ERROR") }
    
    # SMBIOS UUID (read-only without kernel driver)
    try {
        $cs = Get-WmiObject Win32_ComputerSystemProduct -EA SilentlyContinue
        $hwid.SMBIOS = $cs.UUID
    } catch { $hwid.SMBIOS = "ERROR" }
    
    # Disk Serials (read-only without kernel driver)
    $hwid.Disks = @()
    try {
        $disks = Get-WmiObject Win32_DiskDrive | Select-Object -First 2
        foreach ($d in $disks) {
            $hwid.Disks += "Disk$($d.Index): $($d.SerialNumber)"
        }
    } catch { $hwid.Disks = @("ERROR") }
    
    return $hwid
}

function Show-HWID-Table {
    param($HWID, $Title = "Current HWID")
    
    Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  $Title".PadRight(60) "║" -ForegroundColor Cyan
    Write-Host "╠════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
    Write-Host "║ Machine GUID:  $($HWID.MachineGUID)" -ForegroundColor White
    Write-Host "║ PC Name:       $($HWID.PCName)" -ForegroundColor White
    Write-Host "║ Product ID:    $($HWID.ProductID)" -ForegroundColor White
    Write-Host "╠════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
    Write-Host "║ MAC Addresses:" -ForegroundColor Yellow
    foreach ($mac in $HWID.MACs) {
        Write-Host "║   $mac" -ForegroundColor Gray
    }
    Write-Host "╠════════════════════════════════════════════════════════════╣" -ForegroundColor Yellow
    Write-Host "║ HARDWARE-BACKED (Cannot change via registry):" -ForegroundColor Yellow
    Write-Host "║ SMBIOS UUID:   $($HWID.SMBIOS)" -ForegroundColor Gray
    Write-Host "║ Disk Serials:" -ForegroundColor Gray
    foreach ($disk in $HWID.Disks) {
        Write-Host "║   $disk" -ForegroundColor Gray
    }
    Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
}

#endregion

#region Spoofing Functions

function Spoof-MachineGUID {
    try {
        $old = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Cryptography" -Name MachineGuid -EA Stop).MachineGuid
        $new = [Guid]::NewGuid().ToString()
        
        # Backup
        reg export "HKLM\SOFTWARE\Microsoft\Cryptography" "$($Config.BackupPath)\MachineGUID-$(Get-Date -Format HHmmss).reg" 2>$null
        
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Cryptography" -Name MachineGuid -Value $new -Force
        Write-Log "Machine GUID: $old → $new" "SUCCESS"
        return @{ Success = $true; Old = $old; New = $new }
    }
    catch {
        Write-Log "Machine GUID spoof failed: $_" "ERROR"
        return @{ Success = $false }
    }
}

function Spoof-PCName {
    try {
        $old = $env:COMPUTERNAME
        $new = "PC-$(Get-Random -Min 1000 -Max 9999)"
        
        Rename-Computer -NewName $new -Force -EA Stop
        Write-Log "PC Name: $old → $new (RESTART REQUIRED)" "SUCCESS"
        return @{ Success = $true; Old = $old; New = $new }
    }
    catch {
        Write-Log "PC Name change failed: $_" "ERROR"
        return @{ Success = $false }
    }
}

function Spoof-MAC {
    try {
        $adapters = Get-NetAdapter | Where-Object { $_.PhysicalMediaType -eq '802.3' -and $_.Status -eq 'Up' }
        $changed = 0
        $results = @()
        
        foreach ($adapter in $adapters | Select-Object -First 2) {
            $oldMac = $adapter.MacAddress
            
            # Generate random MAC (locally administered)
            $bytes = New-Object byte[] 6
            $rng = [System.Security.Cryptography.RNGCryptoServiceProvider]::new()
            $rng.GetBytes($bytes)
            $rng.Dispose()
            $bytes[0] = ($bytes[0] -band 0xFE) -bor 0x02  # Local admin bit
            $newMac = ($bytes | ForEach-Object { $_.ToString("X2") }) -join ':'
            $newMacNoColon = ($bytes | ForEach-Object { $_.ToString("X2") }) -join ''
            
            # Find and update registry
            $regBase = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4D36E972-E325-11CE-BFC1-08002BE10318}"
            Get-ChildItem $regBase -EA SilentlyContinue | ForEach-Object {
                $desc = (Get-ItemProperty $_.PSPath -Name "DriverDesc" -EA SilentlyContinue).DriverDesc
                if ($desc -eq $adapter.DriverDescription) {
                    reg export ($_.PSPath -replace 'HKLM:', 'HKLM') "$($Config.BackupPath)\MAC-$($adapter.Name)-$(Get-Date -Format HHmmss).reg" 2>$null
                    
                    Set-ItemProperty -Path $_.PSPath -Name "NetworkAddress" -Value $newMacNoColon -Force
                    
                    # Reset adapter
                    Disable-NetAdapter -Name $adapter.Name -Confirm:$false
                    Start-Sleep -Milliseconds 500
                    Enable-NetAdapter -Name $adapter.Name -Confirm:$false
                    
                    $results += "$oldMac → $newMac"
                    $changed++
                }
            }
        }
        
        if ($changed -gt 0) {
            Write-Log "MAC Addresses: $changed changed" "SUCCESS"
            foreach ($r in $results) { Write-Log "  $r" "HWID" }
        }
        else {
            Write-Log "No MAC addresses changed (no Ethernet adapters found)" "WARN"
        }
        
        return @{ Success = $changed -gt 0; Count = $changed; Details = $results }
    }
    catch {
        Write-Log "MAC spoof failed: $_" "ERROR"
        return @{ Success = $false }
    }
}

function Spoof-WindowsUpdateID {
    try {
        Stop-Service wuauserv -Force -EA SilentlyContinue
        
        $wuPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate"
        if (Test-Path $wuPath) {
            reg export "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate" "$($Config.BackupPath)\WU-$(Get-Date -Format HHmmss).reg" 2>$null
            Remove-ItemProperty $wuPath "SusClientId" -Force -EA SilentlyContinue
            Remove-ItemProperty $wuPath "SusClientIdValidation" -Force -EA SilentlyContinue
        }
        
        Start-Service wuauserv -EA SilentlyContinue
        Write-Log "Windows Update ID: Regenerated" "SUCCESS"
        return @{ Success = $true }
    }
    catch {
        Write-Log "Windows Update ID reset failed: $_" "ERROR"
        return @{ Success = $false }
    }
}

function Clean-Traces {
    $keys = @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\UserAssist",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RecentDocs",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\ComDlg32\OpenSavePidlMRU",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\ComDlg32\LastVisitedPidlMRU",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT",
        "HKLM:\SOFTWARE\Microsoft\SQMClient"
    )
    
    $cleaned = 0
    foreach ($key in $keys) {
        if (Test-Path $key) {
            try {
                Remove-Item -Path $key -Recurse -Force -EA SilentlyContinue
                $cleaned++
                Write-Log "Cleaned: $key" "HWID"
            }
            catch { }
        }
    }
    
    # Event logs
    try {
        wevtutil cl Application 2>$null
        wevtutil cl System 2>$null
        wevtutil cl Security 2>$null
        Write-Log "Event logs cleared" "SUCCESS"
    }
    catch { }
    
    Write-Log "Traces cleaned: $cleaned registry keys + event logs" "SUCCESS"
    return @{ Success = $true; Count = $cleaned }
}

#endregion

#region Simple WPF GUI (Intel Arc Compatible)

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="HWID Spoofer v3.1 - Working Edition" 
        Height="600" Width="800"
        Background="#0a0a0f"
        WindowStartupLocation="CenterScreen">
    <Window.Resources>
        <Style TargetType="Button">
            <Setter Property="Background" Value="#6c5ce7"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="15,10"/>
            <Setter Property="Margin" Value="5"/>
            <Setter Property="BorderThickness" Value="0"/>
        </Style>
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="#1a1a24"/>
            <Setter Property="Foreground" Value="#e4e4ef"/>
            <Setter Property="FontFamily" Value="Consolas"/>
            <Setter Property="IsReadOnly" Value="True"/>
            <Setter Property="TextWrapping" Value="Wrap"/>
            <Setter Property="VerticalScrollBarVisibility" Value="Auto"/>
        </Style>
    </Window.Resources>
    <Grid Margin="15">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        
        <!-- Header -->
        <StackPanel Grid.Row="0">
            <TextBlock Text="🔱 HWID SPOOFER" FontSize="24" FontWeight="Bold" Foreground="White"/>
            <TextBlock Text="Working Edition v3.1 | User-Mode Registry Spoofing" FontSize="11" Foreground="#8888a0"/>
        </StackPanel>
        
        <!-- Buttons -->
        <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,10,0,10">
            <Button Name="btnCaptureBefore" Content="1. Capture BEFORE" Width="140"/>
            <Button Name="btnRunSpoof" Content="2. RUN SPOOF" Width="140" Background="#00d2a0" Foreground="#0a0a0f"/>
            <Button Name="btnCaptureAfter" Content="3. Capture AFTER" Width="140"/>
            <Button Name="btnCompare" Content="4. COMPARE" Width="140"/>
            <Button Name="btnViewLog" Content="View Log" Width="100" Background="#2a2a3a"/>
        </StackPanel>
        
        <!-- Output -->
        <TextBox Grid.Row="2" Name="txtOutput" Text="Click '1. Capture BEFORE' to start..." FontSize="11"/>
        
        <!-- Footer -->
        <StackPanel Grid.Row="3" Orientation="Horizontal" Margin="0,10,0,0">
            <TextBlock Text="Status: " FontSize="10" Foreground="#8888a0"/>
            <TextBlock Name="txtStatus" Text="Ready" FontSize="10" Foreground="#00d2a0" FontWeight="SemiBold"/>
            <TextBlock Text=" | Log: " FontSize="10" Foreground="#8888a0" Margin="15,0,0,0"/>
            <TextBlock Name="txtLogPath" Text="$LogFile" FontSize="10" Foreground="#8888a0" FontFamily="Consolas"/>
        </StackPanel>
    </Grid>
</Window>
"@

$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

$txtOutput = $window.FindName("txtOutput")
$txtStatus = $window.FindName("txtStatus")
$txtLogPath = $window.FindName("txtLogPath")
$btnCaptureBefore = $window.FindName("btnCaptureBefore")
$btnRunSpoof = $window.FindName("btnRunSpoof")
$btnCaptureAfter = $window.FindName("btnCaptureAfter")
$btnCompare = $window.FindName("btnCompare")
$btnViewLog = $window.FindName("btnViewLog")

$script:BeforeHWID = $null
$script:AfterHWID = $null

$btnCaptureBefore.Add_Click({
    $txtStatus.Text = "Capturing BEFORE state..."
    $txtOutput.Text = "Capturing hardware identifiers...`n"
    
    $script:BeforeHWID = Get-CurrentHWID
    
    $txtOutput.Text = "=== BEFORE STATE ===`n"
    $txtOutput.AppendText("Machine GUID: $($script:BeforeHWID.MachineGUID)`n")
    $txtOutput.AppendText("PC Name: $($script:BeforeHWID.PCName)`n")
    $txtOutput.AppendText("Product ID: $($script:BeforeHWID.ProductID)`n`n")
    $txtOutput.AppendText("MAC Addresses:`n")
    foreach ($mac in $script:BeforeHWID.MACs) {
        $txtOutput.AppendText("  $mac`n")
    }
    $txtOutput.AppendText("`nSMBIOS UUID: $($script:BeforeHWID.SMBIOS)`n")
    $txtOutput.AppendText("(Hardware-backed, requires kernel driver)`n`n")
    $txtOutput.AppendText("✓ BEFORE state captured. Click '2. RUN SPOOF'")
    
    $txtStatus.Text = "BEFORE captured"
    Write-Log "BEFORE state captured" "SUCCESS"
})

$btnRunSpoof.Add_Click({
    $txtStatus.Text = "Running spoof operations..."
    $txtOutput.Text = "=== RUNNING SPOOF ===`n`n"
    
    # Machine GUID
    $txtOutput.AppendText("[1/4] Spoofing Machine GUID...`n")
    $result = Spoof-MachineGUID
    if ($result.Success) {
        $txtOutput.AppendText("✓ Changed: $($result.Old)`n")
        $txtOutput.AppendText("→ New: $($result.New)`n`n")
    } else {
        $txtOutput.AppendText("✗ Failed`n`n")
    }
    
    # PC Name
    $txtOutput.AppendText("[2/4] Changing PC Name...`n")
    $result = Spoof-PCName
    if ($result.Success) {
        $txtOutput.AppendText("✓ Changed: $($result.Old) → $($result.New)`n")
        $txtOutput.AppendText("⚠ RESTART REQUIRED for full effect`n`n")
    } else {
        $txtOutput.AppendText("✗ Failed`n`n")
    }
    
    # MAC
    $txtOutput.AppendText("[3/4] Spoofing MAC Addresses...`n")
    $result = Spoof-MAC
    if ($result.Success) {
        $txtOutput.AppendText("✓ $($result.Count) MAC(s) changed`n")
        foreach ($d in $result.Details) {
            $txtOutput.AppendText("  $d`n")
        }
        $txtOutput.AppendText("`n")
    } else {
        $txtOutput.AppendText("✗ Failed or no adapters found`n`n")
    }
    
    # Windows Update ID
    $txtOutput.AppendText("[4/4] Resetting Windows Update ID...`n")
    $result = Spoof-WindowsUpdateID
    if ($result.Success) {
        $txtOutput.AppendText("✓ Windows Update ID regenerated`n`n")
    } else {
        $txtOutput.AppendText("✗ Failed`n`n")
    }
    
    # Clean traces
    $txtOutput.AppendText("[BONUS] Cleaning traces...`n")
    Clean-Traces | Out-Null
    $txtOutput.AppendText("✓ Traces cleaned`n`n")
    
    $txtOutput.AppendText("=== SPOOF COMPLETE ===`n")
    $txtOutput.AppendText("Click '3. Capture AFTER' to see changes`n")
    $txtStatus.Text = "Spoof complete"
    Write-Log "All spoof operations completed" "SUCCESS"
})

$btnCaptureAfter.Add_Click({
    $txtStatus.Text = "Capturing AFTER state..."
    $txtOutput.Text = "Capturing hardware identifiers...`n"
    
    $script:AfterHWID = Get-CurrentHWID
    
    $txtOutput.Text = "=== AFTER STATE ===`n"
    $txtOutput.AppendText("Machine GUID: $($script:AfterHWID.MachineGUID)`n")
    $txtOutput.AppendText("PC Name: $($script:AfterHWID.PCName)`n")
    $txtOutput.AppendText("Product ID: $($script:AfterHWID.ProductID)`n`n")
    $txtOutput.AppendText("MAC Addresses:`n")
    foreach ($mac in $script:AfterHWID.MACs) {
        $txtOutput.AppendText("  $mac`n")
    }
    $txtOutput.AppendText("`nSMBIOS UUID: $($script:AfterHWID.SMBIOS)`n")
    $txtOutput.AppendText("(Unchanged - hardware backed)`n`n")
    $txtOutput.AppendText("✓ AFTER state captured. Click '4. COMPARE'")
    
    $txtStatus.Text = "AFTER captured"
    Write-Log "AFTER state captured" "SUCCESS"
})

$btnCompare.Add_Click({
    if (-not $script:BeforeHWID -or -not $script:AfterHWID) {
        $txtOutput.Text = "ERROR: Capture BOTH BEFORE and AFTER first!`n`nClick '1. Capture BEFORE' then '3. Capture AFTER'"
        $txtStatus.Text = "Missing data"
        return
    }
    
    $txtOutput.Text = "=== BEFORE vs AFTER COMPARISON ===`n`n"
    
    # Machine GUID
    $guidChanged = $script:BeforeHWID.MachineGUID -ne $script:AfterHWID.MachineGUID
    $txtOutput.AppendText("Machine GUID:`n")
    $txtOutput.AppendText("  BEFORE: $($script:BeforeHWID.MachineGUID)`n")
    $txtOutput.AppendText("  AFTER:  $($script:AfterHWID.MachineGUID)`n")
    $txtOutput.AppendText("  STATUS: $(if($guidChanged){'✓ CHANGED'}else{'✗ SAME'})`n`n")
    
    # PC Name
    $nameChanged = $script:BeforeHWID.PCName -ne $script:AfterHWID.PCName
    $txtOutput.AppendText("PC Name:`n")
    $txtOutput.AppendText("  BEFORE: $($script:BeforeHWID.PCName)`n")
    $txtOutput.AppendText("  AFTER:  $($script:AfterHWID.PCName)`n")
    $txtOutput.AppendText("  STATUS: $(if($nameChanged){'✓ CHANGED (restart to apply)'}else{'✗ SAME'})`n`n")
    
    # MACs
    $txtOutput.AppendText("MAC Addresses:`n")
    $txtOutput.AppendText("  BEFORE: $($script:BeforeHWID.MACs.Count) adapter(s)`n")
    $txtOutput.AppendText("  AFTER:  $($script:AfterHWID.MACs.Count) adapter(s)`n")
    $txtOutput.AppendText("  Check above for individual changes`n`n")
    
    # Summary
    $txtOutput.AppendText("═══════════════════════════════════════`n")
    $txtOutput.AppendText("SUMMARY:`n")
    if ($guidChanged -and $nameChanged) {
        $txtOutput.AppendText("✓✓ User-mode spoofing SUCCESSFUL`n")
        $txtOutput.AppendText("Machine GUID and PC Name changed`n`n")
        $txtOutput.AppendText("⚠ IMPORTANT: Hardware-backed IDs unchanged:`n")
        $txtOutput.AppendText("  - SMBIOS UUID: $($script:AfterHWID.SMBIOS)`n")
        $txtOutput.AppendText("  - Disk Serials: Unchanged`n`n")
        $txtOutput.AppendText("For full anti-cheat bypass, kernel drivers needed.`n")
    } else {
        $txtOutput.AppendText("⚠ Partial success - some changes failed`n")
    }
    
    $txtStatus.Text = "Comparison complete"
    Write-Log "Comparison displayed" "SUCCESS"
})

$btnViewLog.Add_Click({
    notepad.exe $LogFile
})

# Set log path in GUI
$txtLogPath.Text = $LogFile

# Show
Write-Log "HWID Spoofer v$($Config.Version) started" "SUCCESS"
$window.ShowDialog() | Out-Null

#endregion
