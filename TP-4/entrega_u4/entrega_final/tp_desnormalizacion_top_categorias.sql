-- ============================================================================
-- ENTREGA U4 - PARTE 2: DESNORMALIZACION CONTROLADA DEL REPORTE TOP 5
-- CATEGORIAS POR MONTO VENDIDO DEL DIA
-- Archivo: entrega_u4/sql/02_desnormalizacion.sql
-- Motor: PostgreSQL 17 (compatible con PostgreSQL 18)
-- Base destino: foodstore_u4_dev (sandbox de desarrollo, aislada de produccion)
-- ============================================================================
--
-- OBJETIVO
--   Responder el reporte de las cinco categorias con mayor monto vendido
--   durante el dia, comparando la consulta sobre el esquema normalizado con
--   una consulta sobre una estructura desnormalizada (vista materializada),
--   midiendo ambos planes con EXPLAIN (ANALYZE, BUFFERS) y auditando la
--   consistencia de la redundancia.
--
-- ESQUEMA REAL UTILIZADO (adaptaciones documentadas)
--   pedido.fecha_hora           -> TIMESTAMPTZ (no existe columna fecha)
--   detalle_pedido.cantidad     -> CHECK cantidad > 0
--   detalle_pedido.precio_unitario_historico -> CHECK >= 0
--   Importe de linea = cantidad * precio_unitario_historico
--                               (no existe columna subtotal)
--   No existen columnas tipo eliminado en pedido ni en detalle_pedido.
--   categoria.nombre tiene restriccion UNIQUE (sql/01_schema.sql:44), pero
--   la vista materializada usa categoria.id_categoria como identificador
--   estable de agrupacion, con categoria.nombre como dato descriptivo.
--
-- PATRON DE DESNORMALIZACION SELECCIONADO
--   Vista materializada que precalcula el monto vendido por categoria y
--   fecha (dia), almacenando el resultado agregado de la union de cuatro
--   tablas (pedido, detalle_pedido, producto, categoria). La consulta de
--   reporte lee solo la vista materializada filtrando por fecha.
--
--   Justificacion: el reporte se consulta con mucha frecuencia y el conjunto
--   de datos fuente es grande (miles de pedidos y cientos de miles de
--   detalles). El costo de agregacion se traslada del momento de consulta
--   al momento de refresco. La MV se refresca periodicamente (no en cada
--   consulta), por lo que NO garantiza tiempo real: entre dos refrescos
--   puede reflejar datos desactualizados. La latencia introducida es igual
--   al intervalo entre refrescos.
--
-- ZONA HORARIA
--   pedido.fecha_hora es TIMESTAMPTZ. La fecha diaria se calcula en la zona
--   horaria America/Argentina/Mendoza para que el corte de dia coincida con
--   el horario local del negocio, tanto en la MV como en las consultas
--   normalizadas y auditorias.
--
-- DEPENDENCIAS
--   sql/01_schema.sql  y  sql/02_data.sql  deben haberse ejecutado con
--   anterioridad sobre foodstore_u4_dev.
--
-- ORDEN DE EJECUCION
--   psql -U postgres -d foodstore_u4_dev -f entrega_u4/entrega_final/tp_desnormalizacion_top_categorias.sql
-- ============================================================================

\set ON_ERROR_STOP on
\timing on

-- ----------------------------------------------------------------------------
-- PASO 0 - ESTADISTICAS ACTUALIZADAS
-- Las mediciones de plano dependen de las estadisticas del optimizador.
-- ----------------------------------------------------------------------------

ANALYZE categoria;
ANALYZE producto;
ANALYZE pedido;
ANALYZE detalle_pedido;

-- ----------------------------------------------------------------------------
-- PASO 1 - CONSULTA NORMALIZADA (linea base)
-- Top 5 de categorias por monto vendido del dia sobre el esquema normalizado.
-- El filtro de fecha usa un rango sobre fecha_hora (sargable) en la zona
-- horaria America/Argentina/Mendoza. El ORDER BY incluye categoria ASC como
-- criterio secundario para que el resultado sea determinista ante empates.
-- ----------------------------------------------------------------------------

\echo '=== LINEA BASE: Top 5 del dia sobre el esquema normalizado ==='

EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT
    c.nombre                                        AS categoria,
    SUM(dp.cantidad * dp.precio_unitario_historico) AS total_vendido
FROM detalle_pedido dp
JOIN producto  pr  ON pr.id_producto = dp.id_producto
JOIN categoria c   ON c.id_categoria = pr.id_categoria
JOIN pedido    ped ON ped.id_pedido  = dp.id_pedido
WHERE ped.fecha_hora >= ((now() AT TIME ZONE 'America/Argentina/Mendoza')::date || ' 00:00:00 America/Argentina/Mendoza')::timestamptz
  AND ped.fecha_hora <  (((now() AT TIME ZONE 'America/Argentina/Mendoza')::date + 1) || ' 00:00:00 America/Argentina/Mendoza')::timestamptz
GROUP BY c.id_categoria, c.nombre
ORDER BY total_vendido DESC, c.nombre ASC
LIMIT 5;

-- ----------------------------------------------------------------------------
-- PASO 2 - ESTRUCTURA DESNORMALIZADA: VISTA MATERIALIZADA
--
-- Se agrupa por fecha (dia) y categoria para todo el historial. El filtro
-- WHERE fecha = (now() AT TIME ZONE 'America/Argentina/Mendoza')::date se aplica al consultar, nunca dentro del DDL,
-- porque (now() AT TIME ZONE 'America/Argentina/Mendoza')::date es volátil y no puede fijarse en la definicion de una
-- MV. La vista materializada almacena todas las fechas del historial; el filtro por dia se aplica solo al consultar.
--
-- Identificador estable: categoria.id_categoria (categoria.nombre tiene
-- UNIQUE pero se prefiere el id por estabilidad semantica). La columna
-- categoria se incluye como dato descriptivo.
--
-- Orden requerido por PostgreSQL para evitar doble carga de datos:
--   1. CREATE MATERIALIZED VIEW ... WITH NO DATA (no ejecuta la consulta de agrupacion)
--   2. CREATE UNIQUE INDEX (obligatorio para REFRESH ... CONCURRENTLY;
--      puede crearse sobre la MV vacia porque no hay filas que violen unicidad)
--   3. CREATE INDEX secundario (opcional, orientado a la consulta Top 5)
--   4. REFRESH MATERIALIZED VIEW (carga inicial, ejecuta la consulta y popula la MV)
-- ----------------------------------------------------------------------------

DROP MATERIALIZED VIEW IF EXISTS u4_mv_ventas_categoria_diaria;

CREATE MATERIALIZED VIEW u4_mv_ventas_categoria_diaria WITH NO DATA AS
SELECT
    (ped.fecha_hora AT TIME ZONE 'America/Argentina/Mendoza')::DATE AS fecha,
    c.id_categoria                                                   AS id_categoria,
    c.nombre                                                        AS categoria,
    SUM(dp.cantidad * dp.precio_unitario_historico) AS total_vendido,
    COUNT(*)                                                        AS lineas_vendidas,
    SUM(dp.cantidad)                                                AS unidades_vendidas
FROM detalle_pedido dp
JOIN producto  pr  ON pr.id_producto = dp.id_producto
JOIN categoria c   ON c.id_categoria = pr.id_categoria
JOIN pedido    ped ON ped.id_pedido  = dp.id_pedido
GROUP BY (ped.fecha_hora AT TIME ZONE 'America/Argentina/Mendoza')::DATE,
         c.id_categoria,
         c.nombre;

-- Indice unico obligatorio para REFRESH MATERIALIZED VIEW CONCURRENTLY.
-- Garantiza unicidad de (fecha, id_categoria) en la MV.
-- Puede crearse despues de CREATE MATERIALIZED VIEW ... WITH NO DATA porque
-- no hay filas que violen la restriccion de unicidad.
CREATE UNIQUE INDEX IF NOT EXISTS u4_idx_mv_ventas_fecha_cat
    ON u4_mv_ventas_categoria_diaria (fecha, id_categoria);

-- Indice secundario orientado a la consulta Top 5.
-- Coincide con el filtro WHERE fecha = ... y el ORDER BY total_vendido DESC, categoria ASC
-- de la consulta desnormalizada para permitir un escaneo ordenado sin orden adicional.
CREATE INDEX IF NOT EXISTS u4_idx_mv_ventas_fecha_total
    ON u4_mv_ventas_categoria_diaria (fecha, total_vendido DESC, categoria ASC);

-- ----------------------------------------------------------------------------
-- PASO 3 - CARGA INICIAL DE LA VISTA MATERIALIZADA
--
-- REFRESH MATERIALIZED VIEW (sin CONCURRENTLY) ejecuta la consulta de agrupacion
-- y popula la MV creada con WITH NO DATA. Es el unico refresco normal del script;
-- los refrescos posteriores deben usar CONCURRENTLY para permitir lecturas
-- durante el refresco:
--
--   REFRESH MATERIALIZED VIEW CONCURRENTLY u4_mv_ventas_categoria_diaria;
--
-- Nota: PostgreSQL no permite ejecutar REFRESH MATERIALIZED VIEW CONCURRENTLY
-- dentro de una funcion PL/pgSQL, por lo que no se encapsula en una funcion.
-- El refresco debe invocarse directamente (pg_cron, programador de tareas o
-- job externo) con la frecuencia que el negocio tolere, sabiendo que entre
-- dos refrescos los datos pueden estar desactualizados (no es tiempo real).
-- ----------------------------------------------------------------------------

REFRESH MATERIALIZED VIEW u4_mv_ventas_categoria_diaria;

-- Actualizar estadisticas de la MV despues de la carga inicial para que el
-- optimizador genere planes precisos en los EXPLAIN (ANALYZE, BUFFERS) que siguen.
ANALYZE u4_mv_ventas_categoria_diaria;

-- ----------------------------------------------------------------------------
-- PASO 4 - CONSULTA DESNORMALIZADA (reporte Top 5 del dia)
-- Equivalente a la consulta normalizada pero leyendo solo la MV.
-- El filtro usa la columna fecha (DATE) de la MV, ya calculada en la zona
-- horaria America/Argentina/Mendoza. ORDER BY incluye categoria ASC como
-- criterio secundario para determinismo ante empates.
-- ----------------------------------------------------------------------------

\echo '=== CONSULTA OPTIMIZADA: Top 5 del dia sobre la vista materializada ==='

EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT
    categoria,
    total_vendido
FROM u4_mv_ventas_categoria_diaria
WHERE fecha = (now() AT TIME ZONE 'America/Argentina/Mendoza')::date
ORDER BY total_vendido DESC, categoria ASC
LIMIT 5;

-- ----------------------------------------------------------------------------
-- PASO 5 - AUDITORIA DE CONSISTENCIA
-- Compara la vista materializada contra el esquema normalizado en ambas
-- direcciones para la fecha del dia. Resultado esperado: 0 filas en cada
-- direccion y conteos iguales.
-- ----------------------------------------------------------------------------

\echo '=== AUDITORIA: filas de la MV que no coinciden con el esquema normalizado ==='

WITH datos_normalizados AS (
    SELECT
        c.id_categoria                                                   AS id_categoria,
        c.nombre                                                        AS categoria,
        SUM(dp.cantidad * dp.precio_unitario_historico) AS total_vendido
    FROM detalle_pedido dp
    JOIN producto  pr  ON pr.id_producto = dp.id_producto
    JOIN categoria c   ON c.id_categoria = pr.id_categoria
    JOIN pedido    ped ON ped.id_pedido  = dp.id_pedido
    WHERE ped.fecha_hora >= ((now() AT TIME ZONE 'America/Argentina/Mendoza')::date || ' 00:00:00 America/Argentina/Mendoza')::timestamptz
      AND ped.fecha_hora <  (((now() AT TIME ZONE 'America/Argentina/Mendoza')::date + 1) || ' 00:00:00 America/Argentina/Mendoza')::timestamptz
    GROUP BY c.id_categoria, c.nombre
),
datos_mv AS (
    SELECT id_categoria, categoria, total_vendido
    FROM u4_mv_ventas_categoria_diaria
    WHERE fecha = (now() AT TIME ZONE 'America/Argentina/Mendoza')::date
)
SELECT 'MV_sobra'    AS direccion, id_categoria, categoria, total_vendido
FROM (
    SELECT id_categoria, categoria, total_vendido FROM datos_mv
    EXCEPT
    SELECT id_categoria, categoria, total_vendido FROM datos_normalizados
) AS sobrantes
UNION ALL
SELECT 'MV_falta'    AS direccion, id_categoria, categoria, total_vendido
FROM (
    SELECT id_categoria, categoria, total_vendido FROM datos_normalizados
    EXCEPT
    SELECT id_categoria, categoria, total_vendido FROM datos_mv
) AS faltantes;

\echo '=== AUDITORIA: conteos comparados por fuente ==='

SELECT 'esquema_normalizado' AS fuente, COUNT(*) AS categorias
FROM (
    SELECT c.id_categoria
    FROM detalle_pedido dp
    JOIN producto  pr  ON pr.id_producto = dp.id_producto
    JOIN categoria c   ON c.id_categoria = pr.id_categoria
    JOIN pedido    ped ON ped.id_pedido  = dp.id_pedido
    WHERE ped.fecha_hora >= ((now() AT TIME ZONE 'America/Argentina/Mendoza')::date || ' 00:00:00 America/Argentina/Mendoza')::timestamptz
      AND ped.fecha_hora <  (((now() AT TIME ZONE 'America/Argentina/Mendoza')::date + 1) || ' 00:00:00 America/Argentina/Mendoza')::timestamptz
    GROUP BY c.id_categoria
) AS q
UNION ALL
SELECT 'u4_mv_ventas_categoria_diaria', COUNT(*)
FROM u4_mv_ventas_categoria_diaria
WHERE fecha = (now() AT TIME ZONE 'America/Argentina/Mendoza')::date;

-- ----------------------------------------------------------------------------
-- PASO 6 - RESULTADOS IGUALES (consulta normalizada vs MV)
-- Compara el resultado completo (Top 5 ordenado) de ambas consultas para la
-- fecha del dia. Resultado esperado: 0 filas de diferencia.
-- ----------------------------------------------------------------------------

\echo '=== COMPARACION DE RESULTADOS: normalizada vs desnormalizada ==='

WITH normalizada AS (
    SELECT
        c.id_categoria                                                   AS id_categoria,
        c.nombre                                                        AS categoria,
        SUM(dp.cantidad * dp.precio_unitario_historico) AS total_vendido
    FROM detalle_pedido dp
    JOIN producto  pr  ON pr.id_producto = dp.id_producto
    JOIN categoria c   ON c.id_categoria = pr.id_categoria
    JOIN pedido    ped ON ped.id_pedido  = dp.id_pedido
    WHERE ped.fecha_hora >= ((now() AT TIME ZONE 'America/Argentina/Mendoza')::date || ' 00:00:00 America/Argentina/Mendoza')::timestamptz
      AND ped.fecha_hora <  (((now() AT TIME ZONE 'America/Argentina/Mendoza')::date + 1) || ' 00:00:00 America/Argentina/Mendoza')::timestamptz
    GROUP BY c.id_categoria, c.nombre
    ORDER BY total_vendido DESC, c.nombre ASC
    LIMIT 5
),
desnormalizada AS (
    SELECT id_categoria, categoria, total_vendido
    FROM u4_mv_ventas_categoria_diaria
    WHERE fecha = (now() AT TIME ZONE 'America/Argentina/Mendoza')::date
    ORDER BY total_vendido DESC, categoria ASC
    LIMIT 5
)
SELECT 'resultado_normalizado_sobra' AS direccion, id_categoria, categoria, total_vendido
FROM (
    SELECT id_categoria, categoria, total_vendido FROM normalizada
    EXCEPT
    SELECT id_categoria, categoria, total_vendido FROM desnormalizada
) AS sobrantes
UNION ALL
SELECT 'resultado_desnormalizado_sobra' AS direccion, id_categoria, categoria, total_vendido
FROM (
    SELECT id_categoria, categoria, total_vendido FROM desnormalizada
    EXCEPT
    SELECT id_categoria, categoria, total_vendido FROM normalizada
) AS faltantes;

-- ----------------------------------------------------------------------------
-- PASO 7 - GUIDA DE MEDICION (no se inventan valores)
-- Registrar en docs/informe_tecnico.md, copiando la salida real de cada
-- EXPLAIN (ANALYZE, BUFFERS) y el tiempo de ejecucion de \timing:
--   1. Execution Time y Planning Time de la consulta normalizada.
--   2. Nodo dominante del plan normalizado (coste relativo y filas).
--   3. Tiempo del REFRESH MATERIALIZED VIEW inicial (registro de \timing on).
--   4. Execution Time y Planning Time de la consulta sobre la MV.
--   5. Nodo dominante del plan sobre la MV.
--   6. Tiempo de REFRESH MATERIALIZED VIEW CONCURRENTLY y espacio de la MV
--      (pg_total_relation_size / pg_relation_size).
--   7. Filas leidas y buffers compartidos en ambos planes.
-- Las cifras deben obtenerse ejecutando este script en foodstore_u4_dev con
-- credenciales validas. No se incluyen valores inventados en este archivo.
-- ============================================================================
