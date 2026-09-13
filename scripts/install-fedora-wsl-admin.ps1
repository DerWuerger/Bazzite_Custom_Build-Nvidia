$ErrorActionPreference = "Continue"

$logDir = "D:\Bazzite-Custom"
$logFile = Join-Path $logDir "fedora-wsl-install.log"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
Start-Transcript -Path $logFile -Append

try {
    Write-Host "=== Fedora WSL install started: $(Get-Date -Format o) ==="
    Write-Host "--- Current distros ---"
    & wsl.exe --list --verbose
    Write-Host "wsl list exit: $LASTEXITCODE"

    $list = (& wsl.exe --list --quiet 2>$null) -join "`n"
    if ($list -notmatch "FedoraLinux-44") {
        Write-Host "Installing FedoraLinux-44 for WSL."
        & wsl.exe --install FedoraLinux-44 --no-launch
        Write-Host "wsl install exit: $LASTEXITCODE"
        if ($LASTEXITCODE -ne 0) {
            throw "FedoraLinux-44 installation failed with exit code $LASTEXITCODE"
        }
    } else {
        Write-Host "FedoraLinux-44 is already installed."
    }

    Write-Host "--- Initializing distro as root ---"
    & wsl.exe -d FedoraLinux-44 -u root -- /bin/sh -lc "id && uname -a && cat /etc/os-release"
    Write-Host "init exit: $LASTEXITCODE"
    if ($LASTEXITCODE -ne 0) {
        throw "FedoraLinux-44 root initialization failed with exit code $LASTEXITCODE"
    }

    Write-Host "--- Final distros ---"
    & wsl.exe --list --verbose
    "READY" | Set-Content -LiteralPath (Join-Path $logDir "fedora-wsl-install.status") -Encoding ascii
    Write-Host "=== Fedora WSL install finished: $(Get-Date -Format o) ==="
} catch {
    "FAILED" | Set-Content -LiteralPath (Join-Path $logDir "fedora-wsl-install.status") -Encoding ascii
    Write-Error $_
    exit 1
} finally {
    Stop-Transcript
}
