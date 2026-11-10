param(
    [switch]$Recreate
)

$ErrorActionPreference = 'Stop'

$hostName = 'localhost'
$port = 5432
$user = 'admin_datos'
$sourceDatabase = 'foodstore_dev'
$targetDatabase = 'foodstore_restore_test'
$unitRoot = Split-Path -Parent $PSScriptRoot
$backupDirectory = Join-Path $unitRoot 'backups'
$logDirectory = Join-Path $unitRoot 'logs'

New-Item -ItemType Directory -Path $logDirectory -Force -ErrorAction Stop | Out-Null
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$logPath = Join-Path $logDirectory "log_restore_test_$timestamp.txt"
$script:restoreLogPath = $logPath
[IO.File]::WriteAllText(
    $logPath,
    "SIMULACRO DE RESTAURACION - FOOD STORE | U6`r`n",
    (New-Object System.Text.UTF8Encoding($true))
)

function Write-RestoreLog {
    param([string]$Message)

    [IO.File]::AppendAllText(
        $script:restoreLogPath,
        "$Message`r`n",
        (New-Object System.Text.UTF8Encoding($false))
    )
    Write-Host $Message
}

function Invoke-PostgresCommand {
    param(
        [string]$Name,
        [string[]]$Arguments,
        [switch]$CaptureOutput
    )

    $command = Get-Command "$Name.exe" -ErrorAction Stop
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $command.Source @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }

    if ($CaptureOutput -or $exitCode -ne 0) {
        foreach ($line in $output) {
            Write-RestoreLog ([string]$line)
        }
    }

    Write-RestoreLog "$Name exit code: $exitCode"
    if ($exitCode -ne 0) {
        throw "$Name termino con codigo $exitCode."
    }

    return $output
}

try {
    $backup = Get-ChildItem -LiteralPath $backupDirectory -Filter 'foodstore_dev_*.dump' -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($null -eq $backup) {
        throw "No se encontro un dump foodstore_dev_*.dump en '$backupDirectory'."
    }

    $checksumPath = "$($backup.FullName).sha256"
    if (-not (Test-Path -LiteralPath $checksumPath -PathType Leaf)) {
        throw "Falta el checksum correspondiente: $checksumPath"
    }

    $expectedHash = ((Get-Content -LiteralPath $checksumPath -Raw).Trim() -split '\s+')[0]
    $actualHash = (Get-FileHash -LiteralPath $backup.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
    if ($actualHash -ine $expectedHash) {
        throw 'El SHA-256 del dump no coincide; se cancela la restauracion.'
    }

    Write-RestoreLog "Base origen        : $sourceDatabase"
    Write-RestoreLog "Base destino       : $targetDatabase"
    Write-RestoreLog "Respaldo utilizado : $($backup.FullName)"
    Write-RestoreLog "Fecha del respaldo : $($backup.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss zzz'))"
    Write-RestoreLog 'RPO calculado con la fecha de modificacion local del archivo.'
    Write-RestoreLog "SHA-256 verificado : $actualHash"

    $archiveEntries = @(Invoke-PostgresCommand 'pg_restore' @('--list', $backup.FullName))
    if ($archiveEntries.Count -eq 0) {
        throw 'pg_restore --list no devolvio el contenido del archivo.'
    }
    Write-RestoreLog 'Validacion pg_restore --list: OK'

    $databaseCheck = @(
        Invoke-PostgresCommand 'psql' @(
            '-h', $hostName, '-p', "$port", '-U', $user, '-w',
            '-X', '-A', '-t', '-q', '-d', $sourceDatabase,
            '-c', "SELECT EXISTS (SELECT 1 FROM pg_database WHERE datname = '$targetDatabase');"
        )
    )
    $targetExists = (($databaseCheck | ForEach-Object { ([string]$_).Trim() }) -join '').Trim()

    if ($targetExists -eq 't') {
        if (-not $Recreate) {
            throw "La base '$targetDatabase' ya existe. Confirma que es descartable y ejecuta de nuevo con -Recreate para reemplazarla."
        }

        Write-RestoreLog "Se reemplazara unicamente la base descartable '$targetDatabase' (-Recreate)."
        $null = Invoke-PostgresCommand 'dropdb' @(
            '-h', $hostName, '-p', "$port", '-U', $user, '-w', $targetDatabase
        ) -CaptureOutput
    }
    elseif ($targetExists -ne 'f') {
        throw "No se pudo determinar si existe la base destino. Respuesta de psql: $targetExists"
    }

    # Baseline counts registered before the backup; update if the source data changes.
    $expectedCounts = @(
        "('categoria', 9::bigint)",
        "('cliente', 20000::bigint)",
        "('producto', 50000::bigint)",
        "('pedido', 203000::bigint)",
        "('detalle_pedido', 306700::bigint)"
    ) -join ",`r`n        "

    $validationSql = @"
WITH esperados(tabla, filas_esperadas) AS (
    VALUES
        $expectedCounts
),
actuales(tabla, filas_actuales) AS (
    SELECT 'categoria', COUNT(*) FROM categoria
    UNION ALL SELECT 'cliente', COUNT(*) FROM cliente
    UNION ALL SELECT 'producto', COUNT(*) FROM producto
    UNION ALL SELECT 'pedido', COUNT(*) FROM pedido
    UNION ALL SELECT 'detalle_pedido', COUNT(*) FROM detalle_pedido
),
comparacion AS (
    SELECT e.tabla, e.filas_esperadas, a.filas_actuales
    FROM esperados AS e
    JOIN actuales AS a USING (tabla)
),
controles AS (
    SELECT 'productos_invalidos'::text AS tabla, 0::bigint AS esperado, COUNT(*) AS actual
    FROM producto
    WHERE precio_lista < 0 OR stock < 0
    UNION ALL
    SELECT 'detalles_invalidos', 0::bigint, COUNT(*)
    FROM detalle_pedido
    WHERE cantidad <= 0 OR precio_unitario_historico < 0
)
SELECT 'CONTEO|' || tabla || '|' || filas_esperadas || '|' || filas_actuales || '|' ||
        CASE WHEN filas_esperadas = filas_actuales THEN 'OK' ELSE 'ERROR' END
FROM comparacion
UNION ALL
SELECT 'CONTROL|' || tabla || '|' || esperado || '|' || actual || '|' ||
        CASE WHEN esperado = actual THEN 'OK' ELSE 'ERROR' END
FROM controles
ORDER BY 1;
"@

    # RTO starts just before database creation and ends after validation.
    $restoreStartedAt = Get-Date
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()

    $null = Invoke-PostgresCommand 'createdb' @(
        '-h', $hostName, '-p', "$port", '-U', $user, '-w', $targetDatabase
    ) -CaptureOutput

    $null = Invoke-PostgresCommand 'pg_restore' @(
        '-h', $hostName, '-p', "$port", '-U', $user, '-w',
        '-d', $targetDatabase, '--no-owner', '--no-privileges', $backup.FullName
    ) -CaptureOutput

    $validationOutput = @(
        Invoke-PostgresCommand 'psql' @(
            '-h', $hostName, '-p', "$port", '-U', $user, '-w',
            '-d', $targetDatabase, '-X', '-A', '-t', '-F', '|', '-q',
            '-v', 'ON_ERROR_STOP=1', '-c', $validationSql
        ) -CaptureOutput
    )
    $validationRows = @(
        $validationOutput |
            ForEach-Object { ([string]$_).Trim() } |
            Where-Object { $_ -match '^(CONTEO|CONTROL)\|' }
    )

    if ($validationRows.Count -ne 7) {
        throw "Se esperaban siete resultados de validacion y se recibieron $($validationRows.Count)."
    }
    foreach ($row in $validationRows) {
        if (($row -split '\|')[-1] -ne 'OK') {
            throw "Fallo una validacion: $row"
        }
    }

    $stopwatch.Stop()
    $validationFinishedAt = Get-Date
    $rpo = $restoreStartedAt - $backup.LastWriteTime

    Write-RestoreLog "Inicio de restauracion : $($restoreStartedAt.ToString('yyyy-MM-dd HH:mm:ss zzz'))"
    Write-RestoreLog "Fin de validaciones    : $($validationFinishedAt.ToString('yyyy-MM-dd HH:mm:ss zzz'))"
    Write-RestoreLog "RTO observado          : $($stopwatch.Elapsed)"
    Write-RestoreLog "RPO al iniciar         : $rpo"
    Write-RestoreLog 'Validaciones            : OK'

    # Remove the disposable database only after successful validation.
    $null = Invoke-PostgresCommand 'dropdb' @(
        '-h', $hostName, '-p', "$port", '-U', $user, '-w', $targetDatabase
    ) -CaptureOutput
    Write-RestoreLog "Base descartable '$targetDatabase' eliminada tras validar."
    Write-RestoreLog 'Resultado              : OK'
}
catch {
    Write-RestoreLog "Resultado              : ERROR"
    Write-RestoreLog "Error                  : $($_.Exception.Message)"
    Write-RestoreLog "Log                    : $logPath"
    [Console]::Error.WriteLine("$($_.Exception.Message) Log: $logPath")
    exit 1
}

Write-Host "Simulacro completo. Log: $logPath"
