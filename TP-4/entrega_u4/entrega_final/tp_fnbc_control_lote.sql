-- ============================================================================
-- ENTREGA U4 - PARTE 1: NORMALIZACION FNBC DEL CASO ControlLoteAlmacen
-- Archivo: entrega_u4/sql/01_normalizacion_fnbc.sql
-- Motor: PostgreSQL 17 (compatible con PostgreSQL 18)
-- Base destino: foodstore_u4_dev (sandbox de desarrollo, aislada de produccion)
-- ============================================================================
--
-- OBJETIVO
--   Detectar, demostrar y corregir la violacion de la Forma Normal de
--   Boyce-Codd (FNBC) en la relacion
--       u4_control_lote_almacen(L, D, R)
--   aplicando el Teorema de Heath sobre la DF R -> D, migrando los datos de
--   ejemplo y verificando la propiedad lossless-join (reunion sin perdida).
--
-- NOTACION
--   L = lote_id           (referencia a u4_lote.id)
--   D = deposito_id       (referencia a u4_deposito.id)
--   R = responsable_id    (referencia a u4_responsable.id)
--
-- REGLAS DE NEGOCIO (dependencias funcionales)
--   DF1: {L, D} -> R   Para un lote y un deposito dados existe un unico
--                      responsable de control. Es la PK original.
--   DF2: R    -> D     Cada responsable pertenece a un unico deposito,
--                      independientemente del lote que audite.
--
-- CLAVES CANDIDATAS (demostracion mediante clausuras)
--   {L, D}+ = {L, D, R}   por DF1  -> superclave, minimal  -> clave candidata
--   {L, R}+ = {L, R, D}   por DF2  -> superclave, minimal  -> clave candidata
--   Ningun atributo simple determina a todos los demas.
--   Por lo tanto las claves candidatas son {L, D} y {L, R}.
--   Todos los atributos L, D y R son primos (pertenecen al menos a una
--   clave candidata). No hay atributos no primos.
--
-- ADAPTACION AL ESQUEMA REAL DE FOOD STORE
--   La consigna menciona una tabla usuario(id), pero en el esquema real de
--   Food Store no existe tal tabla. El atributo responsable se modela con la
--   tabla propia u4_responsable(id, dni, mail, nombre_completo), que es la
--   estructura disponible en el alcance de la Unidad 4 para representar al
--   personal de control de almacen. No se inventa ninguna tabla usuario.
--
-- PROPIEDADES DEL SCRIPT
--   - Autocontenido: crea tablas maestras, relacion original, tablas
--     descompuestas, vista de compatibilidad y migra datos de ejemplo.
--   - Idempotente: CREATE TABLE IF NOT EXISTS, ON CONFLICT DO NOTHING,
--     dominios creados condicionalmente con to_regtype(). Reejecutable sin
--     efectos duplicados ni errores.
--   - No destructivo: conserva la tabla original u4_control_lote_almacen como
--     evidenca y oraculo de comparacion. No usa DROP ... CASCADE.
--   - Transaccional: todo el contenido va dentro de BEGIN ... COMMIT.
--   - Caracteres ASCII unicamente en comentarios (compatibilidad WIN1252/UTF-8).
--   - Estrategia de reejecucion: u4_resp_deposito usa ON CONFLICT DO UPDATE
--     para sincronizar el deposito si la fuente cambio; u4_control_asignacion
--     usa ON CONFLICT DO NOTHING (solo agrega pares faltantes). Si la
--     relacion original se modifico entre ejecuciones (filas eliminadas o
--     responsables cambiados de deposito), la verificacion de equivalencia
--     del PASO 5 detecta filas sobrantes o faltantes y lanza EXCEPTION,
--     abortando la transaccion para no presentar datos obsoletos como una
--     migración exitosa.
--
-- ORDEN DE EJECUCION
--   psql -U postgres -d foodstore_u4_dev -f entrega_u4/entrega_final/tp_fnbc_control_lote.sql
-- ============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- ----------------------------------------------------------------------------
-- PASO 0.A - DOMINIOS REUTILIZABLES (creados solo si no existen)
-- ----------------------------------------------------------------------------

DO $do$
BEGIN
    IF to_regtype('u4_codigo_producto_dom') IS NULL THEN
        EXECUTE $ddl$
            CREATE DOMAIN u4_codigo_producto_dom AS VARCHAR(50)
                CONSTRAINT u4_ck_codigo_producto_formato
                    CHECK (VALUE ~ '^[A-Z0-9][A-Z0-9\-]{1,48}[A-Z0-9]$')
        $ddl$;
    END IF;

    IF to_regtype('u4_dni_arg_dom') IS NULL THEN
        EXECUTE $ddl$
            CREATE DOMAIN u4_dni_arg_dom AS VARCHAR(20)
                CONSTRAINT u4_ck_dni_arg_formato
                    CHECK (VALUE ~ '^\d{7,8}$')
        $ddl$;
    END IF;
END
$do$;

-- ----------------------------------------------------------------------------
-- PASO 0.B - TABLAS MAESTRAS DEL ALCANCE DE ALMACEN
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS u4_deposito (
    id        BIGINT       PRIMARY KEY,
    nombre    VARCHAR(100) NOT NULL,
    ubicacion VARCHAR(255) NOT NULL,
    capacidad INT          NOT NULL
        CONSTRAINT u4_chk_deposito_capacidad CHECK (capacidad > 0)
);

CREATE TABLE IF NOT EXISTS u4_lote (
    id                 BIGINT                PRIMARY KEY,
    codigo_producto    u4_codigo_producto_dom NOT NULL,
    fecha_vencimiento  DATE                  NOT NULL
);

CREATE TABLE IF NOT EXISTS u4_responsable (
    id              BIGINT        PRIMARY KEY,
    dni             u4_dni_arg_dom NOT NULL UNIQUE,
    mail            VARCHAR(100) NOT NULL
        CONSTRAINT u4_chk_responsable_mail
            CHECK (mail ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
    nombre_completo VARCHAR(150) NOT NULL
);

-- ----------------------------------------------------------------------------
-- PASO 0.C - DATOS MAESTROS DE EJEMPLO (idempotente)
-- Se eliminó la restriccion temporal CHECK (fecha_vencimiento >= CURRENT_DATE)
-- de u4_lote para que los datos de ejemplo no dejen de ser validos con el
-- paso del tiempo. Las fechas de vencimiento se mantienen en 2027 como dato
-- de prueba representativo, sin depender de la fecha de ejecucion.
-- ----------------------------------------------------------------------------

INSERT INTO u4_deposito (id, nombre, ubicacion, capacidad)
VALUES
    (30, 'Deposito Central', 'Mendoza',   10000),
    (31, 'Deposito Sur',     'San Martin',  5000)
ON CONFLICT (id) DO NOTHING;

INSERT INTO u4_lote (id, codigo_producto, fecha_vencimiento)
VALUES
    (501, 'PROD-01', '2027-12-31'),
    (502, 'PROD-02', '2027-11-15'),
    (503, 'PROD-03', '2027-10-20')
ON CONFLICT (id) DO NOTHING;

INSERT INTO u4_responsable (id, dni, mail, nombre_completo)
VALUES
    (801, '30111222', 'carlos@foodstore.com', 'Carlos Gomez'),
    (802, '32333444', 'ana@foodstore.com',    'Ana Lopez')
ON CONFLICT (id) DO NOTHING;

-- ----------------------------------------------------------------------------
-- PASO 1 - RELACION ORIGINAL DEFECTUOSA (PRE-FNBC)
-- Se conserva intacta como evidenca y como oraculo para la prueba
-- lossless-join.
--
-- Analisis de clausuras sobre F = { {L,D}->R, R->D }:
--   {L}+   = {L}
--   {D}+   = {D}
--   {R}+   = {R, D}          por DF2
--   {L, D}+ = {L, D, R}      por DF1  -> superclave minimal -> clave candidata
--   {L, R}+ = {L, R, D}      por DF2  -> superclave minimal -> clave candidata
--   {D, R}+ = {D, R}
--
-- Claves candidatas: {L, D} y {L, R}.
-- Atributos primos: L, D, R (todos pertenecen al menos a una clave candidata).
-- Atributos no primos: ninguno.
--
-- PK original declarada: (lote_id, deposito_id) = {L, D}.
--
-- Verificacion FNBC:
--   DF1: {L, D} -> R. El determinante {L, D} es clave candidata (superclave).
--        Cumple FNBC.
--   DF2: R -> D. El determinante R no es superclave porque {R}+ = {R, D}
--        no contiene L. Viola FNBC.
--   La relacion cumple 3FN porque D es atributo primo (en la DF R->D, el
--   atributo determinado D es primo), pero no cumple FNBC.
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS u4_control_lote_almacen (
    lote_id         BIGINT NOT NULL REFERENCES u4_lote(id),
    deposito_id     BIGINT NOT NULL REFERENCES u4_deposito(id),
    responsable_id  BIGINT NOT NULL REFERENCES u4_responsable(id),
    PRIMARY KEY (lote_id, deposito_id)
);

INSERT INTO u4_control_lote_almacen (lote_id, deposito_id, responsable_id)
VALUES
    (501, 30, 801),
    (502, 30, 801),
    (503, 31, 802)
ON CONFLICT DO NOTHING;

-- ----------------------------------------------------------------------------
-- PASO 2 - TABLAS DESCOMPUESTAS EN FNBC (Teorema de Heath sobre R -> D)
--
-- R1: u4_resp_deposito(R, D)         aisla la DF R -> D; PK = R
-- R2: u4_control_asignacion(L, R)    conserva el vinculo lote-responsable;
--                                    PK compuesta = {L, R} (segunda clave
--                                    candidata de la relacion original)
--
-- Verificacion de FNBC en R1:
--   La unica DF no trivial es R -> D. R es la PK de R1, por lo tanto es
--   superclave. R1 cumple FNBC.
--
-- Verificacion de FNBC en R2:
--   No hay atributos no primos adicionales aparte de la clave {L, R}.
--   {L, R} es superclave de todos sus atributos. R2 cumple FNBC.
--
-- La FK de R2 apunta a R1 (no a u4_responsable directamente) para garantizar
-- que solo se vinculen responsables cuya asignacion de deposito ya exista,
-- lo cual hace posible la reunion sin perdida.
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS u4_resp_deposito (
    responsable_id BIGINT PRIMARY KEY
        REFERENCES u4_responsable(id),
    deposito_id    BIGINT NOT NULL
        REFERENCES u4_deposito(id)
);

CREATE TABLE IF NOT EXISTS u4_control_asignacion (
    lote_id        BIGINT NOT NULL REFERENCES u4_lote(id),
    responsable_id BIGINT NOT NULL
        REFERENCES u4_resp_deposito(responsable_id),
    PRIMARY KEY (lote_id, responsable_id)
);

-- ----------------------------------------------------------------------------
-- PASO 3 - VISTA DE COMPATIBILIDAD
-- Reconstruye (L, D, R) mediante la reunion natural R2 JOIN R1 sobre R.
-- Sirve de oraculo para la prueba de equivalencia y de capa de compatibilidad
-- hacia atras para consultas existentes.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE VIEW u4_vw_control_lote_almacen AS
SELECT
    ca.lote_id        AS lote_id,
    rd.deposito_id    AS deposito_id,
    ca.responsable_id AS responsable_id
FROM u4_control_asignacion AS ca
JOIN u4_resp_deposito      AS rd
    ON rd.responsable_id = ca.responsable_id;

-- ----------------------------------------------------------------------------
-- PASO 4 - VALIDACION PREVIA Y MIGRACION DE DATOS
--
-- Se rechaza la ejecucion si la instancia original ya viola DF2 (un
-- responsable asociado a mas de un deposito), porque la migracion a R1
-- seria ambigua.
-- ----------------------------------------------------------------------------

DO $do$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM u4_control_lote_almacen
        GROUP BY responsable_id
        HAVING COUNT(DISTINCT deposito_id) > 1
    ) THEN
        RAISE EXCEPTION
            'La instancia viola DF2 (R -> D): un responsable aparece en mas de un deposito.';
    END IF;
END
$do$;

-- R1: DISTINCT colapsa los pares (R, D) repetidos por cada lote del mismo
-- responsable. ON CONFLICT DO UPDATE sincroniza el deposito si la fuente
-- cambio entre ejecuciones. Si un responsable dejo de existir en la original,
-- su fila en R1 queda huérfana y sera detectada por la verificacion de
-- equivalencia del PASO 5 (direccion B: filas sobrantes en la vista).
INSERT INTO u4_resp_deposito (responsable_id, deposito_id)
SELECT DISTINCT responsable_id, deposito_id
FROM u4_control_lote_almacen
ON CONFLICT (responsable_id) DO UPDATE
    SET deposito_id = EXCLUDED.deposito_id;

-- R2: cada par (lote, responsable) se migra una sola vez. ON CONFLICT DO
-- NOTHING solo agrega pares faltantes; no elimina pares que ya no existan en
-- la original. Si la relacion original se modifico entre ejecuciones, la
-- verificacion de equivalencia del PASO 5 detecta filas sobrantes o faltantes
-- y lanza EXCEPTION, abortando la transaccion para no presentar datos
-- obsoletos como una migracion exitosa.
INSERT INTO u4_control_asignacion (lote_id, responsable_id)
SELECT lote_id, responsable_id
FROM u4_control_lote_almacen
ON CONFLICT (lote_id, responsable_id) DO NOTHING;

-- ----------------------------------------------------------------------------
-- PASO 5 - VERIFICACION DE EQUIVALENCIA (LOSSLESS-JOIN)
-- Resultado esperado: 0 filas en ambas direcciones y conteos iguales.
-- ----------------------------------------------------------------------------

\echo '--- Direccion A: filas de la vista que no existen en la tabla original ---'
SELECT lote_id, deposito_id, responsable_id
FROM u4_vw_control_lote_almacen
EXCEPT
SELECT lote_id, deposito_id, responsable_id
FROM u4_control_lote_almacen;

\echo '--- Direccion B: filas de la tabla original que no existen en la vista ---'
SELECT lote_id, deposito_id, responsable_id
FROM u4_control_lote_almacen
EXCEPT
SELECT lote_id, deposito_id, responsable_id
FROM u4_vw_control_lote_almacen;

\echo '--- Conteos: original, vista, R1 y R2 ---'
SELECT 'u4_control_lote_almacen' AS relacion, COUNT(*) AS filas
FROM u4_control_lote_almacen
UNION ALL
SELECT 'u4_vw_control_lote_almacen', COUNT(*)
FROM u4_vw_control_lote_almacen
UNION ALL
SELECT 'u4_resp_deposito', COUNT(*) FROM u4_resp_deposito
UNION ALL
SELECT 'u4_control_asignacion', COUNT(*) FROM u4_control_asignacion
ORDER BY relacion;

DO $do$
DECLARE
    v_orig  BIGINT;
    v_vista BIGINT;
    v_faltan BIGINT;
    v_sobran BIGINT;
BEGIN
    SELECT COUNT(*) INTO v_orig  FROM u4_control_lote_almacen;
    SELECT COUNT(*) INTO v_vista FROM u4_vw_control_lote_almacen;

    SELECT COUNT(*) INTO v_faltan
    FROM (
        SELECT lote_id, deposito_id, responsable_id
        FROM u4_control_lote_almacen
        EXCEPT
        SELECT lote_id, deposito_id, responsable_id
        FROM u4_vw_control_lote_almacen
    ) AS faltantes;

    SELECT COUNT(*) INTO v_sobran
    FROM (
        SELECT lote_id, deposito_id, responsable_id
        FROM u4_vw_control_lote_almacen
        EXCEPT
        SELECT lote_id, deposito_id, responsable_id
        FROM u4_control_lote_almacen
    ) AS sobrantes;

    IF v_orig <> v_vista OR v_faltan > 0 OR v_sobran > 0 THEN
        RAISE EXCEPTION
            'Lossless-join FALLA: original=%, vista=%, faltan=%, sobran=%',
            v_orig, v_vista, v_faltan, v_sobran;
    END IF;

    RAISE NOTICE 'Lossless-join OK: original=%, vista=%, faltan=0, sobran=0',
        v_orig, v_vista;
END
$do$;

COMMIT;

-- ============================================================================
-- PASO 6 - PLAN DE REVERSION (documentado; ejecutar solo si se requiere)
-- La tabla original u4_control_lote_almacen se conserva, por lo que la
-- reversión es directa y no destruye datos.
--
--   BEGIN;
--   DROP VIEW  IF EXISTS u4_vw_control_lote_almacen;
--   DROP TABLE IF EXISTS u4_control_asignacion;
--   DROP TABLE IF EXISTS u4_resp_deposito;
--   COMMIT;
--
-- Si en una migracion real se hubiera eliminado la tabla original, puede
-- reconstruirse desde la vista antes de borrar R1 y R2:
--
--   CREATE TABLE u4_control_lote_almacen AS
--   SELECT lote_id, deposito_id, responsable_id
--   FROM u4_vw_control_lote_almacen;
--
--   ALTER TABLE u4_control_lote_almacen
--       ADD CONSTRAINT u4_pk_control_lote_almacen PRIMARY KEY (lote_id, deposito_id);
-- ============================================================================
