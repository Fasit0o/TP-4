-- =============================================================================
-- roles.sql  |  TP Unidad 5 — Administración y Seguridad  |  Food Store
-- =============================================================================
-- Ejecución:
--   psql -U postgres -d foodstore_dev -f food_store_tp_u5/sql/roles.sql
--
-- Las contraseñas están hardcodeadas con valores de sandbox (desarrollo).
-- En un entorno real se reemplazarían por variables: -v app_pass='...'
--
-- El script es IDEMPOTENTE: puede reejecutarse sobre una base ya configurada
-- sin generar errores ni dejar permisos residuales.
-- Corre TODO dentro de una transacción; si algo falla hace ROLLBACK completo.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;  -- ── Todo o nada ───────────────────────────────────────────────────────

-- ---------------------------------------------------------------------------
-- 0. EXTENSIÓN pgcrypto (necesaria para crypt() y gen_salt())
-- ---------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pgcrypto;


-- ===========================================================================
-- SECCIÓN 1 — LIMPIEZA IDEMPOTENTE
-- Revoca todos los permisos previos de los roles antes de
-- recrearlos. En una base limpia este bloque no hace nada dañino.
-- ===========================================================================
DO $$
DECLARE
    r   TEXT;
    g   TEXT;
    m   RECORD;
BEGIN
    FOR r IN
        SELECT rolname FROM pg_roles
        WHERE  rolname IN (
            'rol_app_lectura', 'rol_app_escritura',
            'rol_soporte',     'rol_reportes',
            'app_web'
        )
    LOOP
        -- 1.1 Permisos sobre objetos existentes en el esquema público.
        --     Revocar sobre la tabla también revoca permisos de columna.
        EXECUTE format('REVOKE ALL ON SCHEMA            public            FROM %I', r);
        EXECUTE format('REVOKE ALL ON ALL TABLES    IN  SCHEMA public     FROM %I', r);
        EXECUTE format('REVOKE ALL ON ALL SEQUENCES  IN  SCHEMA public    FROM %I', r);
        EXECUTE format('REVOKE ALL ON ALL ROUTINES   IN  SCHEMA public    FROM %I', r);

        -- 1.2 Privilegios por defecto configurados por CUALQUIER rol anterior.
        FOR g IN
            SELECT DISTINCT pg_get_userbyid(defaclrole)
            FROM   pg_default_acl
        LOOP
            EXECUTE format(
                'ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA public '
                'REVOKE ALL ON TABLES    FROM %I', g, r);
            EXECUTE format(
                'ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA public '
                'REVOKE ALL ON SEQUENCES FROM %I', g, r);
            EXECUTE format(
                'ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA public '
                'REVOKE ALL ON FUNCTIONS FROM %I', g, r);
        END LOOP;
    END LOOP;

    -- 1.3 Membresías: se quitan todas aquí y se reponen en la sección 6.
    FOR m IN
        SELECT gr.rolname AS grupo, mi.rolname AS miembro
        FROM   pg_auth_members am
        JOIN   pg_roles gr ON gr.oid = am.roleid
        JOIN   pg_roles mi ON mi.oid = am.member
        WHERE  gr.rolname IN (
            'rol_app_lectura', 'rol_app_escritura',
            'rol_soporte',     'rol_reportes'
        )
    LOOP
        EXECUTE format('REVOKE %I FROM %I', m.grupo, m.miembro);
    END LOOP;
END $$;


-- ===========================================================================
-- SECCIÓN 2 — CREACIÓN Y CORRECCIÓN DE ROLES
-- ===========================================================================
DO $$
DECLARE r TEXT;
BEGIN
    -- 2.1 Crea cada rol solo si no existe
    FOREACH r IN ARRAY ARRAY[
        'rol_app_lectura', 'rol_app_escritura',
        'rol_soporte',     'rol_reportes',
        'app_web',         'admin_datos'
    ]
    LOOP
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = r) THEN
            EXECUTE format('CREATE ROLE %I', r);
            RAISE NOTICE 'Rol % creado.', r;
        ELSE
            RAISE NOTICE 'Rol % ya existía; se reusan atributos.', r;
        END IF;
    END LOOP;

    -- 2.2 Los grupos siempre deben ser NOLOGIN (corrige si alguien los alteró)
    FOREACH r IN ARRAY ARRAY[
        'rol_app_lectura', 'rol_app_escritura',
        'rol_soporte',     'rol_reportes'
    ]
    LOOP
        EXECUTE format('ALTER ROLE %I NOLOGIN', r);
    END LOOP;
END $$;

-- Atributos y contraseñas de los roles de login (se reaplican en cada ejecución)
ALTER ROLE app_web     WITH LOGIN          PASSWORD 'app_web_pass_dev';
ALTER ROLE admin_datos WITH LOGIN CREATEDB CREATEROLE NOSUPERUSER
                                           PASSWORD 'admin_datos_pass_dev';

-- admin_datos es dueño del esquema público
ALTER SCHEMA public OWNER TO admin_datos;


-- ===========================================================================
-- SECCIÓN 3 — FUNCIONES DE SEGURIDAD (SECURITY DEFINER)
-- ===========================================================================

-- 3.1 fn_autenticar — valida mail/contraseña y retorna id_cliente (o NULL)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_autenticar(
    p_mail TEXT,
    p_pass TEXT
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_id   BIGINT;
    v_hash TEXT;
BEGIN
    -- Intentamos recuperar el hash; si no existe el mail, ambas variables quedan NULL
    SELECT c.id_cliente, c.contrasena_hash
    INTO   v_id, v_hash
    FROM   cliente c
    WHERE  c.email = p_mail;

    -- Si el cliente no existe, ejecutamos un crypt ficticio para nivelar tiempos
    IF v_id IS NULL THEN
        PERFORM crypt(p_pass, gen_salt('bf'));   -- resultado descartado
        RETURN NULL;
    END IF;

    -- Comparamos el hash almacenado con la contraseña provista.
    -- Se verifica explícitamente que el hash no sea NULL (cliente sin contraseña registrada).
    IF v_hash IS NOT NULL AND v_hash = crypt(p_pass, v_hash) THEN
        RETURN v_id;
    END IF;

    RETURN NULL;
END;
$$;

-- ---------------------------------------------------------------------------
-- 3.2 fn_resetear_password — actualiza el hash de contraseña de un cliente
--
-- Dado en Clase 2 (adaptado al esquema real: tabla `cliente`, campo
-- `contrasena_hash`, clave primaria `id_cliente`).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_resetear_password(
    p_cliente_id BIGINT,
    p_nueva      TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    UPDATE cliente
    SET    contrasena_hash = crypt(p_nueva, gen_salt('bf'))
    WHERE  id_cliente = p_cliente_id;

    -- Si no se actualizó ninguna fila el llamante no recibe error explícito,
    -- pero puede verificarlo mediante GET DIAGNOSTICS si lo necesita.
END;
$$;

-- ---------------------------------------------------------------------------
-- La columna `contrasena_hash` fue agregada a `cliente` en sql/01_schema.sql
-- como parte del alcance de la Unidad 5 (autenticación de clientes).
-- ---------------------------------------------------------------------------


-- ===========================================================================
-- SECCIÓN 4 — CERRAR SUPERFICIE DE ATAQUE DE PUBLIC
-- ===========================================================================

-- Nadie que no tenga un GRANT explícito puede usar el esquema
REVOKE ALL ON SCHEMA public FROM PUBLIC;

-- Las funciones SECURITY DEFINER no son ejecutables por ningún rol por defecto
REVOKE ALL ON FUNCTION fn_autenticar(TEXT, TEXT)        FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_resetear_password(BIGINT, TEXT) FROM PUBLIC;


-- ===========================================================================
-- SECCIÓN 5 — ASIGNACIÓN EXPLÍCITA DE PERMISOS (Principio de Mínimo Privilegio)
-- ===========================================================================

-- 5.0 USAGE en el esquema: requisito previo para que cualquier rol resuelva objetos
GRANT USAGE ON SCHEMA public
    TO rol_app_lectura, rol_app_escritura, rol_soporte, rol_reportes;


-- ── rol_app_lectura ──────────────────────────────────────────────────────────
-- Objetivo: servir el catálogo público sin capacidad de modificación alguna.
GRANT SELECT ON vw_productos_vigentes TO rol_app_lectura;
GRANT SELECT ON categoria             TO rol_app_lectura;


-- ── rol_app_escritura ────────────────────────────────────────────────────────
-- Objetivo: crear y actualizar pedidos. DELETE y TRUNCATE omitidos (baja lógica).
GRANT SELECT, INSERT, UPDATE ON pedido         TO rol_app_escritura;
GRANT SELECT, INSERT, UPDATE ON detalle_pedido TO rol_app_escritura;

-- sp_crear_pedido: firma explícita (definida en sql/05_procedimientos.sql).
-- Usar la firma exacta evita otorgar permisos a sobrecargas futuras accidentalmente.
GRANT EXECUTE ON PROCEDURE sp_crear_pedido(BIGINT, forma_pago_enum, JSONB)
    TO rol_app_escritura;


-- ── rol_soporte ──────────────────────────────────────────────────────────────
-- Objetivo: atención al cliente e inspección de pedidos. Sin acceso a datos
--           sensibles de la tabla cliente (telefono, direccion).
--
-- Permiso POR COLUMNA sobre `cliente` (Data Minimization — REQ-SEC1):
GRANT SELECT (id_cliente, nombre, email) ON cliente TO rol_soporte;

-- Vista segura de pedidos con datos del cliente ya filtrados por la vista:
GRANT SELECT ON vw_pedidos_cliente_segura TO rol_soporte;

-- Rutinas de gestión de credenciales:
-- fn_autenticar se otorga SOLO a app_web (sección de app_web más abajo).
-- rol_soporte no necesita autenticar clientes — eso es responsabilidad del backend.
GRANT EXECUTE ON FUNCTION fn_resetear_password(BIGINT, TEXT) TO rol_soporte;


-- ── rol_reportes ─────────────────────────────────────────────────────────────
-- Objetivo: analítica sobre datos pre-calculados sin tocar tablas transaccionales.
GRANT SELECT ON mv_facturacion_categoria_mes  TO rol_reportes;
GRANT SELECT ON mv_ventas_categoria_diario    TO rol_reportes;


-- ── app_web (login) ──────────────────────────────────────────────────────────
-- Objetivo: backend de la aplicación — autenticación de clientes.
-- Los permisos de lectura y escritura le llegan por membresía (sección 6).
GRANT EXECUTE ON FUNCTION fn_autenticar(TEXT, TEXT) TO app_web;


-- ===========================================================================
-- SECCIÓN 6 — MEMBRESÍAS
-- ===========================================================================
-- app_web hereda todos los privilegios de lectura y escritura mediante membresía.
GRANT rol_app_lectura, rol_app_escritura TO app_web;


-- ===========================================================================
-- SECCIÓN 7 — PRIVILEGIOS POR DEFECTO (objetos futuros)
--
-- Política explícita: un objeto nuevo NO hereda permisos automáticamente.
-- Cada permiso se otorga de forma manual y deliberada después de crearlo.
-- Se configura para los dos roles que pueden crear objetos en este esquema.
-- ===========================================================================

-- 7.1 Objetos creados por postgres
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
    REVOKE ALL ON TABLES FROM
        rol_app_lectura, rol_app_escritura, rol_soporte, rol_reportes;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
    REVOKE ALL ON SEQUENCES FROM
        rol_app_lectura, rol_app_escritura, rol_soporte, rol_reportes;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres
    REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

-- 7.2 Objetos creados por admin_datos
ALTER DEFAULT PRIVILEGES FOR ROLE admin_datos IN SCHEMA public
    REVOKE ALL ON TABLES FROM
        rol_app_lectura, rol_app_escritura, rol_soporte, rol_reportes;
ALTER DEFAULT PRIVILEGES FOR ROLE admin_datos IN SCHEMA public
    REVOKE ALL ON SEQUENCES FROM
        rol_app_lectura, rol_app_escritura, rol_soporte, rol_reportes;
ALTER DEFAULT PRIVILEGES FOR ROLE admin_datos
    REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;


COMMIT;  -- ── Fin del bloque transaccional ──────────────────────────────────


-- ===========================================================================
-- SECCIÓN 8 — VERIFICACIÓN POST-DEPLOY
-- (fuera de la transacción; adjuntar la salida en el entregable)
-- ===========================================================================

-- 8.1 Listado de roles y atributos
\du

-- 8.2 Privilegios por defecto vigentes
\ddp

-- 8.3 Permisos sobre tablas/vistas por rol
SELECT
    grantee,
    table_schema,
    table_name,
    privilege_type
FROM information_schema.role_table_grants
WHERE grantee IN (
    'rol_app_lectura', 'rol_app_escritura',
    'rol_soporte',     'rol_reportes',
    'app_web'
)
ORDER BY grantee, table_name, privilege_type;

-- 8.4 Permisos por columna sobre `cliente` para rol_soporte (Data Minimization)
SELECT
    grantee,
    table_name,
    column_name,
    privilege_type
FROM information_schema.column_privileges
WHERE  grantee    = 'rol_soporte'
  AND  table_name = 'cliente'
ORDER BY column_name;

-- 8.5 Permisos sobre rutinas
SELECT
    grantee,
    routine_name,
    privilege_type
FROM information_schema.routine_privileges
WHERE  routine_schema = 'public'
  AND  routine_name   IN ('fn_autenticar', 'fn_resetear_password', 'sp_crear_pedido')
ORDER BY routine_name, grantee;
