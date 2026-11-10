\set ON_ERROR_STOP on
\encoding UTF8

\echo '============================================================'
\echo 'REVISION DE MANTENIMIENTO - FOOD STORE | UNIDAD 6'
\echo '============================================================'

SELECT current_database() AS base,
        current_user AS rol,
        now() AS fecha_hora;

-- Revisar que autovacuum este habilitado y consultar sus umbrales efectivos.
\echo ''
\echo '--- CONFIGURACION DE AUTOVACUUM ---'
SELECT name, setting, unit
FROM pg_settings
WHERE name IN (
    'autovacuum',
    'autovacuum_analyze_threshold',
    'autovacuum_analyze_scale_factor',
    'autovacuum_vacuum_threshold',
    'autovacuum_vacuum_scale_factor'
)
ORDER BY name;

-- Calcular el umbral efectivo de autoanalyze, respetando ajustes por tabla.
\echo ''
\echo '--- ESTADO Y UMBRAL ANTES DEL ANALYZE ---'
CREATE TEMP TABLE maintenance_analyze_decision AS
SELECT s.schemaname,
        s.relname,
        s.n_live_tup,
        s.n_dead_tup,
        s.n_mod_since_analyze,
        s.last_autovacuum,
        s.last_autoanalyze,
        s.last_vacuum,
        s.last_analyze,
        thresholds.analyze_threshold
          + thresholds.analyze_scale_factor * GREATEST(c.reltuples, 0) AS umbral_autoanalyze,
        s.n_mod_since_analyze >=
          thresholds.analyze_threshold
          + thresholds.analyze_scale_factor * GREATEST(c.reltuples, 0) AS requiere_analyze
FROM pg_stat_user_tables AS s
JOIN pg_class AS c
  ON c.oid = format('%I.%I', s.schemaname, s.relname)::regclass
CROSS JOIN LATERAL (
    SELECT COALESCE(
                (SELECT option_value::double precision
                  FROM pg_options_to_table(c.reloptions)
                  WHERE option_name = 'autovacuum_analyze_threshold'),
                current_setting('autovacuum_analyze_threshold')::double precision
            ) AS analyze_threshold,
            COALESCE(
                (SELECT option_value::double precision
                  FROM pg_options_to_table(c.reloptions)
                  WHERE option_name = 'autovacuum_analyze_scale_factor'),
                current_setting('autovacuum_analyze_scale_factor')::double precision
            ) AS analyze_scale_factor
) AS thresholds
WHERE s.schemaname = 'public'
  AND s.relname IN ('pedido', 'detalle_pedido', 'producto');

SELECT schemaname AS esquema,
        relname AS tabla,
        n_live_tup AS filas_estimadas,
        n_dead_tup AS tuplas_muertas_estimadas,
        n_mod_since_analyze AS modificaciones_desde_analyze,
        round(umbral_autoanalyze::numeric, 0) AS umbral_autoanalyze,
        requiere_analyze,
        last_autovacuum,
        last_autoanalyze,
        last_vacuum,
        last_analyze
FROM maintenance_analyze_decision
ORDER BY relname;

-- Ejecutar ANALYZE solo cuando las modificaciones alcancen el umbral calculado.
\set ON_ERROR_STOP on
SELECT EXISTS (
    SELECT 1
    FROM maintenance_analyze_decision
    WHERE requiere_analyze
) AS analyze_needed \gset

\if :analyze_needed
\echo ''
\echo '--- ACCION: ANALYZE EN TABLAS QUE ALCANZARON EL UMBRAL ---'
SELECT format('ANALYZE VERBOSE %I.%I;', schemaname, relname)
FROM maintenance_analyze_decision
WHERE requiere_analyze
ORDER BY relname
\gexec
\else
\echo ''
\echo 'No se ejecuta ANALYZE: ninguna tabla alcanzo su umbral de autoanalyze.'
\endif

-- Mostrar nuevamente el historial y las estadisticas despues de la decision.
\echo ''
\echo '--- ESTADO DESPUES DE LA REVISION ---'
SELECT schemaname AS esquema,
        relname AS tabla,
        n_live_tup AS filas_estimadas,
        n_dead_tup AS tuplas_muertas_estimadas,
        n_mod_since_analyze AS modificaciones_desde_analyze,
        last_autovacuum,
        last_autoanalyze,
        last_vacuum,
        last_analyze
FROM pg_stat_user_tables
WHERE schemaname = 'public'
  AND relname IN ('pedido', 'detalle_pedido', 'producto')
ORDER BY relname;

\echo ''
\echo 'Fin de la revision. No se ejecuta VACUUM FULL ni VACUUM manual.'
