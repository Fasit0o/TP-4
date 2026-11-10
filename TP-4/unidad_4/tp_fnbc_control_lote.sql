-- =============================================================================
-- EJERCICIO FNBC - CONTROL DE LOTE EN ALMACEN
-- Archivo : unidad_4/tp_fnbc_control_lote.sql
-- Motor   : PostgreSQL 17
-- Base    : foodstore_dev
-- Autora  : Agustina Micaela Guzman
--
-- OBJETIVO
--   Detectar y corregir una violacion de la Forma Normal de Boyce-Codd (FNBC)
--   en la relacion control_lote_almacen(L, D, R), aplicando el Teorema de Heath
--   para obtener dos relaciones en FNBC, migrar los datos y demostrar que la
--   reunion natural no pierde informacion.
--
-- NOTACION
--   L = lote_id
--   D = deposito_id
--   R = responsable_control_id
--
-- DEPENDENCIAS FUNCIONALES (reglas de negocio)
--   DF1: {L, D} -> R
--        Para un lote y un deposito determinados existe un unico responsable
--        de control.
--   DF2: R -> D
--        Cada responsable de control pertenece a un unico deposito,
--        independientemente del lote que audite.
--
-- CLAUSURAS DE ATRIBUTOS
--   {L}+     = {L}
--   {D}+     = {D}
--   {R}+     = {R, D}                 (por DF2)
--   {L, D}+  = {L, D, R}              (por DF1)
--   {L, R}+  = {L, R, D}              (por DF2)
--   {D, R}+  = {D, R}
--
-- CLAVES
--   Clave candidata : {L, D}          (unica)
--   Superclaves     : {L, D}, {L, D, R}
--   Atributos primos: L, D
--   Atributo no primo: R
--
-- VERIFICACION FORMAL DE FNBC
--   DF1: determinante {L, D} es superclave -> cumple FNBC.
--   DF2: determinante {R}; {R}+ = {R, D} no contiene L, por lo tanto R no es
--        superclave de R(L, D, R). DF2 viola FNBC.
--
-- ANOMALIAS SOBRE LA INSTANCIA
--   Instancia:
--     (501, 30, 801), (502, 30, 801), (503, 31, 802)
--   Insercion: se puede insertar (504, 31, 801), dejando al responsable 801
--              asociado a los depositos 30 y 31 a la vez. El esquema original
--              no puede impedirlo porque no impone R -> D.
--   Borrado:   si se eliminan (501, 30, 801) y (502, 30, 801) y no quedan mas
--              filas de 801, se pierde el hecho "801 pertenece al deposito 30".
--   Actualizacion: cambiar solo (501, 30, 801) a (501, 31, 801) deja a 801
--              con dos depositos distintos en la misma tabla.
--
-- DESCOMPOSICION (Teorema de Heath sobre R -> D)
--   R1 = pi{R, D}(R) -> responsable_deposito(R, D)      PK = R
--   R2 = pi{L, R}(R) -> control_lote_responsable(L, R)  PK = {L, R}
--
--   Atributo comun: R. En R1, R es clave; y R -> D es DF valida. Por lo tanto
--   R1 JOIN R2 reconstruye exactamente R sin tuplas espurias (lossless-join).
--
-- EJECUCION
--   psql -U postgres -d foodstore_dev -f unidad_4/tp_fnbc_control_lote.sql
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- =============================================================================
-- PASO 0.A - DOMINIOS REUTILIZABLES (IDEMPOTENTES)
-- Se crean solo si no existen. NO se usa DROP DOMAIN ... CASCADE porque eso
-- eliminaria en cascada las columnas lote.codigo_producto y
-- responsable_control.dni, rompiendo la reejecucion del script.
-- =============================================================================

DO $do$
BEGIN
    IF to_regtype('codigo_producto_dom') IS NULL THEN
        EXECUTE $ddl$
            CREATE DOMAIN codigo_producto_dom AS VARCHAR(50)
                CONSTRAINT ck_codigo_producto_formato
                    CHECK (VALUE ~ '^[A-Z0-9][A-Z0-9\-]{1,48}[A-Z0-9]$')
        $ddl$;
    END IF;

    IF to_regtype('dni_arg_dom') IS NULL THEN
        EXECUTE $ddl$
            CREATE DOMAIN dni_arg_dom AS VARCHAR(20)
                CONSTRAINT ck_dni_arg_formato
                    CHECK (VALUE ~ '^\d{7,8}$')
        $ddl$;
    END IF;
END
$do$;

-- =============================================================================
-- PASO 0.B - TABLAS MAESTRAS DE LA EXTENSION MAYORISTA
-- =============================================================================

CREATE TABLE IF NOT EXISTS deposito (
    id        BIGINT       PRIMARY KEY,
    nombre    VARCHAR(100) NOT NULL,
    ubicacion VARCHAR(255) NOT NULL,
    capacidad INT          NOT NULL
        CONSTRAINT chk_deposito_capacidad CHECK (capacidad > 0)
);

CREATE TABLE IF NOT EXISTS lote (
    id                BIGINT              PRIMARY KEY,
    codigo_producto   codigo_producto_dom NOT NULL,
    fecha_vencimiento DATE                NOT NULL
        CONSTRAINT chk_lote_vencimiento CHECK (fecha_vencimiento >= CURRENT_DATE)
);

CREATE TABLE IF NOT EXISTS responsable_control (
    id              BIGINT       PRIMARY KEY,
    dni             dni_arg_dom  NOT NULL UNIQUE,
    mail            VARCHAR(100) NOT NULL
        CONSTRAINT chk_responsable_mail
            CHECK (mail ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
    nombre_completo VARCHAR(150) NOT NULL
);

-- =============================================================================
-- PASO 0.C - DATOS MAESTROS DE LA INSTANCIA DE EJEMPLO
-- =============================================================================

INSERT INTO deposito (id, nombre, ubicacion, capacidad)
VALUES
    (30, 'Deposito Central', 'Mendoza',   10000),
    (31, 'Deposito Sur',     'San Martin', 5000)
ON CONFLICT (id) DO NOTHING;

-- Fechas futuras para superar chk_lote_vencimiento en ejecuciones de 2026.
INSERT INTO lote (id, codigo_producto, fecha_vencimiento)
VALUES
    (501, 'PROD-01', '2027-12-31'),
    (502, 'PROD-02', '2027-11-15'),
    (503, 'PROD-03', '2027-10-20')
ON CONFLICT (id) DO NOTHING;

INSERT INTO responsable_control (id, dni, mail, nombre_completo)
VALUES
    (801, '30111222', 'carlos@foodstore.com', 'Carlos Gomez'),
    (802, '32333444', 'ana@foodstore.com',    'Ana Lopez')
ON CONFLICT (id) DO NOTHING;

-- =============================================================================
-- PASO 1 - ESQUEMA ORIGINAL DEFECTUOSO (PRE-FNBC)
-- Se conserva como oraculo para comparar la vista de compatibilidad.
-- =============================================================================

CREATE TABLE IF NOT EXISTS control_lote_almacen (
    lote_id                BIGINT NOT NULL REFERENCES lote(id),
    deposito_id            BIGINT NOT NULL REFERENCES deposito(id),
    responsable_control_id BIGINT NOT NULL REFERENCES responsable_control(id),
    PRIMARY KEY (lote_id, deposito_id)
);

INSERT INTO control_lote_almacen (lote_id, deposito_id, responsable_control_id)
VALUES
    (501, 30, 801),
    (502, 30, 801),
    (503, 31, 802)
ON CONFLICT DO NOTHING;

-- =============================================================================
-- PASO 2 - TABLAS DESCOMPUESTAS EN FNBC
-- =============================================================================

-- R1: aisla DF2 (R -> D). R es PK, por lo tanto R1 esta en FNBC.
CREATE TABLE IF NOT EXISTS responsable_deposito (
    responsable_control_id BIGINT PRIMARY KEY
        REFERENCES responsable_control(id),
    deposito_id            BIGINT NOT NULL
        REFERENCES deposito(id)
);

-- R2: vinculo lote-responsable. PK {L, R}; no hay atributos no primos,
-- por lo tanto R2 esta en FNBC. La FK apunta a R1 para garantizar que todo
-- responsable tenga deposito asignado antes de vincularlo a un lote.
CREATE TABLE IF NOT EXISTS control_lote_responsable (
    lote_id                BIGINT NOT NULL REFERENCES lote(id),
    responsable_control_id BIGINT NOT NULL
        REFERENCES responsable_deposito(responsable_control_id),
    PRIMARY KEY (lote_id, responsable_control_id)
);

-- =============================================================================
-- PASO 3 - VISTA DE COMPATIBILIDAD
-- Reconstruye (L, D, R) mediante la reunion natural de R1 y R2 sobre R.
-- =============================================================================

CREATE OR REPLACE VIEW vw_control_lote_almacen_compatibilidad AS
SELECT
    clr.lote_id,
    rd.deposito_id,
    clr.responsable_control_id
FROM control_lote_responsable AS clr
JOIN responsable_deposito   AS rd
    ON rd.responsable_control_id = clr.responsable_control_id;

-- =============================================================================
-- PASO 4 - VALIDACION PREVIA Y MIGRACION DE DATOS
-- =============================================================================

-- Si el esquema original violara DF2, la migracion a R1 seria ambigua.
DO $do$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM control_lote_almacen
        GROUP BY responsable_control_id
        HAVING COUNT(DISTINCT deposito_id) > 1
    ) THEN
        RAISE EXCEPTION
            'La instancia viola la DF R -> D: un responsable aparece en mas de un deposito.';
    END IF;
END
$do$;

-- R1: DISTINCT colapsa los pares (R, D) repetidos.
-- DO UPDATE mantiene sincronizado el deposito si la fuente cambio.
INSERT INTO responsable_deposito (responsable_control_id, deposito_id)
SELECT DISTINCT responsable_control_id, deposito_id
FROM control_lote_almacen
ON CONFLICT (responsable_control_id) DO UPDATE
    SET deposito_id = EXCLUDED.deposito_id;

-- R2: cada par (lote, responsable) se migra una sola vez.
INSERT INTO control_lote_responsable (lote_id, responsable_control_id)
SELECT lote_id, responsable_control_id
FROM control_lote_almacen
ON CONFLICT (lote_id, responsable_control_id) DO NOTHING;

-- =============================================================================
-- PASO 5 - VERIFICACION DE EQUIVALENCIA (LOSSLESS-JOIN)
-- Resultado esperado: 0 filas en ambas direcciones y conteos iguales.
-- =============================================================================

\echo '--- Direccion A: filas de la vista que no existen en la tabla original ---'
SELECT lote_id, deposito_id, responsable_control_id
FROM vw_control_lote_almacen_compatibilidad
EXCEPT
SELECT lote_id, deposito_id, responsable_control_id
FROM control_lote_almacen;

\echo '--- Direccion B: filas de la tabla original que no existen en la vista ---'
SELECT lote_id, deposito_id, responsable_control_id
FROM control_lote_almacen
EXCEPT
SELECT lote_id, deposito_id, responsable_control_id
FROM vw_control_lote_almacen_compatibilidad;

\echo '--- Conteos: original, vista, R1 y R2 ---'
SELECT 'control_lote_almacen' AS relacion, COUNT(*) AS filas FROM control_lote_almacen
UNION ALL
SELECT 'vw_control_lote_almacen_compatibilidad', COUNT(*) FROM vw_control_lote_almacen_compatibilidad
UNION ALL
SELECT 'responsable_deposito', COUNT(*) FROM responsable_deposito
UNION ALL
SELECT 'control_lote_responsable', COUNT(*) FROM control_lote_responsable
ORDER BY relacion;

-- Fallo controlado si la descomposicion no es equivalente.
DO $do$
DECLARE
    v_orig    BIGINT;
    v_vista   BIGINT;
    v_faltan  BIGINT;
    v_sobran  BIGINT;
BEGIN
    SELECT COUNT(*) INTO v_orig  FROM control_lote_almacen;
    SELECT COUNT(*) INTO v_vista FROM vw_control_lote_almacen_compatibilidad;

    SELECT COUNT(*) INTO v_faltan
    FROM (
        SELECT lote_id, deposito_id, responsable_control_id
        FROM control_lote_almacen
        EXCEPT
        SELECT lote_id, deposito_id, responsable_control_id
        FROM vw_control_lote_almacen_compatibilidad
    ) AS faltantes;

    SELECT COUNT(*) INTO v_sobran
    FROM (
        SELECT lote_id, deposito_id, responsable_control_id
        FROM vw_control_lote_almacen_compatibilidad
        EXCEPT
        SELECT lote_id, deposito_id, responsable_control_id
        FROM control_lote_almacen
    ) AS sobrantes;

    IF v_orig <> v_vista OR v_faltan > 0 OR v_sobran > 0 THEN
        RAISE EXCEPTION
            'Lossless-join FALLA: original=%, vista=%, faltan=%, sobran=%',
            v_orig, v_vista, v_faltan, v_sobran;
    END IF;

    RAISE NOTICE
        'Lossless-join OK: original=%, vista=%, faltan=0, sobran=0',
        v_orig, v_vista;
END
$do$;

COMMIT;

-- =============================================================================
-- PASO 6 - PLAN DE REVERSION
-- La tabla original control_lote_almacen se conserva intacta. Para volver al
-- esquema anterior sin perder datos:
--
--   BEGIN;
--   -- 1. Si se necesita una copia independiente antes de eliminar la vista:
--   CREATE TABLE control_lote_almacen_respaldo AS
--   SELECT * FROM vw_control_lote_almacen_compatibilidad;
--
--   -- 2. Eliminar objetos de la descomposicion.
--   DROP VIEW  IF EXISTS vw_control_lote_almacen_compatibilidad;
--   DROP TABLE IF EXISTS control_lote_responsable;
--   DROP TABLE IF EXISTS responsable_deposito;
--
--   -- 3. La tabla original sigue existiendo, por lo que no hay perdida.
--   COMMIT;
--
-- Si en una migracion real se hubiera eliminado la tabla original, reconstruirla
-- desde la vista antes de borrar R1/R2:
--
--   CREATE TABLE control_lote_almacen AS
--   SELECT lote_id, deposito_id, responsable_control_id
--   FROM vw_control_lote_almacen_compatibilidad;
--   ALTER TABLE control_lote_almacen
--       ADD CONSTRAINT pk_control_lote_almacen PRIMARY KEY (lote_id, deposito_id);
-- =============================================================================
