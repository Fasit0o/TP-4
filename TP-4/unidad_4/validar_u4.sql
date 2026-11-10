-- =============================================================================
-- VALIDACION AUTOMATICA - UNIDAD 4
-- Archivo : unidad_4/validar_u4.sql
-- Motor   : PostgreSQL 17
-- Base    : foodstore_dev
--
-- PRERREQUISITOS
--   1. sql/01_schema.sql
--   2. sql/02_data.sql
--   3. unidad_4/tp_fnbc_control_lote.sql
--   4. unidad_4/data_u4_pruebas.sql
--   5. unidad_4/tp_desnormalizacion_top_categorias.sql
--
-- El script es de solo lectura: no modifica datos ni objetos.
-- Si una verificacion critica falla, lanza EXCEPTION y detiene la ejecucion.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- =============================================================================
-- 1. OBJETOS ESPERADOS
-- =============================================================================

\echo '=== 1. Existencia de objetos U4 ==='

SELECT
    objeto,
    CASE WHEN to_regclass(objeto) IS NOT NULL THEN 'OK' ELSE 'FALTA' END AS estado
FROM (VALUES
    ('public.control_lote_almacen'),
    ('public.responsable_deposito'),
    ('public.control_lote_responsable'),
    ('public.vw_control_lote_almacen_compatibilidad'),
    ('public.mv_ventas_categoria_diario')
) AS v(objeto);

SELECT
    rutina,
    CASE WHEN to_regprocedure(rutina) IS NOT NULL THEN 'OK' ELSE 'FALTA' END AS estado
FROM (VALUES
    ('public.fn_refrescar_top5_categorias()')
) AS v(rutina);

-- =============================================================================
-- 2. FNBC: CLAVES Y DEPENDENCIAS
-- =============================================================================

\echo '=== 2. Integridad de R1 (responsable_deposito) ==='

SELECT
    COUNT(*) AS filas,
    COUNT(DISTINCT responsable_control_id) AS responsables_distintos,
    CASE WHEN COUNT(*) = COUNT(DISTINCT responsable_control_id) THEN 'OK' ELSE 'ERROR' END AS pk_r1
FROM responsable_deposito;

\echo '=== 3. Integridad de R2 (control_lote_responsable) ==='

SELECT
    COUNT(*) AS filas,
    COUNT(DISTINCT (lote_id, responsable_control_id)) AS pares_distintos,
    CASE WHEN COUNT(*) = COUNT(DISTINCT (lote_id, responsable_control_id)) THEN 'OK' ELSE 'ERROR' END AS pk_r2
FROM control_lote_responsable;

\echo '=== 4. DF2: cada responsable pertenece a un solo deposito ==='

SELECT
    COUNT(*) AS responsables_con_multiples_depositos
FROM (
    SELECT responsable_control_id
    FROM responsable_deposito
    GROUP BY responsable_control_id
    HAVING COUNT(DISTINCT deposito_id) > 1
) AS violaciones;

\echo '=== 5. Todo control de lote tiene responsable con deposito asignado ==='

SELECT COUNT(*) AS controles_huerfanos
FROM control_lote_responsable clr
LEFT JOIN responsable_deposito rd
    ON rd.responsable_control_id = clr.responsable_control_id
WHERE rd.responsable_control_id IS NULL;

-- =============================================================================
-- 6. EQUIVALENCIA ORIGINAL <-> VISTA (LOSSLESS-JOIN)
-- =============================================================================

\echo '=== 6. Direccion A: original menos vista (debe ser 0) ==='

SELECT COUNT(*) AS faltan_en_vista
FROM (
    SELECT lote_id, deposito_id, responsable_control_id
    FROM control_lote_almacen
    EXCEPT
    SELECT lote_id, deposito_id, responsable_control_id
    FROM vw_control_lote_almacen_compatibilidad
) AS faltantes;

\echo '=== 7. Direccion B: vista menos original (debe ser 0) ==='

SELECT COUNT(*) AS sobran_en_vista
FROM (
    SELECT lote_id, deposito_id, responsable_control_id
    FROM vw_control_lote_almacen_compatibilidad
    EXCEPT
    SELECT lote_id, deposito_id, responsable_control_id
    FROM control_lote_almacen
) AS sobrantes;

\echo '=== 8. Conteos comparados ==='

SELECT
    (SELECT COUNT(*) FROM control_lote_almacen) AS original,
    (SELECT COUNT(*) FROM vw_control_lote_almacen_compatibilidad) AS vista,
    (SELECT COUNT(*) FROM responsable_deposito) AS r1,
    (SELECT COUNT(*) FROM control_lote_responsable) AS r2;

-- =============================================================================
-- 9. VALIDACION BLOQUEANTE DE FNBC
-- =============================================================================

DO $do$
DECLARE
    v_original BIGINT;
    v_vista    BIGINT;
    v_faltan   BIGINT;
    v_sobran   BIGINT;
    v_multi    BIGINT;
BEGIN
    SELECT COUNT(*) INTO v_original FROM control_lote_almacen;
    SELECT COUNT(*) INTO v_vista    FROM vw_control_lote_almacen_compatibilidad;

    SELECT COUNT(*) INTO v_faltan
    FROM (
        SELECT lote_id, deposito_id, responsable_control_id
        FROM control_lote_almacen
        EXCEPT
        SELECT lote_id, deposito_id, responsable_control_id
        FROM vw_control_lote_almacen_compatibilidad
    ) AS f;

    SELECT COUNT(*) INTO v_sobran
    FROM (
        SELECT lote_id, deposito_id, responsable_control_id
        FROM vw_control_lote_almacen_compatibilidad
        EXCEPT
        SELECT lote_id, deposito_id, responsable_control_id
        FROM control_lote_almacen
    ) AS s;

    SELECT COUNT(*) INTO v_multi
    FROM (
        SELECT responsable_control_id
        FROM responsable_deposito
        GROUP BY responsable_control_id
        HAVING COUNT(DISTINCT deposito_id) > 1
    ) AS m;

    IF v_original <> v_vista OR v_faltan > 0 OR v_sobran > 0 THEN
        RAISE EXCEPTION
            'FNBC: descomposicion NO equivalente (original=%, vista=%, faltan=%, sobran=%)',
            v_original, v_vista, v_faltan, v_sobran;
    END IF;

    IF v_multi > 0 THEN
        RAISE EXCEPTION
            'FNBC: % responsables violan R -> D en responsable_deposito', v_multi;
    END IF;

    RAISE NOTICE 'FNBC OK: descomposicion equivalente y DF2 respetada';
END
$do$;

-- =============================================================================
-- 10. VISTA MATERIALIZADA: DEFINICION E INDICES
-- =============================================================================

\echo '=== 9. Indices de la vista materializada ==='

SELECT
    indexname,
    indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename = 'mv_ventas_categoria_diario'
ORDER BY indexname;

\echo '=== 10. Auditoria MV vs esquema normalizado (debe devolver 0 filas) ==='

WITH normalizado AS (
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
materializado AS (
    SELECT categoria, total_vendido
    FROM mv_ventas_categoria_diario
    WHERE fecha = CURRENT_DATE
)
SELECT 'MV_sobra' AS direccion, categoria, total_vendido
FROM (
    SELECT categoria, total_vendido FROM materializado
    EXCEPT
    SELECT categoria, total_vendido FROM normalizado
) AS s
UNION ALL
SELECT 'MV_falta' AS direccion, categoria, total_vendido
FROM (
    SELECT categoria, total_vendido FROM normalizado
    EXCEPT
    SELECT categoria, total_vendido FROM materializado
) AS f;

-- =============================================================================
-- 11. VALIDACION BLOQUEANTE DE LA MV
-- =============================================================================

DO $do$
DECLARE
    v_normalizado BIGINT;
    v_mv          BIGINT;
    v_diferencias BIGINT;
BEGIN
    SELECT COUNT(*) INTO v_normalizado
    FROM (
        SELECT c.nombre
        FROM detalle_pedido dp
        JOIN producto  pr  ON pr.id_producto = dp.id_producto
        JOIN categoria c   ON c.id_categoria = pr.id_categoria
        JOIN pedido    ped ON ped.id_pedido  = dp.id_pedido
        WHERE DATE(ped.fecha_hora) = CURRENT_DATE
        GROUP BY c.nombre
    ) AS q;

    SELECT COUNT(*) INTO v_mv
    FROM mv_ventas_categoria_diario
    WHERE fecha = CURRENT_DATE;

    WITH normalizado AS (
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
    materializado AS (
        SELECT categoria, total_vendido
        FROM mv_ventas_categoria_diario
        WHERE fecha = CURRENT_DATE
    ),
    diferencias AS (
        (SELECT categoria, total_vendido FROM normalizado
         EXCEPT
         SELECT categoria, total_vendido FROM materializado)
        UNION ALL
        (SELECT categoria, total_vendido FROM materializado
         EXCEPT
         SELECT categoria, total_vendido FROM normalizado)
    )
    SELECT COUNT(*) INTO v_diferencias FROM diferencias;

    IF v_normalizado <> v_mv OR v_diferencias > 0 THEN
        RAISE EXCEPTION
            'MV: inconsistencia (normalizado=%, mv=%, diferencias=%). Ejecutar fn_refrescar_top5_categorias().',
            v_normalizado, v_mv, v_diferencias;
    END IF;

    RAISE NOTICE 'MV OK: % categorias consistentes con el esquema normalizado', v_mv;
END
$do$;

-- =============================================================================
-- 12. REPORTE DE ANOMALIAS DE LA INSTANCIA ORIGINAL
-- La tabla original conserva la redundancia a proposito, como evidencia.
-- =============================================================================

\echo '=== 11. Redundancia visible en la tabla original ==='

SELECT
    responsable_control_id,
    deposito_id,
    COUNT(*) AS filas_redundantes
FROM control_lote_almacen
GROUP BY responsable_control_id, deposito_id
HAVING COUNT(*) > 1
ORDER BY filas_redundantes DESC, responsable_control_id;

COMMIT;

\echo '=== VALIDACION U4 FINALIZADA ==='
