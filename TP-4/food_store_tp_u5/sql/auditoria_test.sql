-- =============================================================================
-- auditoria_test.sql  |  TP Unidad 5 — Parte B: Prueba de Auditoría
-- =============================================================================
-- Ejecutar con:
--   psql -U app_web -d foodstore_dev -f food_store_tp_u5/sql/auditoria_test.sql
--
-- Propósito: generar una secuencia de operaciones auditables (lectura,
-- inserción, actualización) para verificar que log_statement='mod' las
-- registra correctamente en el log del servidor.
-- =============================================================================

-- 1. LECTURA (SELECT) — no queda en el log con log_statement='mod'
--    Se incluye para mostrar el contraste: las lecturas NO se auditan
--    con esta configuración básica.
SELECT id_cliente, nombre, email
FROM   cliente
LIMIT  3;

-- 2. INSERCIÓN — queda registrada en el log
INSERT INTO cliente (nombre, email, telefono, direccion)
VALUES ('Cliente Prueba Auditoria', 'auditoria@test.com', '1100000000', 'Calle Falsa 123');

-- 3. ACTUALIZACIÓN — queda registrada en el log
UPDATE cliente
SET    telefono = '1199999999'
WHERE  email = 'auditoria@test.com';

-- 4. Limpieza (también queda en el log como operación de modificación)
DELETE FROM cliente
WHERE  email = 'auditoria@test.com';
