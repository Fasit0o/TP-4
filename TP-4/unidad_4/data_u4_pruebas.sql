-- =============================================================================
-- DATOS DE PRUEBA AMPLIADOS - UNIDAD 4 (FNBC)
-- Archivo : unidad_4/data_u4_pruebas.sql
-- Motor   : PostgreSQL 17
-- Base    : foodstore_dev
--
-- Depende de:
--   sql/01_schema.sql
--   sql/02_data.sql
--   unidad_4/tp_fnbc_control_lote.sql  (crea deposito, lote,
--                                       responsable_control y las tablas FNBC)
--
-- Este archivo agrega registros adicionales a las tablas maestras de la
-- extension mayorista y nuevos controles de lote. Mantiene la vista de
-- compatibilidad sincronizada migrando los nuevos controles a R1/R2.
-- =============================================================================

BEGIN;

-- Depositos adicionales (ids 32-36)
INSERT INTO deposito (id, nombre, ubicacion, capacidad)
VALUES
    (32, 'Deposito Norte',       'Las Heras',  8000),
    (33, 'Deposito Este',        'Guaymallen', 6000),
    (34, 'Deposito Oeste',       'Lujan',      4500),
    (35, 'Deposito Mayorista',   'Maipu',     12000),
    (36, 'Deposito Frigorifico', 'Godoy Cruz', 3000)
ON CONFLICT (id) DO NOTHING;

-- Lotes adicionales (ids 504-508). Fechas futuras para superar el CHECK.
INSERT INTO lote (id, codigo_producto, fecha_vencimiento)
VALUES
    (504, 'PROD-04', '2027-08-15'),
    (505, 'PROD-05', '2027-09-01'),
    (506, 'PROD-06', '2027-06-30'),
    (507, 'PROD-07', '2027-03-20'),
    (508, 'PROD-08', '2027-11-28')
ON CONFLICT (id) DO NOTHING;

-- Responsables adicionales (ids 803-807)
INSERT INTO responsable_control (id, dni, mail, nombre_completo)
VALUES
    (803, '28500111', 'lucia@foodstore.com',   'Lucia Martinez'),
    (804, '31200222', 'pedro@foodstore.com',   'Pedro Sanchez'),
    (805, '25700333', 'sofia@foodstore.com',   'Sofia Romero'),
    (806, '33100444', 'matias@foodstore.com',  'Matias Torres'),
    (807, '29900555', 'valeria@foodstore.com', 'Valeria Diaz')
ON CONFLICT (id) DO NOTHING;

-- Controles de lote adicionales.
-- DF2 visible: el responsable 803 aparece en los lotes 504 y 505 con el
-- mismo deposito 32, replicando la redundancia del esquema original.
INSERT INTO control_lote_almacen (lote_id, deposito_id, responsable_control_id)
VALUES
    (504, 32, 803),
    (505, 32, 803),
    (506, 33, 804),
    (507, 34, 805),
    (508, 35, 806)
ON CONFLICT DO NOTHING;

-- Migracion de cualquier control de lote que aun no este en R1/R2.
-- Es idempotente y permite que data_u4_pruebas.sql se ejecute solo una vez
-- o se repita sin duplicar filas.
INSERT INTO responsable_deposito (responsable_control_id, deposito_id)
SELECT DISTINCT responsable_control_id, deposito_id
FROM control_lote_almacen
ON CONFLICT (responsable_control_id) DO NOTHING;

INSERT INTO control_lote_responsable (lote_id, responsable_control_id)
SELECT lote_id, responsable_control_id
FROM control_lote_almacen
ON CONFLICT (lote_id, responsable_control_id) DO NOTHING;

COMMIT;

ANALYZE deposito;
ANALYZE lote;
ANALYZE responsable_control;
ANALYZE control_lote_almacen;
ANALYZE responsable_deposito;
ANALYZE control_lote_responsable;
