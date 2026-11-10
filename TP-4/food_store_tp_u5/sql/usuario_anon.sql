-- =============================================================================
-- usuario_anon.sql  |  TP Unidad 5 — Parte D: Anonimizacion de Datos
-- =============================================================================
-- Crea la tabla cliente_anon con datos sinteticos deterministas.
-- "Deterministico" significa que para un mismo id_cliente siempre se genera
-- el mismo valor sintetico: permite reproducir el script sin alterar los
-- resultados agregados.
--
-- Tecnica aplicada (patron de Clase 2):
--   - nombre    -> 'cliente_anon_' || id_cliente
--   - email     -> 'anon_' || id_cliente || '@anon.local'
--   - telefono  -> '000' || LPAD(id_cliente::TEXT, 7, '0')
--   - direccion -> 'Direccion Anonima ' || id_cliente
--   - contrasena_hash -> NULL (no se expone ni siquiera el hash)
--
-- La tabla conserva id_cliente original para que los JOINs con pedido
-- funcionen y las consultas agregadas sean equivalentes a las de la
-- tabla real.
--
-- Ejecutar:
--   psql -U postgres -d foodstore_dev -f food_store_tp_u5/sql/usuario_anon.sql
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Crear o recrear la tabla anonimizada
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS cliente_anon;

CREATE TABLE cliente_anon AS
SELECT
    id_cliente,
    'cliente_anon_' || id_cliente::TEXT                        AS nombre,
    'anon_' || id_cliente::TEXT || '@anon.local'               AS email,
    '000' || LPAD(id_cliente::TEXT, 7, '0')                    AS telefono,
    'Direccion Anonima ' || id_cliente::TEXT                   AS direccion,
    NULL::TEXT                                                  AS contrasena_hash
FROM cliente;

-- ---------------------------------------------------------------------------
-- 2. Restricciones minimas para que la tabla sea utilizable en consultas
-- ---------------------------------------------------------------------------
ALTER TABLE cliente_anon
    ADD CONSTRAINT pk_cliente_anon PRIMARY KEY (id_cliente);

ALTER TABLE cliente_anon
    ADD CONSTRAINT uq_cliente_anon_email UNIQUE (email);

-- ---------------------------------------------------------------------------
-- 3. Verificacion rapida: el conteo debe coincidir con la tabla real
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    n_real INTEGER;
    n_anon INTEGER;
BEGIN
    SELECT COUNT(*) INTO n_real FROM cliente;
    SELECT COUNT(*) INTO n_anon FROM cliente_anon;

    IF n_real <> n_anon THEN
        RAISE EXCEPTION
            'Discrepancia de conteo: cliente=% vs cliente_anon=%', n_real, n_anon;
    END IF;

    RAISE NOTICE 'Verificacion OK: cliente=% filas, cliente_anon=% filas.',
        n_real, n_anon;
END $$;

COMMIT;

-- ---------------------------------------------------------------------------
-- 4. Consulta de equivalencia
--
-- Pregunta de negocio: distribucion de clientes segun el mes en que
-- realizaron su primer pedido y el volumen de actividad (rangos de cantidad
-- de pedidos por cliente).
--
-- Se ejecuta dos veces: una sobre cliente (tabla real) y otra sobre
-- cliente_anon (tabla anonimizada). Los resultados deben ser identicos.
-- ---------------------------------------------------------------------------

-- CONSULTA A: sobre la tabla REAL
SELECT
    EXTRACT(YEAR  FROM primer_pedido)::INT              AS anio,
    EXTRACT(MONTH FROM primer_pedido)::INT              AS mes,
    CASE
        WHEN total_pedidos BETWEEN 1  AND 5  THEN '1-5'
        WHEN total_pedidos BETWEEN 6  AND 10 THEN '6-10'
        WHEN total_pedidos BETWEEN 11 AND 15 THEN '11-15'
        ELSE '16+'
    END                                                 AS rango_pedidos,
    COUNT(*)                                            AS cantidad_clientes
FROM (
    SELECT
        c.id_cliente,
        MIN(p.fecha_hora)  AS primer_pedido,
        COUNT(p.id_pedido) AS total_pedidos
    FROM cliente c
    JOIN pedido p ON p.id_cliente = c.id_cliente
    GROUP BY c.id_cliente
) sub
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3;

-- CONSULTA B: sobre la tabla ANONIMIZADA
-- Identica en estructura; solo cambia la tabla de clientes.
-- El JOIN con pedido usa id_cliente, que se conservo sin alteracion.
SELECT
    EXTRACT(YEAR  FROM primer_pedido)::INT              AS anio,
    EXTRACT(MONTH FROM primer_pedido)::INT              AS mes,
    CASE
        WHEN total_pedidos BETWEEN 1  AND 5  THEN '1-5'
        WHEN total_pedidos BETWEEN 6  AND 10 THEN '6-10'
        WHEN total_pedidos BETWEEN 11 AND 15 THEN '11-15'
        ELSE '16+'
    END                                                 AS rango_pedidos,
    COUNT(*)                                            AS cantidad_clientes
FROM (
    SELECT
        ca.id_cliente,
        MIN(p.fecha_hora)  AS primer_pedido,
        COUNT(p.id_pedido) AS total_pedidos
    FROM cliente_anon ca
    JOIN pedido p ON p.id_cliente = ca.id_cliente
    GROUP BY ca.id_cliente
) sub
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3;

-- ---------------------------------------------------------------------------
-- 5. Verificacion de equivalencia por EXCEPT
-- Ambas direcciones deben retornar 0 filas.
-- ---------------------------------------------------------------------------

-- Direccion A minus B
SELECT
    EXTRACT(YEAR  FROM primer_pedido)::INT              AS anio,
    EXTRACT(MONTH FROM primer_pedido)::INT              AS mes,
    CASE
        WHEN total_pedidos BETWEEN 1  AND 5  THEN '1-5'
        WHEN total_pedidos BETWEEN 6  AND 10 THEN '6-10'
        WHEN total_pedidos BETWEEN 11 AND 15 THEN '11-15'
        ELSE '16+'
    END                                                 AS rango_pedidos,
    COUNT(*)                                            AS cantidad_clientes
FROM (
    SELECT c.id_cliente, MIN(p.fecha_hora) AS primer_pedido, COUNT(p.id_pedido) AS total_pedidos
    FROM cliente c JOIN pedido p ON p.id_cliente = c.id_cliente GROUP BY c.id_cliente
) sub GROUP BY 1, 2, 3

EXCEPT

SELECT
    EXTRACT(YEAR  FROM primer_pedido)::INT,
    EXTRACT(MONTH FROM primer_pedido)::INT,
    CASE
        WHEN total_pedidos BETWEEN 1  AND 5  THEN '1-5'
        WHEN total_pedidos BETWEEN 6  AND 10 THEN '6-10'
        WHEN total_pedidos BETWEEN 11 AND 15 THEN '11-15'
        ELSE '16+'
    END,
    COUNT(*)
FROM (
    SELECT ca.id_cliente, MIN(p.fecha_hora) AS primer_pedido, COUNT(p.id_pedido) AS total_pedidos
    FROM cliente_anon ca JOIN pedido p ON p.id_cliente = ca.id_cliente GROUP BY ca.id_cliente
) sub GROUP BY 1, 2, 3;

-- Direccion B minus A
SELECT
    EXTRACT(YEAR  FROM primer_pedido)::INT,
    EXTRACT(MONTH FROM primer_pedido)::INT,
    CASE
        WHEN total_pedidos BETWEEN 1  AND 5  THEN '1-5'
        WHEN total_pedidos BETWEEN 6  AND 10 THEN '6-10'
        WHEN total_pedidos BETWEEN 11 AND 15 THEN '11-15'
        ELSE '16+'
    END,
    COUNT(*)
FROM (
    SELECT ca.id_cliente, MIN(p.fecha_hora) AS primer_pedido, COUNT(p.id_pedido) AS total_pedidos
    FROM cliente_anon ca JOIN pedido p ON p.id_cliente = ca.id_cliente GROUP BY ca.id_cliente
) sub GROUP BY 1, 2, 3

EXCEPT

SELECT
    EXTRACT(YEAR  FROM primer_pedido)::INT,
    EXTRACT(MONTH FROM primer_pedido)::INT,
    CASE
        WHEN total_pedidos BETWEEN 1  AND 5  THEN '1-5'
        WHEN total_pedidos BETWEEN 6  AND 10 THEN '6-10'
        WHEN total_pedidos BETWEEN 11 AND 15 THEN '11-15'
        ELSE '16+'
    END,
    COUNT(*)
FROM (
    SELECT c.id_cliente, MIN(p.fecha_hora) AS primer_pedido, COUNT(p.id_pedido) AS total_pedidos
    FROM cliente c JOIN pedido p ON p.id_cliente = c.id_cliente GROUP BY c.id_cliente
) sub GROUP BY 1, 2, 3;
