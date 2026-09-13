$ErrorActionPreference = "Stop"

$logDir = "D:\Bazzite-Custom"
$logFile = Join-Path $logDir "wsl2-admin-setup.log"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

Start-Transcript -Path $logFile -Append

try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        throw "This script must run elevated."
    }

    Write-Host "=== WSL2 admin setup started: $(Get-Date -Format o) ==="

    $features = @(
        "Microsoft-Windows-Subsystem-Linux",
        "VirtualMachinePlatform"
    )

    foreach ($feature in $features) {
        Write-Host "Current state for $feature"
        dism.exe /online /Get-FeatureInfo /FeatureName:$feature
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to query feature $feature"
        }

        Write-Host "Enabling $feature"
        dism.exe /online /enable-feature /featurename:$feature /all /norestart
        if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 3010) {
            throw "Failed to enable feature $feature, exit code $LASTEXITCODE"
        }
    }

    Write-Host "Setting WSL 2 as default version if wsl.exe is available."
    & wsl.exe --set-default-version 2
    if ($LASTEXITCODE -ne 0) {
        Write-Host "wsl --set-default-version 2 returned $LASTEXITCODE; this can be normal before reboot."
    }

    Write-Host "Updating WSL if supported by this Windows build."
    & wsl.exe --update
    if ($LASTEXITCODE -ne 0) {
        Write-Host "wsl --update returned $LASTEXITCODE; continuing because feature activation may require reboot first."
    }

    Write-Host "Final feature states:"
    foreach ($feature in $features) {
        dism.exe /online /Get-FeatureInfo /FeatureName:$feature
    }

    $rebootKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
        "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations"
    )

    $needsReboot = $false
    foreach ($key in $rebootKeys) {
        if (Test-Path $key) {
            $needsReboot = $true
            Write-Host "Pending reboot marker found: $key"
        }
    }

    if ($needsReboot) {
        "REBOOT_REQUIRED" | Set-Content -LiteralPath (Join-Path $logDir "wsl2-admin-setup.status") -Encoding ascii
        Write-Host "WSL2 feature setup completed; reboot is required."
    } else {
        "READY" | Set-Content -LiteralPath (Join-Path $logDir "wsl2-admin-setup.status") -Encoding ascii
        Write-Host "WSL2 feature setup completed; no reboot marker detected."
    }

    Write-Host "=== WSL2 admin setup finished: $(Get-Date -Format o) ==="
} catch {
    "FAILED" | Set-Content -LiteralPath (Join-Path $logDir "wsl2-admin-setup.status") -Encoding ascii
    Write-Error $_
    exit 1
} finally {
    Stop-Transcript
}
