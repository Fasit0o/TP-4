# FoodStore - Sistema de Gestion y Base de Datos (TP Integrador)

**Estudiante:** Agustina Micaela Guzman  
**Asignatura:** Bases de Datos II  
**Motor de BD:** PostgreSQL 17  
**Base de datos de desarrollo (Sandbox):** `foodstore_dev`

---

## 1. Descripcion del proyecto

Este repositorio contiene el trabajo practico integrador sobre la base de datos de FoodStore. Incluye:

- esquema relacional, tipos, restricciones y datos sinteticos;
- analisis de planes de ejecucion con `EXPLAIN ANALYZE`, indices y su costo de escritura;
- vistas de reporte y una vista segura que oculta datos personales;
- vistas materializadas y estrategias de refresco;
- triggers de integridad;
- pruebas de concurrencia y aislamiento transaccional (MVCC);
- correccion de una violacion de FNBC y una desnormalizacion controlada (Unidad 4);
- administracion de roles, auditoria y anonimizacion (Unidad 5);
- respaldos, restauracion, monitoreo y mantenimiento automatizado (Unidad 6).

El uso de IA se documenta en `docs/DUIA.md`. Las especificaciones tecnicas estan en `docs/specs/`.

---

## 2. Estructura del repositorio

```text
TPI_BD-main/
├── AGENTS.md
├── README.md
├── sql/
│   ├── 01_schema.sql
│   ├── 02_data.sql
│   ├── 03_views.sql
│   ├── 04_restricciones_integridad.sql
│   ├── 05_procedimientos.sql
│   ├── 06_consultas.sql
│   └── 07_indices.sql
├── unidad_4/
│   ├── unidad_4/tp_fnbc_control_lote.sql
│   ├── unidad_4/tp_desnormalizacion_top_categorias.sql
│   ├── data_u4_pruebas.sql
│   ├── validar_u4.sql
│   └── INFORME_TECNICO_U4.md
├── docs/
│   ├── DUIA.md
│   ├── protocolo_seguridad.md
│   ├── informes/
│   │   ├── informe_mediciones.md
│   │   ├── informe_concurrencia.md
│   │   ├── bitacora_competencia.md
│   │   ├── ejercicio_lectura_critica.md
│   │   └── informe_reorganizacion.md
│   └── docs/specs/
│       ├── base/
│       │   ├── spec_clientes_like_*.md
│       │   ├── spec_pedidos_*.md
│       │   ├── spec_productos_*.md
│       │   └── spec_vistas_reportes_*.md
│       └── unidad4/
│           ├── tp_fnbc_control_lote.md
│           └── archive/
│               ├── spec_fnbc_control_lote_requirements.md
│               ├── spec_fnbc_control_lote_design.md
│               └── spec_fnbc_control_lote_tasks.md
├── food_store_tp_u5/
│   ├── BITACORA.md
│   ├── sql/
│   │   ├── roles.sql
│   │   ├── auditoria_test.sql
│   │   ├── simulacro_incidente.sql
│   │   └── usuario_anon.sql
│   └── docs/
│       ├── kiro_roles_spec/
│       ├── informe_auditoria.md
│       ├── log_auditoria_prueba.txt
│       ├── log_simulacro_anonimizado.txt
│       ├── informe_incidente.md
│       └── verificacion_equivalencia.md
└── food_store_tp_u6/
    ├── BITACORA_U6.md
    ├── scripts/
    │   ├── backup_foodstore.ps1
    │   ├── restore_test.ps1
    │   ├── health_check.sql
    │   ├── health_check_pre.sql
    │   ├── maintenance.sql
    │   └── setup_ownership.sql
    ├── backups/
    ├── docs/kiro_maintain_specs/SPEC_U6.md
    └── logs/
```

### 2.1 Scripts SQL base (`sql/`)

| Archivo | Contenido |
|---|---|
| `01_schema.sql` | Tablas, tipos `ENUM`, claves `IDENTITY`, restricciones `CHECK` y `ON DELETE RESTRICT`. |
| `02_data.sql` | Carga sintetica con semilla fija: 9 categorias, 50.000 productos, 20.000 clientes, 200.000 pedidos y 300.000 detalles, mas 3.000 pedidos del dia y 6.700 detalles adicionales. |
| `03_views.sql` | Vistas de reporte, vista segura, verificaciones `EXCEPT` y `mv_facturacion_categoria_mes`. |
| `04_restricciones_integridad.sql` | Triggers de validacion de fechas y productos inactivos. |
| `05_procedimientos.sql` | Procedimientos y funciones PL/pgSQL del proyecto. |
| `06_consultas.sql` | Catalogo de consultas, rankings, `EXPLAIN ANALYZE` y competencia de optimizacion. |
| `07_indices.sql` | Guion de experimentos de indexacion para ejecutar bloque por bloque. |

### 2.2 Unidad 4 (`unidad_4/`)

| Archivo | Contenido |
|---|---|
| `unidad_4/tp_fnbc_control_lote.sql` | Correccion FNBC, descomposicion, migracion, vista de compatibilidad y verificacion lossless-join. |
| `unidad_4/tp_desnormalizacion_top_categorias.sql` | Vista materializada `mv_ventas_categoria_diario`, indices, refresco y auditoria. |
| `data_u4_pruebas.sql` | Datos adicionales para las tablas FNBC y la vista materializada. |
| `validar_u4.sql` | Validacion automatica de objetos, claves, dependencias, equivalencia y consistencia de la MV. |
| `INFORME_TECNICO_U4.md` | Informe con teoria, decisiones, pruebas, reversion y limitaciones. |

### 2.3 Documentacion (`docs/`)

- `DUIA.md`: declaracion de uso de IA, prompts, sugerencias aceptadas y descartes.
- `protocolo_seguridad.md`: transacciones, respaldos y reglas de aislamiento.
- `informes/informe_mediciones.md`: planes, tiempos e impacto de indices.
- `informes/informe_concurrencia.md`: anomalias transaccionales y pruebas en paralelo.
- `informes/bitacora_competencia.md`: comparativa de estrategias de optimizacion.
- `informes/ejercicio_lectura_critica.md`: evaluacion de errores y alucinaciones de IA.
- `informes/informe_reorganizacion.md`: cambios de estructura, correcciones U4 y validaciones ejecutadas.
- `docs/specs/base/`: especificaciones de clientes, pedidos, productos y vistas.
- `docs/specs/unidad4/`: especificacion consolidada y documentos Kiro de FNBC.

### 2.4 Unidad 5 (`food_store_tp_u5/`)

Administracion y seguridad: roles, permisos, auditoria, anonimizacion y simulacro de incidente. La estructura se mantiene aislada segun la consigna.

### 2.5 Unidad 6 (`food_store_tp_u6/`)

Mantenimiento y automatizacion en PowerShell: respaldo, restauracion de prueba, `health_check`, `ANALYZE` condicional y transferencia de propiedad.

---

## 3. Guia de reproduccion

### Paso 1: Crear la base de desarrollo

```powershell
createdb -U postgres foodstore_dev
```

### Paso 2: Cargar esquema y datos

```powershell
psql -U postgres -d foodstore_dev -f sql/01_schema.sql
psql -U postgres -d foodstore_dev -f sql/02_data.sql
```

`sql/02_data.sql` usa `SELECT setseed(0.5);` al inicio. En una base limpia, las columnas numericas e inmutables son deterministas. Las columnas `fecha_hora` y `email` pueden variar porque derivan de `now()`.

### Paso 3: Verificar la carga

```powershell
psql -U postgres -d foodstore_dev -c "SELECT 'categoria' AS tabla, COUNT(*) FROM categoria UNION ALL SELECT 'producto', COUNT(*) FROM producto UNION ALL SELECT 'cliente', COUNT(*) FROM cliente UNION ALL SELECT 'pedido', COUNT(*) FROM pedido UNION ALL SELECT 'detalle_pedido', COUNT(*) FROM detalle_pedido;"
```

Valores esperados con una ejecucion completa de `sql/02_data.sql`:

| Tabla | Filas |
|---|---:|
| `categoria` | 9 |
| `producto` | 50.000 |
| `cliente` | 20.000 |
| `pedido` | 203.000 |
| `detalle_pedido` | 306.700 |

> Los conteos de `pedido` y `detalle_pedido` incluyen los 3.000 pedidos del dia y sus 6.700 detalles. Son los valores que valida `food_store_tp_u6/scripts/restore_test.ps1`.

### Paso 4: Medir antes de indexar

```powershell
psql -U postgres -d foodstore_dev -f sql/06_consultas.sql -o salida_queries.txt
```

Los planes de referencia se registran antes de `sql/07_indices.sql`. Los experimentos de indices se ejecutan bloque por bloque, no con `-f`.

### Paso 5: Indices

Abrir una sesion interactiva:

```powershell
psql -U postgres -d foodstore_dev
```

Seguir los bloques de `sql/07_indices.sql`: `BEGIN`, `ANALYZE`, `EXPLAIN (ANALYZE, BUFFERS)`, crear indice, repetir el plan y `ROLLBACK` o `COMMIT` segun corresponda.

### Paso 6: Vistas y vista materializada

```powershell
psql -U postgres -d foodstore_dev -f sql/03_views.sql
```

Verificar que las comparaciones `EXCEPT` devuelvan `(0 rows)` y que `rol_reportes` solo acceda a la vista segura:

```sql
SET ROLE rol_reportes;
SELECT * FROM vw_pedidos_cliente_segura LIMIT 1;
SELECT * FROM cliente LIMIT 1;  -- debe fallar por permisos
RESET ROLE;
```

Refrescar la MV:

```sql
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_facturacion_categoria_mes;
```

### Paso 7: Restricciones de integridad

```powershell
psql -U postgres -d foodstore_dev -f sql/04_restricciones_integridad.sql
```

Las pruebas al final del script provocan errores a proposito dentro de `BEGIN ... ROLLBACK`.

### Paso 8: Unidad 4

Orden obligatorio:

```powershell
psql -U postgres -d foodstore_dev -f unidad_4/tp_fnbc_control_lote.sql
psql -U postgres -d foodstore_dev -f unidad_4/data_u4_pruebas.sql
psql -U postgres -d foodstore_dev -f unidad_4/tp_desnormalizacion_top_categorias.sql
psql -U postgres -d foodstore_dev -f unidad_4/validar_u4.sql
```

`unidad_4/tp_fnbc_control_lote.sql` es idempotente: crea dominios solo si no existen, no usa `DROP DOMAIN ... CASCADE` y conserva la tabla original como evidencia.

La validacion debe terminar con:

- `original = vista` en `control_lote_almacen`;
- 0 filas en ambas direcciones de `EXCEPT`;
- 0 responsables con mas de un deposito;
- 0 diferencias entre la MV y el esquema normalizado.

Si se reejecuta `unidad_4/tp_desnormalizacion_top_categorias.sql` despues de `food_store_tp_u5/sql/roles.sql`, volver a aplicar el `GRANT SELECT` de la Unidad 5 sobre la MV.

### Paso 9: Unidad 5

```powershell
psql -U postgres -d foodstore_dev -f food_store_tp_u5/sql/roles.sql
```

Revisar `food_store_tp_u5/BITACORA.md` para el orden de auditoria, anonimizacion y simulacro.

### Paso 10: Unidad 6

Los scripts de PowerShell requieren `pg_dump`, `pg_restore` y `psql` en el `PATH` o configurados en el script, ademas de `%APPDATA%\postgresql\pgpass.conf`.

```powershell
powershell -ExecutionPolicy Bypass -File food_store_tp_u6/scripts/backup_foodstore.ps1
powershell -ExecutionPolicy Bypass -File food_store_tp_u6/scripts/restore_test.ps1
```

Todo script de U6 debe auditar `$LASTEXITCODE`, abortar ante error y registrar el resultado en `food_store_tp_u6/logs/`.

### Paso 11: Concurrencia

`docs/informes/informe_concurrencia.md` describe las pruebas de `Non-Repeatable Read`, `Lock Wait` y `Phantom Read`. Para reproducirlas, abrir dos sesiones `psql` sobre `foodstore_dev` y ejecutar los pasos de forma intercalada.

---

## 4. Protocolo de seguridad operativa

Toda modificacion manual o experimental debe ejecutarse dentro de una transaccion:

```sql
BEGIN;
-- DDL o DML de prueba
ROLLBACK;
```

Reglas adicionales:

- trabajar solo sobre `foodstore_dev`;
- no ejecutar `DROP DATABASE` sobre bases protegidas;
- no incluir contrasenas en scripts;
- conservar la tabla original de la Unidad 4 para permitir reversion y auditoria;
- no inventar mediciones: registrar solo salidas reales de `EXPLAIN (ANALYZE, BUFFERS)`.

---

## 5. Estado de validacion

La reorganizacion fue validada el 2026-11-09 sobre un cluster PostgreSQL 17 temporal local, con autenticacion `trust` y puerto alternativo, sin tocar `foodstore` ni `foodstore_tp3_prueba`. Se ejecutaron en orden `sql/01_schema.sql`, `sql/02_data.sql`, los tres scripts de `unidad_4/` y `unidad_4/validar_u4.sql`; todas las validaciones pasaron. Los detalles y las mediciones reales estan en `docs/informes/informe_reorganizacion.md` y `unidad_4/INFORME_TECNICO_U4.md`.

La instancia original sigue solicitando contrasena para `postgres` y `admin_datos`; si se necesita evidencia directa sobre esa instancia, repetir la secuencia con credenciales validas.
