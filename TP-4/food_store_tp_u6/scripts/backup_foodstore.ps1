$ErrorActionPreference = 'Continue'

# Datos de conexión; la contraseña se toma de pgpass.conf, no del script.
$database = 'foodstore_dev'
$hostName = 'localhost'
$port = 5432
$user = 'admin_datos'

# Prepara nombres únicos para el backup, su checksum y el log.
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$unitRoot = Split-Path -Parent $PSScriptRoot
$backupDirectory = Join-Path $unitRoot 'backups'
$logDirectory = Join-Path $unitRoot 'logs'
$backupPath = Join-Path $backupDirectory "foodstore_dev_$timestamp.dump"
$checksumPath = "$backupPath.sha256"
$logPath = Join-Path $logDirectory "log_backup_foodstore_dev_$timestamp.txt"
$startedAt = Get-Date
$pgDumpExitCode = $null
$pgRestoreExitCode = $null
$failureMessage = $null
$removeBackupOnFailure = $false
$logLines = New-Object 'System.Collections.Generic.List[string]'

try {
    New-Item -ItemType Directory -Path $backupDirectory -Force -ErrorAction Stop | Out-Null
    New-Item -ItemType Directory -Path $logDirectory -Force -ErrorAction Stop | Out-Null

    # Evita pisar archivos anteriores y genera el dump en formato custom.
    if ((Test-Path -LiteralPath $backupPath) -or
        (Test-Path -LiteralPath $checksumPath)) {
        throw "El respaldo o su checksum ya existe; se evita sobrescribirlo: $backupPath"
    }

    $pgDump = Get-Command 'pg_dump.exe' -ErrorAction Stop
    $dumpOutput = & $pgDump.Source `
        -h $hostName -p $port -U $user -d $database `
        -w -Fc -Z 6 -f $backupPath 2>&1
    $pgDumpExitCode = $LASTEXITCODE

    foreach ($line in $dumpOutput) {
        $logLines.Add("pg_dump: $line")
    }

    if ($pgDumpExitCode -ne 0) {
        $removeBackupOnFailure = $true
        throw "pg_dump terminó con código $pgDumpExitCode."
    }

    if (-not (Test-Path -LiteralPath $backupPath) -or
        (Get-Item -LiteralPath $backupPath -ErrorAction Stop).Length -eq 0) {
        $removeBackupOnFailure = $true
        throw 'pg_dump terminó sin error, pero no generó un archivo de respaldo válido.'
    }

    # Comprueba que PostgreSQL pueda leer el archivo y calcula su SHA-256.
    $pgRestore = Get-Command 'pg_restore.exe' -ErrorAction Stop
    $restoreOutput = & $pgRestore.Source --list $backupPath 2>&1
    $pgRestoreExitCode = $LASTEXITCODE

    if ($pgRestoreExitCode -ne 0) {
        $removeBackupOnFailure = $true
        foreach ($line in $restoreOutput) {
            $logLines.Add("pg_restore --list: $line")
        }
        throw "pg_restore --list terminó con código $pgRestoreExitCode."
    }

    $logLines.Add('Validacion pg_restore --list: OK')
    $fileInfo = Get-Item -LiteralPath $backupPath
    $hash = Get-FileHash -LiteralPath $backupPath -Algorithm SHA256 -ErrorAction Stop
    $checksumLine = "$($hash.Hash) *$($fileInfo.Name)"
    [IO.File]::WriteAllText(
        $checksumPath,
        "$checksumLine`r`n",
        [Text.Encoding]::ASCII
    )
}
catch {
    $failureMessage = $_.Exception.Message

    # Si la generación o validación falló, no deja un dump incompleto.
    if ($removeBackupOnFailure -and (Test-Path -LiteralPath $backupPath)) {
        try {
            Remove-Item -LiteralPath $backupPath -Force -ErrorAction Stop
        }
        catch {
            $failureMessage += " No se pudo borrar el archivo parcial: $($_.Exception.Message)"
        }
    }
}

$finishedAt = Get-Date
$status = if ($null -eq $failureMessage) { 'OK' } else { 'ERROR' }
$backupSize = if (Test-Path -LiteralPath $backupPath) {
    (Get-Item -LiteralPath $backupPath -ErrorAction Stop).Length
} else {
    0
}
$checksum = if (Test-Path -LiteralPath $checksumPath) {
    (Get-Content -LiteralPath $checksumPath -TotalCount 1 -ErrorAction Stop)
} else {
    'No disponible'
}

# Deja constancia de la ejecución, sus códigos de salida y el resultado.
$header = @(
    'LOG DE BACKUP - FOOD STORE | U6'
    "Inicio       : $($startedAt.ToString('yyyy-MM-dd HH:mm:ss zzz'))"
    "Fin          : $($finishedAt.ToString('yyyy-MM-dd HH:mm:ss zzz'))"
    "Base         : $database"
    "Servidor     : ${hostName}:$port"
    "Rol          : $user"
    "Archivo      : $backupPath"
    "Tamano bytes : $backupSize"
    "pg_dump      : $(if ($null -eq $pgDumpExitCode) { 'NO EJECUTADO' } else { $pgDumpExitCode })"
    "pg_restore   : $(if ($null -eq $pgRestoreExitCode) { 'NO EJECUTADO' } else { $pgRestoreExitCode })"
    "SHA-256      : $checksum"
    "Resultado    : $status"
)
$logLines.InsertRange(0, [string[]]$header)

if ($null -ne $failureMessage) {
    $logLines.Add("Error: $failureMessage")
}

try {
    [IO.File]::WriteAllLines(
        $logPath,
        $logLines.ToArray(),
        (New-Object System.Text.UTF8Encoding($true))
    )
}
catch {
    throw "No se pudo escribir el log '$logPath': $($_.Exception.Message)"
}

if ($null -ne $failureMessage) {
    [Console]::Error.WriteLine("$failureMessage Log: $logPath")
    exit 1
}

Write-Host "Backup creado y validado: $backupPath"
Write-Host "SHA-256: $checksum"
Write-Host "Log: $logPath"
