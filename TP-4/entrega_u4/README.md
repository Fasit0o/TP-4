# Entrega U4 - Normalización y Desnormalización (Food Store)

TP independiente de la Unidad 4 de Bases de Datos II. Motor: PostgreSQL 17 (compatible con PostgreSQL 18). Base de destino: `foodstore_dev` (sandbox aislada de las bases protegidas `foodstore` y `foodstore_tp3_prueba`).

---

## Estructura de la entrega

```
entrega_u4/
├── README.md
├── sql/
│   ├── 01_normalizacion_fnbc.sql      # Parte 1: FNBC, descomposición, migración, vista, reversión
│   ├── 02_desnormalizacion.sql        # Parte 2: MV Top 5, consultas, EXPLAIN ANALYZE, auditoría
│   └── 03_validaciones.sql            # Validaciones de solo lectura (ambas partes)
└── docs/
    ├── informe_tecnico.md             # Informe técnico completo
    ├── decisiones_de_diseno.md        # Decisiones de diseño y diferencias con la previa
    └── plan_reversion.md              # Plan de reversión de ambas partes
```

Los tres entregables exigidos por la cátedra son:
1. `sql/01_normalizacion_fnbc.sql` — normalización FNBC.
2. `sql/02_desnormalizacion.sql` — desnormalización del reporte Top 5.
3. `sql/03_validaciones.sql` — validación automática de ambos.

---

## Requisitos previos

1. PostgreSQL 17 (o 18) instalado y en ejecución.
2. Base de desarrollo `foodstore_dev` creada y cargada:

   ```powershell
   createdb -U postgres foodstore_dev
   psql -U postgres -d foodstore_dev -f sql/01_schema.sql
   psql -U postgres -d foodstore_dev -f sql/02_data.sql
   ```

3. Credenciales válidas para conectar como `postgres` (configurar `%APPDATA%\postgresql\pgpass.conf` o equivalentemente). **No incluir contraseñas en los scripts.**

> **Seguridad:** antes de ejecutar cualquier script, verificar que la base de destino sea una copia aislada (`foodstore_dev`). Queda prohibido ejecutar sobre `foodstore` ni `foodstore_tp3_prueba`.

---

## Orden de ejecución

```powershell
# 1. Parte 1 - Normalización FNBC (idempotente, reejecutable)
psql -U postgres -d foodstore_dev -f entrega_u4/sql/01_normalizacion_fnbc.sql

# 2. Parte 2 - Desnormalización Top 5 (requiere esquema principal cargado)
psql -U postgres -d foodstore_dev -f entrega_u4/sql/02_desnormalizacion.sql

# 3. Validaciones automáticas (solo lectura)
psql -U postgres -d foodstore_dev -f entrega_u4/sql/03_validaciones.sql
```

---

## Qué hace cada script

### `sql/01_normalizacion_fnbc.sql`
- Crea tablas maestras del alcance de almacén (`u4_deposito`, `u4_lote`, `u4_responsable`) con dominios condicionales.
- Crea y popula la relación original `u4_control_lote_almacen` (conservada como evidencia).
- Define DFs: `{L, D} → R` y `R → D`; demuestra que `R → D` viola FNBC.
- Descompone en `u4_resp_deposito` (R1) y `u4_control_asignacion` (R2) con PK, FK y restricciones.
- Crea la vista de compatibilidad `u4_vw_control_lote_almacen`.
- Migra datos de ejemplo de forma segura y verifica lossless-join con `EXCEPT` en ambas direcciones.
- Incluye plan de reversión documentado.

### `sql/02_desnormalizacion.sql`
- Consulta normalizada de línea base con `EXPLAIN (ANALYZE, BUFFERS)`.
- Crea la vista materializada `u4_mv_ventas_categoria_diaria` con índices.
- Consulta equivalente sobre la MV con nueva medición `EXPLAIN (ANALYZE, BUFFERS)`.
- Audita consistencia MV vs esquema normalizado en ambas direcciones.

### `sql/03_validaciones.sql`
- Solo lectura. Verifica existencia de objetos, unicidad de PK, cumplimiento de `R → D`, lossless-join, equivalencia de resultados normalizada vs desnormalizada y consistencia de la MV. Lanza `EXCEPTION` ante cualquier crítica fallida.

---

## Mediciones de rendimiento

Las secciones de `EXPLAIN ANALYZE` de `sql/02_desnormalizacion.sql` generan planes reales que **deben copiarse a `docs/informe_tecnico.md`** tras la ejecución. En esta entrega no se inventan tiempos ni costes; las tablas comparativas del informe quedan pendientes de los valores obtenidos en `foodstore_dev`.

---

## Reversión

Consultar `docs/plan_reversion.md`. La Parte 1 es reversible sin pérdida porque la tabla original se conserva. La Parte 2 se revierte eliminando la vista materializada; la consulta normalizada sigue disponible.

---

## Elementos que el estudiante debe comprender y defender oralmente

1. Las dependencias funcionales del caso (`{L, D} → R`, `R → D`) y por qué `R → D` viola FNBC.
2. Las clausuras de atributos y las dos claves candidatas `{L, D}` y `{L, R}`.
3. Atributos primos (`L`, `D` y `R`: todos son primos) y ausencia de atributos no primos.
4. Las anomalías de inserción, eliminación y actualización sobre la instancia de ejemplo.
5. El Teorema de Heath y por qué la descomposición en `u4_resp_deposito` y `u4_control_asignacion` está en FNBC y es sin pérdida.
6. Cómo reconstruye la vista de compatibilidad la relación original y qué significa que `EXCEPT` devuelva 0 filas en ambas direcciones.
7. Por qué la FK de `u4_control_asignacion` apunta a `u4_resp_deposito` y no directamente a `u4_responsable`.
8. La adaptación al esquema real: no existe tabla `usuario`; se usa `u4_responsable`.
9. El patrón de desnormalización elegido (vista materializada), sus índices y el mecanismo de refresco directo `REFRESH MATERIALIZED VIEW CONCURRENTLY`.
10. Que la desnormalización **no garantiza tiempo real** y que la latencia es el intervalo entre refrescos.
11. Cómo auditar la consistencia de la redundancia y qué hacer si hay diferencias.
12. Los pasos exactos de reversión de ambas partes y la prohibición de ejecutar sobre bases protegidas.
