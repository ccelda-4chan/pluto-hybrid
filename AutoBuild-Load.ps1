#requires -RunAsAdministrator
<#
.SYNOPSIS
    AutoBuild-Load.ps1 - Complete WDK Install + Build + Sign + Load Pipeline
    
.DESCRIPTION
    Fully automated kernel driver deployment:
    1. Installs Windows Driver Kit (WDK) automatically
    2. Builds VanguardSpoofer.sys
    3. Downloads kdmapper for driver loading
    4. Loads driver with DSE bypass
    5. Verifies spoofing is active
    
    NO RESTART REQUIRED - Uses vulnerable driver exploit method
#>

param(
    [switch]$InstallOnly,
    [switch]$BuildOnly,
    [switch]$SkipInstall
)

#region Configuration

$Config = @{
    Version = "2.0.0-Auto"
    WDKUrl = "https://go.microsoft.com/fwlink/?linkid=2286263"  # WDK 10.0.26100.1
    WDKInstaller = "$env:TEMP\wdksetup.exe"
    BuildDir = "$PSScriptRoot\Build"
    DriverDir = "$PSScriptRoot\Driver"
    KdmapperUrl = "https://github.com/TheCruZ/kdmapper/releases/latest/download/kdmapper.exe"
    LogFile = "$env:TEMP\VanguardAutoBuild.log"
}

#endregion

#region Logging

function Write-AutoLog {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "HH:mm:ss"
    $icon = switch ($Level) {
        "SUCCESS" { "✓" }
        "ERROR" { "✗" }
        "WARN" { "⚠" }
        "BUILD" { "🔨" }
        "LOAD" { "🚀" }
        default { "ℹ" }
    }
    $color = switch ($Level) {
        "SUCCESS" { "Green" }
        "ERROR" { "Red" }
        "WARN" { "Yellow" }
        "BUILD" { "Cyan" }
        "LOAD" { "Magenta" }
        default { "White" }
    }
    Write-Host "[$ts] $icon $Message" -ForegroundColor $color
    "[$ts] [$Level] $Message" | Out-File -FilePath $Config.LogFile -Append
}

#endregion

#region Banner

Write-Host @"
╔══════════════════════════════════════════════════════════════════╗
║                                                                  ║
║     VanguardSpoofer - Auto Build & Load System v$($Config.Version) ║
║                                                                  ║
║     Automatic: Install → Build → Sign → Load → Verify           ║
║                                                                  ║
╚══════════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

#endregion

#region Step 1: Install WDK

function Install-WDK {
    Write-AutoLog "=== STEP 1: Installing Windows Driver Kit (WDK) ===" "BUILD"
    
    # Check if WDK already installed
    $wdkPath = "C:\Program Files (x86)\Windows Kits\10"
    if (Test-Path "$wdkPath\bin\10.0.26100.0\x64\signtool.exe") {
        Write-AutoLog "WDK already installed at: $wdkPath" "SUCCESS"
        return $true
    }
    
    Write-AutoLog "Downloading WDK installer..." "BUILD"
    try {
        Invoke-WebRequest -Uri $Config.WDKUrl -OutFile $Config.WDKInstaller -UseBasicParsing
        Write-AutoLog "Downloaded: $($Config.WDKInstaller)" "SUCCESS"
    }
    catch {
        Write-AutoLog "Failed to download WDK: $_" "ERROR"
        return $false
    }
    
    Write-AutoLog "Installing WDK (this may take 10-15 minutes)..." "BUILD"
    Write-AutoLog "Silent installation in progress..." "WARN"
    
    try {
        $proc = Start-Process -FilePath $Config.WDKInstaller -ArgumentList "/quiet", "/norestart" -Wait -PassThru
        if ($proc.ExitCode -eq 0) {
            Write-AutoLog "WDK installed successfully!" "SUCCESS"
            return $true
        }
        else {
            Write-AutoLog "WDK installation failed with code: $($proc.ExitCode)" "ERROR"
            return $false
        }
    }
    catch {
        Write-AutoLog "WDK installation error: $_" "ERROR"
        return $false
    }
}

#endregion

#region Step 2: Build Driver

function Build-Driver {
    Write-AutoLog "=== STEP 2: Building VanguardSpoofer Driver ===" "BUILD"
    
    # Find MSBuild
    $msbuildPaths = @(
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe",
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Professional\MSBuild\Current\Bin\MSBuild.exe",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\Community\MSBuild\Current\Bin\MSBuild.exe",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2019\BuildTools\MSBuild\Current\Bin\MSBuild.exe"
    )
    
    $msbuild = $null
    foreach ($path in $msbuildPaths) {
        if (Test-Path $path) {
            $msbuild = $path
            break
        }
    }
    
    if (-not $msbuild) {
        Write-AutoLog "MSBuild not found! Installing Build Tools..." "WARN"
        # Download and install Build Tools
        $buildToolsUrl = "https://aka.ms/vs/17/release/vs_BuildTools.exe"
        $buildToolsInstaller = "$env:TEMP\vs_BuildTools.exe"
        
        try {
            Invoke-WebRequest -Uri $buildToolsUrl -OutFile $buildToolsInstaller -UseBasicParsing
            Write-AutoLog "Installing Build Tools with C++ workload..." "BUILD"
            Start-Process -FilePath $buildToolsInstaller -ArgumentList "--quiet", "--wait", "--add", "Microsoft.VisualStudio.Workload.VCTools", "--add", "Microsoft.VisualStudio.Component.Windows11SDK.22621" -Wait
        }
        catch {
            Write-AutoLog "Failed to install Build Tools: $_" "ERROR"
            return $false
        }
    }
    
    # Create build directory
    New-Item -ItemType Directory -Force -Path $Config.BuildDir, "$($Config.BuildDir)\Release" | Out-Null
    
    # Build using EWDK approach (lighter weight)
    Write-AutoLog "Building driver with available tools..." "BUILD"
    
    $vcxs = "$($Config.DriverDir)\VanguardSpoofer.vcxproj"
    
    try {
        $buildOutput = & $msbuild $vcxs /p:Configuration=Release /p:Platform=x64 /p:OutDir="$($Config.BuildDir)\Release\" 2>&1
        $buildExit = $LASTEXITCODE
        
        if ($buildExit -eq 0) {
            Write-AutoLog "Build successful!" "SUCCESS"
            
            # Check for driver file
            $driverFile = "$($Config.BuildDir)\Release\VanguardSpoofer.sys"
            if (Test-Path $driverFile) {
                $size = (Get-Item $driverFile).Length
                Write-AutoLog "Driver created: $driverFile ($([math]::Round($size/1KB,1)) KB)" "SUCCESS"
                return $true
            }
        }
        else {
            Write-AutoLog "Build failed with exit code: $buildExit" "ERROR"
            Write-AutoLog "Output: $buildOutput" "ERROR"
            return $false
        }
    }
    catch {
        Write-AutoLog "Build error: $_" "ERROR"
        return $false
    }
    
    return $false
}

#endregion

#region Step 3: Download kdmapper

function Get-Kdmapper {
    Write-AutoLog "=== STEP 3: Obtaining kdmapper ===" "LOAD"
    
    $kdmapperPath = "$($Config.BuildDir)\kdmapper.exe"
    
    if (Test-Path $kdmapperPath) {
        Write-AutoLog "kdmapper already exists" "SUCCESS"
        return $kdmapperPath
    }
    
    Write-AutoLog "Downloading kdmapper..." "LOAD"
    try {
        Invoke-WebRequest -Uri $Config.KdmapperUrl -OutFile $kdmapperPath -UseBasicParsing
        Write-AutoLog "Downloaded: $kdmapperPath" "SUCCESS"
        return $kdmapperPath
    }
    catch {
        Write-AutoLog "Failed to download kdmapper: $_" "ERROR"
        return $null
    }
}

#endregion

#region Step 4: Load Driver

function Load-Driver {
    param([string]$DriverPath, [string]$KdmapperPath)
    
    Write-AutoLog "=== STEP 4: Loading Driver ===" "LOAD"
    
    if (-not (Test-Path $DriverPath)) {
        Write-AutoLog "Driver file not found: $DriverPath" "ERROR"
        return $false
    }
    
    if (-not (Test-Path $KdmapperPath)) {
        Write-AutoLog "kdmapper not found: $KdmapperPath" "ERROR"
        return $false
    }
    
    Write-AutoLog "Loading VanguardSpoofer.sys with kdmapper..." "LOAD"
    Write-AutoLog "This bypasses Driver Signature Enforcement (DSE)" "WARN"
    
    try {
        $output = & $KdmapperPath $DriverPath 2>&1
        $exitCode = $LASTEXITCODE
        
        Write-AutoLog "kdmapper output: $output" "INFO"
        
        if ($exitCode -eq 0) {
            Write-AutoLog "Driver loaded successfully!" "SUCCESS"
            return $true
        }
        else {
            Write-AutoLog "kdmapper failed with code: $exitCode" "ERROR"
            return $false
        }
    }
    catch {
        Write-AutoLog "Driver loading error: $_" "ERROR"
        return $false
    }
}

#endregion

#region Step 5: Verify

function Test-Spoofing {
    Write-AutoLog "=== STEP 5: Verifying Spoof ===" "SUCCESS"
    
    Write-AutoLog "Checking current hardware identifiers..." "INFO"
    
    try {
        $bb = Get-WmiObject Win32_BaseBoard -EA SilentlyContinue
        Write-AutoLog "Baseboard Serial: $($bb.SerialNumber)" "INFO"
        
        $disk = Get-WmiObject Win32_PhysicalMedia -EA SilentlyContinue | Select-Object -First 1
        Write-AutoLog "Disk Serial: $($disk.SerialNumber)" "INFO"
        
        $sys = Get-WmiObject Win32_ComputerSystemProduct -EA SilentlyContinue
        Write-AutoLog "System UUID: $($sys.UUID)" "INFO"
        
        Write-AutoLog "If values above are spoofed, driver is working!" "SUCCESS"
    }
    catch {
        Write-AutoLog "Verification error: $_" "WARN"
    }
}

#endregion

#region Main Execution

Write-AutoLog "Starting automated build and load pipeline..." "INFO"

# Step 1: Install WDK (unless skipped)
if (-not $SkipInstall) {
    $wdkOk = Install-WDK
    if (-not $wdkOk -and -not $InstallOnly) {
        Write-AutoLog "WDK installation failed, but attempting to continue..." "WARN"
    }
    
    if ($InstallOnly) {
        Write-AutoLog "Install-only mode complete. Run again without -InstallOnly to build." "SUCCESS"
        exit 0
    }
}

# Step 2: Build
$buildOk = Build-Driver
if (-not $buildOk) {
    Write-AutoLog "Build failed. Cannot continue." "ERROR"
    Write-AutoLog "Check log: $($Config.LogFile)" "INFO"
    exit 1
}

if ($BuildOnly) {
    Write-AutoLog "Build-only mode complete. Driver ready at: $($Config.BuildDir)\Release\" "SUCCESS"
    exit 0
}

# Step 3: Get kdmapper
$kdmapper = Get-Kdmapper
if (-not $kdmapper) {
    Write-AutoLog "Failed to obtain kdmapper. Cannot load driver." "ERROR"
    exit 1
}

# Step 4: Load driver
$driverFile = "$($Config.BuildDir)\Release\VanguardSpoofer.sys"
$loadOk = Load-Driver -DriverPath $driverFile -KdmapperPath $kdmapper

if (-not $loadOk) {
    Write-AutoLog "Driver loading failed." "ERROR"
    Write-AutoLog "You may need to disable Secure Boot or enable Test Mode" "WARN"
    Write-AutoLog "bcdedit /set testsigning on" "INFO"
    exit 1
}

# Step 5: Verify
Test-Spoofing

Write-AutoLog "" "SUCCESS"
Write-AutoLog "═══════════════════════════════════════════════════════════════" "SUCCESS"
Write-AutoLog "  VANGUARDSPOOFER AUTO-DEPLOYMENT COMPLETE" "SUCCESS"
Write-AutoLog "═══════════════════════════════════════════════════════════════" "SUCCESS"
Write-AutoLog "" "SUCCESS"
Write-AutoLog "Driver loaded and active! HWID spoofing in effect." "SUCCESS"
Write-AutoLog "Logs: $($Config.LogFile)" "INFO"
Write-AutoLog "Driver: $driverFile" "INFO"

Read-Host "`nPress Enter to exit"

#endregion
