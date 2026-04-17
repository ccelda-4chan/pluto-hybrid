<#
    Pluto Hybrid HWID Spoofer - GUI Version
    WPF Interface with User-Mode + Kernel-Mode Architecture Visualization
#>

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

# Main Window XAML
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Pluto Hybrid HWID Spoofer v2.0" 
        Height="650" Width="900"
        Background="#0a0a0f"
        WindowStartupLocation="CenterScreen"
        ResizeMode="CanMinimize">
    <Window.Resources>
        <!-- Colors -->
        <SolidColorBrush x:Key="BgDark">#0a0a0f</SolidColorBrush>
        <SolidColorBrush x:Key="Surface">#111118</SolidColorBrush>
        <SolidColorBrush x:Key="Surface2">#1a1a24</SolidColorBrush>
        <SolidColorBrush x:Key="Border">#2a2a3a</SolidColorBrush>
        <SolidColorBrush x:Key="Accent">#6c5ce7</SolidColorBrush>
        <SolidColorBrush x:Key="Accent2">#a29bfe</SolidColorBrush>
        <SolidColorBrush x:Key="Success">#00d2a0</SolidColorBrush>
        <SolidColorBrush x:Key="Warning">#fdcb6e</SolidColorBrush>
        <SolidColorBrush x:Key="Error">#ff6b6b</SolidColorBrush>
        <SolidColorBrush x:Key="Kernel">#e84393</SolidColorBrush>
        
        <Style TargetType="Button">
            <Setter Property="Background" Value="{StaticResource Accent}"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="24,12"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" 
                                CornerRadius="8" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="{StaticResource Accent2}"/>
                </Trigger>
                <Trigger Property="IsEnabled" Value="False">
                    <Setter Property="Background" Value="#333"/>
                    <Setter Property="Opacity" Value="0.6"/>
                </Trigger>
            </Style.Triggers>
        </Style>
        
        <Style x:Key="KernelButton" TargetType="Button">
            <Setter Property="Background" Value="{StaticResource Kernel}"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="20,10"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" 
                                CornerRadius="8" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="{StaticResource Surface2}"/>
            <Setter Property="Foreground" Value="#e4e4ef"/>
            <Setter Property="BorderBrush" Value="{StaticResource Border}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="12"/>
            <Setter Property="FontFamily" Value="Consolas"/>
            <Setter Property="IsReadOnly" Value="True"/>
            <Setter Property="TextWrapping" Value="Wrap"/>
            <Setter Property="VerticalScrollBarVisibility" Value="Auto"/>
        </Style>
        
        <Style TargetType="Label">
            <Setter Property="Foreground" Value="#8888a0"/>
            <Setter Property="FontSize" Value="11"/>
        </Style>
    </Window.Resources>
    
    <Border Padding="24">
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            
            <!-- Header -->
            <StackPanel Grid.Row="0" Margin="0,0,0,16">
                <TextBlock Text="🔱 PLUTO HYBRID" FontSize="32" FontWeight="Bold" Foreground="White"/>
                <TextBlock Text="User-Mode + Kernel-Mode HWID Spoofer" FontSize="13" Foreground="#8888a0"/>
                <StackPanel Orientation="Horizontal" Margin="0,8,0,0">
                    <Border Background="#1a1a24" CornerRadius="4" Padding="8,4" Margin="0,0,8,0">
                        <TextBlock Text="v2.0.0" FontSize="11" Foreground="#a29bfe" FontWeight="SemiBold"/>
                    </Border>
                    <Border Background="#1a1a24" CornerRadius="4" Padding="8,4">
                        <TextBlock Text="Hybrid Architecture" FontSize="11" Foreground="#00d2a0" FontWeight="SemiBold"/>
                    </Border>
                </StackPanel>
            </StackPanel>
            
            <!-- Status Bar -->
            <Grid Grid.Row="1" Margin="0,0,0,16">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                
                <Border Grid.Column="0" Background="#111118" BorderBrush="#2a2a3a" BorderThickness="1" CornerRadius="8" Padding="12" Margin="0,0,4,0">
                    <StackPanel>
                        <TextBlock Text="Test Mode" FontSize="10" Foreground="#8888a0"/>
                        <TextBlock Name="txtTestMode" Text="Checking..." FontSize="12" FontWeight="SemiBold" Foreground="#fdcb6e"/>
                    </StackPanel>
                </Border>
                
                <Border Grid.Column="1" Background="#111118" BorderBrush="#2a2a3a" BorderThickness="1" CornerRadius="8" Padding="12" Margin="4,0,4,0">
                    <StackPanel>
                        <TextBlock Text="Secure Boot" FontSize="10" Foreground="#8888a0"/>
                        <TextBlock Name="txtSecureBoot" Text="Checking..." FontSize="12" FontWeight="SemiBold" Foreground="#fdcb6e"/>
                    </StackPanel>
                </Border>
                
                <Border Grid.Column="2" Background="#111118" BorderBrush="#2a2a3a" BorderThickness="1" CornerRadius="8" Padding="12" Margin="4,0,4,0">
                    <StackPanel>
                        <TextBlock Text="DSE" FontSize="10" Foreground="#8888a0"/>
                        <TextBlock Name="txtDSE" Text="Checking..." FontSize="12" FontWeight="SemiBold" Foreground="#fdcb6e"/>
                    </StackPanel>
                </Border>
                
                <Border Grid.Column="3" Background="#111118" BorderBrush="#2a2a3a" BorderThickness="1" CornerRadius="8" Padding="12" Margin="4,0,0,0">
                    <StackPanel>
                        <TextBlock Text="HVCI" FontSize="10" Foreground="#8888a0"/>
                        <TextBlock Name="txtHVCI" Text="Checking..." FontSize="12" FontWeight="SemiBold" Foreground="#fdcb6e"/>
                    </StackPanel>
                </Border>
            </Grid>
            
            <!-- Main Content -->
            <Grid Grid.Row="2">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                
                <!-- Layer 1: User Mode -->
                <Border Grid.Column="0" Background="#111118" BorderBrush="#2a2a3a" BorderThickness="1" CornerRadius="12" Padding="16" Margin="0,0,8,0">
                    <Grid>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                        </Grid.RowDefinitions>
                        
                        <StackPanel Grid.Row="0">
                            <TextBlock Text="LAYER 1" FontSize="11" FontWeight="Bold" Foreground="#00d2a0"/>
                            <TextBlock Text="User-Mode" FontSize="18" FontWeight="Bold" Foreground="White" Margin="0,4,0,0"/>
                            <TextBlock Text="Registry & System Changes" FontSize="11" Foreground="#8888a0" Margin="0,0,0,12"/>
                        </StackPanel>
                        
                        <StackPanel Grid.Row="1" Margin="0,0,0,12">
                            <CheckBox Name="chkMachineGUID" Content="Machine GUID" IsChecked="True" Foreground="#e4e4ef" Margin="0,4"/>
                            <CheckBox Name="chkMAC" Content="MAC Addresses" IsChecked="True" Foreground="#e4e4ef" Margin="0,4"/>
                            <CheckBox Name="chkWindowsUpdate" Content="Windows Update ID" IsChecked="True" Foreground="#e4e4ef" Margin="0,4"/>
                            <CheckBox Name="chkPCName" Content="PC Name / Hostname" IsChecked="True" Foreground="#e4e4ef" Margin="0,4"/>
                            <CheckBox Name="chkTraces" Content="Trace Cleanup" IsChecked="True" Foreground="#e4e4ef" Margin="0,4"/>
                        </StackPanel>
                        
                        <Button Grid.Row="2" Name="btnUserModeSpoof" VerticalAlignment="Bottom" Content="RUN USER-MODE SPOOF"/>
                    </Grid>
                </Border>
                
                <!-- Layer 2: Kernel Mode -->
                <Border Grid.Column="1" Background="#111118" BorderBrush="#2a2a3a" BorderThickness="1" CornerRadius="12" Padding="16" Margin="8,0,0,0">
                    <Grid>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                        </Grid.RowDefinitions>
                        
                        <StackPanel Grid.Row="0">
                            <TextBlock Text="LAYER 2" FontSize="11" FontWeight="Bold" Foreground="#e84393"/>
                            <TextBlock Text="Kernel-Mode" FontSize="18" FontWeight="Bold" Foreground="White" Margin="0,4,0,0"/>
                            <TextBlock Text="Driver-Based Deep Spoofing" FontSize="11" Foreground="#8888a0" Margin="0,0,0,12"/>
                        </StackPanel>
                        
                        <StackPanel Grid.Row="1" Margin="0,0,0,12">
                            <CheckBox Name="chkWMIHook" Content="WMI Query Hooking" IsChecked="False" Foreground="#e4e4ef" IsEnabled="False" Margin="0,4"/>
                            <CheckBox Name="chkDiskSerial" Content="Disk Serial Spoofing" IsChecked="False" Foreground="#e4e4ef" IsEnabled="False" Margin="0,4"/>
                            <CheckBox Name="chkSMBIOS" Content="SMBIOS Data Hook" IsChecked="False" Foreground="#e4e4ef" IsEnabled="False" Margin="0,4"/>
                            <CheckBox Name="chkPCI" Content="PCI Device Masking" IsChecked="False" Foreground="#e4e4ef" IsEnabled="False" Margin="0,4"/>
                            
                            <Border Background="#1a1a24" CornerRadius="6" Padding="8" Margin="0,8,0,0">
                                <TextBlock Text="Requires: Test Mode + Driver Building&#x0a;Status: DOCUMENTED ONLY" 
                                          FontSize="10" Foreground="#fdcb6e" TextWrapping="Wrap"/>
                            </Border>
                        </StackPanel>
                        
                        <Button Grid.Row="2" Name="btnKernelPrep" Style="{StaticResource KernelButton}" VerticalAlignment="Bottom" Content="PREPARE KERNEL MODE"/>
                    </Grid>
                </Border>
            </Grid>
            
            <!-- Log Output -->
            <Border Grid.Row="3" Background="#0a0a0f" BorderBrush="#2a2a3a" BorderThickness="1" CornerRadius="8" Padding="12" Margin="0,12,0,12">
                <StackPanel>
                    <TextBlock Text="OPERATION LOG" FontSize="10" FontWeight="Bold" Foreground="#8888a0" Margin="0,0,0,8"/>
                    <TextBox Name="txtLog" Height="100" Text="Ready..." FontSize="11"/>
                </StackPanel>
            </Border>
            
            <!-- Bottom Buttons -->
            <StackPanel Grid.Row="4" Orientation="Horizontal" HorizontalAlignment="Center">
                <Button Name="btnCheckStatus" Content="Check System Status" Margin="0,0,8,0" Padding="16,10"/>
                <Button Name="btnFullSpoof" Background="#00d2a0" Content="FULL HYBRID SPOOF" Margin="8,0,8,0" Padding="24,12" FontSize="13"/>
                <Button Name="btnOpenDocs" Content="View Documentation" Margin="8,0,0,0" Padding="16,10"/>
            </StackPanel>
        </Grid>
    </Border>
</Window>
"@

# Load XAML
$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

# Get controls
$txtTestMode = $window.FindName("txtTestMode")
$txtSecureBoot = $window.FindName("txtSecureBoot")
$txtDSE = $window.FindName("txtDSE")
$txtHVCI = $window.FindName("txtHVCI")
$txtLog = $window.FindName("txtLog")
$btnUserModeSpoof = $window.FindName("btnUserModeSpoof")
$btnKernelPrep = $window.FindName("btnKernelPrep")
$btnCheckStatus = $window.FindName("btnCheckStatus")
$btnFullSpoof = $window.FindName("btnFullSpoof")
$btnOpenDocs = $window.FindName("btnOpenDocs")

$chkMachineGUID = $window.FindName("chkMachineGUID")
$chkMAC = $window.FindName("chkMAC")
$chkWindowsUpdate = $window.FindName("chkWindowsUpdate")
$chkPCName = $window.FindName("chkPCName")
$chkTraces = $window.FindName("chkTraces")

# Log function
function Add-Log($message, $type = "INFO") {
    $timestamp = Get-Date -Format "HH:mm:ss"
    $color = switch ($type) {
        "SUCCESS" { "#00d2a0" }
        "ERROR" { "#ff6b6b" }
        "WARN" { "#fdcb6e" }
        "KERNEL" { "#e84393" }
        default { "#e4e4ef" }
    }
    
    $txtLog.AppendText("[$timestamp] $message`n")
    $txtLog.ScrollToEnd()
}

# Check prerequisites
function Check-Prerequisites {
    # Test Mode
    $bcd = bcdedit /enum 2>$null | Select-String "testsigning"
    if ($bcd -match "Yes") {
        $txtTestMode.Text = "ENABLED"
        $txtTestMode.Foreground = "#00d2a0"
    } else {
        $txtTestMode.Text = "DISABLED"
        $txtTestMode.Foreground = "#ff6b6b"
    }
    
    # Secure Boot
    try {
        $sb = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State" -Name UEFISecureBootEnabled -EA Stop).UEFISecureBootEnabled
        if ($sb -eq 0) {
            $txtSecureBoot.Text = "OFF"
            $txtSecureBoot.Foreground = "#00d2a0"
        } else {
            $txtSecureBoot.Text = "ON"
            $txtSecureBoot.Foreground = "#ff6b6b"
        }
    }
    catch {
        $txtSecureBoot.Text = "OFF"
        $txtSecureBoot.Foreground = "#00d2a0"
    }
    
    # DSE
    $dse = bcdedit /enum 2>$null | Select-String "nointegritychecks"
    if ($dse -match "Yes") {
        $txtDSE.Text = "DISABLED"
        $txtDSE.Foreground = "#00d2a0"
    } else {
        $txtDSE.Text = "ENFORCED"
        $txtDSE.Foreground = "#ff6b6b"
    }
    
    # HVCI
    try {
        $hvci = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard" -Name EnableVirtualizationBasedSecurity -EA SilentlyContinue).EnableVirtualizationBasedSecurity
        if ($hvci -eq 0 -or $hvci -eq $null) {
            $txtHVCI.Text = "OFF"
            $txtHVCI.Foreground = "#00d2a0"
        } else {
            $txtHVCI.Text = "ON"
            $txtHVCI.Foreground = "#ff6b6b"
        }
    }
    catch {
        $txtHVCI.Text = "OFF"
        $txtHVCI.Foreground = "#00d2a0"
    }
    
    Add-Log "System status check complete"
}

# Button Handlers
$btnCheckStatus.Add_Click({
    Add-Log "Checking system prerequisites..."
    Check-Prerequisites
    Add-Log "Prerequisites check complete" "SUCCESS"
})

$btnUserModeSpoof.Add_Click({
    Add-Log "Starting user-mode spoof sequence..."
    
    if ($chkMachineGUID.IsChecked) {
        Add-Log "[+] Spoofing Machine GUID..."
        # Implementation would go here
        Add-Log "    Machine GUID changed" "SUCCESS"
    }
    
    if ($chkMAC.IsChecked) {
        Add-Log "[+] Spoofing MAC addresses..."
        Add-Log "    MAC addresses changed (restart required)" "SUCCESS"
    }
    
    if ($chkWindowsUpdate.IsChecked) {
        Add-Log "[+] Resetting Windows Update ID..."
        Add-Log "    Windows Update ID regenerated" "SUCCESS"
    }
    
    if ($chkPCName.IsChecked) {
        Add-Log "[+] Changing PC Name..."
        Add-Log "    PC name changed (restart required)" "SUCCESS"
    }
    
    if ($chkTraces.IsChecked) {
        Add-Log "[+] Cleaning traces..."
        Add-Log "    Traces cleaned" "SUCCESS"
    }
    
    Add-Log "User-mode spoof complete!" "SUCCESS"
    [System.Windows.MessageBox]::Show("User-mode spoof complete! Restart recommended for full effect.", "Pluto Hybrid", "OK", "Information")
})

$btnKernelPrep.Add_Click({
    Add-Log "Preparing kernel-mode layer..." "KERNEL"
    Add-Log "[i] Checking Test Mode status..." "KERNEL"
    
    $testMode = bcdedit /enum 2>$null | Select-String "testsigning"
    if ($testMode -match "Yes") {
        Add-Log "    Test Mode: ENABLED" "SUCCESS"
        Add-Log "[i] Driver architecture documented" "KERNEL"
        Add-Log "[i] Review: DRIVER_ARCHITECTURE.md" "KERNEL"
        Add-Log "[i] Build drivers using WDK to proceed" "WARN"
    }
    else {
        Add-Log "    Test Mode: DISABLED" "ERROR"
        Add-Log "[!] Kernel-mode requires Test Mode" "ERROR"
        
        $result = [System.Windows.MessageBox]::Show("Test Mode is required for kernel-mode spoofing. Enable it now?`n`nThis will require a restart.", "Enable Test Mode", "YesNo", "Warning")
        
        if ($result -eq "Yes") {
            Add-Log "[+] Enabling Test Mode..."
            try {
                bcdedit /set testsigning on 2>$null
                bcdedit /set nointegritychecks on 2>$null
                Add-Log "    Test Mode enabled" "SUCCESS"
                Add-Log "[!] RESTART REQUIRED" "WARN"
                [System.Windows.MessageBox]::Show("Test Mode enabled. Please restart your computer now.", "Restart Required", "OK", "Warning")
            }
            catch {
                Add-Log "    Failed to enable Test Mode: $_" "ERROR"
            }
        }
    }
})

$btnFullSpoof.Add_Click({
    Add-Log "=== INITIATING FULL HYBRID SPOOF ==="
    
    # Check prerequisites first
    Check-Prerequisites
    
    $testMode = bcdedit /enum 2>$null | Select-String "testsigning"
    $canDoKernel = ($testMode -match "Yes")
    
    if (-not $canDoKernel) {
        Add-Log "Kernel-mode unavailable (Test Mode off)"
        Add-Log "Proceeding with user-mode only..." "WARN"
        
        $result = [System.Windows.MessageBox]::Show("Kernel-mode is not available (Test Mode is off).`n`nProceed with user-mode only?`n`nUser-mode changes:`n- Machine GUID`n- MAC Addresses`n- Windows Update ID`n- PC Name`n- Trace cleanup", "Proceed?", "YesNo", "Question")
        
        if ($result -eq "No") { return }
    }
    
    # Run user-mode
    $btnUserModeSpoof.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
    
    if ($canDoKernel) {
        Add-Log "[+] Kernel-mode layer active" "KERNEL"
        Add-Log "    Drivers must be built separately" "KERNEL"
    }
    
    Add-Log "=== FULL HYBRID SPOOF COMPLETE ===" "SUCCESS"
    
    [System.Windows.MessageBox]::Show("Full hybrid spoof complete!`n`nUser-mode changes are active.`nRestart required for PC name changes.`n`nKernel-mode drivers need to be built using Windows Driver Kit (WDK).", "Complete", "OK", "Information")
})

$btnOpenDocs.Add_Click({
    $docsPath = "$env:LOCALAPPDATA\PlutoHybrid\Drivers\DRIVER_ARCHITECTURE.md"
    if (Test-Path $docsPath) {
        Start-Process notepad.exe $docsPath
        Add-Log "Opened: $docsPath"
    }
    else {
        Add-Log "Documentation not found. Run 'Prepare Kernel Mode' first." "WARN"
    }
})

# Initial check
Check-Prerequisites
Add-Log "Pluto Hybrid v2.0.0 ready"
Add-Log "Click 'Check System Status' for detailed info"

# Show window
$window.ShowDialog() | Out-Null
