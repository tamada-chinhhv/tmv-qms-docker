#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '_Compose-Root.ps1')

$RootDir = Get-QmsDockerRoot
$env:DOCKER_BUILDKIT = '1'

Write-Host '==> Dang build tmv-qms-be:latest'
& docker build `
    -f (Join-Path $RootDir 'Dockerfile.backend') `
    --build-context "qms-docker=$RootDir" `
    -t 'tmv-qms-be:latest' `
    (Join-Path $RootDir '..\tmv-qms-be')
if ($LASTEXITCODE -ne 0) {
    throw 'Build tmv-qms-be that bai.'
}

Write-Host '==> Dang build tmv-qms-fe:latest'
& docker build `
    -f (Join-Path $RootDir 'Dockerfile.frontend') `
    -t 'tmv-qms-fe:latest' `
    (Join-Path $RootDir '..\tmv-qms')
if ($LASTEXITCODE -ne 0) {
    throw 'Build tmv-qms-fe that bai.'
}

Write-Host '==> Hoan tat. Image: tmv-qms-be:latest, tmv-qms-fe:latest'