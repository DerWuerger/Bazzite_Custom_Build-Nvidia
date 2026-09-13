param(
    [string]$IsoPath = "D:\Bazzite-Custom\OUTPUT\Bazzite-Custom-Deck-NVIDIA.iso",
    [string]$VmName = "Bazzite-Custom-BootTest",
    [string]$WorkDir = "D:\Bazzite-Custom\BOOTTEST",
    [int64]$MemoryStartupBytes = 8GB,
    [int64]$DiskSizeBytes = 64GB,
    [int]$CpuCount = 4,
    [switch]$Recreate,
    [switch]$NoConnect
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Assert-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Please run this script from an elevated PowerShell window."
    }
}

function Assert-IsoHash {
    param([string]$Path)

    $shaPath = "$Path.sha256"
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "ISO not found: $Path"
    }
    if (-not (Test-Path -LiteralPath $shaPath -PathType Leaf)) {
        throw "SHA file not found: $shaPath"
    }

    Write-Step "Verifying ISO SHA-256"
    $expected = ((Get-Content -LiteralPath $shaPath -Raw).Trim() -split "\s+")[0].ToLowerInvariant()
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
    if ($actual -ne $expected) {
        throw "ISO SHA-256 mismatch. Expected $expected but got $actual."
    }
    Write-Host "SHA-256 OK: $actual"
}

function Get-HyperVCommand {
    param([string]$Name)
    Get-Command $Name -ErrorAction SilentlyContinue
}

Assert-Admin
Assert-IsoHash -Path $IsoPath

if (-not (Get-HyperVCommand -Name "New-VM")) {
    Write-Host ""
    Write-Host "Hyper-V PowerShell cmdlets are not available in this PowerShell session." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "If this Windows edition supports Hyper-V, enable it from an elevated PowerShell with:"
    Write-Host "Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -All"
    Write-Host ""
    Write-Host "After the required reboot, run this script again:"
    Write-Host "powershell -ExecutionPolicy Bypass -File `"D:\Bazzite-Custom\start-bazzite-boot-test-admin.ps1`""
    exit 2
}

Write-Step "Preparing Hyper-V boot test VM"
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

$vhdPath = Join-Path $WorkDir "$VmName.vhdx"
$existingVm = Get-VM -Name $VmName -ErrorAction SilentlyContinue

if ($existingVm -and $Recreate) {
    Write-Step "Removing existing VM because -Recreate was specified"
    if ($existingVm.State -ne "Off") {
        Stop-VM -Name $VmName -TurnOff -Force
    }
    Remove-VM -Name $VmName -Force
    if (Test-Path -LiteralPath $vhdPath -PathType Leaf) {
        Remove-Item -LiteralPath $vhdPath -Force
    }
    $existingVm = $null
}

if (-not (Test-Path -LiteralPath $vhdPath -PathType Leaf)) {
    Write-Step "Creating disposable test disk"
    New-VHD -Path $vhdPath -Dynamic -SizeBytes $DiskSizeBytes | Out-Null
}

$switch = Get-VMSwitch -Name "Default Switch" -ErrorAction SilentlyContinue
if (-not $switch) {
    $switch = Get-VMSwitch | Sort-Object Name | Select-Object -First 1
}
if (-not $switch) {
    throw "No Hyper-V virtual switch was found. Create one in Hyper-V Manager, then rerun this script."
}

if (-not $existingVm) {
    Write-Step "Creating VM $VmName"
    New-VM `
        -Name $VmName `
        -Generation 2 `
        -MemoryStartupBytes $MemoryStartupBytes `
        -VHDPath $vhdPath `
        -Path $WorkDir `
        -SwitchName $switch.Name | Out-Null
}

Set-VMProcessor -VMName $VmName -Count $CpuCount
Set-VMMemory -VMName $VmName -DynamicMemoryEnabled $true -MinimumBytes 4GB -MaximumBytes 12GB -StartupBytes $MemoryStartupBytes
Set-VMFirmware -VMName $VmName -EnableSecureBoot Off
Set-VM -Name $VmName -CheckpointType Disabled

$dvd = Get-VMDvdDrive -VMName $VmName -ErrorAction SilentlyContinue | Select-Object -First 1
if ($dvd) {
    Set-VMDvdDrive -VMName $VmName -ControllerNumber $dvd.ControllerNumber -ControllerLocation $dvd.ControllerLocation -Path $IsoPath
} else {
    Add-VMDvdDrive -VMName $VmName -Path $IsoPath
    $dvd = Get-VMDvdDrive -VMName $VmName | Select-Object -First 1
}
Set-VMFirmware -VMName $VmName -FirstBootDevice $dvd

$vm = Get-VM -Name $VmName
if ($vm.State -ne "Running") {
    Write-Step "Starting VM"
    Start-VM -Name $VmName
}

Write-Step "Boot test VM is running"
Write-Host "VM name: $VmName"
Write-Host "ISO:     $IsoPath"
Write-Host "Disk:    $vhdPath"
Write-Host "Switch:  $($switch.Name)"

if (-not $NoConnect) {
    $vmConnect = Get-Command vmconnect.exe -ErrorAction SilentlyContinue
    if ($vmConnect) {
        Start-Process -FilePath $vmConnect.Source -ArgumentList @($env:COMPUTERNAME, $VmName)
    } else {
        Write-Host "Open Hyper-V Manager and connect to VM '$VmName' to view the boot screen."
    }
}
