-- =============================================================================
-- CHEQUEO PRE-TRABAJO — FOOD STORE (Unidad 6)
-- Archivo : health_check_pre.sql
-- Base    : foodstore_dev
-- Rol     : admin_datos
-- Propósito: Verificar que el esquema, los datos y las relaciones estén
--            íntegros antes de comenzar las tareas de mantenimiento.
-- Log     : food_store_tp_u6/logs/log_health_check_pre.txt
-- =============================================================================

\set ON_ERROR_STOP on
\encoding UTF8

\echo '============================================================'
\echo 'CHEQUEO PRE-TRABAJO — FOOD STORE'
\echo '============================================================'

-- ─────────────────────────────────────────────────────────────────────────────
-- BLOQUE 0: CONTEXTO REAL DE LA CONEXIÓN
-- ─────────────────────────────────────────────────────────────────────────────
\echo ''
\echo '--- [0] CONEXIÓN ACTUAL (comparar con la base objetivo del backup) ---'

SELECT current_database() AS base,
        current_user AS rol,
        inet_server_addr() AS servidor,
        inet_server_port() AS puerto,
        pg_is_in_recovery() AS es_replica;

-- ─────────────────────────────────────────────────────────────────────────────
-- BLOQUE 1: EXISTENCIA DE TABLAS Y TIPO ENUM
-- ─────────────────────────────────────────────────────────────────────────────
\echo ''
\echo '--- [1] TABLAS PRESENTES EN EL ESQUEMA PUBLIC ---'

SELECT
    table_name,
    table_type
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_type    = 'BASE TABLE'
ORDER BY table_name;

-- El listado muestra todas las tablas base del esquema public.

\echo ''
\echo '--- [1b] TIPO ENUM forma_pago_enum ---'

SELECT
    t.typname   AS enum_nombre,
    e.enumlabel AS valor
FROM pg_type t
JOIN pg_enum e ON e.enumtypid = t.oid
WHERE t.typname = 'forma_pago_enum'
ORDER BY e.enumsortorder;

-- Esperado: EFECTIVO, TARJETA, TRANSFERENCIA

-- ─────────────────────────────────────────────────────────────────────────────
-- BLOQUE 2: DEFINICIÓN DE COLUMNAS (tipos, nulabilidad, defaults)
-- ─────────────────────────────────────────────────────────────────────────────
\echo ''
\echo '--- [2] DEFINICIÓN DE COLUMNAS POR TABLA ---'

SELECT
    c.table_name,
    c.column_name,
    c.data_type,
    c.is_nullable,
    c.column_default
FROM information_schema.columns c
WHERE c.table_schema = 'public'
  AND c.table_name IN ('categoria','producto','cliente','pedido','detalle_pedido')
ORDER BY c.table_name, c.ordinal_position;

-- ─────────────────────────────────────────────────────────────────────────────
-- BLOQUE 3: CLAVES PRIMARIAS
-- ─────────────────────────────────────────────────────────────────────────────
\echo ''
\echo '--- [3] CLAVES PRIMARIAS ---'

SELECT
    tc.table_name,
    kcu.column_name,
    tc.constraint_name
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
    ON kcu.constraint_name = tc.constraint_name
   AND kcu.table_schema    = tc.table_schema
WHERE tc.constraint_type = 'PRIMARY KEY'
  AND tc.table_schema    = 'public'
ORDER BY tc.table_name, kcu.ordinal_position;

-- ─────────────────────────────────────────────────────────────────────────────
-- BLOQUE 4: CLAVES FORÁNEAS, VALIDACIÓN Y POLÍTICA ON DELETE
-- ─────────────────────────────────────────────────────────────────────────────
\echo ''
\echo '--- [4] CLAVES FORÁNEAS (incluye estado de validación) ---'

SELECT
    conrelid::regclass AS tabla_hija,
    conname AS nombre,
    confrelid::regclass AS tabla_padre,
    pg_get_constraintdef(oid) AS definicion,
    CASE confdeltype
        WHEN 'a' THEN 'NO ACTION'
        WHEN 'r' THEN 'RESTRICT'
        WHEN 'c' THEN 'CASCADE'
        WHEN 'n' THEN 'SET NULL'
        WHEN 'd' THEN 'SET DEFAULT'
    END AS on_delete,
    convalidated AS validada
FROM pg_constraint
WHERE contype = 'f'
  AND connamespace = 'public'::regnamespace
ORDER BY conrelid::regclass::text, conname;

-- Revisar cualquier clave foránea no validada y confirmar la política ON DELETE
-- esperada para cada relación del esquema.

-- ─────────────────────────────────────────────────────────────────────────────
-- BLOQUE 5: RESTRICCIONES CHECK
-- ─────────────────────────────────────────────────────────────────────────────
\echo ''
\echo '--- [5] RESTRICCIONES CHECK ---'

SELECT
    tc.table_name,
    tc.constraint_name,
    cc.check_clause
FROM information_schema.table_constraints tc
JOIN information_schema.check_constraints cc
    ON cc.constraint_name   = tc.constraint_name
   AND cc.constraint_schema = tc.table_schema
WHERE tc.constraint_type = 'CHECK'
  AND tc.table_schema    = 'public'
ORDER BY tc.table_name, tc.constraint_name;

-- ─────────────────────────────────────────────────────────────────────────────
-- BLOQUE 6: ÍNDICES Y ESTADO OPERATIVO
-- ─────────────────────────────────────────────────────────────────────────────
\echo ''
\echo '--- [6] ÍNDICES DEL ESQUEMA Y ESTADO DE VALIDEZ ---'

SELECT
    ns.nspname AS esquema,
    tbl.relname AS tabla,
    idx.relname AS indice,
    pg_get_indexdef(i.indexrelid) AS definicion,
    i.indisvalid AS valido,
    i.indisready AS listo_para_escrituras,
    i.indislive AS activo
FROM pg_index i
JOIN pg_class idx ON idx.oid = i.indexrelid
JOIN pg_class tbl ON tbl.oid = i.indrelid
JOIN pg_namespace ns ON ns.oid = tbl.relnamespace
WHERE ns.nspname = 'public'
ORDER BY tbl.relname, idx.relname;

-- Un índice con valido/listo_para_escrituras/activo = false requiere revisión.

-- ─────────────────────────────────────────────────────────────────────────────
-- BLOQUE 7: CONTEOS DE FILAS POR TABLA
-- ─────────────────────────────────────────────────────────────────────────────
\echo ''
\echo '--- [7] CONTEO EXACTO DE FILAS EN TODAS LAS TABLAS Y VISTAS MATERIALIZADAS ---'

-- COUNT(*) exacto puede leer cada relación completa. Se limita a objetos de
-- esquemas de usuario y se ejecuta de manera dinámica para incluir tablas nuevas.
SELECT format(
           'SELECT %L AS esquema, %L AS relacion, %L AS tipo, count(*) AS filas FROM %I.%I',
           n.nspname,
           c.relname,
           CASE c.relkind
               WHEN 'r' THEN 'TABLA'
               WHEN 'p' THEN 'TABLA PARTICIONADA'
               WHEN 'm' THEN 'VISTA MATERIALIZADA'
           END,
           n.nspname,
           c.relname
       )
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r', 'p', 'm')
  AND n.nspname <> 'information_schema'
  AND n.nspname NOT LIKE 'pg_%'
ORDER BY n.nspname, c.relname
\gexec

-- ─────────────────────────────────────────────────────────────────────────────
-- BLOQUE 8: INTEGRIDAD REFERENCIAL — HUÉRFANOS EN TODAS LAS FKs DEL ESQUEMA
-- ─────────────────────────────────────────────────────────────────────────────
\echo ''
\echo '--- [8] REGISTROS HUÉRFANOS EN LAS RELACIONES DEL ESQUEMA ---'

SELECT 'producto.id_categoria -> categoria.id_categoria' AS verificacion, COUNT(*) AS huerfanos
FROM producto p
WHERE NOT EXISTS (
    SELECT 1 FROM categoria c WHERE c.id_categoria = p.id_categoria
)
UNION ALL
SELECT 'pedido.id_cliente -> cliente.id_cliente', COUNT(*)
FROM pedido pe
WHERE NOT EXISTS (
    SELECT 1 FROM cliente cl WHERE cl.id_cliente = pe.id_cliente
)
UNION ALL
SELECT 'detalle_pedido.id_pedido -> pedido.id_pedido', COUNT(*)
FROM detalle_pedido dp
WHERE NOT EXISTS (
    SELECT 1 FROM pedido pe WHERE pe.id_pedido = dp.id_pedido
)
UNION ALL
SELECT 'detalle_pedido.id_producto -> producto.id_producto', COUNT(*)
FROM detalle_pedido dp
WHERE NOT EXISTS (
    SELECT 1 FROM producto pr WHERE pr.id_producto = dp.id_producto
)
UNION ALL
SELECT 'control_lote_almacen.lote_id -> lote.id', COUNT(*)
FROM control_lote_almacen cla
WHERE NOT EXISTS (SELECT 1 FROM lote l WHERE l.id = cla.lote_id)
UNION ALL
SELECT 'control_lote_almacen.deposito_id -> deposito.id', COUNT(*)
FROM control_lote_almacen cla
WHERE NOT EXISTS (SELECT 1 FROM deposito d WHERE d.id = cla.deposito_id)
UNION ALL
SELECT 'control_lote_almacen.responsable_control_id -> responsable_control.id', COUNT(*)
FROM control_lote_almacen cla
WHERE NOT EXISTS (
    SELECT 1 FROM responsable_control rc
    WHERE rc.id = cla.responsable_control_id
)
UNION ALL
SELECT 'control_lote_responsable.lote_id -> lote.id', COUNT(*)
FROM control_lote_responsable clr
WHERE NOT EXISTS (SELECT 1 FROM lote l WHERE l.id = clr.lote_id)
UNION ALL
SELECT 'control_lote_responsable.responsable_control_id -> responsable_deposito.responsable_control_id', COUNT(*)
FROM control_lote_responsable clr
WHERE NOT EXISTS (
    SELECT 1 FROM responsable_deposito rd
    WHERE rd.responsable_control_id = clr.responsable_control_id
)
UNION ALL
SELECT 'responsable_deposito.deposito_id -> deposito.id', COUNT(*)
FROM responsable_deposito rd
WHERE NOT EXISTS (SELECT 1 FROM deposito d WHERE d.id = rd.deposito_id)
UNION ALL
SELECT 'responsable_deposito.responsable_control_id -> responsable_control.id', COUNT(*)
FROM responsable_deposito rd
WHERE NOT EXISTS (
    SELECT 1 FROM responsable_control rc
    WHERE rc.id = rd.responsable_control_id
);

-- ─────────────────────────────────────────────────────────────────────────────
-- BLOQUE 9: VIOLACIONES DE CHECK — DATOS INVÁLIDOS
-- ─────────────────────────────────────────────────────────────────────────────
\echo ''
\echo '--- [9] VIOLACIONES DE REGLAS DE NEGOCIO (deben ser 0) ---'

SELECT 'precio_lista < 0'    AS violacion, COUNT(*) AS cantidad FROM producto WHERE precio_lista < 0
UNION ALL
SELECT 'stock < 0',                        COUNT(*) FROM producto WHERE stock < 0
UNION ALL
SELECT 'cantidad detalle <= 0',            COUNT(*) FROM detalle_pedido WHERE cantidad <= 0
UNION ALL
SELECT 'precio_hist < 0',                  COUNT(*) FROM detalle_pedido WHERE precio_unitario_historico < 0;

-- ─────────────────────────────────────────────────────────────────────────────
-- BLOQUE 10: VALORES ÚNICOS — DUPLICADOS EN COLUMNAS UNIQUE
-- ─────────────────────────────────────────────────────────────────────────────
\echo ''
\echo '--- [10] DUPLICADOS EN COLUMNAS UNIQUE (deben ser 0) ---'

SELECT 'emails duplicados en cliente' AS verificacion,
        COUNT(*) - COUNT(DISTINCT email) AS duplicados
FROM cliente
UNION ALL
SELECT 'nombres duplicados en categoria',
        COUNT(*) - COUNT(DISTINCT nombre)
FROM categoria
UNION ALL
SELECT 'nombres duplicados en producto',
        COUNT(*) - COUNT(DISTINCT nombre)
FROM producto;

-- ─────────────────────────────────────────────────────────────────────────────
-- BLOQUE 11: DISTRIBUCIÓN DE FORMA DE PAGO
-- ─────────────────────────────────────────────────────────────────────────────
\echo ''
\echo '--- [11] DISTRIBUCIÓN DE FORMA DE PAGO EN PEDIDOS ---'

SELECT
    forma_pago,
    COUNT(*)                                      AS cantidad,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS porcentaje
FROM pedido
GROUP BY forma_pago
ORDER BY cantidad DESC;

-- ─────────────────────────────────────────────────────────────────────────────
-- BLOQUE 12: ESTADÍSTICAS DE pg_stat_user_tables
-- ─────────────────────────────────────────────────────────────────────────────
\echo ''
\echo '--- [12] ESTADO DE VACÍO/ANALYZE (pg_stat_user_tables) ---'

SELECT
    relname                         AS tabla,
    n_live_tup                      AS filas_vivas,
    n_dead_tup                      AS tuplas_muertas,
    last_vacuum,
    last_autovacuum,
    last_analyze,
    last_autoanalyze
FROM pg_stat_user_tables
WHERE schemaname = 'public'
ORDER BY relname;

-- ─────────────────────────────────────────────────────────────────────────────
-- BLOQUE 13: SECUENCIAS DE COLUMNAS IDENTITY
-- ─────────────────────────────────────────────────────────────────────────────
\echo ''
\echo '--- [13] SECUENCIAS IDENTITY (comparar último valor con ID máximo) ---'

SELECT string_agg(
    format(
        'SELECT %L AS tabla, %L AS columna, %L AS secuencia, ' ||
        '(SELECT max(%I) FROM %I.%I) AS id_maximo, ' ||
        '(SELECT last_value FROM %I.%I) AS ultimo_valor',
        format('%I.%I', s.table_schema, s.table_name),
        s.column_name,
        format('%I.%I', s.sequence_schema, s.sequence_name),
        s.column_name,
        s.table_schema,
        s.table_name,
        s.sequence_schema,
        s.sequence_name
    ),
    ' UNION ALL '
) AS identity_checks
FROM (
    SELECT c.table_schema,
           c.table_name,
           c.column_name,
           seq_ns.nspname AS sequence_schema,
           seq.relname AS sequence_name
    FROM information_schema.columns c
    JOIN pg_namespace tbl_ns ON tbl_ns.nspname = c.table_schema
    JOIN pg_class tbl ON tbl.relnamespace = tbl_ns.oid AND tbl.relname = c.table_name
    JOIN pg_attribute attr ON attr.attrelid = tbl.oid AND attr.attname = c.column_name
    JOIN pg_depend dep ON dep.refobjid = tbl.oid
                      AND dep.refobjsubid = attr.attnum
                      AND dep.classid = 'pg_class'::regclass
                      AND dep.refclassid = 'pg_class'::regclass
                      AND dep.deptype = 'i'
    JOIN pg_class seq ON seq.oid = dep.objid AND seq.relkind = 'S'
    JOIN pg_namespace seq_ns ON seq_ns.oid = seq.relnamespace
    WHERE c.table_schema = 'public'
      AND c.is_identity = 'YES'
) s
\gexec

-- Un último valor menor que el ID máximo puede indicar una secuencia atrasada.
-- Revisar antes de futuras inserciones; este diagnóstico no modifica secuencias.

-- ─────────────────────────────────────────────────────────────────────────────
-- BLOQUE 14: INVENTARIO DE OBJETOS DE ESQUEMAS DE USUARIO
-- ─────────────────────────────────────────────────────────────────────────────
\echo ''
\echo '--- [14] INVENTARIO DE OBJETOS (esquemas no internos) ---'

WITH objetos AS (
    SELECT 'ESQUEMA' AS tipo, n.nspname AS esquema, n.nspname AS objeto, '' AS detalle
    FROM pg_namespace n
    WHERE n.nspname <> 'information_schema'
      AND n.nspname NOT LIKE 'pg_%'
    UNION ALL
    SELECT
        CASE c.relkind
            WHEN 'r' THEN 'TABLA'
            WHEN 'p' THEN 'TABLA PARTICIONADA'
            WHEN 'v' THEN 'VISTA'
            WHEN 'm' THEN 'VISTA MATERIALIZADA'
            WHEN 'S' THEN 'SECUENCIA'
            WHEN 'f' THEN 'TABLA EXTERNA'
            WHEN 'i' THEN 'ÍNDICE'
            WHEN 'I' THEN 'ÍNDICE PARTICIONADO'
        END,
        n.nspname,
        c.relname,
        CASE WHEN c.relkind = 'm'
             THEN 'poblada=' || c.relispopulated::text
             ELSE '' END
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname <> 'information_schema'
      AND n.nspname NOT LIKE 'pg_%'
      AND c.relkind IN ('r', 'p', 'v', 'm', 'S', 'f', 'i', 'I')
    UNION ALL
    SELECT 'COLUMNA', c.table_schema, c.table_name || '.' || c.column_name,
           c.data_type || ', nullable=' || c.is_nullable
    FROM information_schema.columns c
    WHERE c.table_schema <> 'information_schema'
      AND c.table_schema NOT LIKE 'pg_%'
    UNION ALL
    SELECT
        CASE con.contype
            WHEN 'p' THEN 'PRIMARY KEY'
            WHEN 'f' THEN 'FOREIGN KEY'
            WHEN 'u' THEN 'UNIQUE'
            WHEN 'c' THEN 'CHECK'
            WHEN 'x' THEN 'EXCLUSION'
        END,
        n.nspname,
        tbl.relname || '.' || con.conname,
        pg_get_constraintdef(con.oid)
    FROM pg_constraint con
    JOIN pg_class tbl ON tbl.oid = con.conrelid
    JOIN pg_namespace n ON n.oid = tbl.relnamespace
    WHERE n.nspname <> 'information_schema'
      AND n.nspname NOT LIKE 'pg_%'
    UNION ALL
    SELECT
        CASE p.prokind
            WHEN 'p' THEN 'PROCEDIMIENTO'
            WHEN 'a' THEN 'AGREGADO'
            WHEN 'w' THEN 'FUNCIÓN DE VENTANA'
            ELSE 'FUNCIÓN'
        END,
        n.nspname,
        p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
        pg_get_function_result(p.oid)
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname <> 'information_schema'
      AND n.nspname NOT LIKE 'pg_%'
      AND p.prokind IN ('f', 'p', 'w', 'a')
    UNION ALL
    SELECT 'TIPO', n.nspname, t.typname,
           CASE t.typtype WHEN 'e' THEN 'ENUM' WHEN 'd' THEN 'DOMINIO'
                          WHEN 'r' THEN 'RANGE' WHEN 'm' THEN 'MULTIRANGE'
                          WHEN 'c' THEN 'TIPO COMPUESTO'
                          ELSE 'TIPO DEFINIDO POR EL USUARIO' END
    FROM pg_type t
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname <> 'information_schema'
      AND n.nspname NOT LIKE 'pg_%'
      AND t.typtype IN ('e', 'd', 'r', 'm', 'c')
    UNION ALL
    SELECT 'TRIGGER', n.nspname, tbl.relname || '.' || tr.tgname,
           pg_get_triggerdef(tr.oid)
    FROM pg_trigger tr
    JOIN pg_class tbl ON tbl.oid = tr.tgrelid
    JOIN pg_namespace n ON n.oid = tbl.relnamespace
    WHERE NOT tr.tgisinternal
      AND n.nspname <> 'information_schema'
      AND n.nspname NOT LIKE 'pg_%'
    UNION ALL
    SELECT 'POLÍTICA RLS', schemaname, tablename || '.' || policyname,
           'comando=' || cmd || ', roles=' || array_to_string(roles, ',')
    FROM pg_policies
    WHERE schemaname <> 'information_schema'
      AND schemaname NOT LIKE 'pg_%'
    UNION ALL
    SELECT 'EXTENSIÓN', n.nspname, e.extname, 'versión=' || e.extversion
    FROM pg_extension e
    JOIN pg_namespace n ON n.oid = e.extnamespace
)
SELECT tipo, esquema, objeto, detalle
FROM objetos
ORDER BY esquema, tipo, objeto;

-- El inventario cubre objetos de esquemas de usuario; excluye catálogos y
-- objetos internos de PostgreSQL.

-- ─────────────────────────────────────────────────────────────────────────────
-- BLOQUE 15: TAMAÑO DE LA BASE Y LAS TABLAS
-- ─────────────────────────────────────────────────────────────────────────────
\echo ''
\echo '--- [15] TAMAÑO DE LA BASE DE DATOS ---'

SELECT
    pg_database.datname                                 AS base,
    pg_size_pretty(pg_database_size(pg_database.datname)) AS tamanio_total
FROM pg_database
WHERE datname = current_database();

\echo ''
\echo '--- [15b] TAMAÑO POR TABLA (total = tabla + índices) ---'

SELECT
    relname                                   AS tabla,
    pg_size_pretty(pg_relation_size(oid))     AS solo_tabla,
    pg_size_pretty(pg_total_relation_size(oid)) AS con_indices
FROM pg_class
WHERE relkind = 'r'
  AND relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
ORDER BY pg_total_relation_size(oid) DESC;

-- ─────────────────────────────────────────────────────────────────────────────
-- BLOQUE 16: RESUMEN FINAL
-- ─────────────────────────────────────────────────────────────────────────────
\echo ''
\echo '============================================================'
\echo 'FIN DEL CHEQUEO PRE-TRABAJO'
\echo 'Revisar todo resultado fuera del valor esperado antes de continuar.'
\echo 'Huérfanos, violaciones de reglas y duplicados inesperados: deben ser 0.'
\echo 'FKs no validadas, índices no válidos y secuencias atrasadas: investigar.'
\echo 'Tuplas muertas, filas, tamaños y distribuciones: valores informativos;'
\echo 'un valor positivo no implica por sí solo un error.'
\echo '============================================================'
