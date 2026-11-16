#requires -Version 5.1
[CmdletBinding()]
param(
    [string] $BackupDir,
    [int] $RetentionDays = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '_Compose-Root.ps1')

$RootDir = Get-QmsDockerRoot
$EnvFile = Get-QmsEnvFile -RootDir $RootDir
$ComposeFile = Join-Path $RootDir 'docker-compose.yml'

if (-not (Test-Path -LiteralPath $EnvFile)) {
    Write-Error "Thieu file $EnvFile"
    exit 1
}

Import-QmsDotEnv -EnvFile $EnvFile

if (-not $BackupDir) {
    if ($env:BACKUP_DIR) {
        $BackupDir = $env:BACKUP_DIR
    } else {
        $BackupDir = Join-Path $RootDir 'backups'
    }
}

if ($RetentionDays -lt 1) {
    if ($env:BACKUP_RETENTION_DAYS) {
        $RetentionDays = [int]$env:BACKUP_RETENTION_DAYS
    } else {
        $RetentionDays = 14
    }
}

New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null

$ts = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
$dbDump = Join-Path $BackupDir "qms_db_$ts.dump"
$storageTar = Join-Path $BackupDir "qms_storage_$ts.tar"
$bundle = Join-Path $BackupDir "qms_backup_$ts.tar"

$pgUser = if ($env:POSTGRES_SUPERUSER) { $env:POSTGRES_SUPERUSER } else { 'postgres' }
$pgDb = if ($env:POSTGRES_DB) { $env:POSTGRES_DB } else { 'qms_db' }

Write-Host '==> pg_dump (dinh dang tuy chinh)'
Invoke-QmsComposeStdoutToFile -EnvFile $EnvFile -ComposeFiles @($ComposeFile) -OutFile $dbDump -ComposeArgs @(
    'exec', '-T', 'postgres',
    'pg_dump', '-U', $pgUser, '-d', $pgDb, '-Fc'
)

Write-Host '==> Dong goi volume storage (tu container qms-be)'
Invoke-QmsComposeStdoutToFile -EnvFile $EnvFile -ComposeFiles @($ComposeFile) -OutFile $storageTar -ComposeArgs @(
    'exec', '-T', 'qms-be', 'sh', '-c', 'tar -C /data/storage -cf - .'
)

& tar -cf $bundle -C $BackupDir (Split-Path -Leaf $dbDump) (Split-Path -Leaf $storageTar)
if ($LASTEXITCODE -ne 0) {
    throw 'Tao file bundle tar that bai.'
}
Remove-Item -LiteralPath $dbDump, $storageTar -Force

$encrypted = $bundle
if ($env:AGE_RECIPIENT -and (Get-Command age -ErrorAction SilentlyContinue)) {
    $encrypted = "$bundle.age"
    & age -r $env:AGE_RECIPIENT -o $encrypted $bundle
    if ($LASTEXITCODE -ne 0) { throw 'Ma hoa age that bai.' }
    Remove-Item -LiteralPath $bundle -Force
    Write-Host "==> Da ma hoa bang age: $encrypted"
} elseif ($env:GPG_RECIPIENT -and (Get-Command gpg -ErrorAction SilentlyContinue)) {
    $encrypted = "$bundle.gpg"
    & gpg --batch --yes -r $env:GPG_RECIPIENT -o $encrypted -e $bundle
    if ($LASTEXITCODE -ne 0) { throw 'Ma hoa gpg that bai.' }
    Remove-Item -LiteralPath $bundle -Force
    Write-Host "==> Da ma hoa bang gpg: $encrypted"
} else {
    Write-Host "==> Ban backup (chua ma hoa): $encrypted"
    Write-Host 'Dat AGE_RECIPIENT hoac GPG_RECIPIENT trong .env de ma hoa.'
}

$cutoff = (Get-Date).AddDays(-$RetentionDays)
Get-ChildItem -LiteralPath $BackupDir -File |
    Where-Object {
        $_.Name -like 'qms_backup_*.tar' -or
        $_.Name -like 'qms_backup_*.tar.age' -or
        $_.Name -like 'qms_backup_*.tar.gpg'
    } |
    Where-Object { $_.LastWriteTime -lt $cutoff } |
    ForEach-Object {
        Write-Host "Xoa ban cu: $($_.FullName)"
        Remove-Item -LiteralPath $_.FullName -Force
    }

Write-Host '==> Hoan tat backup'