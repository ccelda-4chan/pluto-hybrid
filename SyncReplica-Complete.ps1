<#
.SYNOPSIS
    SyncReplica-Complete.ps1 - Exact UI/Output Clone of sync.top loader
    
.DESCRIPTION
    Replicates the exact sync.top loader UI shown in screenshot:
    - Process: loader.exe
    - Tabs: Instructions | Driver | Free Trial
    - Status: "Spoof Complete"
    - Output: Baseboard, Disk #1/2, MAC #1 with spoofed values
    
    Screenshot shows kernel-level spoofing (Baseboard + Disk serials changed)
    This requires kernel driver or pre-boot modification.
    
.NOTES
    Version: 3.0.0-Complete
    UI Match: Exact replica of sync.top loader window
#>

#requires -RunAsAdministrator

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

#region Configuration

$Config = @{
    Version = "3.0.0-Complete"
    Title = "loader.exe"
    SpoofedValues = @{
        Baseboard = "123485EE214982"
        Disk1 = "0025_38B5_53A0_93CB."
        Disk2 = "6893_9100_0CF8_4482_0040_4006_0000_0000."
        MAC1 = "N/A"
    }
}

#endregion

#region WPF GUI - Exact sync.top Style

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="loader.exe" 
        Height="500" Width="700"
        Background="#1a1a2e"
        WindowStartupLocation="CenterScreen"
        ResizeMode="CanMinimize">
    <Window.Resources>
        <SolidColorBrush x:Key="BgDark">#1a1a2e</SolidColorBrush>
        <SolidColorBrush x:Key="BgCard">#16213e</SolidColorBrush>
        <SolidColorBrush x:Key="Accent">#0f3460</SolidColorBrush>
        <SolidColorBrush x:Key="Green">#00d9a5</SolidColorBrush>
        <SolidColorBrush x:Key="TextGray">#8b9dc3</SolidColorBrush>
        <SolidColorBrush x:Key="TextWhite">#ffffff</SolidColorBrush>
        
        <Style TargetType="Button">
            <Setter Property="Background" Value="#0f3460"/>
            <Setter Property="Foreground" Value="#8b9dc3"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Padding" Value="15,8"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        
        <Style x:Key="ActiveTab" TargetType="Button">
            <Setter Property="Background" Value="#00d9a5"/>
            <Setter Property="Foreground" Value="#1a1a2e"/>
            <Setter Property="FontWeight" Value="Bold"/>
        </Style>
    </Window.Resources>
    
    <Border Background="#1a1a2e" BorderBrush="#0f3460" BorderThickness="1">
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            
            <!-- Top Bar - Process Info -->
            <Border Grid.Row="0" Background="#0f0f1a" BorderBrush="#0f3460" BorderThickness="0,0,0,1" Padding="10,5">
                <TextBlock Name="txtProcessInfo" 
                           Text="loader.exe    8544    Running    Sam    05    86,712 K    x64    ZYDYRR" 
                           FontFamily="Consolas" FontSize="11" Foreground="#8b9dc3"/>
            </Border>
            
            <!-- Tabs -->
            <StackPanel Grid.Row="1" Orientation="Horizontal" Background="#16213e">
                <Button Name="btnInstructions" Content="Instructions" Style="{StaticResource ActiveTab}"/>
                <Button Name="btnDriver" Content="Driver" Foreground="#8b9dc3"/>
                <Button Name="btnTrial" Content="Free Trial" Foreground="#8b9dc3"/>
            </StackPanel>
            
            <!-- Main Content -->
            <Grid Grid.Row="2" Margin="20">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                
                <!-- Status -->
                <TextBlock Grid.Row="0" 
                           Text="Spoof Complete" 
                           FontSize="24" FontWeight="Bold" 
                           Foreground="#00d9a5" 
                           HorizontalAlignment="Center"
                           Margin="0,20,0,5"/>
                
                <TextBlock Grid.Row="1" 
                           Text="Hardware identifiers successfully modified" 
                           FontSize="12" 
                           Foreground="#8b9dc3" 
                           HorizontalAlignment="Center"
                           Margin="0,0,0,30"/>
                
                <!-- Results Table -->
                <Border Grid.Row="2" Background="#16213e" CornerRadius="8" Padding="20">
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="120"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="35"/>
                            <RowDefinition Height="35"/>
                            <RowDefinition Height="35"/>
                            <RowDefinition Height="35"/>
                        </Grid.RowDefinitions>
                        
                        <!-- Headers -->
                        <TextBlock Grid.Row="0" Grid.Column="0" Text="Baseboard" 
                                   Foreground="#8b9dc3" FontSize="13" VerticalAlignment="Center"/>
                        <TextBlock Grid.Row="0" Grid.Column="1" Name="txtBaseboard" 
                                   Text="123485EE214982" 
                                   Foreground="#ffffff" FontSize="13" FontFamily="Consolas" VerticalAlignment="Center"/>
                        
                        <TextBlock Grid.Row="1" Grid.Column="0" Text="Disk #1" 
                                   Foreground="#8b9dc3" FontSize="13" VerticalAlignment="Center"/>
                        <TextBlock Grid.Row="1" Grid.Column="1" Name="txtDisk1" 
                                   Text="0025_38B5_53A0_93CB." 
                                   Foreground="#ffffff" FontSize="13" FontFamily="Consolas" VerticalAlignment="Center"/>
                        
                        <TextBlock Grid.Row="2" Grid.Column="0" Text="Disk #2" 
                                   Foreground="#8b9dc3" FontSize="13" VerticalAlignment="Center"/>
                        <TextBlock Grid.Row="2" Grid.Column="1" Name="txtDisk2" 
                                   Text="6893_9100_0CF8_4482_0040_4006..." 
                                   Foreground="#ffffff" FontSize="13" FontFamily="Consolas" VerticalAlignment="Center"/>
                        
                        <TextBlock Grid.Row="3" Grid.Column="0" Text="MAC #1" 
                                   Foreground="#8b9dc3" FontSize="13" VerticalAlignment="Center"/>
                        <TextBlock Grid.Row="3" Grid.Column="1" Name="txtMAC1" 
                                   Text="N/A" 
                                   Foreground="#8b9dc3" FontSize="13" FontFamily="Consolas" VerticalAlignment="Center"/>
                    </Grid>
                </Border>
            </Grid>
            
            <!-- Footer -->
            <StackPanel Grid.Row="3" Background="#0f0f1a" Orientation="Horizontal" HorizontalAlignment="Center" Padding="10">
                <TextBlock Text="Copyright 2021–2026 | sync.top" 
                           FontSize="10" Foreground="#5a6a8a"/>
                <TextBlock Text="     Windows 11 (Build 26200)" 
                           FontSize="10" Foreground="#5a6a8a" Margin="20,0,0,0"/>
            </StackPanel>
        </Grid>
    </Border>
</Window>
"@

#endregion

#region Spoof Functions

function Get-RealHWID {
    $hwid = @{}
    
    # Get current values (these are what sync.top is spoofing)
    try {
        $bb = Get-WmiObject Win32_BaseBoard -EA SilentlyContinue
        $hwid.Baseboard = $bb.SerialNumber
    } catch { $hwid.Baseboard = "UNKNOWN" }
    
    try {
        $disks = Get-WmiObject Win32_PhysicalMedia -EA SilentlyContinue
        if ($disks.Count -ge 1) { $hwid.Disk1 = $disks[0].SerialNumber }
        if ($disks.Count -ge 2) { $hwid.Disk2 = $disks[1].SerialNumber }
    } catch { 
        $hwid.Disk1 = "UNKNOWN"
        $hwid.Disk2 = "UNKNOWN"
    }
    
    try {
        $mac = Get-NetAdapter -EA SilentlyContinue | Where-Object { $_.Status -eq 'Up' -and $_.PhysicalMediaType -eq '802.3' } | Select-Object -First 1
        $hwid.MAC1 = if ($mac) { $mac.MacAddress } else { "N/A" }
    } catch { $hwid.MAC1 = "N/A" }
    
    return $hwid
}

function Invoke-SyncSpoof {
    param([switch]$KernelMode)
    
    Write-Host "`n╔══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                    ANALYSIS: sync.top Loader                          ║" -ForegroundColor Cyan
    Write-Host "╠══════════════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
    Write-Host "║                                                                      ║" -ForegroundColor White
    Write-Host "║  Screenshot shows KERNEL-LEVEL spoofing:                            ║" -ForegroundColor Yellow
    Write-Host "║                                                                      ║" -ForegroundColor White
    Write-Host "║  BEFORE (Your Real HWID):                                           ║" -ForegroundColor Gray
    
    $real = Get-RealHWID
    Write-Host "║    Baseboard: $($real.Baseboard)" -ForegroundColor Gray
    Write-Host "║    Disk #1:   $($real.Disk1)" -ForegroundColor Gray
    Write-Host "║    Disk #2:   $($real.Disk2)" -ForegroundColor Gray
    Write-Host "║    MAC #1:    $($real.MAC1)" -ForegroundColor Gray
    Write-Host "║                                                                      ║" -ForegroundColor White
    Write-Host "║  AFTER (sync.top spoofed):                                         ║" -ForegroundColor Green
    Write-Host "║    Baseboard: 123485EE214982 (CHANGED!)" -ForegroundColor Green
    Write-Host "║    Disk #1:   0025_38B5_53A0_93CB. (CHANGED!)" -ForegroundColor Green
    Write-Host "║    Disk #2:   6893_9100_0CF8_4482... (CHANGED!)" -ForegroundColor Green
    Write-Host "║    MAC #1:    N/A (no ethernet)" -ForegroundColor Gray
    Write-Host "║                                                                      ║" -ForegroundColor White
    Write-Host "╠══════════════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
    Write-Host "║  HOW sync.top ACHIEVES THIS:                                         ║" -ForegroundColor Yellow
    Write-Host "║                                                                      ║" -ForegroundColor White
    Write-Host "║  1. Kernel driver loaded via vulnerable driver exploit                ║" -ForegroundColor White
    Write-Host "║     OR pre-boot EFI modification                                     ║" -ForegroundColor White
    Write-Host "║                                                                      ║" -ForegroundColor White
    Write-Host "║  2. Hooks WMI queries at kernel level                                ║" -ForegroundColor White
    Write-Host "║     (Win32_BaseBoard, Win32_PhysicalMedia)                          ║" -ForegroundColor White
    Write-Host "║                                                                      ║" -ForegroundColor White
    Write-Host "║  3. Intercepts disk IOCTLs (IOCTL_STORAGE_QUERY_PROPERTY)            ║" -ForegroundColor White
    Write-Host "║                                                                      ║" -ForegroundColor White
    Write-Host "║  This is NOT registry-only - this is RING-0 kernel spoofing          ║" -ForegroundColor Magenta
    Write-Host "║                                                                      ║" -ForegroundColor White
    Write-Host "╚══════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    
    # Update GUI with real values
    return $real
}

#endregion

#region Main

# Parse XAML
$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

# Get controls
$txtProcessInfo = $window.FindName("txtProcessInfo")
$txtBaseboard = $window.FindName("txtBaseboard")
$txtDisk1 = $window.FindName("txtDisk1")
$txtDisk2 = $window.FindName("txtDisk2")
$txtMAC1 = $window.FindName("txtMAC1")

$btnInstructions = $window.FindName("btnInstructions")
$btnDriver = $window.FindName("btnDriver")
$btnTrial = $window.FindName("btnTrial")

# Set real PID and info
$pidNum = $PID
$mem = (Get-Process -Id $pidNum).WorkingSet64 / 1KB
$txtProcessInfo.Text = "loader.exe    $pidNum    Running    $env:USERNAME    05    $([math]::Round($mem,0)) K    x64    ZYDYRR"

# Get real hardware info
$hwid = Get-RealHWID

# Update display with real values initially
$txtBaseboard.Text = $hwid.Baseboard
$txtDisk1.Text = $hwid.Disk1
if ($hwid.Disk2) { $txtDisk2.Text = $hwid.Disk2 } else { $txtDisk2.Text = "N/A" }
$txtMAC1.Text = $hwid.MAC1

# Button handlers
$btnInstructions.Add_Click({
    # Already on instructions tab
})

$btnDriver.Add_Click({
    [System.Windows.MessageBox]::Show("Kernel driver required for full spoofing.`n`nUse InstantKernel-Spoofer.ps1 for kernel-level spoofing.`n`nOr use PreBootSMBIOS-Spoofer.ps1 for EFI-level modification.", "Driver Required", "OK", "Information")
})

$btnTrial.Add_Click({
    # Simulate spoof after countdown
    $result = [System.Windows.MessageBox]::Show("Start spoofing sequence?`n`nThis will:`n1. Capture current HWID`n2. Show what sync.top does`n3. Demonstrate the difference", "Free Trial", "YesNo", "Question")
    
    if ($result -eq "Yes") {
        # Show analysis
        Invoke-SyncSpoof
        
        # Update GUI to show "spoofed" values
        $txtBaseboard.Dispatcher.Invoke([Action]{ $txtBaseboard.Text = "123485EE214982" })
        $txtBaseboard.Dispatcher.Invoke([Action]{ $txtBaseboard.Foreground = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(0, 217, 165)) })
        
        $txtDisk1.Dispatcher.Invoke([Action]{ $txtDisk1.Text = "0025_38B5_53A0_93CB." })
        $txtDisk1.Dispatcher.Invoke([Action]{ $txtDisk1.Foreground = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(0, 217, 165)) })
        
        $txtDisk2.Dispatcher.Invoke([Action]{ $txtDisk2.Text = "6893_9100_0CF8_4482..." })
        $txtDisk2.Dispatcher.Invoke([Action]{ $txtDisk2.Foreground = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(0, 217, 165)) })
    }
})

# Show window
$window.ShowDialog() | Out-Null

#endregion
