\set ON_ERROR_STOP on
\encoding UTF8

\echo '============================================================'
\echo 'CHEQUEO DE SALUD - FOOD STORE | UNIDAD 6'
\echo '============================================================'

-- Contexto de la conexion
SELECT current_database() AS base,
        current_user AS rol,
        now() AS fecha_hora;

-- 1. Tamano total de la base conectada
\echo ''
\echo '--- 1. TAMANO DE LA BASE ---'
SELECT pg_size_pretty(pg_database_size(current_database())) AS tamano_base;

-- 2. Actividad y transacciones registradas para esta base
\echo ''
\echo '--- 2. ACTIVIDAD DE CONEXIONES ---'
SELECT numbackends AS conexiones_actuales,
        xact_commit AS transacciones_confirmadas,
        xact_rollback AS transacciones_revertidas,
        stats_reset AS estadisticas_reiniciadas
FROM pg_stat_database
WHERE datname = current_database();

-- 3. Estado estadistico de las tablas de usuario; los conteos son estimados
\echo ''
\echo '--- 3. ESTADO DE TABLAS ---'
SELECT schemaname AS esquema,
        relname AS tabla,
        n_live_tup AS filas_estimadas,
        n_dead_tup AS tuplas_muertas_estimadas,
        last_autovacuum,
        last_autoanalyze,
        last_vacuum,
        last_analyze
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC, schemaname, relname;

-- 4. Consultas de otras sesiones que no estan inactivas
\echo ''
\echo '--- 4. CONSULTAS ACTIVAS ---'
SELECT pid,
        usename AS usuario,
        state AS estado,
        now() - query_start AS duracion,
        wait_event_type,
        wait_event,
        pg_blocking_pids(pid) AS bloqueado_por,
        query
FROM pg_stat_activity
WHERE datname = current_database()
  AND pid <> pg_backend_pid()
  AND state <> 'idle'
ORDER BY query_start;

\echo ''
\echo 'Fin del chequeo. Las filas y tuplas de pg_stat_user_tables son estimaciones.'
