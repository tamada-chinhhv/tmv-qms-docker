# Shared helpers for host PowerShell scripts (UTF-8 BOM).
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-QmsDockerRoot {
    $scriptDir = Split-Path -Parent $PSCommandPath
    return (Resolve-Path (Join-Path $scriptDir '..')).Path
}

function Get-QmsEnvFile {
    param(
        [string] $RootDir
    )
    if ($env:COMPOSE_ENV_FILE) {
        return $env:COMPOSE_ENV_FILE
    }
    return (Join-Path $RootDir '.env')
}

function Import-QmsDotEnv {
    param(
        [string] $EnvFile
    )

    if (-not (Test-Path -LiteralPath $EnvFile)) {
        throw "Khong tim thay file moi truong: $EnvFile"
    }

    $raw = [System.IO.File]::ReadAllText($EnvFile)
    if ($raw -match "`r") {
        $raw = $raw -replace "`r`n", "`n" -replace "`r", "`n"
        Write-Host 'Da chuan hoa xuong dong LF khi doc .env (tranh loi CRLF).'
    }

    foreach ($line in $raw -split "`n") {
        $trimmed = $line.Trim()
        if ($trimmed.Length -eq 0 -or $trimmed.StartsWith('#')) {
            continue
        }
        $eq = $trimmed.IndexOf('=')
        if ($eq -lt 1) {
            continue
        }
        $key = $trimmed.Substring(0, $eq).Trim()
        $value = $trimmed.Substring($eq + 1).Trim()
        if (
            ($value.StartsWith('"') -and $value.EndsWith('"')) -or
            ($value.StartsWith("'") -and $value.EndsWith("'"))
        ) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        Set-Item -Path "Env:$key" -Value $value
    }
}

function Get-QmsDockerComposeArgumentList {
    param(
        [string] $EnvFile,
        [string[]] $ComposeFiles,
        [string[]] $ComposeArgs
    )

    $argsList = New-Object System.Collections.Generic.List[string]
    $null = $argsList.Add('compose')
    $null = $argsList.Add('--env-file')
    $null = $argsList.Add($EnvFile)
    foreach ($f in $ComposeFiles) {
        $null = $argsList.Add('-f')
        $null = $argsList.Add($f)
    }
    foreach ($a in $ComposeArgs) {
        $null = $argsList.Add($a)
    }
    return $argsList.ToArray()
}

function Invoke-QmsCompose {
    param(
        [string] $RootDir,
        [string] $EnvFile,
        [string[]] $ComposeFiles,
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]] $ComposeArgs
    )

    $argsList = Get-QmsDockerComposeArgumentList -EnvFile $EnvFile -ComposeFiles $ComposeFiles -ComposeArgs $ComposeArgs
    & docker @argsList
    if ($LASTEXITCODE -ne 0) {
        throw "Lenh docker compose that bai (ma thoat $LASTEXITCODE)."
    }
}

function Invoke-QmsComposeStdoutToFile {
    param(
        [string] $EnvFile,
        [string[]] $ComposeFiles,
        [string[]] $ComposeArgs,
        [string] $OutFile
    )

    $argsList = Get-QmsDockerComposeArgumentList -EnvFile $EnvFile -ComposeFiles $ComposeFiles -ComposeArgs $ComposeArgs
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'docker'
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $quoted = $argsList | ForEach-Object {
        if ($_ -match '\s') { """$_""" } else { $_ }
    }
    $psi.Arguments = $quoted -join ' '

    $process = [System.Diagnostics.Process]::Start($psi)
    if (-not $process) {
        throw 'Khong khoi dong duoc tien trinh docker.'
    }
    $errTask = $process.StandardError.ReadToEndAsync()

    $outStream = [System.IO.File]::Create($OutFile)
    try {
        $buffer = New-Object byte[] 65536
        $stdout = $process.StandardOutput.BaseStream
        while (($read = $stdout.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $outStream.Write($buffer, 0, $read)
        }
    } finally {
        $outStream.Close()
    }

    $process.WaitForExit()
    $err = $errTask.Result
    if ($process.ExitCode -ne 0) {
        if ($err) { Write-Host $err }
        throw "docker compose that bai (ma thoat $($process.ExitCode))."
    }
}

function Invoke-QmsComposeStdinFromFile {
    param(
        [string] $EnvFile,
        [string[]] $ComposeFiles,
        [string[]] $ComposeArgs,
        [string] $InFile
    )

    $argsList = Get-QmsDockerComposeArgumentList -EnvFile $EnvFile -ComposeFiles $ComposeFiles -ComposeArgs $ComposeArgs
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'docker'
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $quoted = $argsList | ForEach-Object {
        if ($_ -match '\s') { """$_""" } else { $_ }
    }
    $psi.Arguments = $quoted -join ' '

    $process = [System.Diagnostics.Process]::Start($psi)
    if (-not $process) {
        throw 'Khong khoi dong duoc tien trinh docker.'
    }
    $errTask = $process.StandardError.ReadToEndAsync()

    $inStream = [System.IO.File]::OpenRead($InFile)
    try {
        $buffer = New-Object byte[] 65536
        $stdin = $process.StandardInput.BaseStream
        while (($read = $inStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $stdin.Write($buffer, 0, $read)
        }
    } finally {
        $inStream.Close()
        $process.StandardInput.Close()
    }

    $process.WaitForExit()
    $err = $errTask.Result
    if ($process.ExitCode -ne 0) {
        if ($err) { Write-Host $err }
        throw "docker compose that bai (ma thoat $($process.ExitCode))."
    }
}