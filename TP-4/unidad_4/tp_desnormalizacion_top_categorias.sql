-- =============================================================================
-- DESNORMALIZACION CONTROLADA - TOP 5 CATEGORIAS POR VENTAS DEL DIA
-- Archivo : unidad_4/tp_desnormalizacion_top_categorias.sql
-- Motor   : PostgreSQL 17
-- Base    : foodstore_dev
-- Autora  : Agustina Micaela Guzman
--
-- OBJETIVO
--   Precalcular en una vista materializada la facturacion diaria por categoria
--   para responder el Top 5 sin recorrer pedido + detalle_pedido + producto +
--   categoria en cada consulta.
--
-- ESQUEMA REAL UTILIZADO
--   pedido.fecha_hora                 (no existe pedido.fecha)
--   detalle_pedido.cantidad           (cantidad > 0 por CHECK)
--   detalle_pedido.precio_unitario_historico
--   Importe de linea = cantidad * precio_unitario_historico
--   (no existe detalle_pedido.subtotal)
--
-- DEPENDENCIAS
--   sql/01_schema.sql
--   sql/02_data.sql
--   El script debe ejecutarse DESPUES de la carga de datos.
--
-- ORDEN DE EJECUCION
--   psql -U postgres -d foodstore_dev -f unidad_4/tp_desnormalizacion_top_categorias.sql
-- =============================================================================

\set ON_ERROR_STOP on

-- =============================================================================
-- PASO 0 - ESTADISTICAS ACTUALIZADAS
-- =============================================================================

ANALYZE pedido;
ANALYZE detalle_pedido;
ANALYZE producto;
ANALYZE categoria;

-- =============================================================================
-- PASO 1 - CONSULTA ORIGINAL (SIN DESNORMALIZAR)
-- Se conserva como linea base de comparacion. Debe medirse ANTES de crear la
-- vista materializada y con las mismas estadisticas.
-- =============================================================================

\echo '=== LINEA BASE: Top 5 del dia sobre el esquema normalizado ==='

EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT
    c.nombre AS categoria,
    SUM(dp.cantidad * dp.precio_unitario_historico) AS total_vendido
FROM detalle_pedido dp
JOIN producto  pr  ON pr.id_producto = dp.id_producto
JOIN categoria c   ON c.id_categoria = pr.id_categoria
JOIN pedido    ped ON ped.id_pedido  = dp.id_pedido
WHERE DATE(ped.fecha_hora) = CURRENT_DATE
GROUP BY c.nombre
ORDER BY total_vendido DESC
LIMIT 5;

-- =============================================================================
-- PASO 2 - VISTA MATERIALIZADA
-- Agrupa por fecha y categoria para todos los dias historicos. El filtro
-- WHERE fecha = CURRENT_DATE se aplica al consultar, no en el DDL, porque
-- CURRENT_DATE es volatil y no puede usarse dentro de una MV.
--
-- Se elimina sin CASCADE para no borrar objetos dependientes de forma
-- silenciosa. Si se reejecuta despues de food_store_tp_u5/sql/roles.sql,
-- hay que volver a aplicar el GRANT SELECT al rol_reportes.
-- =============================================================================

DROP MATERIALIZED VIEW IF EXISTS mv_ventas_categoria_diario;

CREATE MATERIALIZED VIEW mv_ventas_categoria_diario AS
SELECT
    DATE(ped.fecha_hora)                            AS fecha,
    c.nombre                                        AS categoria,
    SUM(dp.cantidad * dp.precio_unitario_historico) AS total_vendido,
    COUNT(*)                                        AS lineas_vendidas,
    SUM(dp.cantidad)                                AS unidades_vendidas
FROM detalle_pedido dp
JOIN producto  pr  ON pr.id_producto = dp.id_producto
JOIN categoria c   ON c.id_categoria = pr.id_categoria
JOIN pedido    ped ON ped.id_pedido  = dp.id_pedido
GROUP BY DATE(ped.fecha_hora), c.nombre;

-- Indice unico obligatorio para REFRESH MATERIALIZED VIEW CONCURRENTLY.
-- Tambien acelera el filtro por fecha y el orden por total_vendido.
CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_ventas_fecha_cat
    ON mv_ventas_categoria_diario (fecha, categoria);

CREATE INDEX IF NOT EXISTS idx_mv_ventas_fecha_total
    ON mv_ventas_categoria_diario (fecha, total_vendido DESC);

-- =============================================================================
-- PASO 3 - CARGA INICIAL
-- =============================================================================

REFRESH MATERIALIZED VIEW mv_ventas_categoria_diario;

-- =============================================================================
-- PASO 4 - FUNCION DE REFRESCO
-- Encapsula el refresco concurrente para que pueda invocarse desde pg_cron,
-- pgAgent, Task Scheduler o un job externo.
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_refrescar_top5_categorias()
RETURNS void
LANGUAGE plpgsql
AS $fn$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_ventas_categoria_diario;
END;
$fn$;

-- Ejemplo de refresco manual:
--   SELECT fn_refrescar_top5_categorias();

-- =============================================================================
-- PASO 5 - CONSULTA DE USO SOBRE LA VISTA MATERIALIZADA
-- =============================================================================

\echo '=== CONSULTA OPTIMIZADA: Top 5 del dia sobre la MV ==='

EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT
    categoria,
    total_vendido
FROM mv_ventas_categoria_diario
WHERE fecha = CURRENT_DATE
ORDER BY total_vendido DESC
LIMIT 5;

-- =============================================================================
-- PASO 6 - AUDITORIA DE CONSISTENCIA
-- Compara la MV contra el esquema normalizado en ambas direcciones.
-- Resultado esperado: 0 filas y conteos iguales.
-- =============================================================================

\echo '=== AUDITORIA: filas de la MV que no coinciden con el esquema normalizado ==='

WITH datos_normalizados AS (
    SELECT
        c.nombre AS categoria,
        SUM(dp.cantidad * dp.precio_unitario_historico) AS total_vendido
    FROM detalle_pedido dp
    JOIN producto  pr  ON pr.id_producto = dp.id_producto
    JOIN categoria c   ON c.id_categoria = pr.id_categoria
    JOIN pedido    ped ON ped.id_pedido  = dp.id_pedido
    WHERE DATE(ped.fecha_hora) = CURRENT_DATE
    GROUP BY c.nombre
),
datos_mv AS (
    SELECT categoria, total_vendido
    FROM mv_ventas_categoria_diario
    WHERE fecha = CURRENT_DATE
)
SELECT 'MV_sobra' AS direccion, categoria, total_vendido
FROM (
    SELECT categoria, total_vendido FROM datos_mv
    EXCEPT
    SELECT categoria, total_vendido FROM datos_normalizados
) AS sobrantes
UNION ALL
SELECT 'MV_falta' AS direccion, categoria, total_vendido
FROM (
    SELECT categoria, total_vendido FROM datos_normalizados
    EXCEPT
    SELECT categoria, total_vendido FROM datos_mv
) AS faltantes;

\echo '=== AUDITORIA: conteos por fuente ==='

SELECT 'esquema_normalizado' AS fuente, COUNT(*) AS categorias
FROM (
    SELECT c.nombre
    FROM detalle_pedido dp
    JOIN producto  pr  ON pr.id_producto = dp.id_producto
    JOIN categoria c   ON c.id_categoria = pr.id_categoria
    JOIN pedido    ped ON ped.id_pedido  = dp.id_pedido
    WHERE DATE(ped.fecha_hora) = CURRENT_DATE
    GROUP BY c.nombre
) AS q
UNION ALL
SELECT 'mv_ventas_categoria_diario', COUNT(*)
FROM mv_ventas_categoria_diario
WHERE fecha = CURRENT_DATE;

-- =============================================================================
-- PASO 7 - GUIA DE MEDICION
-- Registrar en docs/informes/informe_mediciones.md:
--   1. Tiempo de ejecucion (Execution Time) de la consulta original.
--   2. Tiempo de ejecucion de la consulta sobre la MV.
--   3. Filas leidas / buffers compartidos en cada plan.
--   4. Costo de mantenimiento: tiempo de REFRESH MATERIALIZED VIEW.
--   5. Espacio ocupado por la MV y sus indices.
--
-- NO se deben inventar valores: las cifras deben copiarse de la salida real
-- de EXPLAIN (ANALYZE, BUFFERS) en foodstore_dev.
-- =============================================================================
