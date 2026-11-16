#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '_Compose-Root.ps1')

$RootDir = Get-QmsDockerRoot
$EnvFile = Get-QmsEnvFile -RootDir $RootDir
$ComposeFile = Join-Path $RootDir 'docker-compose.yml'

if (-not (Test-Path -LiteralPath $EnvFile)) {
    Write-Error "Thieu file $EnvFile. Chay: Copy-Item .env.example .env va dien gia tri."
    exit 1
}

Import-QmsDotEnv -EnvFile $EnvFile

$sslDir = if ($env:NGINX_SSL_DIR) { $env:NGINX_SSL_DIR } else { Join-Path $RootDir 'nginx\ssl' }
if (-not [System.IO.Path]::IsPathRooted($sslDir)) {
    $sslDir = Join-Path $RootDir ($sslDir -replace '/', '\')
}
$certPath = Join-Path $sslDir 'fullchain.pem'
if (-not (Test-Path -LiteralPath $certPath)) {
    Write-Error "Thieu chung chi TLS: $certPath. Xem README.md (muc tao cert dev)."
    exit 1
}

Write-Host '==> Keo image co so (postgres, redis, nginx)'
Invoke-QmsCompose -RootDir $RootDir -EnvFile $EnvFile -ComposeFiles @($ComposeFile) -ComposeArgs @('pull', 'postgres', 'redis', 'nginx')

Write-Host '==> Khoi dong stack'
Invoke-QmsCompose -RootDir $RootDir -EnvFile $EnvFile -ComposeFiles @($ComposeFile) -ComposeArgs @('up', '-d')

Write-Host '==> Reload nginx (cap nhat upstream DNS)'
$nginxName = 'tmv-qms-nginx'
$running = docker ps --format '{{.Names}}' | Where-Object { $_ -eq $nginxName }
if ($running) {
    & docker exec $nginxName nginx -t
    if ($LASTEXITCODE -ne 0) {
        throw 'Cau hinh nginx khong hop le (nginx -t).'
    }
    & docker exec $nginxName nginx -s reload
    if ($LASTEXITCODE -ne 0) {
        throw 'Reload nginx that bai.'
    }
}

Write-Host '==> Trang thai dich vu'
Invoke-QmsCompose -RootDir $RootDir -EnvFile $EnvFile -ComposeFiles @($ComposeFile) -ComposeArgs @('ps')