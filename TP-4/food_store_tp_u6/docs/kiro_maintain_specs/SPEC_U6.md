# **SPEC_U6 — Plan de Mantenimiento y Respaldo | Food Store**

### 1. Objetivo del Plan de Mantenimiento

Garantizar la disponibilidad, integridad y recuperabilidad de la base de datos `foodstore` (PostgreSQL 17) mediante tareas automatizadas de respaldo, monitoreo de salud, mantenimiento de estadísticas y validación periódica de restauración. Todas las tareas se ejecutan con el rol `admin_datos` (DB Owner). Las credenciales se resuelven exclusivamente desde `%APPDATA%\postgresql\pgpass.conf`; queda prohibido hardcodearlas en cualquier script. La base `foodstore` nunca recibe operaciones destructivas; las pruebas de restauración se realizan sobre la base descartable `foodstore_restore_test`.

> **Aclaración sobre el Entorno de Pruebas y Horarios:**
> - **Horarios:** Las horas indicadas en la tabla corresponden a la planificación teórica de ventana nocturna en producción. En este entorno de laboratorio, la ejecución y generación de logs/evidencias se realiza a demanda de forma manual a través de la CLI de VS Code/PowerShell.
> - **Carga de Datos:** Al ser un entorno de desarrollo sin tráfico concurrente real de clientes, la base es inmutable salvo por las inserciones/modificaciones manuales ejecutadas durante las pruebas, lo cual se refleja en las lecturas de `pg_stat_user_tables`.
> - **Nombre de la base en el laboratorio:** Para las pruebas locales de esta entrega, la base configurada es `foodstore_dev`; el script de backup de evidencia apunta a esa base.
> - **Organización del Proyecto:** Los scripts están en `food_store_tp_u6/scripts/`, el dump y su checksum en `food_store_tp_u6/backups/`, los logs y evidencias en `food_store_tp_u6/logs/`, y esta especificación en `food_store_tp_u6/docs/kiro_maintain_specs/`. La bitácora está en `food_store_tp_u6/BITACORA_U6.md`.

La estructura actual de la unidad es:

```text
food_store_tp_u6/
├── BITACORA_U6.md
├── backups/
│   ├── foodstore_dev_<fecha_hora>.dump
│   └── foodstore_dev_<fecha_hora>.dump.sha256
├── docs/
│   └── kiro_maintain_specs/
│       └── SPEC_U6.md
├── logs/
│   ├── .gitkeep
│   ├── log_backup_foodstore_dev_<fecha_hora>.txt
│   ├── log_health_check.txt
│   ├── log_health_check_pre.txt
│   ├── log_maintenance.txt
│   ├── log_restore_test_<fecha_hora>.txt
│   └── log_setup_ownership.txt
└── scripts/
    ├── backup_foodstore.ps1
    ├── health_check.sql
    ├── health_check_pre.sql
    ├── maintenance.sql
    ├── restore_test.ps1
    └── setup_ownership.sql
```

La bitácora de U6 complementa esta especificación: registra decisiones, cambios realizados, pruebas y referencias a evidencias. Los logs generados por las automatizaciones se conservan en `food_store_tp_u6/logs/` y no reemplazan la bitácora.

Los logs iniciales `log_health_check_pre.txt` y `log_setup_ownership.txt` son evidencias de las verificaciones realizadas sobre `foodstore_dev`. Cada ejecución de backup, chequeo diario, mantenimiento o restauración deberá generar su propio log fechado en `logs/`.

### 2. Tabla de Tareas Programadas y Evidencias

| # | Tarea | Frecuencia | Script | Acción | Criterio de Éxito |
|---|---|---|---|---|---|
| 1 | Respaldo lógico | Diario 02:00 | `backup_foodstore.ps1` | `pg_dump -Fc -Z 6` sobre `foodstore_dev` en el laboratorio | Archivo `foodstore_dev_YYYYMMDD_HHMMSS.dump` generado; `pg_restore --list` sin errores; checksum SHA-256; log fechado en `logs/`; ejecución manual antes de considerarlo apto |
| 2 | Chequeo de salud | Diario 03:00 | `health_check.sql` vía `psql` | Consulta `pg_stat_activity`, `pg_stat_database`, `pg_stat_user_tables` | Log fechado con métricas de conexiones, tamaño de BD, sesiones bloqueadas y transacciones activas; sin errores de ejecución |
| 3 | Revisión de mantenimiento | Semanal Dom 03:30 | `maintenance.sql` vía `psql` | Revisa configuración de autovacuum e indicadores; ejecuta `ANALYZE` en `pedido`, `detalle_pedido` o `producto` solo si sus modificaciones desde el último análisis alcanzan el umbral efectivo de autoanalyze. No ejecuta `VACUUM FULL` ni `VACUUM` manual. | Log con umbrales y estadísticas previas; deja constancia de las tablas analizadas o de que no hacía falta actuar; muestra el estado posterior |
| 4 | Restauración de prueba | Semanal Dom 06:00 | `restore_test.ps1` | Verifica SHA-256 y `pg_restore --list`; restaura el dump más reciente en `foodstore_restore_test`; compara conteos con la referencia previa al backup y valida restricciones lógicas. | Registra RTO y RPO en un log; elimina la base descartable solo tras validar correctamente. Si ya existe, exige ejecutar con `-Recreate` para autorizar su reemplazo. |


### 3. Criterios de Aceptación y Reglas de Seguridad en PowerShell

- **Verificación de `$LASTEXITCODE`:** cada script `.ps1` evalúa `$LASTEXITCODE` inmediatamente después de invocar `pg_dump`, `pg_restore` o `psql`. Si el valor es distinto de `0`, el script aborta, registra el error en el log y sale con código no cero.
- **Sin credenciales en código:** las contraseñas se resuelven únicamente vía `pgpass.conf`. Ningún script contendrá literales de contraseña ni variables de entorno con credenciales en texto plano.
- **Prohibición sobre `foodstore`:** `DROP DATABASE foodstore`, `TRUNCATE` y `DELETE` sin `WHERE` sobre la base principal están estrictamente prohibidos. Toda operación destructiva se ejecuta exclusivamente sobre `foodstore_restore_test`.
- **Integridad del respaldo:** todo `.dump` debe pasar `pg_restore --list` antes de considerarse válido. Un archivo que no supere esa prueba no cuenta como respaldo del día.
- **Retención automática:** el script de respaldo elimina archivos con más de 14 días vía `Get-ChildItem | Where-Object | Remove-Item`. Cada eliminación queda registrada en el log.

### 4. Casos de Prueba Obligatorios para la Bitácora

| ID | Descripción | Resultado esperado |
|---|---|---|
| CP-01 | Ejecutar `backup_foodstore.ps1` manualmente | `.dump` presente; `pg_restore --list` sin errores; hash SHA-256 registrado en log |
| CP-02 | Simular falla de `pg_dump` (apuntar a BD inexistente) | Script aborta; `$LASTEXITCODE != 0` registrado; no se genera archivo corrupto |
| CP-03 | Ejecutar `health_check.sql` y verificar salida | Log fechado con valores de `pg_stat_database`; sin errores de conexión |
| CP-04 | Ejecutar `maintenance.sql` y verificar la decisión | Se ejecuta `ANALYZE` solo en tablas que alcanzan el umbral; si ninguna lo alcanza, el log lo indica y no se modifica el estado |
| CP-05 | Ejecutar `restore_test.ps1` con el último `.dump` válido | SHA-256 y archivo validados; conteos de referencia coinciden; productos/detalles inválidos dan cero; RTO/RPO registrados; base eliminada al finalizar correctamente |
| CP-06 | Verificar resolución de credenciales vía `pgpass.conf` | `psql` y `pg_dump` completan sin prompt interactivo de contraseña |