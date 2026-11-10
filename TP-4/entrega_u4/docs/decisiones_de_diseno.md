# Decisiones de diseño - Entrega U4 (Food Store)

Este documento explica las decisiones de diseño adoptadas para reconstruir de forma independiente el TP de la Unidad 4, sin copiar literalmente la implementación previa de `unidad_4/`.

---

## 1. Carpeta de entrega independiente

Todos los artefactos nuevos viven en `entrega_u4/`, separada de la carpeta original `unidad_4/`. No se modificó ningún archivo fuera del alcance de la Unidad 4 ni ningún script consolidado del proyecto (`sql/01_schema.sql`, `sql/02_data.sql`, etc.).

---

## 2. Nomenclatura interna (prefijo `u4_`)

Se adoptó el prefijo `u4_` para todos los objetos nuevos de esta entrega:

- `u4_deposito`, `u4_lote`, `u4_responsable` (tablas maestras del alcance de almacen).
- `u4_control_lote_almacen` (relación original, conservada como evidencia).
- `u4_resp_deposito` (R1), `u4_control_asignacion` (R2).
- `u4_vw_control_lote_almacen` (vista de compatibilidad).
- `u4_mv_ventas_categoria_diaria` (Parte 2).

**Razón:** evitar colisiones de nombres con los objetos ya existentes en `unidad_4/` (`control_lote_almacen`, `responsable_deposito`, `control_lote_responsable`, `vw_control_lote_almacen_compatibilidad`, `mv_ventas_categoria_diario`, `fn_refrescar_top5_categorias`) cuando ambos entregables se ejecuten sobre la misma base `foodstore_dev`. Los nombres son coherentes y descriptivos dentro de esta entrega, y cada objeto se documenta con su abreviatura (L, D, R) en el script SQL.

---

## 3. Adaptación al esquema real (sin tabla `usuario`)

La consigna menciona `usuario(id)`, pero en el esquema real de Food Store no existe tal tabla. Se decidió:

- No inventar la tabla `usuario`.
- Crear `u4_responsable(id, dni, mail, nombre_completo)` dentro del alcance de la Unidad 4 como la estructura que representa al personal de control de almacén.
- Documentar la adaptación expresamente en el encabezado de `sql/01_normalizacion_fnbc.sql`.

---

## 4. Tipos de datos y restricciones

- `BIGINT` para todos los identificadores surrogates y claves foráneas (volumen potencial mayorista).
- `DATE` para `u4_lote.fecha_vencimiento`: la caducidad legal de un alimento es un día calendario, no un instante con zona horaria. `TIMESTAMPTZ` se reserva para instantes del sistema (como `pedido.fecha_hora` en el esquema principal).
- `VARCHAR(n)` con longitud acotada para texto, cada una justificada: `nombre VARCHAR(100)`, `ubicacion VARCHAR(255)`, `mail VARCHAR(100)`, `nombre_completo VARCHAR(150)`.
- `INT` para `capacidad` con `CHECK (capacidad > 0)`: cantidad física de unidades, sin rango de BIGINT.
- Dominios reutilizables `u4_codigo_producto_dom` y `u4_dni_arg_dom` con `CHECK` de formato, creados condicionalmente con `to_regtype()` para evitar fallos en reejecuciones.

---

## 5. No operaciones destructivas

- No se utiliza `DROP ... CASCADE` en ninguna parte. La implementación previa usaba `DROP DOMAIN ... CASCADE`, que eliminaba columnas dependientes (`lote.codigo_producto`, `responsable_control.dni`) y rompía la reejecución; esa práctica se reemplaza por dominios condicionales y `IF NOT EXISTS`.
- La tabla original `u4_control_lote_almacen` se conserva intencionalmente: sirve como evidencia de la violación de FNBC, como oráculo de la prueba lossless-join y como base de una reversión simple sin pérdida de datos.
- `sql/02_desnormalizacion.sql` usa `DROP MATERIALIZED VIEW IF EXISTS` antes de crear la MV; esto solo afecta a la MV, nunca a las tablas originales del esquema principal.
- No hay `GRANT ALL` ni privilegios innecesarios en los scripts.

---

## 6. Patrón de desnormalización seleccionado

Se eligió una **vista materializada** que precalcula el monto vendido por categoría y día sobre la unión de `pedido`, `detalle_pedido`, `producto` y `categoria`, con índice único sobre `(fecha, id_categoria)` (requisito de `REFRESH CONCURRENTLY`) e índice secundario sobre `(fecha, total_vendido DESC, categoria ASC)`.

Razones:

- El reporte Top 5 se consulta con frecuencia sobre un conjunto grande de datos; trasladar la agregación al refresco reduce el costo de cada consulta.
- Permite índices especializados que la consulta normalizada no tiene sobre `fecha_hora` (no existe índice en el esquema base sobre esa columna).
- Aísla el costo de cálculo en el momento del refresco programado.

Contrapartidas documentadas:

- Ocupa espacio adicional en disco.
- Requiere refresco periódico.
- No garantiza tiempo real: entre refrescos los datos pueden estar desactualizados. La latencia máxima es el intervalo entre refrescos consecutivos.

---

## 7. Seguridad operativa

- Todos los scripts de implementación van dentro de `BEGIN ... COMMIT` con `\set ON_ERROR_STOP on`.
- `sql/03_validaciones.sql` es de solo lectura (sin DDL ni DML).
- No se incluyen contraseñas ni datos personales reales (los correos y nombres de ejemplo son genéricos del dominio `foodstore.com` y DNIs sintéticos).
- No se crean ni eliminan bases de datos; todo se ejecuta sobre `foodstore_dev`.

---

## 8. Diferencias respecto de la implementación previa (`unidad_4/`)

| Aspecto | Implementación previa (`unidad_4/`) | Esta entrega (`entrega_u4/`) |
|---------|-------------------------------------|------------------------------|
| Carpeta | `unidad_4/` | `entrega_u4/` (independiente) |
| Prefijo de objetos | Ninguno (nombres en conflicto posible) | `u4_` para todos los objetos nuevos |
| Tablas maestras | `deposito`, `lote`, `responsable_control` | `u4_deposito`, `u4_lote`, `u4_responsable` |
| Relación original | `control_lote_almacen` (misma, conservada) | `u4_control_lote_almacen` (conservada) |
| Tablas descompuestas | `responsable_deposito`, `control_lote_responsable` | `u4_resp_deposito`, `u4_control_asignacion` |
| Vista de compatibilidad | `vw_control_lote_almacen_compatibilidad` | `u4_vw_control_lote_almacen` |
| Vista materializada | `mv_ventas_categoria_diario` | `u4_mv_ventas_categoria_diaria` |
| Función de refresco | `fn_refrescar_top5_categorias()` | `REFRESH MATERIALIZED VIEW CONCURRENTLY` directo (sin función PL/pgSQL) |
| Medición | `DATE(pedido.fecha_hora) = CURRENT_DATE` | Rango `fecha_hora >= ((now() AT TIME ZONE 'America/Argentina/Mendoza')::date || ' 00:00:00 America/Argentina/Mendoza')::timestamptz` y `< ((now() AT TIME ZONE 'America/Argentina/Mendoza')::date + 1) || ' 00:00:00 America/Argentina/Mendoza')::timestamptz` (sargable, zona horaria Mendoza) |
| Dominios | `DROP DOMAIN ... CASCADE` en versión previa (corregido después) | `to_regtype()` condicional, sin `DROP ... CASCADE` |
| Documentación | Informe con mediciones inventadas sobre cluster temporal | Sin valores inventados; se marca evidencia pendiente hasta ejecución real |
