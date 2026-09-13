param(
    [string]$IsoPath = "D:\Bazzite-Custom\OUTPUT\Bazzite-Custom-Deck-NVIDIA.iso",
    [string]$WorkDir = "D:\Bazzite-Custom\BOOTTEST",
    [string]$DiskName = "bazzite-custom-boot-test.qcow2",
    [int]$MemoryMb = 8192,
    [int]$CpuCount = 4,
    [int]$DiskSizeGb = 64,
    [switch]$RecreateDisk,
    [switch]$UseTcgOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Resolve-QemuTool {
    param([string]$FileName)

    $fromPath = Get-Command $FileName -ErrorAction SilentlyContinue
    $candidates = @()
    if ($fromPath) {
        $candidates += $fromPath.Source
    }
    $candidates += @(
        (Join-Path "C:\Program Files\qemu" $FileName),
        (Join-Path "C:\Program Files (x86)\qemu" $FileName)
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    throw "$FileName was not found. Run D:\Bazzite-Custom\install-qemu-for-boot-test-admin.ps1 first."
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

function Test-HypervisorPlatformEnabled {
    try {
        $feature = Get-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform -ErrorAction Stop
        return $feature.State -eq "Enabled"
    } catch {
        return $false
    }
}

function Find-UefiFirmware {
    param([string]$QemuExe)

    $qemuDir = Split-Path -Parent $QemuExe
    $root = Split-Path -Parent $qemuDir
    $patterns = @(
        "share\edk2-x86_64-code.fd",
        "share\qemu\edk2-x86_64-code.fd",
        "share\edk2-x86_64-secure-code.fd",
        "share\qemu\edk2-x86_64-secure-code.fd",
        "share\OVMF_CODE.fd",
        "share\qemu\OVMF_CODE.fd"
    )

    foreach ($base in @($qemuDir, $root)) {
        foreach ($pattern in $patterns) {
            $candidate = Join-Path $base $pattern
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                return (Resolve-Path -LiteralPath $candidate).Path
            }
        }
    }
    return $null
}

Assert-IsoHash -Path $IsoPath
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

$qemu = Resolve-QemuTool -FileName "qemu-system-x86_64.exe"
$qemuImg = Resolve-QemuTool -FileName "qemu-img.exe"
$diskPath = Join-Path $WorkDir $DiskName

if ($RecreateDisk -and (Test-Path -LiteralPath $diskPath -PathType Leaf)) {
    Write-Step "Removing old disposable test disk"
    Remove-Item -LiteralPath $diskPath -Force
}

if (-not (Test-Path -LiteralPath $diskPath -PathType Leaf)) {
    Write-Step "Creating disposable QEMU test disk"
    & $qemuImg create -f qcow2 $diskPath "${DiskSizeGb}G"
}

$accel = "tcg"
if (-not $UseTcgOnly -and (Test-HypervisorPlatformEnabled)) {
    $accel = "whpx"
}

$uefi = Find-UefiFirmware -QemuExe $qemu
$varsPath = Join-Path $WorkDir "OVMF_VARS.fd"

$args = @(
    "-name", "Bazzite-Custom-BootTest",
    "-machine", "q35,accel=$accel",
    "-cpu", "max",
    "-smp", "$CpuCount",
    "-m", "$MemoryMb",
    "-device", "virtio-vga",
    "-device", "qemu-xhci",
    "-device", "usb-kbd",
    "-device", "usb-tablet",
    "-netdev", "user,id=net0",
    "-device", "virtio-net-pci,netdev=net0",
    "-drive", "file=$diskPath,if=virtio,format=qcow2",
    "-drive", "file=$IsoPath,media=cdrom,readonly=on,index=2",
    "-boot", "d",
    "-display", "default"
)

if ($uefi) {
    if (-not (Test-Path -LiteralPath $varsPath -PathType Leaf)) {
        Copy-Item -LiteralPath $uefi -Destination $varsPath
    }
    $args = @(
        "-drive", "if=pflash,format=raw,readonly=on,file=$uefi",
        "-drive", "if=pflash,format=raw,file=$varsPath"
    ) + $args
    Write-Step "Starting QEMU boot test with UEFI and $accel acceleration"
} else {
    Write-Step "Starting QEMU boot test with legacy BIOS and $accel acceleration"
}

Write-Host "ISO:  $IsoPath"
Write-Host "Disk: $diskPath"
Write-Host "QEMU: $qemu"
Write-Host ""
Write-Host "Close the QEMU window to end the boot test."

& $qemu @args
