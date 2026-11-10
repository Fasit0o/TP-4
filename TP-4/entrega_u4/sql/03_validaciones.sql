-- ============================================================================
-- ENTREGA U4 - VALIDACIONES AUTOMATICAS (SOLO LECTURA)
-- Archivo: entrega_u4/sql/03_validaciones.sql
-- Motor: PostgreSQL 17 (compatible con PostgreSQL 18)
-- Base destino: foodstore_dev
-- ============================================================================
--
-- OBJETIVO
--   Verificar de forma declarativa y sin modificar datos:
--   1. Existencia de los objetos de la Parte 1 (FNBC) y Parte 2
--      (desnormalizacion).
--   2. Unicidad de las claves primarias en las tablas descompuestas.
--   3. Cumplimiento de DF2 (R -> D): cada responsable tiene un unico deposito.
--   4. Propiedad lossless-join: original EXCEPT vista y vista EXCEPT original
--      devuelven 0 filas en ambas direcciones.
--   5. Equivalencia de resultados entre la consulta normalizada y la
--      consulta sobre la estructura desnormalizada para la fecha del dia.
--   6. Consistencia de la vista materializada frente al esquema normalizado.
--
-- El script es de solo lectura: todo va dentro de BEGIN ... COMMIT y no
-- contiene DDL ni DML. Si una verificacion critica falla, lanza EXCEPTION
-- y detiene la ejecucion.
--
-- PRERREQUISITOS
--   1. sql/01_schema.sql y sql/02_data.sql (esquema principal y datos)
--   2. entrega_u4/sql/01_normalizacion_fnbc.sql
--   3. entrega_u4/sql/02_desnormalizacion.sql
--
-- ORDEN DE EJECUCION
--   psql -U postgres -d foodstore_dev -f entrega_u4/sql/03_validaciones.sql
-- ============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- ============================================================================
-- 0. COMPROBACION ANTICIPADA DE OBJETOS OBLIGATORIOS
-- Se ejecuta inmediatamente despues de BEGIN, antes de cualquier consulta
-- sobre las tablas o vistas, para fallar temprano con un mensaje claro.
-- ============================================================================

DO $do$
DECLARE
    v_obj_faltan TEXT;
BEGIN
    SELECT string_agg(obj, ', ') INTO v_obj_faltan
    FROM (
        SELECT obj
        FROM (VALUES
            ('u4_deposito'),
            ('u4_lote'),
            ('u4_responsable'),
            ('u4_control_lote_almacen'),
            ('u4_resp_deposito'),
            ('u4_control_asignacion'),
            ('u4_vw_control_lote_almacen'),
            ('u4_mv_ventas_categoria_diaria'),
            ('detalle_pedido'),
            ('producto'),
            ('categoria'),
            ('pedido')
        ) AS t(obj)
        WHERE to_regclass('public.' || obj) IS NULL
    ) AS faltantes;

    IF v_obj_faltan IS NOT NULL THEN
        RAISE EXCEPTION
            'Validacion bloqueada: faltan objetos obligatorios: %', v_obj_faltan;
    END IF;
END
$do$;

-- ============================================================================
-- 1. EXISTENCIA DE OBJETOS (reporte informativo)
-- ============================================================================

\echo '=== 1. Objetos de la Parte 1 - Normalizacion FNBC ==='

SELECT
    objeto,
    CASE WHEN to_regclass(objeto) IS NOT NULL THEN 'OK' ELSE 'FALTA' END AS estado
FROM (VALUES
    ('public.u4_deposito'),
    ('public.u4_lote'),
    ('public.u4_responsable'),
    ('public.u4_control_lote_almacen'),
    ('public.u4_resp_deposito'),
    ('public.u4_control_asignacion'),
    ('public.u4_vw_control_lote_almacen')
) AS v(objeto);

\echo '=== 2. Objetos de la Parte 2 - Desnormalizacion Top 5 ==='

SELECT
    objeto,
    CASE WHEN to_regclass(objeto) IS NOT NULL THEN 'OK' ELSE 'FALTA' END AS estado
FROM (VALUES
    ('public.u4_mv_ventas_categoria_diaria')
) AS v(objeto);

-- ============================================================================
-- 2. UNICIDAD DE CLAVES PRIMARIAS EN TABLAS DESCOMPUESTAS
-- ============================================================================

\echo '=== 3. Unicidad de PK en u4_resp_deposito (responsable_id) ==='

SELECT
    COUNT(*)                                          AS filas,
    COUNT(DISTINCT responsable_id)                    AS responsables_distintos,
    CASE WHEN COUNT(*) = COUNT(DISTINCT responsable_id)
         THEN 'OK' ELSE 'ERROR' END                   AS pk_resp_deposito
FROM u4_resp_deposito;

\echo '=== 4. Unicidad de PK en u4_control_asignacion ({lote_id, responsable_id}) ==='

SELECT
    COUNT(*)                                                              AS filas,
    COUNT(DISTINCT (lote_id, responsable_id))                             AS pares_distintos,
    CASE WHEN COUNT(*) = COUNT(DISTINCT (lote_id, responsable_id))
         THEN 'OK' ELSE 'ERROR' END                                       AS pk_control_asignacion
FROM u4_control_asignacion;

\echo '=== 5. Metadatos de restricciones PRIMARY KEY ==='

SELECT
    tc.table_name,
    kcu.column_name,
    tc.constraint_type
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
    ON tc.constraint_name = kcu.constraint_name
   AND tc.table_schema = kcu.table_schema
   AND tc.table_name = kcu.table_name
WHERE tc.table_schema = 'public'
  AND tc.table_name IN ('u4_resp_deposito', 'u4_control_asignacion')
  AND tc.constraint_type = 'PRIMARY KEY'
ORDER BY tc.table_name, kcu.ordinal_position;

-- ============================================================================
-- 3. DF2: CADA RESPONSABLE PERTENECE A UN SOLO DEPOSITO
-- ============================================================================

\echo '=== 6. DF2 (R -> D): responsables con mas de un deposito ==='

SELECT
    COUNT(*) AS responsables_con_multiples_depositos
FROM (
    SELECT responsable_id
    FROM u4_resp_deposito
    GROUP BY responsable_id
    HAVING COUNT(DISTINCT deposito_id) > 1
) AS violaciones;

-- ============================================================================
-- 4. PROPIEDAD LOSSLESS-JOIN (original <-> vista de compatibilidad)
-- ============================================================================

\echo '=== 7. Direccion A: vista EXCEPT original (debe ser 0 filas - sin tuplas espurias) ==='

SELECT COUNT(*) AS filas_espurias
FROM (
    SELECT lote_id, deposito_id, responsable_id
    FROM u4_vw_control_lote_almacen
    EXCEPT
    SELECT lote_id, deposito_id, responsable_id
    FROM u4_control_lote_almacen
) AS espurias;

\echo '=== 8. Direccion B: original EXCEPT vista (debe ser 0 filas - sin perdida de tuplas) ==='

SELECT COUNT(*) AS filas_perdidas
FROM (
    SELECT lote_id, deposito_id, responsable_id
    FROM u4_control_lote_almacen
    EXCEPT
    SELECT lote_id, deposito_id, responsable_id
    FROM u4_vw_control_lote_almacen
) AS perdidas;

\echo '=== 9. Conteos comparados ==='

SELECT
    (SELECT COUNT(*) FROM u4_control_lote_almacen)          AS original,
    (SELECT COUNT(*) FROM u4_vw_control_lote_almacen)       AS vista,
    (SELECT COUNT(*) FROM u4_resp_deposito)                 AS r1,
    (SELECT COUNT(*) FROM u4_control_asignacion)            AS r2;

-- ============================================================================
-- 5. EQUIVALENCIA CONSULTA NORMALIZADA vs DESNORMALIZADA (fecha del dia)
-- ============================================================================

\echo '=== 10. Diferencia de resultados: normalizada EXCEPT desnormalizada ==='

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
SELECT COUNT(*) AS filas_diferentes_normalizada
FROM (
    SELECT id_categoria, categoria, total_vendido FROM normalizada
    EXCEPT
    SELECT id_categoria, categoria, total_vendido FROM desnormalizada
) AS d1;

\echo '=== 11. Diferencia de resultados: desnormalizada EXCEPT normalizada ==='

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
SELECT COUNT(*) AS filas_diferentes_desnormalizada
FROM (
    SELECT id_categoria, categoria, total_vendido FROM desnormalizada
    EXCEPT
    SELECT id_categoria, categoria, total_vendido FROM normalizada
) AS d2;

-- ============================================================================
-- 6. CONSISTENCIA VISTA MATERIALIZADA vs ESQUEMA NORMALIZADO (dia actual)
-- ============================================================================

\echo '=== 12. Auditoria MV: diferencias de categoria/total_vendido ==='

WITH normalizado AS (
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
materializado AS (
    SELECT id_categoria, categoria, total_vendido
    FROM u4_mv_ventas_categoria_diaria
    WHERE fecha = (now() AT TIME ZONE 'America/Argentina/Mendoza')::date
),
dif_mv_normalizado AS (
    SELECT id_categoria, categoria, total_vendido FROM normalizado
    EXCEPT
    SELECT id_categoria, categoria, total_vendido FROM materializado
),
dif_mv_materializado AS (
    SELECT id_categoria, categoria, total_vendido FROM materializado
    EXCEPT
    SELECT id_categoria, categoria, total_vendido FROM normalizado
)
SELECT COUNT(*) AS diferencias_mv
FROM (
    SELECT id_categoria, categoria, total_vendido FROM dif_mv_normalizado
    UNION ALL
    SELECT id_categoria, categoria, total_vendido FROM dif_mv_materializado
) AS dif;

\echo '=== 13. Conteos de la auditoria de consistencia ==='

SELECT
    (SELECT COUNT(*) FROM (
        SELECT c.id_categoria
        FROM detalle_pedido dp
        JOIN producto  pr  ON pr.id_producto = dp.id_producto
        JOIN categoria c   ON c.id_categoria = pr.id_categoria
        JOIN pedido    ped ON ped.id_pedido  = dp.id_pedido
        WHERE ped.fecha_hora >= ((now() AT TIME ZONE 'America/Argentina/Mendoza')::date || ' 00:00:00 America/Argentina/Mendoza')::timestamptz
          AND ped.fecha_hora <  (((now() AT TIME ZONE 'America/Argentina/Mendoza')::date + 1) || ' 00:00:00 America/Argentina/Mendoza')::timestamptz
        GROUP BY c.id_categoria
    ) AS q)                                            AS categorias_normalizado,
    (SELECT COUNT(*) FROM u4_mv_ventas_categoria_diaria
     WHERE fecha = (now() AT TIME ZONE 'America/Argentina/Mendoza')::date)                       AS categorias_mv;

-- ============================================================================
-- 7. BLOQUE BLOQUEANTE: toda validacion critica debe pasar
-- ============================================================================

DO $do$
DECLARE
    v_orig     BIGINT;
    v_vista    BIGINT;
    v_faltan   BIGINT;
    v_sobran   BIGINT;
    v_multi    BIGINT;
    v_dif_mv   BIGINT;
    v_dif_res  BIGINT;
    v_pk_check BIGINT;
BEGIN
    -- Verificacion de restricciones PRIMARY KEY exactas
    SELECT COUNT(*) INTO v_pk_check
    FROM (
        SELECT tc.table_name, string_agg(kcu.column_name, ',' ORDER BY kcu.ordinal_position) AS pk_columns
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu
            ON tc.constraint_name = kcu.constraint_name
           AND tc.table_schema = kcu.table_schema
           AND tc.table_name = kcu.table_name
        WHERE tc.table_schema = 'public'
          AND tc.constraint_type = 'PRIMARY KEY'
          AND tc.table_name IN ('u4_resp_deposito', 'u4_control_asignacion')
        GROUP BY tc.table_name
    ) AS pk_info
    WHERE (table_name = 'u4_resp_deposito'     AND pk_columns = 'responsable_id')
       OR (table_name = 'u4_control_asignacion' AND pk_columns = 'lote_id,responsable_id');

    IF v_pk_check <> 2 THEN
        RAISE EXCEPTION
            'Validacion bloqueada: restricciones PRIMARY KEY incorrectas. Se esperan: '
            'u4_resp_deposito(responsable_id) y u4_control_asignacion(lote_id, responsable_id).';
    END IF;

    SELECT COUNT(*) INTO v_orig  FROM u4_control_lote_almacen;
    SELECT COUNT(*) INTO v_vista FROM u4_vw_control_lote_almacen;

    SELECT COUNT(*) INTO v_faltan
    FROM (
        SELECT lote_id, deposito_id, responsable_id
        FROM u4_control_lote_almacen
        EXCEPT
        SELECT lote_id, deposito_id, responsable_id
        FROM u4_vw_control_lote_almacen
    ) AS f;

    SELECT COUNT(*) INTO v_sobran
    FROM (
        SELECT lote_id, deposito_id, responsable_id
        FROM u4_vw_control_lote_almacen
        EXCEPT
        SELECT lote_id, deposito_id, responsable_id
        FROM u4_control_lote_almacen
    ) AS s;

    SELECT COUNT(*) INTO v_multi
    FROM (
        SELECT responsable_id
        FROM u4_resp_deposito
        GROUP BY responsable_id
        HAVING COUNT(DISTINCT deposito_id) > 1
    ) AS m;

    WITH normalizada AS (
        SELECT c.id_categoria AS id_categoria,
               c.nombre AS categoria,
               SUM(dp.cantidad * dp.precio_unitario_historico) AS total_vendido
        FROM detalle_pedido dp
        JOIN producto pr ON pr.id_producto = dp.id_producto
        JOIN categoria c ON c.id_categoria = pr.id_categoria
        JOIN pedido ped ON ped.id_pedido = dp.id_pedido
        WHERE ped.fecha_hora >= ((now() AT TIME ZONE 'America/Argentina/Mendoza')::date || ' 00:00:00 America/Argentina/Mendoza')::timestamptz
          AND ped.fecha_hora < (((now() AT TIME ZONE 'America/Argentina/Mendoza')::date + 1) || ' 00:00:00 America/Argentina/Mendoza')::timestamptz
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
    ),
    dif_res AS (
        (SELECT id_categoria, categoria, total_vendido FROM normalizada
         EXCEPT
         SELECT id_categoria, categoria, total_vendido FROM desnormalizada)
        UNION ALL
        (SELECT id_categoria, categoria, total_vendido FROM desnormalizada
         EXCEPT
         SELECT id_categoria, categoria, total_vendido FROM normalizada)
    )
    SELECT COUNT(*) INTO v_dif_res FROM dif_res;

    WITH normalizado AS (
        SELECT c.id_categoria AS id_categoria,
               c.nombre AS categoria,
               SUM(dp.cantidad * dp.precio_unitario_historico) AS total_vendido
        FROM detalle_pedido dp
        JOIN producto pr ON pr.id_producto = dp.id_producto
        JOIN categoria c ON c.id_categoria = pr.id_categoria
        JOIN pedido ped ON ped.id_pedido = dp.id_pedido
        WHERE ped.fecha_hora >= ((now() AT TIME ZONE 'America/Argentina/Mendoza')::date || ' 00:00:00 America/Argentina/Mendoza')::timestamptz
          AND ped.fecha_hora < (((now() AT TIME ZONE 'America/Argentina/Mendoza')::date + 1) || ' 00:00:00 America/Argentina/Mendoza')::timestamptz
        GROUP BY c.id_categoria, c.nombre
    ),
    materializado AS (
        SELECT id_categoria, categoria, total_vendido
        FROM u4_mv_ventas_categoria_diaria
        WHERE fecha = (now() AT TIME ZONE 'America/Argentina/Mendoza')::date
    ),
    dif_mv AS (
        (SELECT id_categoria, categoria, total_vendido FROM normalizado
         EXCEPT
         SELECT id_categoria, categoria, total_vendido FROM materializado)
        UNION ALL
        (SELECT id_categoria, categoria, total_vendido FROM materializado
         EXCEPT
         SELECT id_categoria, categoria, total_vendido FROM normalizado)
    )
    SELECT COUNT(*) INTO v_dif_mv FROM dif_mv;

    IF v_orig <> v_vista OR v_faltan > 0 OR v_sobran > 0 THEN
        RAISE EXCEPTION
            'FNBC: descomposicion NO equivalente (original=%, vista=%, faltan=%, sobran=%)',
            v_orig, v_vista, v_faltan, v_sobran;
    END IF;

    IF v_multi > 0 THEN
        RAISE EXCEPTION
            'FNBC: % responsables violan R -> D en u4_resp_deposito', v_multi;
    END IF;

    IF v_dif_res > 0 THEN
        RAISE EXCEPTION
            'Desnormalizacion: resultados normalizada vs desnormalizada difieren en % filas',
            v_dif_res;
    END IF;

    IF v_dif_mv > 0 THEN
        RAISE EXCEPTION
            'Desnormalizacion: MV inconsistente con el esquema normalizado (diferencias=%). '
            'Ejecutar REFRESH MATERIALIZED VIEW CONCURRENTLY u4_mv_ventas_categoria_diaria.', v_dif_mv;
    END IF;

    RAISE NOTICE 'VALIDACIONES U4 OK: lossless-join, DF2, unicidad de PK y equivalencia de consultas verificadas';
END
$do$;

COMMIT;

\echo '=== VALIDACIONES U4 FINALIZADAS ==='
