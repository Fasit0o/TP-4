-- =============================================================================
-- TRANSFERENCIA DE PROPIEDAD OPERATIVA A admin_datos — FOOD STORE (Unidad 6)
-- Base objetivo: foodstore_dev
-- Log de evidencia: food_store_tp_u6/logs/log_setup_ownership.txt
--
-- Transfiere los objetos propios de la aplicación en esquemas de usuario:
-- esquemas, relaciones, secuencias, rutinas y tipos definidos por el proyecto.
-- Los objetos miembros de extensiones (por ejemplo, pgcrypto y plpgsql) se
-- excluyen deliberadamente; sus extensiones permanecen bajo administración
-- técnica de postgres.
--
-- Ejecutar como superusuario postgres:
--   psql -X -U postgres -d foodstore_dev -f food_store_tp_u6/scripts/setup_ownership.sql
--
-- admin_datos permanece NOSUPERUSER. El script es transaccional: si falla una
-- transferencia o la verificación, PostgreSQL revierte todos los cambios.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;
SET LOCAL search_path = pg_catalog;

DO $preconditions$
BEGIN
    IF current_database() <> 'foodstore_dev' THEN
        RAISE EXCEPTION 'Base incorrecta: se esperaba foodstore_dev y se recibió %',
            current_database();
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname = current_user
          AND rolsuper
    ) THEN
        RAISE EXCEPTION 'Ejecutar este script con un superusuario técnico';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'admin_datos') THEN
        RAISE EXCEPTION 'El rol admin_datos no existe';
    END IF;

    IF (SELECT rolsuper FROM pg_roles WHERE rolname = 'admin_datos') THEN
        RAISE EXCEPTION 'admin_datos debe permanecer NOSUPERUSER';
    END IF;
END
$preconditions$;

DO $transfer$
DECLARE
    rec RECORD;
    command_name TEXT;
BEGIN
    FOR rec IN
        SELECT n.nspname
        FROM pg_namespace n
        WHERE n.nspname <> 'information_schema'
          AND n.nspname NOT LIKE 'pg_%'
          AND n.nspowner <> 'admin_datos'::regrole
    LOOP
        EXECUTE format('ALTER SCHEMA %I OWNER TO admin_datos', rec.nspname);
    END LOOP;

    FOR rec IN
        SELECT n.nspname, c.relname, c.relkind
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname <> 'information_schema'
          AND n.nspname NOT LIKE 'pg_%'
          AND c.relkind IN ('r', 'p', 'v', 'm', 'S', 'f')
          AND c.relowner <> 'admin_datos'::regrole
    LOOP
        command_name := CASE rec.relkind
            WHEN 'r' THEN 'TABLE'
            WHEN 'p' THEN 'TABLE'
            WHEN 'v' THEN 'VIEW'
            WHEN 'm' THEN 'MATERIALIZED VIEW'
            WHEN 'S' THEN 'SEQUENCE'
            WHEN 'f' THEN 'FOREIGN TABLE'
        END;

        EXECUTE format(
            'ALTER %s %I.%I OWNER TO admin_datos',
            command_name,
            rec.nspname,
            rec.relname
        );
    END LOOP;

    FOR rec IN
        SELECT p.oid::regprocedure AS identity, p.prokind
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname <> 'information_schema'
          AND n.nspname NOT LIKE 'pg_%'
          AND p.proowner <> 'admin_datos'::regrole
          AND p.prokind IN ('f', 'p', 'a', 'w')
          AND NOT EXISTS (
              SELECT 1
              FROM pg_depend d
              WHERE d.classid = 'pg_proc'::regclass
                AND d.objid = p.oid
                AND d.refclassid = 'pg_extension'::regclass
                AND d.deptype = 'e'
          )
    LOOP
        command_name := CASE rec.prokind
            WHEN 'p' THEN 'PROCEDURE'
            WHEN 'a' THEN 'AGGREGATE'
            ELSE 'FUNCTION'
        END;

        EXECUTE format(
            'ALTER %s %s OWNER TO admin_datos',
            command_name,
            rec.identity
        );
    END LOOP;

    FOR rec IN
        SELECT n.nspname, t.typname, t.typtype
        FROM pg_type t
        JOIN pg_namespace n ON n.oid = t.typnamespace
        LEFT JOIN pg_class composite_relation ON composite_relation.oid = t.typrelid
        WHERE n.nspname <> 'information_schema'
          AND n.nspname NOT LIKE 'pg_%'
          AND t.typowner <> 'admin_datos'::regrole
          AND (
              t.typtype IN ('b', 'd', 'e', 'r', 'm')
              OR (t.typtype = 'c' AND composite_relation.relkind = 'c')
          )
          AND t.typcategory <> 'A'
          AND NOT EXISTS (
              SELECT 1
              FROM pg_depend d
              WHERE d.classid = 'pg_type'::regclass
                AND d.objid = t.oid
                AND d.refclassid = 'pg_extension'::regclass
                AND d.deptype = 'e'
          )
    LOOP
        command_name := CASE rec.typtype
            WHEN 'd' THEN 'DOMAIN'
            ELSE 'TYPE'
        END;

        EXECUTE format(
            'ALTER %s %I.%I OWNER TO admin_datos',
            command_name,
            rec.nspname,
            rec.typname
        );
    END LOOP;
END
$transfer$;

ALTER DATABASE foodstore_dev OWNER TO admin_datos;

DO $verify$
BEGIN
    IF (SELECT datdba FROM pg_database WHERE datname = current_database())
       <> 'admin_datos'::regrole THEN
        RAISE EXCEPTION 'La base no quedó a nombre de admin_datos';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_namespace
        WHERE nspname <> 'information_schema'
          AND nspname NOT LIKE 'pg_%'
          AND nspowner <> 'admin_datos'::regrole
    ) THEN
        RAISE EXCEPTION 'Quedó un esquema de usuario fuera de admin_datos';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname <> 'information_schema'
          AND n.nspname NOT LIKE 'pg_%'
          AND c.relkind IN ('r', 'p', 'v', 'm', 'S', 'f', 'i', 'I')
          AND c.relowner <> 'admin_datos'::regrole
    ) THEN
        RAISE EXCEPTION 'Quedó una relación o índice de usuario fuera de admin_datos';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname <> 'information_schema'
          AND n.nspname NOT LIKE 'pg_%'
          AND p.prokind IN ('f', 'p', 'a', 'w')
          AND p.proowner <> 'admin_datos'::regrole
          AND NOT EXISTS (
              SELECT 1
              FROM pg_depend d
              WHERE d.classid = 'pg_proc'::regclass
                AND d.objid = p.oid
                AND d.refclassid = 'pg_extension'::regclass
                AND d.deptype = 'e'
          )
    ) THEN
        RAISE EXCEPTION 'Quedó una rutina de aplicación fuera de admin_datos';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_type t
        JOIN pg_namespace n ON n.oid = t.typnamespace
        LEFT JOIN pg_class composite_relation ON composite_relation.oid = t.typrelid
        WHERE n.nspname <> 'information_schema'
          AND n.nspname NOT LIKE 'pg_%'
          AND (
              t.typtype IN ('b', 'd', 'e', 'r', 'm')
              OR (t.typtype = 'c' AND composite_relation.relkind = 'c')
          )
          AND t.typcategory <> 'A'
          AND t.typowner <> 'admin_datos'::regrole
          AND NOT EXISTS (
              SELECT 1
              FROM pg_depend d
              WHERE d.classid = 'pg_type'::regclass
                AND d.objid = t.oid
                AND d.refclassid = 'pg_extension'::regclass
                AND d.deptype = 'e'
          )
    ) THEN
        RAISE EXCEPTION 'Quedó un tipo de aplicación fuera de admin_datos';
    END IF;

    IF (SELECT rolsuper FROM pg_roles WHERE rolname = 'admin_datos') THEN
        RAISE EXCEPTION 'La transferencia no debe convertir admin_datos en superusuario';
    END IF;
END
$verify$;

COMMIT;

\echo ''
\echo '--- Propietario de la base y esquema public ---'
SELECT d.datname, pg_get_userbyid(d.datdba) AS propietario_base,
       pg_get_userbyid(n.nspowner) AS propietario_esquema
FROM pg_database d
CROSS JOIN pg_namespace n
WHERE d.datname = current_database()
  AND n.nspname = 'public';

\echo ''
\echo '--- Rutinas de aplicación ---'
SELECT p.oid::regprocedure AS rutina, pg_get_userbyid(p.proowner) AS propietario
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname <> 'information_schema'
  AND n.nspname NOT LIKE 'pg_%'
  AND p.prokind IN ('f', 'p', 'a', 'w')
  AND NOT EXISTS (
      SELECT 1
      FROM pg_depend d
      WHERE d.classid = 'pg_proc'::regclass
        AND d.objid = p.oid
        AND d.refclassid = 'pg_extension'::regclass
        AND d.deptype = 'e'
  )
ORDER BY p.oid::regprocedure::text;

\echo ''
\echo '--- Tipos definidos por la aplicación ---'
SELECT n.nspname AS esquema, t.typname AS tipo,
       pg_get_userbyid(t.typowner) AS propietario
FROM pg_type t
JOIN pg_namespace n ON n.oid = t.typnamespace
LEFT JOIN pg_class composite_relation ON composite_relation.oid = t.typrelid
WHERE n.nspname <> 'information_schema'
  AND n.nspname NOT LIKE 'pg_%'
  AND (
      t.typtype IN ('b', 'd', 'e', 'r', 'm')
      OR (t.typtype = 'c' AND composite_relation.relkind = 'c')
  )
  AND t.typcategory <> 'A'
  AND NOT EXISTS (
      SELECT 1
      FROM pg_depend d
      WHERE d.classid = 'pg_type'::regclass
        AND d.objid = t.oid
        AND d.refclassid = 'pg_extension'::regclass
        AND d.deptype = 'e'
  )
ORDER BY n.nspname, t.typname;

\echo ''
\echo 'Extensiones técnicas excluidas; admin_datos sigue NOSUPERUSER.'
