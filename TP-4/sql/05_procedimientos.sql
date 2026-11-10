-- =============================================================================
-- sql/05_procedimientos.sql | TP Unidad 5 | Food Store
-- =============================================================================
\set ON_ERROR_STOP on

-- ---------------------------------------------------------------------------
-- sp_crear_pedido
--
-- Registra un pedido completo en una sola transacción atómica:
--   1. Inserta el encabezado en `pedido`.
--   2. Descompone el JSONB de ítems e inserta cada fila en `detalle_pedido`.
--   3. Descuenta el stock de cada producto.
--   4. Valida stock suficiente antes de descontar (RAISE EXCEPTION si no alcanza).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_crear_pedido(
    p_id_cliente  BIGINT,
    p_forma_pago  forma_pago_enum,
    p_items       JSONB
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_pedido      BIGINT;
    v_item           JSONB;
    v_id_producto    BIGINT;
    v_cantidad       INT;
    v_precio         NUMERIC(10, 2);
    v_stock_actual   INT;
BEGIN
    -- 1. Validación básica: el array no puede estar vacío
    IF jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'El pedido debe contener al menos un ítem.';
    END IF;

    -- 2. Insertar encabezado del pedido
    INSERT INTO pedido (forma_pago, id_cliente)
    VALUES (p_forma_pago, p_id_cliente)
    RETURNING id_pedido INTO v_id_pedido;

    -- 3. Procesar cada ítem del array JSONB
    FOR v_item IN SELECT jsonb_array_elements(p_items)
    LOOP
        v_id_producto := (v_item->>'id_producto')::BIGINT;
        v_cantidad    := (v_item->>'cantidad')::INT;

        -- 3.1 Validar que la cantidad sea positiva
        IF v_cantidad <= 0 THEN
            RAISE EXCEPTION
                'La cantidad debe ser mayor a 0 (producto id=%).', v_id_producto;
        END IF;

        -- 3.2 Obtener precio vigente y stock actual con bloqueo de fila
        --     (FOR UPDATE evita condiciones de carrera en ventas concurrentes)
        SELECT precio_lista, stock
        INTO   v_precio, v_stock_actual
        FROM   producto
        WHERE  id_producto = v_id_producto
          AND  activo = TRUE
        FOR UPDATE;

        IF NOT FOUND THEN
            RAISE EXCEPTION
                'Producto id=% no existe o no está activo.', v_id_producto;
        END IF;

        -- 3.3 Validar stock suficiente
        IF v_stock_actual < v_cantidad THEN
            RAISE EXCEPTION
                'Stock insuficiente para producto id=% (disponible: %, solicitado: %).',
                v_id_producto, v_stock_actual, v_cantidad;
        END IF;

        -- 3.4 Insertar detalle con precio histórico capturado en este momento
        INSERT INTO detalle_pedido (id_pedido, id_producto, cantidad, precio_unitario_historico)
        VALUES (v_id_pedido, v_id_producto, v_cantidad, v_precio);

        -- 3.5 Descontar stock
        UPDATE producto
        SET    stock = stock - v_cantidad
        WHERE  id_producto = v_id_producto;
    END LOOP;

    RAISE NOTICE 'Pedido % creado exitosamente para cliente %.', v_id_pedido, p_id_cliente;
END;
$$;
