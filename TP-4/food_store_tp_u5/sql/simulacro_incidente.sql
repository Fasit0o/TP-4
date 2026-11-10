-- =============================================================================
-- simulacro_incidente.sql  |  TP Unidad 5 — Parte C: Simulacro de Incidente
-- =============================================================================
-- Ejecutar como superusuario:
--   psql -U postgres -d foodstore_dev -f food_store_tp_u5/sql/simulacro_incidente.sql
--
-- Secuencia simulada:
--   1. Setup: cliente víctima con contraseña conocida
--   2. Intentos fallidos de autenticación via fn_autenticar (fuerza bruta)
--   3. Autenticación exitosa
--   4. Lectura masiva de la tabla cliente (exfiltración)
--   5. Intento de escalamiento: app_web intenta GRANT admin_datos TO rol_soporte
--      → debe fallar (app_web no tiene CREATEROLE ni membresía en admin_datos)
--   6. Limpieza
-- =============================================================================

-- ---------------------------------------------------------------------------
-- SETUP: cliente víctima con contraseña conocida
-- ---------------------------------------------------------------------------
INSERT INTO cliente (nombre, email, telefono, direccion)
VALUES ('Victoria Suarez', 'vsuarez@foodstore.com', '1155550001', 'Av. Corrientes 1234')
ON CONFLICT (email) DO NOTHING;

SELECT fn_resetear_password(
    (SELECT id_cliente FROM cliente WHERE email = 'vsuarez@foodstore.com'),
    'pass_correcta_123'
);

-- ---------------------------------------------------------------------------
-- FASE 1: Intentos fallidos de autenticación (fuerza bruta via fn_autenticar)
-- Cada llamada queda en el log como sentencia ejecutada por postgres.
-- ---------------------------------------------------------------------------
SELECT fn_autenticar('vsuarez@foodstore.com', 'intento_1_wrong')   AS resultado;
SELECT fn_autenticar('vsuarez@foodstore.com', 'intento_2_wrong')   AS resultado;
SELECT fn_autenticar('vsuarez@foodstore.com', 'intento_3_wrong')   AS resultado;

-- ---------------------------------------------------------------------------
-- FASE 2: Autenticación exitosa (contraseña correcta)
-- ---------------------------------------------------------------------------
SELECT fn_autenticar('vsuarez@foodstore.com', 'pass_correcta_123') AS resultado;

-- ---------------------------------------------------------------------------
-- FASE 3: Lectura masiva (exfiltración de datos personales)
-- NOTA: con log_statement='mod' este SELECT no queda en el log nativo.
-- Se incluye para completar la secuencia del simulacro.
-- ---------------------------------------------------------------------------
SELECT id_cliente, nombre, email, telefono, direccion
FROM   cliente
ORDER  BY id_cliente
LIMIT  10;

-- ---------------------------------------------------------------------------
-- FASE 4: Intento de escalamiento de privilegios
-- Se ejecuta SET ROLE para cambiar al contexto de app_web (bajo privilegio),
-- luego intenta otorgar membresía en admin_datos a rol_soporte.
-- Debe fallar: app_web no tiene CREATEROLE ni es miembro de admin_datos.
-- ---------------------------------------------------------------------------
SET ROLE app_web;
GRANT admin_datos TO rol_soporte;   -- debe fallar aquí

-- Volvemos a postgres para la limpieza
RESET ROLE;

-- ---------------------------------------------------------------------------
-- LIMPIEZA
-- ---------------------------------------------------------------------------
DELETE FROM cliente WHERE email = 'vsuarez@foodstore.com';
