# Informe tecnico - Unidad 4: Normalizacion y desnormalizacion

**Proyecto:** Food Store - Base de datos PostgreSQL  
**Autora:** Agustina Micaela Guzman  
**Entorno de referencia:** PostgreSQL 17, base `foodstore_dev`  
**Fecha de documento:** 2026-11-09

---

## 1. Resumen ejecutivo

La Unidad 4 aborda dos tecnicas complementarias:

1. **Normalizacion:** detectar y corregir una violacion de la Forma Normal de Boyce-Codd (FNBC) en la relacion `control_lote_almacen(lote_id, deposito_id, responsable_control_id)`.
2. **Desnormalizacion controlada:** crear la vista materializada `mv_ventas_categoria_diario` para acelerar el reporte de Top 5 categorias por ventas del dia.

La correccion FNBC se implementa en `unidad_4/tp_fnbc_control_lote.sql` mediante el Teorema de Heath, preservando la tabla original como evidencia y como oraculo de comparacion. La desnormalizacion se implementa en `unidad_4/tp_desnormalizacion_top_categorias.sql`, con refresco concurrente, auditoria de consistencia y una linea base de medicion.

> **Estado de ejecucion:** los scripts se validaron de punta a punta el 2026-11-09 sobre un cluster PostgreSQL 17 temporal local, con el esquema y la carga completa. No se modificaron `foodstore` ni `foodstore_tp3_prueba`. La tabla de mediciones contiene salidas reales de `EXPLAIN (ANALYZE, BUFFERS)`; no se inventaron tiempos ni planes.

---

## 2. Objetivos

### 2.1 Objetivo general

Aplicar normalizacion y desnormalizacion sobre el modelo Food Store, justificando cada decision con teoria de dependencias funcionales, verificaciones de equivalencia y criterios de rendimiento.

### 2.2 Objetivos especificos

- Identificar dependencias funcionales, clausuras, claves candidatas y atributos primos.
- Detectar la violacion de FNBC y explicar las anomalias de insercion, borrado y actualizacion.
- Descomponer sin perdida de informacion y demostrar la propiedad lossless-join.
- Mantener compatibilidad mediante una vista que reconstruye la relacion original.
- Disenar una desnormalizacion controlada con una vista materializada y una estrategia de refresco.
- Auditar la consistencia entre el esquema normalizado y la vista materializada.
- Documentar el plan de reversion y las limitaciones de la entrega.

---

## 3. Parte 1 - Correccion FNBC

### 3.1 Relacion analizada

```text
control_lote_almacen(L, D, R)

L = lote_id
D = deposito_id
R = responsable_control_id
Clave primaria original: {L, D}
```

Interpretacion de negocio:

- Un lote puede controlarse en distintos depositos.
- Para un lote y un deposito determinados existe un unico responsable.
- Cada responsable de control pertenece a un unico deposito.

### 3.2 Dependencias funcionales

```text
DF1: {L, D} -> R
DF2: R -> D
```

### 3.3 Clausuras de atributos

```text
{L}+    = {L}
{D}+    = {D}
{R}+    = {R, D}          por DF2
{L, D}+ = {L, D, R}       por DF1
{L, R}+ = {L, R, D}       por DF2
{D, R}+ = {D, R}
```

### 3.4 Claves y atributos

| Elemento | Resultado |
|---|---|
| Clave candidata | `{L, D}` |
| Superclaves | `{L, D}`, `{L, D, R}` |
| Atributos primos | `L`, `D` |
| Atributos no primos | `R` |

### 3.5 Verificacion formal de FNBC

Una relacion esta en FNBC si, para toda dependencia funcional no trivial `X -> Y`, `X` es superclave.

- **DF1:** el determinante `{L, D}` es la clave candidata, por lo tanto es superclave. **Cumple.**
- **DF2:** el determinante `{R}` no es superclave, porque `{R}+ = {R, D}` no contiene `L`. **Viola FNBC.**

Conclusion: `control_lote_almacen` esta en 3FN pero no en FNBC, porque `R` es un atributo no primo que determina a otro atributo no primo `D`.

### 3.6 Anomalias sobre la instancia

Instancia de ejemplo:

```text
(501, 30, 801)
(502, 30, 801)
(503, 31, 802)
```

#### Anomalia de insercion

Se puede insertar `(504, 31, 801)`. El responsable `801` queda asociado simultaneamente a los depositos `30` y `31`, contradiciendo `R -> D`. El esquema original no puede impedirlo porque no declara esa dependencia como restriccion.

#### Anomalia de borrado

Si se eliminan `(501, 30, 801)` y `(502, 30, 801)`, y no quedan otras filas del responsable `801`, se pierde el hecho de que `801` pertenece al deposito `30`. Ese hecho no esta representado en ninguna otra tabla.

#### Anomalia de actualizacion

Si se cambia solo `(501, 30, 801)` por `(501, 31, 801)`, el responsable `801` queda con dos depositos distintos. Para mantener consistencia habria que actualizar todas las filas redundantes del responsable, con riesgo de olvidos.

### 3.7 Descomposicion aplicando el Teorema de Heath

La DF `R -> D` permite dividir la relacion en:

```text
R1 = pi{R, D}(R)  ->  responsable_deposito(responsable_control_id, deposito_id)
R2 = pi{L, R}(R)  ->  control_lote_responsable(lote_id, responsable_control_id)
```

Esquema resultante:

```sql
CREATE TABLE responsable_deposito (
    responsable_control_id BIGINT PRIMARY KEY
        REFERENCES responsable_control(id),
    deposito_id            BIGINT NOT NULL
        REFERENCES deposito(id)
);

CREATE TABLE control_lote_responsable (
    lote_id                BIGINT NOT NULL REFERENCES lote(id),
    responsable_control_id BIGINT NOT NULL
        REFERENCES responsable_deposito(responsable_control_id),
    PRIMARY KEY (lote_id, responsable_control_id)
);
```

#### Verificacion de FNBC en R1

- DF: `R -> D`.
- `R` es clave primaria.
- Unico atributo no primo: `D`.
- No hay dependencias parciales ni transitivas.
- **R1 esta en FNBC.**

#### Verificacion de FNBC en R2

- DF implicita: `{L, R} -> {L, R}` (trivial).
- `{L, R}` es clave primaria.
- No tiene atributos no primos.
- **R2 esta en FNBC.**

### 3.8 Demostracion de lossless-join

Atributo comun de la descomposicion: `R = responsable_control_id`.

En `R1`, `R` es clave. Ademas se cumple `R -> D`. Por el Teorema de Heath, la reunion natural:

```sql
responsable_deposito JOIN control_lote_responsable USING (responsable_control_id)
```

reconstruye exactamente la relacion original, sin tuplas espurias ni perdida de filas.

La vista de compatibilidad materializa esa reunion:

```sql
CREATE OR REPLACE VIEW vw_control_lote_almacen_compatibilidad AS
SELECT
    clr.lote_id,
    rd.deposito_id,
    clr.responsable_control_id
FROM control_lote_responsable AS clr
JOIN responsable_deposito   AS rd
    ON rd.responsable_control_id = clr.responsable_control_id;
```

### 3.9 Equivalencia verificada por script

El script `unidad_4/tp_fnbc_control_lote.sql` ejecuta una comparacion bidireccional:

```text
original EXCEPT vista  -> debe devolver 0 filas
vista EXCEPT original  -> debe devolver 0 filas
```

Ademas, un bloque `DO` lanza `EXCEPTION` si:

- los conteos no coinciden;
- falta o sobra alguna fila;
- algun responsable tiene mas de un deposito en `responsable_deposito`.

### 3.10 Idempotencia y correccion del bug detectado

La version anterior del script ejecutaba:

```sql
DROP DOMAIN codigo_producto_dom CASCADE;
DROP DOMAIN dni_arg_dom CASCADE;
```

Ese `CASCADE` eliminaba columnas dependientes:

- `lote.codigo_producto`;
- `responsable_control.dni`.

Como consecuencia, la segunda ejecucion del script fallaba. La version corregida:

- crea los dominios solo si no existen, usando `to_regtype(...)`;
- no elimina dominios ni columnas;
- usa `CREATE TABLE IF NOT EXISTS`;
- usa `ON CONFLICT DO NOTHING` o `DO UPDATE` en las migraciones;
- puede ejecutarse repetidamente sin perder el esquema.

### 3.11 Conservacion de la tabla original

La tabla `control_lote_almacen` se conserva intencionalmente:

- permite comparar la vista con el esquema defectuoso;
- evita una migracion destructiva;
- sirve como evidencia de la redundancia;
- simplifica la reversion.

La redundancia visible se reporta al final de `validar_u4.sql`.

### 3.12 Plan de reversion

Como la tabla original no se elimina, la reversion es directa:

```sql
BEGIN;
DROP VIEW  IF EXISTS vw_control_lote_almacen_compatibilidad;
DROP TABLE IF EXISTS control_lote_responsable;
DROP TABLE IF EXISTS responsable_deposito;
COMMIT;
```

Si en una migracion real se hubiera eliminado la tabla original, puede reconstruirse desde la vista antes de borrar R1/R2:

```sql
CREATE TABLE control_lote_almacen AS
SELECT lote_id, deposito_id, responsable_control_id
FROM vw_control_lote_almacen_compatibilidad;

ALTER TABLE control_lote_almacen
    ADD CONSTRAINT pk_control_lote_almacen PRIMARY KEY (lote_id, deposito_id);
```

### 3.13 Pruebas manuales sugeridas

Ejecutar en `foodstore_dev`:

```sql
-- 1. Verificar que no hay perdida de filas
SELECT COUNT(*) FROM control_lote_almacen;
SELECT COUNT(*) FROM vw_control_lote_almacen_compatibilidad;

-- 2. Intentar una insercion que violaria R -> D en el esquema original
BEGIN;
INSERT INTO responsable_deposito (responsable_control_id, deposito_id)
VALUES (801, 31);
ROLLBACK;

-- 3. Verificar que R1 impide dos depositos para el mismo responsable
--    (la PK sobre responsable_control_id debe rechazar la fila).

-- 4. Reejecutar el script completo y comprobar que no falla por dominios.
\i unidad_4/tp_fnbc_control_lote.sql
```

---

## 4. Parte 2 - Desnormalizacion controlada

### 4.1 Objetivo

Responder el Top 5 de categorias por ventas del dia sin recorrer en cada consulta las tablas `pedido`, `detalle_pedido`, `producto` y `categoria`.

### 4.2 Consulta original

```sql
SELECT
    c.nombre AS categoria,
    SUM(dp.cantidad * dp.precio_unitario_historico) AS total_vendido
FROM detalle_pedido dp
JOIN producto  pr  ON pr.id_producto = dp.id_producto
JOIN categoria c   ON c.id_categoria = pr.id_categoria
JOIN pedido    ped ON ped.id_pedido  = dp.id_pedido
WHERE DATE(ped.fecha_hora) = CURRENT_DATE
GROUP BY c.nombre
ORDER BY total_vendido DESC
LIMIT 5;
```

Adaptaciones respecto de la consigna:

| Consigna | Esquema real | Decision |
|---|---|---|
| `ped.fecha` | `pedido.fecha_hora` | Se usa `DATE(pedido.fecha_hora)`. |
| `dp.subtotal` | No existe | Se calcula `cantidad * precio_unitario_historico`. |
| `dp.eliminado` | No existe | No se aplica filtro de eliminacion. |
| `ped.eliminado` | No existe | No se aplica filtro de eliminacion. |

### 4.3 Vista materializada

```sql
CREATE MATERIALIZED VIEW mv_ventas_categoria_diario AS
SELECT
    DATE(ped.fecha_hora)                            AS fecha,
    c.nombre                                        AS categoria,
    SUM(dp.cantidad * dp.precio_unitario_historico) AS total_vendido,
    COUNT(*)                                        AS lineas_vendidas,
    SUM(dp.cantidad)                                AS unidades_vendidas
FROM detalle_pedido dp
JOIN producto  pr  ON pr.id_producto = dp.id_producto
JOIN categoria c   ON c.id_categoria = pr.id_categoria
JOIN pedido    ped ON ped.id_pedido  = dp.id_pedido
GROUP BY DATE(ped.fecha_hora), c.nombre;
```

Se agregan dos indices:

- `idx_mv_ventas_fecha_cat`: unico sobre `(fecha, categoria)`, obligatorio para `REFRESH CONCURRENTLY`.
- `idx_mv_ventas_fecha_total`: sobre `(fecha, total_vendido DESC)`, orientado al Top 5.

### 4.4 Estrategia de refresco

La funcion `fn_refrescar_top5_categorias()` encapsula:

```sql
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_ventas_categoria_diario;
```

Puede invocarse desde:

- `pg_cron`;
- `pgAgent`;
- Programador de tareas de Windows;
- un job externo de la aplicacion.

Frecuencia recomendada: una vez por hora o al cierre de cada jornada, segun la tolerancia a datos desactualizados. El refresco concurrente reduce el bloqueo de lectura, a cambio de mayor costo de CPU y E/S.

### 4.5 Auditoria de consistencia

El script compara:

```text
normalizado EXCEPT mv  -> 0 filas
mv EXCEPT normalizado  -> 0 filas
```

Tambien compara la cantidad de categorias del dia. Si hay diferencias, `validar_u4.sql` lanza una excepcion e indica ejecutar `fn_refrescar_top5_categorias()`.

### 4.6 Medicion de rendimiento

La linea base y la consulta optimizada se ejecutan con:

```sql
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
```

Medicion realizada el 2026-11-09 sobre un cluster PostgreSQL 17 temporal local (`127.0.0.1:55432`), con el esquema y la carga completa de `sql/01_schema.sql` + `sql/02_data.sql`. No se usaron las bases protegidas `foodstore` ni `foodstore_tp3_prueba`.

| Metrica | Consulta original | Consulta sobre MV | Observacion |
|---|---:|---:|---|
| Tiempo de ejecucion | 61.271 ms | 0.082 ms | `Execution Time` de `EXPLAIN (ANALYZE, BUFFERS)`. |
| Tiempo de planificacion | 5.295 ms | 1.464 ms | `Planning Time`. |
| Filas devueltas | 5 | 5 | Top 5 del dia. |
| Categorias evaluadas | 9 | 9 | Misma cantidad en ambas fuentes. |
| Espacio total de la MV | - | 184 kB | `pg_total_relation_size`. |
| Heap de la MV | - | 64 kB | `pg_relation_size`. |
| Filas almacenadas en la MV | - | 818 | Historial completo por fecha y categoria. |
| Tiempo de refresco concurrente | - | 408.457 ms | `REFRESH MATERIALIZED VIEW CONCURRENTLY`. |

> Las cifras corresponden a un entorno local temporal, no a produccion. Sirven como evidencia reproducible de la diferencia de orden de magnitud entre ambos planes; no deben presentarse como benchmark del servidor principal.

### 4.7 Costos y beneficios

**Beneficios:**

- Reduce el trabajo de agregacion en cada consulta del Top 5.
- Permite indices especializados por fecha y total.
- Aisla el costo de calculo en el momento del refresco.

**Costos:**

- Ocupa espacio adicional en disco.
- Requiere refresco periodico.
- Puede mostrar datos desactualizados entre refrescos.
- El refresco concurrente consume recursos y requiere un indice unico.

### 4.8 Reversion

```sql
DROP MATERIALIZED VIEW IF EXISTS mv_ventas_categoria_diario;
DROP FUNCTION IF EXISTS fn_refrescar_top5_categorias();
```

La consulta original sigue disponible en el script y no depende de la MV.

---

## 5. Estructura de archivos de la Unidad 4

```text
unidad_4/
├── unidad_4/tp_fnbc_control_lote.sql
├── unidad_4/tp_desnormalizacion_top_categorias.sql
├── data_u4_pruebas.sql
├── validar_u4.sql
└── INFORME_TECNICO_U4.md
```

Dependencias de ejecucion:

```text
sql/01_schema.sql
sql/02_data.sql
unidad_4/tp_fnbc_control_lote.sql
unidad_4/data_u4_pruebas.sql
unidad_4/tp_desnormalizacion_top_categorias.sql
unidad_4/validar_u4.sql
```

---

## 6. Seguridad y buenas practicas aplicadas

- Todos los scripts se ejecutan dentro de `BEGIN ... COMMIT`.
- `\set ON_ERROR_STOP on` evita continuar despues de un error.
- No se usan credenciales embebidas.
- No se ejecutan `DROP DATABASE` ni operaciones destructivas sobre bases protegidas.
- La tabla original se conserva para permitir reversion y auditoria.
- Las verificaciones criticas usan `EXCEPT` bidireccional y bloques `DO` con `RAISE EXCEPTION`.
- No se usa `DROP DOMAIN ... CASCADE`.
- Los scripts son idempotentes en la medida de lo posible.

---

## 7. Checklist de cumplimiento

| Requisito | Evidencia | Estado |
|---|---|---|
| Identificar DFs | Seccion 3.2 | Cumplido |
| Clausuras | Seccion 3.3 | Cumplido |
| Claves candidatas | Seccion 3.4 | Cumplido |
| Atributos primos y no primos | Seccion 3.4 | Cumplido |
| Verificacion FNBC | Seccion 3.5 | Cumplido |
| Anomalias de insercion | Seccion 3.6 | Cumplido |
| Anomalia de borrado | Seccion 3.6 | Cumplido |
| Anomalia de actualizacion | Seccion 3.6 | Cumplido |
| Descomposicion sin perdida | Secciones 3.7 y 3.8 | Cumplido |
| Script DDL/DML FNBC | `unidad_4/tp_fnbc_control_lote.sql` | Cumplido |
| Migracion de datos | `unidad_4/tp_fnbc_control_lote.sql` | Cumplido |
| Verificacion de equivalencia | `unidad_4/tp_fnbc_control_lote.sql` y `validar_u4.sql` | Cumplido |
| Vista de compatibilidad | `vw_control_lote_almacen_compatibilidad` | Cumplido |
| Idempotencia | Seccion 3.10 | Cumplido |
| Plan de reversion | Seccion 3.12 | Cumplido |
| Consulta original | Seccion 4.2 | Cumplido |
| Vista materializada | Seccion 4.3 | Cumplido |
| Indices | Seccion 4.3 | Cumplido |
| Estrategia de refresco | Seccion 4.4 | Cumplido |
| Auditoria de consistencia | Seccion 4.5 | Cumplido |
| Medicion real | Seccion 4.6 | Cumplido en cluster temporal |
| Informe tecnico | Este documento | Cumplido |

---

## 8. Limitaciones y trabajo pendiente

1. **Entorno de medicion:** las cifras de la seccion 4.6 se obtuvieron en un cluster temporal local, no en la instancia principal. Si se necesita un benchmark institucional, repetir los `EXPLAIN` en `foodstore_dev` con las mismas condiciones.
2. **Credenciales:** el servidor local original solicita contrasena para `postgres` y `admin_datos`; la validacion se hizo en un cluster temporal con autenticacion `trust` y puerto alternativo.
3. **Pruebas concurrentes:** la Unidad 4 no requiere simulaciones de concurrencia, pero el refresco de la MV podria probarse con dos sesiones para observar el comportamiento de `REFRESH CONCURRENTLY`.
4. **Dependencia con U5:** si se reejecuta `tp_desnormalizacion_top_categorias.sql` despues de `food_store_tp_u5/sql/roles.sql`, se pierde el `GRANT SELECT` sobre la MV. Hay que volver a aplicar el permiso.
5. **Dependencia con U6:** `health_check_pre.sql` consulta las tablas FNBC; por eso la tabla original y las tablas R1/R2 se conservan.

---

## 9. Conclusiones

- La relacion original no esta en FNBC por la dependencia `R -> D`.
- La descomposicion en `responsable_deposito` y `control_lote_responsable` elimina la redundancia y las anomalias asociadas.
- La descomposicion es sin perdida de informacion y puede auditarse con `EXCEPT` bidireccional.
- La tabla original se conserva como evidencia y permite una reversion simple.
- La vista materializada mejora el costo esperado del Top 5, a cambio de espacio y refresco periodico.
- La entrega queda completa en diseno, scripts y validacion ejecutada sobre un cluster temporal. Las mediciones son reproducibles y no se tomaron sobre bases protegidas.
