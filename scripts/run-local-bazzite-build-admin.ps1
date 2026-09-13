$ErrorActionPreference = "Stop"

$logDir = "D:\Bazzite-Custom"
$logFile = Join-Path $logDir "local-bazzite-build.log"
$statusFile = Join-Path $logDir "local-bazzite-build.status"
$scriptPath = Join-Path $logDir "build-bazzite-local-wsl.sh"

New-Item -ItemType Directory -Force -Path $logDir | Out-Null
if (Test-Path $logFile) {
    $archiveLog = Join-Path $logDir ("local-bazzite-build-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
    Move-Item -LiteralPath $logFile -Destination $archiveLog -Force
}
Start-Transcript -Path $logFile -Append

try {
    "RUNNING" | Set-Content -LiteralPath $statusFile -Encoding ascii
    Write-Host "=== Local Bazzite build wrapper started: $(Get-Date -Format o) ==="

    & wsl.exe -d FedoraLinux-44 -u root -- /bin/bash -lc "sed -i 's/\r$//' /mnt/d/Bazzite-Custom/build-bazzite-local-wsl.sh && /bin/bash /mnt/d/Bazzite-Custom/build-bazzite-local-wsl.sh"
    if ($LASTEXITCODE -ne 0) {
        throw "WSL build failed with exit code $LASTEXITCODE"
    }

    "SUCCESS" | Set-Content -LiteralPath $statusFile -Encoding ascii
    Write-Host "=== Local Bazzite build wrapper finished: $(Get-Date -Format o) ==="
} catch {
    "FAILED" | Set-Content -LiteralPath $statusFile -Encoding ascii
    Write-Error $_
    exit 1
} finally {
    Stop-Transcript
}
