# Informe tecnico - Unidad 4: Normalizacion y desnormalizacion (Food Store)

**Proyecto:** Food Store - Base de datos PostgreSQL  
**Motor:** PostgreSQL 17 (compatible con PostgreSQL 18)  
**Base de destino:** `foodstore_u4_dev` (sandbox de desarrollo, aislada de las bases protegidas `foodstore` y `foodstore_tp3_prueba`)  
**Entregables:** `entrega_u4/entrega_final/tp_fnbc_control_lote.sql`, `entrega_u4/entrega_final/tp_desnormalizacion_top_categorias.sql`, `entrega_u4/entrega_final/informe_u4.pdf`

---

## 1. Resumen ejecutivo

Esta entrega resuelve el TP de la Unidad 4 sobre dos tecnicas complementarias:

1. **Normalizacion (FNBC):** se analiza la relacion `u4_control_lote_almacen(lote_id, deposito_id, responsable_id)`, se demuestra que viola la Forma Normal de Boyce-Codd por la dependencia `responsable_id -> deposito_id`, se descompone sin perdida en dos relaciones en FNBC (`u4_resp_deposito` y `u4_control_asignacion`), se migran datos de ejemplo, se crea una vista de compatibilidad y se verifica la equivalencia bidireccional.

2. **Desnormalizacion controlada:** se implementa la vista materializada `u4_mv_ventas_categoria_diaria` para el reporte de las cinco categorias con mayor monto vendido del dia, se miden los planes de ejecucion antes y despues con `EXPLAIN (ANALYZE, BUFFERS)`, se audita la consistencia de la redundancia y se documenta la estrategia de refresco y reversión.

Todas las mediciones de rendimiento deben obtenerse ejecutando los scripts en `foodstore_u4_dev` con credenciales validas. En este informe no se inventan tiempos ni planes de ejecucion; las secciones de evidencia quedan marcadas como pendientes hasta que se ejecute sobre el entorno.

---

## 2. Parte 1 - Normalizacion FNBC

### 2.1 Relacion analizada

```
u4_control_lote_almacen(L, D, R)

L = lote_id         (FK -> u4_lote.id)
D = deposito_id     (FK -> u4_deposito.id)
R = responsable_id  (FK -> u4_responsable.id)

PK original: {L, D}
```

Interpretación de negocio:

- Un lote puede ser controlado en distintos depositos.
- Para un lote y un deposito determinados existe un unico responsable de control.
- Cada responsable de control pertenece a un unico deposito, independientemente del lote que audite.

### 2.2 Adaptacion al esquema real de Food Store

La consigna menciona una tabla `usuario(id)` para representar al responsable. En el esquema real de Food Store **no existe** ninguna tabla `usuario`. Se adopta la tabla `u4_responsable(id, dni, mail, nombre_completo)`, creada dentro del alcance de la Unidad 4, como la estructura que modela al personal de control de almacen. No se inventan tablas ni columnas fuera del alcance de la unidad; la adaptation queda documentada en el encabezado de `sql/01_normalizacion_fnbc.sql`.

### 2.3 Dependencias funcionales

| Etiqueta | Dependencia funcional | Origen |
|----------|----------------------|--------|
| DF1 | {L, D} → R | Para un lote y un deposito existe un unico responsable (PK original). |
| DF2 | R → D | Cada responsable pertenece a un unico deposito (regla de negocio). |

### 2.4 Clausuras de atributos

Bajo el conjunto F = {DF1, DF2}:

- {L}+    = {L}
- {D}+    = {D}
- {R}+    = {R, D}            por DF2
- {L, D}+ = {L, D, R}         por DF1
- {L, R}+ = {L, R, D}         por DF2
- {D, R}+ = {D, R}

### 2.5 Claves candidatas, atributos primos y no primos

| Elemento | Valor |
|----------|-------|
| Claves candidatas | {L, D} y {L, R} |
| Superclaves | {L, D}, {L, R}, {L, D, R} |
| Atributos primos | L, D, R (todos) |
| Atributos no primos | Ninguno |

Justificación: {L, D} determina todos los atributos por DF1 y es minimal. {L, R} determina todos los atributos porque por DF2, {R}+ = {R, D}, por lo tanto {L, R}+ = {L, R, D}; es minimal porque ni {L} ni {R} solos determinan a todos los demás. Ningún atributo simple es superclave. Los tres atributos son primos porque cada uno pertenece al menos a una clave candidata: L pertenece a ambas claves candidatas, D pertenece a {L, D}, y R pertenece a {L, R}. No existen atributos no primos.

### 2.6 Demostración formal de violación de FNBC

Una relación está en FNBC si, para toda dependencia funcional no trivial X → Y, X es superclave de la relación.

- **DF1: {L, D} → R.** El determinante {L, D} es la clave candidata, por lo tanto es superclave. **Cumple FNBC.**
- **DF2: R → D.** El determinante {R} no es superclave porque {R}+ = {R, D} no contiene L. **Viola FNBC.**

Conclusión: `u4_control_lote_almacen` **no está en FNBC** porque DF2 (R → D) tiene un determinante R que no es superclave. La relación **sí cumple 3FN**, porque en la dependencia R → D el atributo determinado D es primo (pertenece a la clave candidata {L, D}), lo que satisface la cláusula de 3FN que permite que Y sea atributo primo incluso cuando X no es superclave. La violación de FNBC genera redundancia estructural: el par (responsable, deposito) se repite en cada fila del responsable.

### 2.7 Anomalias sobre la instancia de ejemplo

Instancia original:

| lote_id | deposito_id | responsable_id |
|---------|-------------|----------------|
| 501 | 30 | 801 |
| 502 | 30 | 801 |
| 503 | 31 | 802 |

**Anomalía de inserción:** se puede insertar `(504, 31, 801)`. El responsable 801 queda asociado simultáneamente a los depósitos 30 y 31, contradiciendo DF2. El esquema original no puede impedirlo porque no declara R → D como restricción.

**Anomalía de eliminación:** si se eliminan `(501, 30, 801)` y `(502, 30, 801)` y no quedan más filas del responsable 801, se pierde el hecho "801 pertenece al depósito 30". Ese hecho no está representado en ninguna otra tabla.

**Anomalía de actualización:** si se cambia solo `(501, 30, 801)` por `(501, 31, 801)`, el responsable 801 queda con dos depósitos distintos. Para mantener la consistencia habría que actualizar todas las filas redundantes del responsable, con riesgo de olvidos y estados contradictorios.

### 2.8 Descomposición sin pérdida (Teorema de Heath)

Aplicando el Teorema de Heath sobre DF2 (R → D):

| Relación | Atributos | PK | DF aislada |
|----------|-----------|----|------------|
| R1 `u4_resp_deposito` | (R, D) | R | R → D |
| R2 `u4_control_asignacion` | (L, R) | {L, R} | — |

- **R1 está en FNBC:** la única DF no trivial es R → D, y R es su clave primaria (superclave mínima).
- **R2 está en FNBC:** no tiene atributos no primos además de la clave; {L, R} es superclave de todos sus atributos.

Atributo común de la descomposición: R = `responsable_id`. En R1, R es clave y se cumple R → D. Por el Teorema de Heath, la reunión natural R1 ⋈ R2 reconstruye exactamente la instancia original, sin tuplas espurias ni pérdida de filas.

Tablas resultantes (ver `sql/01_normalizacion_fnbc.sql`):

```sql
CREATE TABLE u4_resp_deposito (
    responsable_id BIGINT PRIMARY KEY REFERENCES u4_responsable(id),
    deposito_id    BIGINT NOT NULL REFERENCES u4_deposito(id)
);

CREATE TABLE u4_control_asignacion (
    lote_id        BIGINT NOT NULL REFERENCES u4_lote(id),
    responsable_id BIGINT NOT NULL REFERENCES u4_resp_deposito(responsable_id),
    PRIMARY KEY (lote_id, responsable_id)
);
```

La FK de R2 apunta a R1 (no directamente a `u4_responsable`) para garantizar que solo se vinculen responsables cuya asignación de depósito ya exista en R1, preservando la integridad referencial que hace posible la reunión sin pérdida.

### 2.9 Vista de compatibilidad

```sql
CREATE OR REPLACE VIEW u4_vw_control_lote_almacen AS
SELECT
    ca.lote_id        AS lote_id,
    rd.deposito_id    AS deposito_id,
    ca.responsable_id AS responsable_id
FROM u4_control_asignacion AS ca
JOIN u4_resp_deposito      AS rd
    ON rd.responsable_id = ca.responsable_id;
```

Reconstituye (L, D, R) mediante la reunión natural de R2 y R1 sobre R. Sirve de capa de compatibilidad hacia atrás y de oráculo para la prueba de equivalencia.

### 2.10 Migración de datos de ejemplo

1. Validación previa: se rechaza la ejecución si la instancia original ya viola DF2 (algún responsable con más de un depósito), porque la migración a R1 sería ambigua.
2. R1: `INSERT ... SELECT DISTINCT responsable_id, deposito_id` colapsa los pares repetidos. `ON CONFLICT ... DO UPDATE` mantiene sincronizado el depósito si la fuente cambia entre ejecuciones.
3. R2: `INSERT ... SELECT lote_id, responsable_id ... ON CONFLICT DO NOTHING`. Solo agrega pares faltantes; no elimina pares que dejaron de existir en la original.
4. Orden: R1 se popula antes que R2 (FK de R2 hacia R1).

Estrategia de reejecución y aborto ante diferencias: el script es idempotente y transaccional. Si la relación original se modificó entre ejecuciones (filas eliminadas, responsables cambiados de depósito), la verificación de equivalencia del paso 2.11 detecta filas sobrantes o faltantes y lanza `EXCEPTION`, abortando la transacción. De este modo no se presentan datos obsoletos como una migración exitosa.

El script es idempotente: `CREATE TABLE IF NOT EXISTS`, dominios condicionales con `to_regtype()`, `ON CONFLICT DO NOTHING`. No se usa `DROP ... CASCADE` ni se elimina la tabla original.

### 2.11 Verificación de equivalencia (lossless-join)

El script ejecuta una comparación bidireccional con `EXCEPT`:

- Dirección A: `vista EXCEPT original` → debe devolver 0 filas (sin tuplas espurias).
- Dirección B: `original EXCEPT vista` → debe devolver 0 filas (sin pérdida de tuplas).

Un bloque `DO` lanza `EXCEPTION` si los conteos no coinciden, faltan o sobran filas, o algún responsable tiene más de un depósito en `u4_resp_deposito`.

Resultado esperado sobre la instancia de ejemplo:

| Relación | Filas |
|----------|-------|
| u4_control_lote_almacen (original) | 3 |
| u4_vw_control_lote_almacen (vista) | 3 |
| u4_resp_deposito (R1) | 2 |
| u4_control_asignacion (R2) | 3 |

| R2 (lote_id, R) | R1 (R, deposito_id) | Resultado del join |
|-----------------|---------------------|--------------------|
| (501, 801) | (801, 30) | (501, 30, 801) |
| (502, 801) | (801, 30) | (502, 30, 801) |
| (503, 802) | (802, 31) | (503, 31, 802) |

Coincide exactamente con la instancia original.

---

## 3. Parte 2 - Desnormalización del reporte Top 5

### 3.1 Consulta normalizada (escenario de la consigna, adaptada)

Consulta de línea base sobre el esquema normalizado:

```sql
SELECT
    c.nombre                                        AS categoria,
    SUM(dp.cantidad * dp.precio_unitario_historico) AS total_vendido
FROM detalle_pedido dp
JOIN producto  pr  ON pr.id_producto = dp.id_producto
JOIN categoria c   ON c.id_categoria = pr.id_categoria
JOIN pedido    ped ON ped.id_pedido  = dp.id_pedido
WHERE ped.fecha_hora >= ((now() AT TIME ZONE 'America/Argentina/Mendoza')::date || ' 00:00:00 America/Argentina/Mendoza')::timestamptz
  AND ped.fecha_hora <  (((now() AT TIME ZONE 'America/Argentina/Mendoza')::date + 1) || ' 00:00:00 America/Argentina/Mendoza')::timestamptz
GROUP BY c.id_categoria, c.nombre
ORDER BY total_vendido DESC, c.nombre ASC
LIMIT 5;
```

Adaptaciones respecto de la consigna:

| Consigna / típico | Esquema real de Food Store | Decisión adoptada |
|-------------------|---------------------------|-------------------|
| `pedido.fecha` | `pedido.fecha_hora` (TIMESTAMPTZ) | Filtro por rango sobre `fecha_hora` en zona horaria `America/Argentina/Mendoza` (sargable) en lugar de `DATE(fecha_hora) = CURRENT_DATE`. |
| `detalle_pedido.subtotal` | No existe | Se calcula `cantidad * precio_unitario_historico`. |
| Columnas `eliminado` | No existen | No se aplica filtro de eliminación lógica. |

### 3.2 Patrón de desnormalización seleccionado

**Vista materializada** `u4_mv_ventas_categoria_diaria(fecha, categoria, total_vendido, lineas_vendidas, unidades_vendidas)`, agrupada por día y categoría sobre el historial completo.

Justificación:

- El reporte Top 5 se consulta con frecuencia sobre un volumen grande (miles de pedidos, cientos de miles de detalles).
- El costo de la agregación de cuatro tablas se traslada del momento de consulta al momento del refresco.
- Índice único sobre `(fecha, id_categoria)` permite `REFRESH MATERIALIZED VIEW CONCURRENTLY`; índice adicional sobre `(fecha, total_vendido DESC)` orienta la consulta Top 5.

### 3.3 Latencia y frecuencia de actualización (requisito crítico)

La consigna menciona actualización frecuente y consulta en tiempo real. **Esta entrega no afirma que exista actualización en tiempo real**, porque no está garantizada:

- La vista materializada almacena una foto de los datos en el momento del último `REFRESH`.
- Entre dos refrescos, la consulta sobre la MV puede devolver montos desactualizados respecto de las tablas originales.
- La latencia introducida por el patrón es, como máximo, el intervalo entre dos refrescos consecutivos (ejemplo: si se refresca cada hora, los datos pueden tener hasta una hora de retraso).
- El refresco inicial (PASO 3 del script) usa `REFRESH MATERIALIZED VIEW` normal (sin CONCURRENTLY) para poblar la vista por primera vez.
- Los refrescos posteriores deben usar `REFRESH MATERIALIZED VIEW CONCURRENTLY` directamente (no dentro de una función PL/pgSQL) para permitir lecturas durante el refresco. El refresco concurrente requiere que la vista ya haya sido poblada y cuente con el índice UNIQUE `(fecha, id_categoria)`.
- Entre dos refrescos, la consulta sobre la MV puede devolver montos desactualizados respecto de las tablas originales. La latencia introducida por el patrón es, como máximo, el intervalo entre dos refrescos consecutivos.

Estrategia recomendada: refresco programado (pg_cron, programador de tareas o job externo) con frecuencia acorde a la tolerancia al dato desactualizado del negocio (por ejemplo, cada hora o al cierre de cada jornada), nunca tras cada detalle de pedido insertado, salvo que el negocio exija consistencia inmediata (en cuyo caso no corresponde una MV y sí la consulta normalizada con índices adecuados).

### 3.4 Medición de rendimiento (pendiente de ejecución)

Las mediciones siguientes **deben obtenerse ejecutando `sql/02_desnormalizacion.sql` en `foodstore_u4_dev` con credenciales válidas** y copiando la salida real de cada `EXPLAIN (ANALYZE, BUFFERS)`. No se incluyen valores inventados.

| Métrica | Consulta normalizada | Consulta sobre MV | Origen |
|---------|----------------------|-------------------|--------|
| Planning Time | pendiente | pendiente | `EXPLAIN (ANALYZE, BUFFERS)` |
| Execution Time | pendiente | pendiente | `EXPLAIN (ANALYZE, BUFFERS)` |
| Nodo dominante | pendiente | pendiente | Análisis del plan |
| Filas devueltas | 5 | 5 | Resultado de consulta |
| Espacio MV (total) | — | pendiente | `pg_total_relation_size` |
| Espacio MV (heap) | — | pendiente | `pg_relation_size` |
| Filas en MV | — | pendiente | `COUNT(*)` |
| Tiempo de REFRESH inicial | — | pendiente | `REFRESH MATERIALIZED VIEW` (sin CONCURRENTLY) |
| Tiempo de REFRESH concurrente posterior | — | pendiente | `REFRESH MATERIALIZED VIEW CONCURRENTLY` |

Elementos a registrar al ejecutar:

1. Plan de ejecución de la consulta normalizada: identificar el nodo dominante (coste relativo y filas procesadas; típicamente el join/hash sobre `detalle_pedido` y `pedido` filtrado por fecha).
2. Plan de ejecución de la consulta sobre la MV: identificar el nodo dominante (típicamente el escaneo de la MV filtrado por `fecha` y el orden por `total_vendido`).
3. Comparativa antes/después en tabla de costes, filas leídas, buffers compartidos y tiempos.
4. Tiempo y coste de mantenimiento: `REFRESH MATERIALIZED VIEW` y espacio ocupado por la MV e índices.

### 3.5 Consulta equivalente sobre la estructura desnormalizada

```sql
SELECT
    id_categoria,
    categoria,
    total_vendido
FROM u4_mv_ventas_categoria_diaria
WHERE fecha = (now() AT TIME ZONE 'America/Argentina/Mendoza')::date
ORDER BY total_vendido DESC, categoria ASC
LIMIT 5;
```

### 3.6 Auditoría de consistencia

El script compara, para la fecha del día, la vista materializada frente al esquema normalizado en ambas direcciones con `EXCEPT`:

- `MV EXCEPT normalizado` → 0 filas esperadas (sin filas de más en la MV).
- `normalizado EXCEPT MV` → 0 filas esperadas (sin filas faltantes en la MV).
- Conteo de categorías del día: igual en ambas fuentes.

Además, `sql/03_validaciones.sql` compara el resultado completo (Top 5 ordenado) de ambas consultas y lanza `EXCEPTION` si hay diferencias.

Si se detectan inconsistencias, la causa esperada es que la MV no se haya refrescado tras cambios en las tablas originales; la acción correctiva es ejecutar directamente `REFRESH MATERIALIZED VIEW CONCURRENTLY u4_mv_ventas_categoria_diaria;` desde una sesión externa.

### 3.7 Mecanismo de actualización y reversión

- Actualización: ejecutar directamente `REFRESH MATERIALIZED VIEW CONCURRENTLY u4_mv_ventas_categoria_diaria;` desde una sesión externa (pg_cron, programador de tareas o job externo). El refresco concurrente requiere que la vista ya haya sido poblada y cuente con el índice UNIQUE `(fecha, id_categoria)`. El refresco inicial (PASO 3 del script) usa `REFRESH MATERIALIZED VIEW` normal (no concurrente) para poblar la vista por primera vez; los refrescos posteriores deben usar `CONCURRENTLY` para permitir lecturas durante el refresco.
- Reversión de la desnormalización:

```sql
DROP MATERIALIZED VIEW IF EXISTS u4_mv_ventas_categoria_diaria;
```

La consulta normalizada de la Parte 2 sigue disponible y no depende de la MV, por lo que el reporte puede retomarse sobre el esquema normalizado en cualquier momento.

---

## 4. Validaciones automáticas (`sql/03_validaciones.sql`)

Solo lectura, dentro de `BEGIN ... COMMIT`. Verifica:

1. Existencia de objetos de la Parte 1 y Parte 2.
2. Unicidad de PK en `u4_resp_deposito` y `u4_control_asignacion`.
3. DF2: cero responsables con más de un depósito.
4. Lossless-join: 0 filas en `vista EXCEPT original` y `original EXCEPT vista`; conteos iguales.
5. Equivalencia de resultados normalizada vs desnormalizada (Top 5): 0 filas de diferencia en ambas direcciones.
6. Consistencia MV vs esquema normalizado: 0 diferencias y conteos iguales.
7. Bloque `DO` final que lanza `EXCEPTION` ante cualquier crítica fallida.

---

## 5. Pruebas no ejecutadas (falta de autenticación)

Las siguientes pruebas **no se pudieron ejecutar** porque el entorno no dispone de credenciales válidas para autenticar como `postgres` en PostgreSQL 18 (método `scram-sha-256` sin archivo `pgpass.conf` configurado). Ninguno de los scripts SQL se ejecutó, y ninguna medición se obtuvo:

- Creación de la base `foodstore_u4_dev`.
- Ejecución de `sql/01_schema.sql` y `sql/02_data.sql`.
- Ejecución de `entrega_u4/entrega_final/tp_fnbc_control_lote.sql`.
- Ejecución de `entrega_u4/entrega_final/tp_desnormalizacion_top_categorias.sql`.
- Ejecución de `entrega_u4/sql/03_validaciones.sql`.
- Planes `EXPLAIN (ANALYZE, BUFFERS)` de la consulta normalizada y de la consulta sobre la vista materializada.
- Tiempos de ejecución, nodo dominante, filas leídas y buffers compartidos.
- Tiempo del `REFRESH MATERIALIZED VIEW` inicial y del `REFRESH MATERIALIZED VIEW CONCURRENTLY` posterior.
- Espacio ocupado por la vista materializada (`pg_total_relation_size`, `pg_relation_size`).
- Verificación real de equivalencia y auditoría de consistencia.

## 6. Limitaciones

- La base destino debe ser una copia aislada (`foodstore_u4_dev`). Queda prohibido ejecutar sobre `foodstore` ni `foodstore_tp3_prueba`.
- La desnormalización mediante vista materializada no garantiza tiempo real; la latencia está acotada por el intervalo de refresco.
- Los scripts de la Parte 1 son idempotentes; el script de la Parte 2 usa `DROP MATERIALIZED VIEW IF EXISTS` antes de recrear la MV (no es destructivo para las tablas originales).

---

## 7. Plan de reversión

Consulte `entrega_u4/docs/plan_reversion.md`.

---

## 8. Trazabilidad con los entregables de la cátedra

| Requisito de la consigna | Artefacto de esta entrega |
|--------------------------|---------------------------|
| DFs formales | Informe §2.3; `sql/01_normalizacion_fnbc.sql` Paso 1 y comentarios |
| Clausuras de atributos | Informe §2.4 |
| Claves candidatas | Informe §2.5 |
| Atributos primos y no primos | Informe §2.5 |
| Demostración FNBC | Informe §2.6 |
| Anomalias (inserción, eliminación, actualización) | Informe §2.7 |
| Descomposición sin pérdida | Informe §2.8; `sql/01_normalizacion_fnbc.sql` Paso 2 |
| Tablas con PK, FK, restricciones | `sql/01_normalizacion_fnbc.sql` Pasos 0.B, 1, 2 |
| Vista de compatibilidad | `sql/01_normalizacion_fnbc.sql` Paso 3 (`u4_vw_control_lote_almacen`) |
| Migración de datos de ejemplo | `sql/01_normalizacion_fnbc.sql` Paso 4 |
| Verificación de equivalencia ambas direcciones | `sql/01_normalizacion_fnbc.sql` Paso 5; `sql/03_validaciones.sql` |
| Plan de reversión | `docs/plan_reversion.md` |
| Consulta normalizada Top 5 | `sql/02_desnormalizacion.sql` Paso 1 |
| EXPLAIN ANALYZE | `sql/02_desnormalizacion.sql` Pasos 1 y 5; evidencia pendiente |
| Nodo dominante | Informe §3.4; a confirmar con salida real |
| Patrón y justificación de desnormalización | Informe §3.2 |
| Implementación SQL desnormalización | `sql/02_desnormalizacion.sql` Pasos 2-4 |
| Consulta sobre estructura desnormalizada | `sql/02_desnormalizacion.sql` Paso 5; Informe §3.5 |
| Nueva medición EXPLAIN ANALYZE | `sql/02_desnormalizacion.sql` Paso 5; evidencia pendiente |
| Comparación antes/después | Informe §3.4 |
| Auditoría de consistencia | `sql/02_desnormalizacion.sql` Paso 6; `sql/03_validaciones.sql` |
| Mecanismo de actualización y reversión | Informe §3.7; `docs/plan_reversion.md` |
| Evaluación crítica de latencia / no tiempo real | Informe §3.3 |
