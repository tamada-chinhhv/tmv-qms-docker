#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string] $BackupBundle,
    [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '_Compose-Root.ps1')

if (-not (Test-Path -LiteralPath $BackupBundle)) {
    Write-Error "Khong tim thay file backup: $BackupBundle"
    exit 1
}

$RootDir = Get-QmsDockerRoot
$EnvFile = Get-QmsEnvFile -RootDir $RootDir
$ComposeFile = Join-Path $RootDir 'docker-compose.yml'

if (-not (Test-Path -LiteralPath $EnvFile)) {
    Write-Error "Thieu file $EnvFile"
    exit 1
}

Import-QmsDotEnv -EnvFile $EnvFile

$workDir = Join-Path ([System.IO.Path]::GetTempPath()) ("qms-restore-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $workDir | Out-Null

try {
    $plain = Join-Path $workDir 'bundle.tar'
    if ($BackupBundle -like '*.age') {
        if (-not (Get-Command age -ErrorAction SilentlyContinue)) {
            throw 'Can cai age de giai ma file .age'
        }
        & age -d -o $plain $BackupBundle
        if ($LASTEXITCODE -ne 0) { throw 'Giai ma age that bai.' }
    } elseif ($BackupBundle -like '*.gpg') {
        if (-not (Get-Command gpg -ErrorAction SilentlyContinue)) {
            throw 'Can cai gpg de giai ma file .gpg'
        }
        & gpg --decrypt -o $plain $BackupBundle
        if ($LASTEXITCODE -ne 0) { throw 'Giai ma gpg that bai.' }
    } else {
        Copy-Item -LiteralPath $BackupBundle -Destination $plain
    }

    & tar -xf $plain -C $workDir
    if ($LASTEXITCODE -ne 0) { throw 'Giai nen bundle that bai.' }

    $dbDump = Get-ChildItem -LiteralPath $workDir -Filter 'qms_db_*.dump' -File | Select-Object -First 1
    $storageTar = Get-ChildItem -LiteralPath $workDir -Filter 'qms_storage_*.tar' -File | Select-Object -First 1
    if (-not $dbDump -or -not $storageTar) {
        throw 'Bundle khong hop le: can qms_db_*.dump va qms_storage_*.tar'
    }

    if (-not $Force) {
        Write-Host "Restore se ghi de DB va storage. Go 'yes' de tiep tuc."
        $confirm = Read-Host
        if ($confirm -ne 'yes') {
            Write-Host 'Da huy.'
            exit 1
        }
    }

    $pgUser = if ($env:POSTGRES_SUPERUSER) { $env:POSTGRES_SUPERUSER } else { 'postgres' }
    $pgDb = if ($env:POSTGRES_DB) { $env:POSTGRES_DB } else { 'qms_db' }

    Write-Host '==> Dung tang ung dung'
    Invoke-QmsCompose -RootDir $RootDir -EnvFile $EnvFile -ComposeFiles @($ComposeFile) -ComposeArgs @(
        'stop', 'qms-fe', 'qms-be', 'nginx'
    )

    Write-Host '==> Khoi phuc co so du lieu'
    Invoke-QmsComposeStdinFromFile -EnvFile $EnvFile -ComposeFiles @($ComposeFile) -InFile $dbDump.FullName -ComposeArgs @(
        'exec', '-T', 'postgres',
        'pg_restore', '-U', $pgUser, '-d', $pgDb, '--clean', '--if-exists'
    )

    Write-Host '==> Khoi phuc storage'
    Invoke-QmsCompose -RootDir $RootDir -EnvFile $EnvFile -ComposeFiles @($ComposeFile) -ComposeArgs @(
        'run', '--rm', '--no-deps', '-T', '--entrypoint', 'sh', 'qms-be', '-c', 'rm -rf /data/storage/*'
    )
    Invoke-QmsComposeStdinFromFile -EnvFile $EnvFile -ComposeFiles @($ComposeFile) -InFile $storageTar.FullName -ComposeArgs @(
        'run', '--rm', '--no-deps', '-T', '--entrypoint', 'sh', 'qms-be', '-c', 'tar -C /data/storage -xf -'
    )

    Write-Host '==> Khoi dong stack'
    Invoke-QmsCompose -RootDir $RootDir -EnvFile $EnvFile -ComposeFiles @($ComposeFile) -ComposeArgs @('up', '-d')

    Write-Host '==> Luu y: job doi chieu storage/DB (sha256) chua tu dong (Phase 0).'
} finally {
    if (Test-Path -LiteralPath $workDir) {
        Remove-Item -LiteralPath $workDir -Recurse -Force
    }
}