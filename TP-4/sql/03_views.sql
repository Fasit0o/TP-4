--------------------------------------------------------------------------------
-- VISTAS PARA LOS REPORTES Y CONSULTAS DEL SISTEMA - FOODSTORE
-- Parte B: Implementación de vistas transaccionales y analíticas
--------------------------------------------------------------------------------

-- =====================================================================
-- 1. VISTA: vw_productos_vigentes
-- Expone los productos activos junto con su categoría.
-- =====================================================================
CREATE OR REPLACE VIEW vw_productos_vigentes AS
SELECT 
    p.id_producto,
    p.nombre AS producto_nombre,
    p.precio_lista,
    p.stock,
    c.id_categoria,
    c.nombre AS categoria_nombre
FROM producto p
INNER JOIN categoria c ON p.id_categoria = c.id_categoria
WHERE p.activo = TRUE;


-- =====================================================================
-- 2. VISTA: vw_pedidos_cliente_segura
-- Relaciona pedidos con datos de clientes.
-- Se omite 'direccion' para permitir acceso a roles
-- de reportes sin exponer información personal de la tabla base.
-- =====================================================================
CREATE OR REPLACE VIEW vw_pedidos_cliente_segura AS
SELECT 
    p.id_pedido,
    p.fecha_hora,
    p.forma_pago,
    c.id_cliente,
    c.nombre AS cliente_nombre,
    c.email AS cliente_email,
    c.telefono AS cliente_telefono
FROM pedido p
INNER JOIN cliente c ON p.id_cliente = c.id_cliente;


-- =====================================================================
-- 3. VISTA: vw_detalle_pedido_completo
-- Desglose de ítems de un pedido con nombre del producto y subtotal.
-- =====================================================================
CREATE OR REPLACE VIEW vw_detalle_pedido_completo AS
SELECT 
    dp.id_pedido,
    dp.id_producto,
    prod.nombre AS producto_nombre,
    dp.cantidad,
    dp.precio_unitario_historico,
    (dp.cantidad * dp.precio_unitario_historico) AS subtotal
FROM detalle_pedido dp
INNER JOIN producto prod ON dp.id_producto = prod.id_producto;


--------------------------------------------------------------------------------
-- VERIFICACIÓN DE EQUIVALENCIA DE VISTAS (EXCEPT)
-- Ambas direcciones deben retornar 0 filas.
--------------------------------------------------------------------------------

-- Verificación 1: vw_productos_vigentes
SELECT * FROM vw_productos_vigentes
EXCEPT
SELECT 
    p.id_producto, p.nombre, p.precio_lista, p.stock, c.id_categoria, c.nombre
FROM producto p
INNER JOIN categoria c ON p.id_categoria = c.id_categoria
WHERE p.activo = TRUE;

SELECT 
    p.id_producto, p.nombre, p.precio_lista, p.stock, c.id_categoria, c.nombre
FROM producto p
INNER JOIN categoria c ON p.id_categoria = c.id_categoria
WHERE p.activo = TRUE
EXCEPT
SELECT * FROM vw_productos_vigentes;


-- Verificación 2: vw_pedidos_cliente_segura
SELECT * FROM vw_pedidos_cliente_segura
EXCEPT
SELECT 
    p.id_pedido, p.fecha_hora, p.forma_pago, c.id_cliente, c.nombre, c.email, c.telefono
FROM pedido p
INNER JOIN cliente c ON p.id_cliente = c.id_cliente;

SELECT 
    p.id_pedido, p.fecha_hora, p.forma_pago, c.id_cliente, c.nombre, c.email, c.telefono
FROM pedido p
INNER JOIN cliente c ON p.id_cliente = c.id_cliente
EXCEPT
SELECT * FROM vw_pedidos_cliente_segura;


-- Verificación 3: vw_detalle_pedido_completo
SELECT * FROM vw_detalle_pedido_completo
EXCEPT
SELECT 
    dp.id_pedido, dp.id_producto, prod.nombre, dp.cantidad, dp.precio_unitario_historico,
    (dp.cantidad * dp.precio_unitario_historico)
FROM detalle_pedido dp
INNER JOIN producto prod ON dp.id_producto = prod.id_producto;

SELECT 
    dp.id_pedido, dp.id_producto, prod.nombre, dp.cantidad, dp.precio_unitario_historico,
    (dp.cantidad * dp.precio_unitario_historico)
FROM detalle_pedido dp
INNER JOIN producto prod ON dp.id_producto = prod.id_producto
EXCEPT
SELECT * FROM vw_detalle_pedido_completo;


--------------------------------------------------------------------------------
-- CONFIGURACIÓN DE SEGURIDAD: Rol para reportes seguros
-- Implementa el principio de privilegio mínimo.
--------------------------------------------------------------------------------

-- Crear el rol (ejecutar solo si no existe)
CREATE ROLE rol_reportes;

-- Permisos de conexión y uso del esquema público
GRANT CONNECT ON DATABASE foodstore_dev TO rol_reportes;
GRANT USAGE ON SCHEMA public TO rol_reportes;

-- Lectura exclusiva sobre la vista segura
GRANT SELECT ON vw_pedidos_cliente_segura TO rol_reportes;


--------------------------------------------------------------------------------
-- PARTE C: VISTA MATERIALIZADA
-- mv_facturacion_categoria_mes — Facturación por categoría y mes
--------------------------------------------------------------------------------

-- =====================================================================
-- 4. VISTA MATERIALIZADA: mv_facturacion_categoria_mes
-- Almacena físicamente la facturación agregada por categoría y mes
-- calendario, eliminando el costo del JOIN masivo en cada lectura.
-- =====================================================================
CREATE MATERIALIZED VIEW mv_facturacion_categoria_mes AS
SELECT
    EXTRACT(YEAR  FROM ped.fecha_hora)::INT                        AS anio,
    EXTRACT(MONTH FROM ped.fecha_hora)::INT                        AS mes,
    cat.id_categoria,
    cat.nombre                                                     AS categoria_nombre,
    COUNT(DISTINCT ped.id_pedido)                                  AS total_pedidos,
    SUM(dp.cantidad)                                               AS total_unidades,
    SUM(dp.cantidad * dp.precio_unitario_historico)                AS facturacion_total
FROM categoria cat
INNER JOIN producto      pr  ON pr.id_categoria  = cat.id_categoria
INNER JOIN detalle_pedido dp  ON dp.id_producto   = pr.id_producto
INNER JOIN pedido        ped ON ped.id_pedido     = dp.id_pedido
WHERE cat.activo = TRUE
  AND pr.activo  = TRUE
GROUP BY
    EXTRACT(YEAR  FROM ped.fecha_hora),
    EXTRACT(MONTH FROM ped.fecha_hora),
    cat.id_categoria,
    cat.nombre
WITH DATA;


-- =====================================================================
-- ÍNDICE ÚNICO: idx_mv_facturacion_uk
-- Requerido por REFRESH CONCURRENTLY; acelera filtros por año/mes/categoría.
-- =====================================================================
CREATE UNIQUE INDEX idx_mv_facturacion_uk
    ON mv_facturacion_categoria_mes (anio, mes, id_categoria);


-- =====================================================================
-- REFRESCO MANUAL
-- =====================================================================
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_facturacion_categoria_mes;


-- =====================================================================
-- CONSULTA DE REPORTE SOBRE LA MV
-- =====================================================================
-- SELECT anio, mes, categoria_nombre, total_pedidos, facturacion_total
-- FROM mv_facturacion_categoria_mes
-- ORDER BY anio DESC, mes DESC, facturacion_total DESC;
