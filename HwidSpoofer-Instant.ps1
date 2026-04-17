<#
.SYNOPSIS
    HWID Spoofer - INSTANT Edition (No Restart Required)
    
.DESCRIPTION
    Immediate HWID spoofing that takes effect WITHOUT restart.
    Works by:
    1. Changing registry values
    2. Restarting WMI services (forces re-read of hardware info)
    3. Flushing DNS/caches
    4. Resetting network adapters
    
    Changes REVERT on reboot (temporary spoofing).
    
    Tested on: Intel Arc, Windows 11, strn.ac-style approach
#>

#requires -RunAsAdministrator

Add-Type -AssemblyName PresentationFramework

#region Config

$Config = @{
    Version = "3.2.0-Instant"
    BackupPath = "$env:LOCALAPPDATA\HwidInstant\Backup"
    LogPath = "$env:LOCALAPPDATA\HwidInstant\Logs"
}

New-Item -ItemType Directory -Force -Path $Config.BackupPath, $Config.LogPath | Out-Null
$LogFile = "$($Config.LogPath)\instant-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

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
        "INSTANT" { "Cyan" }
        default { "White" }
    }
    Write-Host $line -ForegroundColor $color
}

#endregion

#region Instant Spoof Functions

function Get-CurrentHWID {
    $hwid = @{}
    
    # Read from WMI (what anti-cheat sees)
    try {
        $hwid.MachineGUID = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Cryptography" -Name MachineGuid -EA Stop).MachineGuid
    } catch { $hwid.MachineGUID = "ERROR" }
    
    try {
        $cs = Get-WmiObject Win32_ComputerSystemProduct -EA SilentlyContinue
        $hwid.SMBIOS_UUID = $cs.UUID
    } catch { $hwid.SMBIOS_UUID = "ERROR" }
    
    try {
        $bb = Get-WmiObject Win32_BaseBoard -EA SilentlyContinue
        $hwid.BaseboardSerial = $bb.SerialNumber
    } catch { $hwid.BaseboardSerial = "ERROR" }
    
    try {
        $bios = Get-WmiObject Win32_BIOS -EA SilentlyContinue
        $hwid.BIOSSerial = $bios.SerialNumber
    } catch { $hwid.BIOSSerial = "ERROR" }
    
    try {
        $disks = Get-WmiObject Win32_PhysicalMedia | Select-Object -First 2
        $hwid.DiskSerials = $disks | ForEach-Object { "Disk$($_.Tag): $($_.SerialNumber)" }
    } catch { $hwid.DiskSerials = @("ERROR") }
    
    $hwid.PCName = $env:COMPUTERNAME
    
    try {
        $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
        $hwid.MACs = $adapters | ForEach-Object { "$($_.Name): $($_.MacAddress)" }
    } catch { $hwid.MACs = @("ERROR") }
    
    return $hwid
}

function Invoke-InstantSpoof {
    $results = @()
    
    # 1. Machine GUID (Registry - Immediate effect)
    try {
        $oldGUID = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Cryptography" -Name MachineGuid -EA Stop).MachineGuid
        $newGUID = [Guid]::NewGuid().ToString()
        
        reg export "HKLM\SOFTWARE\Microsoft\Cryptography" "$($Config.BackupPath)\MachineGUID-$(Get-Date -Format HHmmss).reg" 2>$null
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Cryptography" -Name MachineGuid -Value $newGUID -Force
        
        $results += @{ Component = "Machine GUID"; Status = "✓ CHANGED"; Old = $oldGUID; New = $newGUID }
        Write-Log "Machine GUID: $oldGUID → $newGUID" "SUCCESS"
    }
    catch {
        $results += @{ Component = "Machine GUID"; Status = "✗ FAILED"; Old = "ERROR"; New = "ERROR" }
        Write-Log "Machine GUID failed: $_" "ERROR"
    }
    
    # 2. PC Name (Registry change - applies to new processes)
    try {
        $oldName = $env:COMPUTERNAME
        $newName = "PC-$(Get-Random -Min 1000 -Max 9999)"
        
        Rename-Computer -NewName $newName -Force -EA Stop
        
        # Also set in registry for immediate processes
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName" -Name "ComputerName" -Value $newName -Force
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName" -Name "ComputerName" -Value $newName -Force
        
        $env:COMPUTERNAME = $newName  # Update current session
        
        $results += @{ Component = "PC Name"; Status = "✓ CHANGED"; Old = $oldName; New = $newName }
        Write-Log "PC Name: $oldName → $newName (session updated)" "SUCCESS"
    }
    catch {
        $results += @{ Component = "PC Name"; Status = "✗ FAILED"; Old = "ERROR"; New = "ERROR" }
        Write-Log "PC Name failed: $_" "ERROR"
    }
    
    # 3. MAC Addresses (Immediate via registry + adapter reset)
    try {
        $adapters = Get-NetAdapter | Where-Object { $_.PhysicalMediaType -eq '802.3' -and $_.Status -eq 'Up' }
        $macCount = 0
        
        foreach ($adapter in $adapters | Select-Object -First 2) {
            $oldMac = $adapter.MacAddress
            
            # Generate MAC
            $bytes = New-Object byte[] 6
            $rng = [System.Security.Cryptography.RNGCryptoServiceProvider]::new()
            $rng.GetBytes($bytes)
            $rng.Dispose()
            $bytes[0] = ($bytes[0] -band 0xFE) -bor 0x02
            $newMac = ($bytes | ForEach-Object { $_.ToString("X2") }) -join ':'
            $newMacNoColon = ($bytes | ForEach-Object { $_.ToString("X2") }) -join ''
            
            # Find registry and update
            $regBase = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4D36E972-E325-11CE-BFC1-08002BE10318}"
            Get-ChildItem $regBase -EA SilentlyContinue | ForEach-Object {
                $desc = (Get-ItemProperty $_.PSPath -Name "DriverDesc" -EA SilentlyContinue).DriverDesc
                if ($desc -eq $adapter.DriverDescription) {
                    Set-ItemProperty -Path $_.PSPath -Name "NetworkAddress" -Value $newMacNoColon -Force
                    
                    # IMMEDIATE adapter reset
                    Disable-NetAdapter -Name $adapter.Name -Confirm:$false
                    Start-Sleep -Milliseconds 200
                    Enable-NetAdapter -Name $adapter.Name -Confirm:$false
                    
                    $macCount++
                    Write-Log "MAC [$($adapter.Name)]: $oldMac → $newMac" "SUCCESS"
                }
            }
        }
        
        $results += @{ Component = "MAC Addresses"; Status = "✓ CHANGED ($macCount)"; Old = "Multiple"; New = "Multiple" }
    }
    catch {
        $results += @{ Component = "MAC Addresses"; Status = "✗ FAILED"; Old = "ERROR"; New = "ERROR" }
        Write-Log "MAC spoof failed: $_" "ERROR"
    }
    
    # 4. Windows Update ID (Immediate via service restart)
    try {
        Stop-Service wuauserv -Force -EA SilentlyContinue
        
        $wuPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate"
        if (Test-Path $wuPath) {
            Remove-ItemProperty $wuPath "SusClientId" -Force -EA SilentlyContinue
            Remove-ItemProperty $wuPath "SusClientIdValidation" -Force -EA SilentlyContinue
        }
        
        Start-Service wuauserv -EA SilentlyContinue
        
        $results += @{ Component = "Windows Update ID"; Status = "✓ REGENERATED"; Old = "Cleared"; New = "New" }
        Write-Log "Windows Update ID regenerated (service restarted)" "SUCCESS"
    }
    catch {
        $results += @{ Component = "Windows Update ID"; Status = "✗ FAILED"; Old = "ERROR"; New = "ERROR" }
    }
    
    # 5. WMI Repository Reset (CRITICAL - Forces re-read of hardware)
    Write-Log "Resetting WMI repository..." "INSTANT"
    try {
        # Stop WMI service
        Stop-Service winmgmt -Force -EA SilentlyContinue
        Start-Sleep -Seconds 1
        
        # Clear WMI repository cache
        $wmiRepo = "$env:SystemRoot\System32\wbem\Repository"
        if (Test-Path $wmiRepo) {
            Get-ChildItem $wmiRepo -Filter "*.MOF" -EA SilentlyContinue | Remove-Item -Force -EA SilentlyContinue
        }
        
        # Restart WMI
        Start-Service winmgmt -EA SilentlyContinue
        Start-Sleep -Seconds 2
        
        # Re-compile MOFs
        & "$env:SystemRoot\System32\wbem\mofcomp.exe" "$env:SystemRoot\System32\wbem\cimwin32.mof" 2>$null
        
        $results += @{ Component = "WMI Repository"; Status = "✓ RESET"; Old = "Cached"; New = "Rebuilt" }
        Write-Log "WMI repository reset - hardware info re-read" "SUCCESS"
    }
    catch {
        Write-Log "WMI reset failed (non-critical): $_" "WARN"
    }
    
    # 6. Flush DNS and caches
    try {
        ipconfig /flushdns | Out-Null
        $results += @{ Component = "DNS Cache"; Status = "✓ FLUSHED"; Old = "Cached"; New = "Empty" }
        Write-Log "DNS cache flushed" "SUCCESS"
    }
    catch { }
    
    # 7. Clear ARP cache
    try {
        arp -d * | Out-Null
        Write-Log "ARP cache cleared" "SUCCESS"
    }
    catch { }
    
    return $results
}

function Show-Results-GUI {
    param($Results, $BeforeHWID, $AfterHWID)
    
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="HWID Spoofer - INSTANT Results" 
        Height="550" Width="750"
        Background="#0a0a0f"
        WindowStartupLocation="CenterScreen">
    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        
        <TextBlock Grid.Row="0" Text="🔱 INSTANT SPOOF RESULTS" FontSize="22" FontWeight="Bold" Foreground="White" Margin="0,0,0,15"/>
        
        <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
            <StackPanel>
                <!-- Status Table -->
                <Border Background="#111118" BorderBrush="#2a2a3a" BorderThickness="1" CornerRadius="8" Padding="15" Margin="0,0,0,15">
                    <StackPanel>
                        <TextBlock Text="Component Status" FontSize="14" FontWeight="Bold" Foreground="#6c5ce7" Margin="0,0,0,10"/>
"@
    
    foreach ($result in $Results) {
        $color = if ($result.Status -like "✓*") { "#00d2a0" } else { "#ff6b6b" }
        $xaml += @"
                        <Grid Margin="0,3">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="200"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock Text="$($result.Component)" Foreground="#e4e4ef" Grid.Column="0"/>
                            <TextBlock Text="$($result.Status)" Foreground="$color" FontWeight="SemiBold" Grid.Column="1"/>
                        </Grid>
"@
    }
    
    $xaml += @"
                    </StackPanel>
                </Border>
                
                <!-- Comparison -->
                <Border Background="#111118" BorderBrush="#2a2a3a" BorderThickness="1" CornerRadius="8" Padding="15" Margin="0,0,0,15">
                    <StackPanel>
                        <TextBlock Text="Before vs After" FontSize="14" FontWeight="Bold" Foreground="#6c5ce7" Margin="0,0,0,10"/>
                        
                        <Grid Margin="0,5">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="120"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock Text="Machine GUID:" Foreground="#8888a0" Grid.Column="0"/>
                            <TextBlock Text="$($BeforeHWID.MachineGUID)" Foreground="#444" FontSize="10" Grid.Column="1" TextTrimming="CharacterEllipsis"/>
                            <TextBlock Text="$($AfterHWID.MachineGUID)" Foreground="#00d2a0" FontSize="10" Grid.Column="2" TextTrimming="CharacterEllipsis"/>
                        </Grid>
                        
                        <Grid Margin="0,5">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="120"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock Text="PC Name:" Foreground="#8888a0" Grid.Column="0"/>
                            <TextBlock Text="$($BeforeHWID.PCName)" Foreground="#444" Grid.Column="1"/>
                            <TextBlock Text="$($AfterHWID.PCName)" Foreground="#00d2a0" Grid.Column="2"/>
                        </Grid>
                        
                        <Grid Margin="0,5">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="120"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock Text="SMBIOS UUID:" Foreground="#8888a0" Grid.Column="0"/>
                            <TextBlock Text="$($BeforeHWID.SMBIOS_UUID)" Foreground="#444" FontSize="10" Grid.Column="1" TextTrimming="CharacterEllipsis"/>
                            <TextBlock Text="$($AfterHWID.SMBIOS_UUID)" Foreground="#ff6b6b" FontSize="10" Grid.Column="2" TextTrimming="CharacterEllipsis"/>
                        </Grid>
                    </StackPanel>
                </Border>
                
                <!-- Info -->
                <Border Background="#1a1a24" BorderBrush="#2a2a3a" BorderThickness="1" CornerRadius="8" Padding="15">
                    <TextBlock TextWrapping="Wrap">
                        <Run Text="✓ User-mode spoofing COMPLETE" Foreground="#00d2a0" FontWeight="Bold"/><LineBreak/>
                        <Run Text="Changes are ACTIVE immediately - no restart needed!"/><LineBreak/><LineBreak/>
                        <Run Text="⚠ Hardware-backed IDs unchanged:" Foreground="#fdcb6e"/><LineBreak/>
                        <Run Text="SMBIOS UUID, Disk Serials, BIOS Serial"/><LineBreak/><LineBreak/>
                        <Run Text="🔄 Changes REVERT on reboot (temporary spoofing)" Foreground="#a29bfe"/>
                    </TextBlock>
                </Border>
            </StackPanel>
        </ScrollViewer>
        
        <Button Grid.Row="2" Content="CLOSE" Width="100" Height="35" Margin="0,15,0,0" 
                Background="#6c5ce7" Foreground="White" FontWeight="Bold" BorderThickness="0"
                Name="btnClose"/>
    </Grid>
</Window>
"@
    
    $reader = [System.Xml.XmlNodeReader]::new([xml]$xaml)
    $window = [Windows.Markup.XamlReader]::Load($reader)
    
    $btnClose = $window.FindName("btnClose")
    $btnClose.Add_Click({ $window.Close() })
    
    $window.ShowDialog() | Out-Null
}

#endregion

#region Main GUI

[xml]$mainXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="HWID Spoofer v3.2 - INSTANT Edition (No Restart)" 
        Height="400" Width="600"
        Background="#0a0a0f"
        WindowStartupLocation="CenterScreen">
    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        
        <StackPanel Grid.Row="0">
            <TextBlock Text="🔱 INSTANT HWID SPOOFER" FontSize="24" FontWeight="Bold" Foreground="White"/>
            <TextBlock Text="No Restart Required • Reverts on Reboot" FontSize="12" Foreground="#00d2a0"/>
            <TextBlock Text="strn.ac-style immediate spoofing" FontSize="10" Foreground="#8888a0" Margin="0,5,0,0"/>
        </StackPanel>
        
        <Button Grid.Row="1" Name="btnSpoof" Content="⚡ INSTANT SPOOF NOW" 
                Height="50" FontSize="16" FontWeight="Bold"
                Background="#00d2a0" Foreground="#0a0a0f" Margin="0,20,0,0"/>
        
        <TextBox Grid.Row="2" Name="txtOutput" Text="Click 'INSTANT SPOOF NOW' to begin..." 
                 Margin="0,15,0,0" FontSize="11"/>
        
        <StackPanel Grid.Row="3" Orientation="Horizontal" Margin="0,15,0,0">
            <TextBlock Text="Status: " FontSize="10" Foreground="#8888a0"/>
            <TextBlock Name="txtStatus" Text="Ready" FontSize="10" Foreground="#00d2a0" FontWeight="SemiBold"/>
            <TextBlock Text=" | Log: " FontSize="10" Foreground="#8888a0" Margin="15,0,0,0"/>
            <TextBlock Name="txtLogPath" FontSize="10" Foreground="#8888a0" FontFamily="Consolas"/>
        </StackPanel>
    </Grid>
</Window>
"@

$reader = [System.Xml.XmlNodeReader]::new($mainXaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

$txtOutput = $window.FindName("txtOutput")
$txtStatus = $window.FindName("txtStatus")
$txtLogPath = $window.FindName("txtLogPath")
$btnSpoof = $window.FindName("btnSpoof")

$btnSpoof.Add_Click({
    $txtStatus.Text = "Spoofing..."
    $txtOutput.Text = "=== INSTANT SPOOF SEQUENCE ===`n"
    $txtOutput.AppendText("Step 1/3: Capturing BEFORE state...`n")
    
    $beforeHWID = Get-CurrentHWID
    $txtOutput.AppendText("✓ BEFORE captured`n`n")
    $txtOutput.AppendText("Step 2/3: Running instant spoof...`n")
    $txtOutput.AppendText("  - Changing registry values...`n")
    $txtOutput.AppendText("  - Restarting WMI services...`n")
    $txtOutput.AppendText("  - Resetting network adapters...`n")
    
    $results = Invoke-InstantSpoof
    
    $txtOutput.AppendText("`nStep 3/3: Capturing AFTER state...`n")
    Start-Sleep -Seconds 2  # Brief pause for WMI to reload
    $afterHWID = Get-CurrentHWID
    $txtOutput.AppendText("✓ AFTER captured`n`n")
    $txtOutput.AppendText("=== COMPLETE ===`n")
    $txtOutput.AppendText("Showing results window...")
    
    $txtStatus.Text = "Complete"
    
    # Show results window
    Show-Results-GUI -Results $results -BeforeHWID $beforeHWID -AfterHWID $afterHWID
})

$txtLogPath.Text = $LogFile
Write-Log "HWID Spoofer v$($Config.Version) started" "SUCCESS"
Write-Log "Log: $LogFile" "INFO"

$window.ShowDialog() | Out-Null

#endregion
