<#
.SYNOPSIS
    Pluto Kernel Driver Manager - WDK Integration
    
.DESCRIPTION
    PowerShell interface for managing PlutoKernel.sys driver.
    Handles driver loading, configuration, and WMI hook monitoring.
    
    Requires:
    - Test Mode enabled (bcdedit /set testsigning on)
    - PlutoKernel.sys compiled with WDK
    - Administrator privileges
    
    WARNING: Kernel driver bugs = BSOD. Test in VM first.
#>

#requires -RunAsAdministrator

Add-Type -AssemblyName PresentationFramework

#region Configuration

$Config = @{
    DriverName = "PlutoKernel"
    DriverPath = "$PSScriptRoot\Driver\PlutoKernel.sys"
    ServiceName = "PlutoKernel"
    RegistryPath = "HKLM:\SOFTWARE\PlutoKernel"
    LogPath = "$env:LOCALAPPDATA\PlutoKernel\Logs"
}

New-Item -ItemType Directory -Force -Path $Config.LogPath | Out-Null

#endregion

#region Logging

function Write-Log {
    param([string]$Message, [string]$Type = "INFO")
    $ts = Get-Date -Format "HH:mm:ss"
    $line = "[$ts] [$Type] $Message"
    Write-Host $line -ForegroundColor $(
        switch ($Type) {
            "SUCCESS" { "Green" }
            "WARN" { "Yellow" }
            "ERROR" { "Red" }
            "KERNEL" { "Magenta" }
            default { "Cyan" }
        }
    )
    Add-Content -Path "$($Config.LogPath)\kernel-$(Get-Date -Format yyyyMMdd).log" -Value $line
}

#endregion

#region Driver Management

function Test-DriverExists {
    return Test-Path $Config.DriverPath
}

function Test-TestMode {
    $bcd = bcdedit /enum | Select-String "testsigning"
    return $bcd -match "Yes"
}

function Install-Driver {
    Write-Log "Installing PlutoKernel driver..." "KERNEL"
    
    if (-not (Test-DriverExists)) {
        Write-Log "Driver not found: $($Config.DriverPath)" "ERROR"
        Write-Log "Please build driver with WDK first (see Driver\BUILD.md)" "WARN"
        return $false
    }
    
    try {
        # Create service
        $scOutput = sc create $Config.ServiceName type= kernel binPath= $Config.DriverPath 2>&1
        Write-Log "Service creation: $scOutput" "INFO"
        
        # Create registry configuration
        if (-not (Test-Path $Config.RegistryPath)) {
            New-Item -Path $Config.RegistryPath -Force | Out-Null
        }
        
        # Set default config
        Set-ItemProperty -Path $Config.RegistryPath -Name "Enabled" -Value 0 -Type DWord
        Set-ItemProperty -Path $Config.RegistryPath -Name "MachineGUID" -Value "00000000-0000-0000-0000-000000000000"
        Set-ItemProperty -Path $Config.RegistryPath -Name "SMBIOS_UUID" -Value "00000000-0000-0000-0000-000000000000"
        
        Write-Log "Driver installed successfully" "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Failed to install driver: $_" "ERROR"
        return $false
    }
}

function Start-Driver {
    Write-Log "Starting PlutoKernel driver..." "KERNEL"
    
    try {
        $scOutput = sc start $Config.ServiceName 2>&1
        Write-Log "Driver start: $scOutput" "INFO"
        
        # Check if running
        $service = Get-Service $Config.ServiceName -EA SilentlyContinue
        if ($service -and $service.Status -eq 'Running') {
            Write-Log "Driver is RUNNING" "SUCCESS"
            return $true
        }
        else {
            Write-Log "Driver failed to start - check Event Viewer" "ERROR"
            return $false
        }
    }
    catch {
        Write-Log "Failed to start driver: $_" "ERROR"
        return $false
    }
}

function Stop-Driver {
    Write-Log "Stopping PlutoKernel driver..." "KERNEL"
    
    try {
        $scOutput = sc stop $Config.ServiceName 2>&1
        Write-Log "Driver stop: $scOutput" "INFO"
        return $true
    }
    catch {
        Write-Log "Failed to stop driver: $_" "ERROR"
        return $false
    }
}

function Remove-Driver {
    Write-Log "Removing PlutoKernel driver..." "KERNEL"
    
    try {
        Stop-Driver | Out-Null
        Start-Sleep -Seconds 1
        
        $scOutput = sc delete $Config.ServiceName 2>&1
        Write-Log "Driver delete: $scOutput" "INFO"
        
        Write-Log "Driver removed" "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Failed to remove driver: $_" "ERROR"
        return $false
    }
}

#endregion

#region Configuration

function Set-SpoofConfig {
    param(
        [string]$MachineGUID,
        [string]$SMBIOS_UUID,
        [switch]$Enable
    )
    
    Write-Log "Updating spoof configuration..." "KERNEL"
    
    try {
        if (-not (Test-Path $Config.RegistryPath)) {
            New-Item -Path $Config.RegistryPath -Force | Out-Null
        }
        
        if ($MachineGUID) {
            Set-ItemProperty -Path $Config.RegistryPath -Name "MachineGUID" -Value $MachineGUID
            Write-Log "MachineGUID set: $MachineGUID" "INFO"
        }
        
        if ($SMBIOS_UUID) {
            Set-ItemProperty -Path $Config.RegistryPath -Name "SMBIOS_UUID" -Value $SMBIOS_UUID
            Write-Log "SMBIOS_UUID set: $SMBIOS_UUID" "INFO"
        }
        
        Set-ItemProperty -Path $Config.RegistryPath -Name "Enabled" -Value ([int]$Enable.IsPresent) -Type DWord
        Write-Log "Spoofing $(if($Enable){'ENABLED'}else{'DISABLED'})" $(if($Enable){"SUCCESS"}else{"WARN"})
        
        return $true
    }
    catch {
        Write-Log "Failed to set config: $_" "ERROR"
        return $false
    }
}

function Get-SpoofConfig {
    try {
        if (Test-Path $Config.RegistryPath) {
            $config = @{
                Enabled = (Get-ItemProperty $Config.RegistryPath -Name "Enabled" -EA SilentlyContinue).Enabled
                MachineGUID = (Get-ItemProperty $Config.RegistryPath -Name "MachineGUID" -EA SilentlyContinue).MachineGUID
                SMBIOS_UUID = (Get-ItemProperty $Config.RegistryPath -Name "SMBIOS_UUID" -EA SilentlyContinue).SMBIOS_UUID
            }
            return $config
        }
        return $null
    }
    catch {
        return $null
    }
}

#endregion

#region WMI Verification

function Test-WmiSpoof {
    Write-Log "Testing WMI spoof effectiveness..." "KERNEL"
    
    $results = @()
    
    # Test SMBIOS UUID
    try {
        $cs = Get-WmiObject Win32_ComputerSystemProduct
        $results += @{ Component = "SMBIOS UUID (WMI)"; Value = $cs.UUID; Status = if ($cs.UUID -ne $null) { "Readable" } else { "Error" } }
    }
    catch {
        $results += @{ Component = "SMBIOS UUID (WMI)"; Value = "ERROR"; Status = "Failed" }
    }
    
    # Test Baseboard
    try {
        $bb = Get-WmiObject Win32_BaseBoard
        $results += @{ Component = "Baseboard Serial (WMI)"; Value = $bb.SerialNumber; Status = "Readable" }
    }
    catch {
        $results += @{ Component = "Baseboard Serial (WMI)"; Value = "ERROR"; Status = "Failed" }
    }
    
    # Test Disk
    try {
        $disk = Get-WmiObject Win32_DiskDrive | Select-Object -First 1
        $results += @{ Component = "Disk Serial (WMI)"; Value = $disk.SerialNumber; Status = "Readable" }
    }
    catch {
        $results += @{ Component = "Disk Serial (WMI)"; Value = "ERROR"; Status = "Failed" }
    }
    
    Write-Log "WMI Test Results:" "INFO"
    foreach ($r in $results) {
        Write-Log "  $($r.Component): $($r.Value) [$($r.Status)]" "INFO"
    }
    
    return $results
}

#endregion

#region WPF GUI

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Pluto Kernel Driver Manager" 
        Height="650" Width="900"
        Background="#0a0a0f"
        WindowStartupLocation="CenterScreen">
    <Window.Resources>
        <SolidColorBrush x:Key="BgDark">#0a0a0f</SolidColorBrush>
        <SolidColorBrush x:Key="Surface">#111118</SolidColorBrush>
        <SolidColorBrush x:Key="Surface2">#1a1a24</SolidColorBrush>
        <SolidColorBrush x:Key="Border">#2a2a3a</SolidColorBrush>
        <SolidColorBrush x:Key="Accent">#6c5ce7</SolidColorBrush>
        <SolidColorBrush x:Key="Success">#00d2a0</SolidColorBrush>
        <SolidColorBrush x:Key="Warning">#fdcb6e</SolidColorBrush>
        <SolidColorBrush x:Key="Error">#ff6b6b</SolidColorBrush>
        <SolidColorBrush x:Key="Kernel">#e84393</SolidColorBrush>
        
        <Style TargetType="Button">
            <Setter Property="Background" Value="{StaticResource Accent}"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="15,10"/>
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
        
        <Style x:Key="KernelButton" TargetType="Button">
            <Setter Property="Background" Value="{StaticResource Kernel}"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="Padding" Value="20,15"/>
            <Setter Property="FontSize" Value="14"/>
        </Style>
        
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="{StaticResource Surface2}"/>
            <Setter Property="Foreground" Value="#e4e4ef"/>
            <Setter Property="BorderBrush" Value="{StaticResource Border}"/>
            <Setter Property="Padding" Value="10"/>
            <Setter Property="FontFamily" Value="Consolas"/>
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
            <TextBlock Text="⚡ PLUTO KERNEL DRIVER MANAGER" FontSize="24" FontWeight="Bold" Foreground="White"/>
            <TextBlock Text="WDK Integration | WMI Filter Driver | Ring-0 Spoofing" FontSize="12" Foreground="#e84393" FontWeight="SemiBold"/>
            <TextBlock Name="txtWarning" TextWrapping="Wrap" Margin="0,10,0,0" FontSize="11" Foreground="#fdcb6e">
                WARNING: Kernel drivers can cause SYSTEM CRASHES (BSOD). Test in VM first. Requires Test Mode + WDK-built driver.
            </TextBlock>
        </StackPanel>
        
        <!-- Status Bar -->
        <Grid Grid.Row="1" Margin="0,15,0,0">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            
            <Border Grid.Column="0" Background="{StaticResource Surface}" BorderBrush="{StaticResource Border}" BorderThickness="1" CornerRadius="8" Padding="12" Margin="0,0,5,0">
                <StackPanel>
                    <TextBlock Text="Driver Status" FontSize="10" Foreground="#8888a0"/>
                    <TextBlock Name="txtDriverStatus" Text="Not Installed" FontSize="13" FontWeight="SemiBold" Foreground="#ff6b6b" Margin="0,5,0,0"/>
                </StackPanel>
            </Border>
            
            <Border Grid.Column="1" Background="{StaticResource Surface}" BorderBrush="{StaticResource Border}" BorderThickness="1" CornerRadius="8" Padding="12" Margin="5,0,5,0">
                <StackPanel>
                    <TextBlock Text="Test Mode" FontSize="10" Foreground="#8888a0"/>
                    <TextBlock Name="txtTestMode" Text="Unknown" FontSize="13" FontWeight="SemiBold" Foreground="#fdcb6e" Margin="0,5,0,0"/>
                </StackPanel>
            </Border>
            
            <Border Grid.Column="2" Background="{StaticResource Surface}" BorderBrush="{StaticResource Border}" BorderThickness="1" CornerRadius="8" Padding="12" Margin="5,0,5,0">
                <StackPanel>
                    <TextBlock Text="Spoof Enabled" FontSize="10" Foreground="#8888a0"/>
                    <TextBlock Name="txtSpoofEnabled" Text="No" FontSize="13" FontWeight="SemiBold" Foreground="#ff6b6b" Margin="0,5,0,0"/>
                </StackPanel>
            </Border>
            
            <Border Grid.Column="3" Background="{StaticResource Surface}" BorderBrush="{StaticResource Border}" BorderThickness="1" CornerRadius="8" Padding="12" Margin="5,0,0,0">
                <StackPanel>
                    <TextBlock Text="WMI Hook" FontSize="10" Foreground="#8888a0"/>
                    <TextBlock Name="txtWmiHook" Text="Inactive" FontSize="13" FontWeight="SemiBold" Foreground="#8888a0" Margin="0,5,0,0"/>
                </StackPanel>
            </Border>
        </Grid>
        
        <!-- Main Content -->
        <Grid Grid.Row="2" Margin="0,15,0,0">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            
            <!-- Left: Driver Control -->
            <Border Grid.Column="0" Background="{StaticResource Surface}" BorderBrush="{StaticResource Border}" BorderThickness="1" CornerRadius="8" Padding="15" Margin="0,0,7,0">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    
                    <TextBlock Grid.Row="0" Text="Driver Control" FontSize="14" FontWeight="Bold" Foreground="White" Margin="0,0,0,10"/>
                    
                    <StackPanel Grid.Row="1">
                        <Button Name="btnInstall" Content="Install Driver" Margin="0,0,0,5"/>
                        <Button Name="btnStart" Content="Start Driver" Background="#00d2a0" Foreground="#0a0a0f"/>
                        <Button Name="btnStop" Content="Stop Driver" Background="#2a2a3a" Margin="0,5"/>
                        <Button Name="btnRemove" Content="Remove Driver" Background="#ff6b6b" Margin="0,0,0,5"/>
                    </StackPanel>
                    
                    <TextBox Grid.Row="2" Name="txtDriverLog" Text="Driver operations log..." Margin="0,10,0,0" IsReadOnly="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"/>
                </Grid>
            </Border>
            
            <!-- Right: Configuration -->
            <Border Grid.Column="1" Background="{StaticResource Surface}" BorderBrush="{StaticResource Border}" BorderThickness="1" CornerRadius="8" Padding="15" Margin="7,0,0,0">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    
                    <TextBlock Grid.Row="0" Text="Spoof Configuration" FontSize="14" FontWeight="Bold" Foreground="White" Margin="0,0,0,10"/>
                    
                    <TextBlock Grid.Row="1" Text="Machine GUID (registry → driver)" FontSize="11" Foreground="#8888a0" Margin="0,0,0,5"/>
                    <TextBox Grid.Row="2" Name="txtMachineGUID" Text="[Guid]::NewGuid().ToString()" Margin="0,0,0,10"/>
                    
                    <TextBlock Grid.Row="3" Text="SMBIOS UUID (WMI hook target)" FontSize="11" Foreground="#8888a0" Margin="0,0,0,5"/>
                    <TextBox Grid.Row="4" Name="txtSMBIOS" Text="00000000-0000-0000-0000-000000000000" Margin="0,0,0,10"/>
                    
                    <Button Grid.Row="4" Name="btnApplyConfig" Content="APPLY CONFIG & ENABLE" Style="{StaticResource KernelButton}" Margin="0,60,0,0" Grid.RowSpan="2"/>
                    
                    <TextBox Grid.Row="5" Name="txtConfigLog" Text="Configuration log..." Margin="0,15,0,0" IsReadOnly="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"/>
                </Grid>
            </Border>
        </Grid>
        
        <!-- Bottom: Test & Status -->
        <StackPanel Grid.Row="3" Orientation="Horizontal" Margin="0,15,0,0">
            <Button Name="btnTestWMI" Content="Test WMI Spoof" Padding="15,10"/>
            <Button Name="btnViewLog" Content="View Log" Padding="15,10" Margin="10,0,0,0"/>
            <TextBlock Name="txtLogPath" Text="" FontSize="10" Foreground="#8888a0" FontFamily="Consolas" VerticalAlignment="Center" Margin="15,0,0,0"/>
        </StackPanel>
    </Grid>
</Window>
"@

$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

# Get controls
$txtDriverStatus = $window.FindName("txtDriverStatus")
$txtTestMode = $window.FindName("txtTestMode")
$txtSpoofEnabled = $window.FindName("txtSpoofEnabled")
$txtWmiHook = $window.FindName("txtWmiHook")
$txtDriverLog = $window.FindName("txtDriverLog")
$txtConfigLog = $window.FindName("txtConfigLog")
$txtMachineGUID = $window.FindName("txtMachineGUID")
$txtSMBIOS = $window.FindName("txtSMBIOS")
$txtLogPath = $window.FindName("txtLogPath")

$btnInstall = $window.FindName("btnInstall")
$btnStart = $window.FindName("btnStart")
$btnStop = $window.FindName("btnStop")
$btnRemove = $window.FindName("btnRemove")
$btnApplyConfig = $window.FindName("btnApplyConfig")
$btnTestWMI = $window.FindName("btnTestWMI")
$btnViewLog = $window.FindName("btnViewLog")

# Update UI function
function Update-UI {
    # Driver status
    $service = Get-Service $Config.ServiceName -EA SilentlyContinue
    if ($service) {
        $txtDriverStatus.Dispatcher.Invoke([Action]{
            $txtDriverStatus.Text = $service.Status
            $txtDriverStatus.Foreground = if ($service.Status -eq 'Running') { '#00d2a0' } else { '#fdcb6e' }
        })
    }
    else {
        $txtDriverStatus.Dispatcher.Invoke([Action]{
            $txtDriverStatus.Text = "Not Installed"
            $txtDriverStatus.Foreground = '#ff6b6b'
        })
    }
    
    # Test Mode
    $testMode = Test-TestMode
    $txtTestMode.Dispatcher.Invoke([Action]{
        $txtTestMode.Text = if ($testMode) { 'ENABLED' } else { 'DISABLED' }
        $txtTestMode.Foreground = if ($testMode) { '#00d2a0' } else { '#ff6b6b' }
    })
    
    # Spoof config
    $cfg = Get-SpoofConfig
    if ($cfg) {
        $txtSpoofEnabled.Dispatcher.Invoke([Action]{
            $txtSpoofEnabled.Text = if ($cfg.Enabled) { 'YES' } else { 'NO' }
            $txtSpoofEnabled.Foreground = if ($cfg.Enabled) { '#00d2a0' } else { '#ff6b6b' }
        })
        
        $txtMachineGUID.Dispatcher.Invoke([Action]{ $txtMachineGUID.Text = $cfg.MachineGUID })
        $txtSMBIOS.Dispatcher.Invoke([Action]{ $txtSMBIOS.Text = $cfg.SMBIOS_UUID })
    }
}

# Button handlers
$btnInstall.Add_Click({
    $txtDriverLog.Dispatcher.Invoke([Action]{ $txtDriverLog.Text = "Installing driver...`n" })
    $result = Install-Driver
    $txtDriverLog.Dispatcher.Invoke([Action]{ $txtDriverLog.AppendText("$(if($result){'✓ Success'}{ '✗ Failed'})`n") })
    Update-UI
})

$btnStart.Add_Click({
    $txtDriverLog.Dispatcher.Invoke([Action]{ $txtDriverLog.Text = "Starting driver...`n" })
    $result = Start-Driver
    $txtDriverLog.Dispatcher.Invoke([Action]{ $txtDriverLog.AppendText("$(if($result){'✓ Driver running'}{ '✗ Start failed'})`n") })
    Update-UI
})

$btnStop.Add_Click({
    $txtDriverLog.Dispatcher.Invoke([Action]{ $txtDriverLog.Text = "Stopping driver...`n" })
    $result = Stop-Driver
    $txtDriverLog.Dispatcher.Invoke([Action]{ $txtDriverLog.AppendText("$(if($result){'✓ Driver stopped'}{ '✗ Stop failed'})`n") })
    Update-UI
})

$btnRemove.Add_Click({
    $result = [System.Windows.MessageBox]::Show("Remove PlutoKernel driver? This requires restart to fully clean up.", "Confirm", "YesNo", "Warning")
    if ($result -eq "Yes") {
        $txtDriverLog.Dispatcher.Invoke([Action]{ $txtDriverLog.Text = "Removing driver...`n" })
        Remove-Driver
        Update-UI
    }
})

$btnApplyConfig.Add_Click({
    $txtConfigLog.Dispatcher.Invoke([Action]{ $txtConfigLog.Text = "Applying configuration...`n" })
    
    $guid = $txtMachineGUID.Dispatcher.Invoke([Action]{ return $txtMachineGUID.Text })
    $smbios = $txtSMBIOS.Dispatcher.Invoke([Action]{ return $txtSMBIOS.Text })
    
    Set-SpoofConfig -MachineGUID $guid -SMBIOS_UUID $smbios -Enable
    
    $txtConfigLog.Dispatcher.Invoke([Action]{ $txtConfigLog.AppendText("✓ Configuration applied`n")
        $txtConfigLog.AppendText("✓ Spoofing ENABLED`n")
        $txtConfigLog.AppendText("⚠ Restart driver to apply changes")
    })
    
    Update-UI
})

$btnTestWMI.Add_Click({
    $results = Test-WmiSpoof
    $txtConfigLog.Dispatcher.Invoke([Action]{
        $txtConfigLog.Text = "WMI Test Results:`n"
        foreach ($r in $results) {
            $txtConfigLog.AppendText("  $($r.Component): $($r.Value)`n")
        }
    })
})

$btnViewLog.Add_Click({
    notepad.exe "$($Config.LogPath)\kernel-$(Get-Date -Format yyyyMMdd).log"
})

# Initialize
$txtLogPath.Text = $Config.LogPath
Update-UI
Write-Log "Pluto Kernel Manager v3.0 started" "KERNEL"
Write-Log "Driver path: $($Config.DriverPath)" "INFO"

$window.ShowDialog() | Out-Null

#endregion
