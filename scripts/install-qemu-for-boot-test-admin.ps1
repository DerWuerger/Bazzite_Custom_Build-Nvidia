param(
    [string]$ToolsDir = "D:\Bazzite-Custom\TOOLS",
    [string]$InstallDir = "C:\Program Files\qemu",
    [string]$QemuInstallerUrl = "https://qemu.weilnetz.de/w64/qemu-w64-setup-20260811.exe",
    [string]$QemuSha512Url = "https://qemu.weilnetz.de/w64/qemu-w64-setup-20260811.sha512"
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

function Get-QemuBinary {
    $candidates = @(
        (Join-Path $InstallDir "qemu-system-x86_64.exe"),
        "C:\Program Files\qemu\qemu-system-x86_64.exe",
        "C:\Program Files (x86)\qemu\qemu-system-x86_64.exe"
    )

    $fromPath = Get-Command qemu-system-x86_64.exe -ErrorAction SilentlyContinue
    if ($fromPath) {
        $candidates = @($fromPath.Source) + $candidates
    }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    return $null
}

Assert-Admin

$existingQemu = Get-QemuBinary
if ($existingQemu) {
    Write-Step "QEMU is already installed"
    Write-Host $existingQemu
    exit 0
}

New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null
$installerPath = Join-Path $ToolsDir (Split-Path -Leaf $QemuInstallerUrl)
$shaPath = "$installerPath.sha512"

if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) {
    Write-Step "Downloading QEMU installer"
    Invoke-WebRequest -Uri $QemuInstallerUrl -OutFile $installerPath
}

Write-Step "Downloading QEMU installer SHA-512"
Invoke-WebRequest -Uri $QemuSha512Url -OutFile $shaPath

Write-Step "Verifying QEMU installer SHA-512"
$expected = ((Get-Content -LiteralPath $shaPath -Raw).Trim() -split "\s+")[0].ToLowerInvariant()
$actual = (Get-FileHash -Algorithm SHA512 -LiteralPath $installerPath).Hash.ToLowerInvariant()
if ($expected -ne $actual) {
    throw "QEMU installer SHA-512 mismatch. Expected $expected but got $actual."
}
Write-Host "SHA-512 OK: $actual"

Write-Step "Installing QEMU silently"
$process = Start-Process -FilePath $installerPath -ArgumentList "/S" -Wait -PassThru
if ($process.ExitCode -ne 0) {
    throw "QEMU installer failed with exit code $($process.ExitCode)."
}

$installedQemu = Get-QemuBinary
if (-not $installedQemu) {
    throw "QEMU installation finished, but qemu-system-x86_64.exe was not found."
}

Write-Step "QEMU is ready"
Write-Host $installedQemu
