# Plan de reversión - Entrega U4 (Food Store)

Este documento describe cómo deshacer los cambios de cada parte de la entrega sin perder datos ni comprometer la integridad de la base `foodstore_dev`.

---

## 1. Reversión de la Parte 1 - Normalización FNBC

La tabla original `u4_control_lote_almacen` **no se elimina** durante la ejecución de `sql/01_normalizacion_fnbc.sql`. Se conserva como evidencia y como origen de datos. Por tanto, la reversión es directa y no destructiva.

### Pasos de reversión (ejecutar sobre `foodstore_dev`)

```sql
BEGIN;

-- 1. Opcional: respaldo independiente de la vista reconstruida antes de eliminar objetos.
--    Si se desea conservar una copia de los datos descompuestos:
--    CREATE TABLE u4_control_lote_almacen_respaldo AS
--    SELECT * FROM u4_vw_control_lote_almacen;

-- 2. Eliminar objetos de la descomposición.
DROP VIEW  IF EXISTS u4_vw_control_lote_almacen;
DROP TABLE IF EXISTS u4_control_asignacion;
DROP TABLE IF EXISTS u4_resp_deposito;

-- 3. La tabla original u4_control_lote_almacen sigue intacta con todos sus datos,
--    por lo que no hay pérdida de información.
COMMIT;
```

### Si la tabla original se hubiera eliminado en una migración real

Reconstruirla desde la vista de compatibilidad **antes** de borrar R1 y R2:

```sql
CREATE TABLE u4_control_lote_almacen AS
SELECT lote_id, deposito_id, responsable_id
FROM u4_vw_control_lote_almacen;

ALTER TABLE u4_control_lote_almacen
    ADD CONSTRAINT u4_pk_control_lote_almacen PRIMARY KEY (lote_id, deposito_id);

-- Luego se pueden eliminar R1, R2 y la vista si se desea volver al esquema original.
```

### Validación posterior a la reversión

```sql
SELECT COUNT(*) FROM u4_control_lote_almacen;
-- Debe coincidir con el conteo original antes de la descomposición.
```

---

## 2. Reversión de la Parte 2 - Desnormalización (vista materializada)

La desnormalización solo añade objetos nuevos (`u4_mv_ventas_categoria_diaria` y sus índices) sobre tablas existentes del esquema principal. No modifica `pedido`, `detalle_pedido`, `producto` ni `categoria`.

### Pasos de reversión

```sql
DROP MATERIALIZED VIEW IF EXISTS u4_mv_ventas_categoria_diaria;
```

Tras esto, el reporte Top 5 vuelve a ejecutarse exclusivamente sobre la consulta normalizada de `sql/02_desnormalizacion.sql` Paso 1, que no depende de la vista materializada.

---

## 3. Reversión de datos de ejemplo

Los datos de ejemplo de la Parte 1 (`u4_deposito`, `u4_lote`, `u4_responsable`, `u4_control_lote_almacen`) se insertaron con `ON CONFLICT DO NOTHING`. Para eliminarlos de forma segura (respetando `ON DELETE RESTRICT`), primero borrar los hijos:

```sql
BEGIN;
DELETE FROM u4_control_asignacion;
DELETE FROM u4_resp_deposito;
DELETE FROM u4_control_lote_almacen;
DELETE FROM u4_lote;
DELETE FROM u4_responsable;
DELETE FROM u4_deposito;
COMMIT;
```

No usar `DROP ... CASCADE` sobre estas tablas sin revisar primero si existen objetos dependientes.

---

## 4. Precauciones

- Ejecutar siempre sobre `foodstore_dev` (sandbox). Nunca sobre `foodstore` ni `foodstore_tp3_prueba` (bases protegidas).
- Ejecutar los pasos dentro de `BEGIN ... COMMIT` y revisar el resultado antes de hacer `COMMIT`.
- No hay contraseñas embebidas en estos scripts; la conexión depende de las credenciales configuradas en el entorno (`pgpass.conf` o similar).
