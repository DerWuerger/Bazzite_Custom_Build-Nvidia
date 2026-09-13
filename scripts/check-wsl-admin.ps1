$ErrorActionPreference = "Continue"

$logDir = "D:\Bazzite-Custom"
$logFile = Join-Path $logDir "wsl-admin-check.log"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
Start-Transcript -Path $logFile -Append

try {
    Write-Host "=== WSL admin check started: $(Get-Date -Format o) ==="
    whoami
    whoami /groups
    Write-Host "--- wsl --status ---"
    & wsl.exe --status
    Write-Host "wsl --status exit: $LASTEXITCODE"
    Write-Host "--- wsl --list --verbose ---"
    & wsl.exe --list --verbose
    Write-Host "wsl --list exit: $LASTEXITCODE"
    Write-Host "--- wsl --list --online ---"
    & wsl.exe --list --online
    Write-Host "wsl --list --online exit: $LASTEXITCODE"
    Write-Host "=== WSL admin check finished: $(Get-Date -Format o) ==="
} finally {
    Stop-Transcript
}
