# Informe de reorganizacion y validacion - FoodStore

**Fecha:** 2026-11-09  
**Alcance:** reorganizacion integral del repositorio, correccion de la Unidad 4 y validacion en un cluster PostgreSQL 17 temporal.  
**Bases protegidas:** `foodstore` y `foodstore_tp3_prueba` no fueron modificadas.

---

## 1. Resumen

Se reorganizo el repositorio en cuatro areas principales:

- `sql/`: scripts base numerados y ordenados.
- `unidad_4/`: entregables de normalizacion y desnormalizacion.
- `docs/`: DUIA, protocolo, informes y especificaciones.
- `food_store_tp_u5/` y `food_store_tp_u6/`: se conservaron con su estructura y se actualizaron las referencias de rutas.

Se corrigieron los siguientes problemas criticos de la Unidad 4:

- eliminacion de `DROP DOMAIN ... CASCADE`;
- separacion de los datos FNBC de `sql/02_data.sql`;
- incorporacion de la consulta original y de mediciones reales;
- agregado de validaciones bloqueantes y plan de reversion;
- creacion de la vista materializada con indices y auditoria bidireccional.

---

## 2. Cambios de estructura

| Antes | Despues |
|---|---|
| `schema.sql` | `sql/01_schema.sql` |
| `data.sql` | `sql/02_data.sql` |
| `views.sql` | `sql/03_views.sql` |
| `restricciones_integridad.sql` | `sql/04_restricciones_integridad.sql` |
| `procedimientos.sql` | `sql/05_procedimientos.sql` |
| `queries.sql` | `sql/06_consultas.sql` |
| `indices.sql` | `sql/07_indices.sql` |
| `tp_fnbc_control_lote.sql` | `unidad_4/tp_fnbc_control_lote.sql` |
| `tp_desnormalizacion_top_categorias.sql` | `unidad_4/tp_desnormalizacion_top_categorias.sql` |
| `informe_mediciones.md` | `docs/informes/informe_mediciones.md` |
| `informe_concurrencia.md` | `docs/informes/informe_concurrencia.md` |
| `bitacora_competencia.md` | `docs/informes/bitacora_competencia.md` |
| `ejercicio_lectura_critica.md` | `docs/informes/ejercicio_lectura_critica.md` |
| `protocolo_seguridad.md` | `docs/protocolo_seguridad.md` |
| `DUIA.md` | `docs/DUIA.md` |
| `specs/*.md` | `docs/specs/base/` y `docs/specs/unidad4/` |

Los documentos Kiro duplicados de FNBC se movieron a `docs/specs/unidad4/archive/`.

---

## 3. Correcciones en la Unidad 4

### 3.1 Idempotencia de dominios

El script anterior ejecutaba:

```sql
DROP DOMAIN IF EXISTS codigo_producto_dom CASCADE;
DROP DOMAIN IF EXISTS dni_arg_dom CASCADE;
```

Ese patron eliminaba columnas dependientes y rompia la reejecucion. Ahora los dominios se crean solo si no existen:

```sql
IF to_regtype('codigo_producto_dom') IS NULL THEN
    EXECUTE 'CREATE DOMAIN ...';
END IF;
```

### 3.2 Separacion de datos

Los registros de `deposito`, `lote`, `responsable_control` y `control_lote_almacen` se movieron de `sql/02_data.sql` a `unidad_4/data_u4_pruebas.sql`.

Motivo: `sql/02_data.sql` debe poder ejecutarse sin las tablas FNBC y debe conservar los conteos esperados por U6:

- `pedido = 203.000`;
- `detalle_pedido = 306.700`.

### 3.3 Desnormalizacion

El script de la MV ahora incluye:

- consulta original como linea base;
- `EXPLAIN (ANALYZE, BUFFERS)` antes y despues;
- vista materializada con `lineas_vendidas` y `unidades_vendidas`;
- indice unico y indice orientado al Top 5;
- funcion de refresco concurrente;
- auditoria bidireccional con `EXCEPT`;
- eliminacion del `DROP ... CASCADE` sobre la MV.

### 3.4 Validacion

`unidad_4/validar_u4.sql` verifica:

- existencia de tablas, vista y funcion;
- claves de R1 y R2;
- ausencia de responsables con multiples depositos;
- ausencia de controles huerfanos;
- equivalencia bidireccional entre la tabla original y la vista;
- indices de la MV;
- consistencia entre la MV y el esquema normalizado.

---

## 4. Validacion ejecutada

Entorno:

- PostgreSQL 17;
- cluster temporal en `C:\Users\sotof\AppData\Local\Temp\opencode\pg_u4_validate`;
- puerto `55432`;
- autenticacion `trust` solo para el cluster temporal;
- base `foodstore_dev` creada dentro de ese cluster.

Secuencia ejecutada:

```powershell
psql -h 127.0.0.1 -p 55432 -U postgres -d foodstore_dev -v ON_ERROR_STOP=1 -f sql/01_schema.sql
psql -h 127.0.0.1 -p 55432 -U postgres -d foodstore_dev -v ON_ERROR_STOP=1 -f sql/02_data.sql
psql -h 127.0.0.1 -p 55432 -U postgres -d foodstore_dev -v ON_ERROR_STOP=1 -f unidad_4/tp_fnbc_control_lote.sql
psql -h 127.0.0.1 -p 55432 -U postgres -d foodstore_dev -v ON_ERROR_STOP=1 -f unidad_4/data_u4_pruebas.sql
psql -h 127.0.0.1 -p 55432 -U postgres -d foodstore_dev -v ON_ERROR_STOP=1 -f unidad_4/tp_desnormalizacion_top_categorias.sql
psql -h 127.0.0.1 -p 55432 -U postgres -d foodstore_dev -v ON_ERROR_STOP=1 -f unidad_4/validar_u4.sql
```

Resultados principales:

| Verificacion | Resultado |
|---|---|
| `sql/01_schema.sql` | OK |
| `sql/02_data.sql` | OK; 3.000 pedidos y 6.700 detalles del dia |
| Primera ejecucion FNBC | OK; lossless-join con 3 filas |
| Segunda ejecucion FNBC | OK; idempotencia confirmada |
| `data_u4_pruebas.sql` | OK; 5 lotes y 5 controles nuevos |
| Desnormalizacion | OK; MV creada y auditada |
| `validar_u4.sql` | OK; todas las validaciones pasaron |
| Equivalencia FNBC | 8 filas en original y vista; 0 diferencias |
| DF2 | 0 responsables con multiples depositos |
| Consistencia MV | 0 diferencias; 9 categorias |
| `sql/05_procedimientos.sql` | OK; `sp_crear_pedido` creado |
| `food_store_tp_u5/sql/roles.sql` | OK tras crear las vistas; roles y grants aplicados |
| `food_store_tp_u6/scripts/health_check_pre.sql` | OK; FNBC detectadas y conteos correctos |
| `food_store_tp_u6/scripts/health_check.sql` | OK; 203.000 pedidos y 306.700 detalles |

`sql/04_restricciones_integridad.sql` aborta en su prueba intencional de fecha futura cuando se ejecuta con `ON_ERROR_STOP=1`. Ese comportamiento es el esperado: demuestra que el trigger rechaza el pedido; el script no debe tratarse como fallido.

---

## 5. Mediciones reales de la MV

Obtenidas con `EXPLAIN (ANALYZE, BUFFERS)` en el cluster temporal:

| Metrica | Consulta original | Consulta sobre MV |
|---|---:|---:|
| Tiempo de ejecucion | 61.271 ms | 0.082 ms |
| Tiempo de planificacion | 5.295 ms | 1.464 ms |
| Filas devueltas | 5 | 5 |
| Categorias evaluadas | 9 | 9 |

Otros datos:

- filas almacenadas en la MV: 818;
- tamano total de la MV: 184 kB;
- heap de la MV: 64 kB;
- tiempo de `REFRESH MATERIALIZED VIEW CONCURRENTLY`: 408.457 ms.

> Estas cifras corresponden al cluster temporal de validacion, no a produccion. Se registran como evidencia reproducible y no como benchmark institucional.

---

## 6. Referencias actualizadas

Se actualizaron referencias de rutas en:

- `README.md`;
- `AGENTS.md`;
- `docs/DUIA.md`;
- `docs/specs/**`;
- `food_store_tp_u5/BITACORA.md` y `food_store_tp_u5/docs/**`;
- `food_store_tp_u6/BITACORA_U6.md` y `food_store_tp_u6/docs/**`;
- comentarios de cabecera de `sql/01_schema.sql` a `sql/07_indices.sql`.

No se modificaron los logs historicos de U5/U6 ni los respaldos `.dump`.

---

## 7. Pendientes y riesgos

1. **Entorno principal:** la instancia original seguia requiriendo contrasena para `postgres` y `admin_datos`. La validacion se hizo en un cluster temporal; si se necesita evidencia sobre `foodstore_dev`, repetir la secuencia con credenciales.
2. **Unidad 5:** si se reejecuta la desnormalizacion despues de `food_store_tp_u5/sql/roles.sql`, se pierde el `GRANT SELECT` sobre `mv_ventas_categoria_diario`. Volver a aplicar el permiso.
3. **Unidad 6:** los scripts esperan 203.000 pedidos y 306.700 detalles. No cambiar el bloque de 3.000 pedidos sin actualizar `restore_test.ps1`.
4. **Especificaciones U4:** la especificacion consolidada se mantiene como fuente principal; los archivos Kiro originales quedaron archivados para trazabilidad.
5. **Cluster temporal:** puede detenerse y eliminarse cuando no se necesite:

```powershell
pg_ctl -D C:\Users\sotof\AppData\Local\Temp\opencode\pg_u4_validate stop -m immediate
Remove-Item -LiteralPath C:\Users\sotof\AppData\Local\Temp\opencode\pg_u4_validate -Recurse -Force
```
