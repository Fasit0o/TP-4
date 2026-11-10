# Design Specification: Arquitectura de Identidades, Permisos y Funciones de Seguridad

---

## 1. Arquitectura de Identidades — Separación Grupo / Login

PostgreSQL permite que un mismo "rol" actúe como grupo (sin credenciales) o como cuenta de
acceso. El diseño explota esta dualidad para centralizar los privilegios en los **roles de grupo**
y aislar las credenciales en los **roles de login**.

```
┌─────────────────────────────────────────────────────────────────┐
│  ROLES DE GRUPO (NOLOGIN)         ROLES DE LOGIN (WITH LOGIN)   │
│  ─────────────────────────        ──────────────────────────    │
│  rol_app_lectura   ──────────────►  app_web                     │
│  rol_app_escritura ──────────────►  app_web                     │
│  rol_soporte       (sin login)                                  │
│  rol_reportes      (sin login)                                  │
│                                   admin_datos  (DBA, LOGIN)     │
└─────────────────────────────────────────────────────────────────┘
```

**Ventaja del modelo:** revocar un permiso del grupo lo retira instantáneamente de todos los
logins que lo heredan, sin necesidad de modificar cada cuenta individualmente.

---

## 2. Mapeo Objeto → Rol → Privilegio

### 2.1. `rol_app_lectura` — Catálogo público (solo lectura)

| Objeto | Tipo | Privilegio | Justificación |
|---|---|---|---|
| `SCHEMA public` | Esquema | `USAGE` | Permite resolver los nombres de objeto. |
| `vw_productos_vigentes` | Vista | `SELECT` | Sirve el catálogo de productos activos. |
| `categoria` | Tabla | `SELECT` | Permite filtrar/navegar por categoría desde la app. |

> Objetos **no otorgados a este rol de forma intencional:** `pedido`, `cliente`, `detalle_pedido`,
> vistas de soporte/reportes, rutinas transaccionales.

---

### 2.2. `rol_app_escritura` — Operación transaccional

| Objeto | Tipo | Privilegio | Justificación |
|---|---|---|---|
| `SCHEMA public` | Esquema | `USAGE` | Idem anterior. |
| `pedido` | Tabla | `SELECT`, `INSERT`, `UPDATE` | Registra y consulta pedidos. `DELETE` omitido: baja lógica. |
| `detalle_pedido` | Tabla | `SELECT`, `INSERT`, `UPDATE` | Registra ítems del pedido. Misma política de baja lógica. |
| `sp_crear_pedido(BIGINT, forma_pago_enum, JSONB)` | Procedimiento | `EXECUTE` | Lógica de negocio empaquetada: valida stock, inserta pedido+detalles y descuenta stock en una sola transacción atómica con bloqueo `FOR UPDATE`. Definido en `sql/05_procedimientos.sql`. |

> **Firma:** `p_id_cliente BIGINT`, `p_forma_pago forma_pago_enum`, `p_items JSONB` — array de objetos `[{"id_producto": N, "cantidad": N}]`.  
> `roles.sql` localiza el procedimiento por nombre en `pg_proc` para no depender de la firma exacta al momento del `GRANT`.

---

### 2.3. `rol_soporte` — Atención al cliente, con minimización de datos

| Objeto | Tipo | Privilegio | Columnas permitidas | Columnas excluidas |
|---|---|---|---|---|
| `SCHEMA public` | Esquema | `USAGE` | — | — |
| `cliente` | Tabla | `SELECT` (por columna) | `id_cliente`, `nombre`, `email` | `telefono`, `direccion` |
| `vw_pedidos_cliente_segura` | Vista | `SELECT` | Todas las proyectadas | — |
| `fn_resetear_password(BIGINT, TEXT)` | Función `SECURITY DEFINER` | `EXECUTE` | — | — |
| `fn_autenticar(TEXT, TEXT)` | Función `SECURITY DEFINER` | `EXECUTE` | — | — |

> **Decisión de diseño sobre columnas:** `telefono` podría exponerse en un contexto de atención
> al cliente, pero se excluye aquí para cumplir con el mínimo privilegio del REQ-SEC1. Si se
> requiere, debe ser un `GRANT` explícito y documentado por separado.

---

### 2.4. `rol_reportes` — Analítica consolidada (solo vistas materializadas)

| Objeto | Tipo | Privilegio | Justificación |
|---|---|---|---|
| `SCHEMA public` | Esquema | `USAGE` | Idem anterior. |
| `mv_facturacion_categoria_mes` | Vista Materializada | `SELECT` | Facturación agregada por categoría y mes. Pre-calculada; sin costo de JOIN en tiempo real. |
| `mv_ventas_categoria_diario` | Vista Materializada | `SELECT` | Ventas por categoría y fecha. Definida en `unidad_4/tp_desnormalizacion_top_categorias.sql`. |

---

### 2.5. `app_web` — Login del backend de la aplicación

| Atributo / Membresía | Detalle |
|---|---|
| Tipo | `WITH LOGIN` |
| Credencial | `'app_web_pass_dev'` (valor de sandbox; en producción se reemplaza por una credencial segura) |
| Membresías heredadas | `rol_app_lectura`, `rol_app_escritura` |
| Privilegio directo adicional | `EXECUTE` sobre `fn_autenticar(TEXT, TEXT)` |

---

### 2.6. `admin_datos` — DBA sin `SUPERUSER`

| Atributo | Valor | Justificación |
|---|---|---|
| Tipo | `WITH LOGIN` | Necesita autenticarse para operar. |
| `CREATEDB` | SI | Puede crear nuevas bases de desarrollo. |
| `CREATEROLE` | SI | Administra los roles de la instalación. |
| `SUPERUSER` | NO | Excluido explícitamente: reduce el impacto ante credencial comprometida. |
| Propietario de `SCHEMA public` | SI | Permite administrar objetos del esquema sin ser `postgres`. |

---

## 3. Funciones de Seguridad (`SECURITY DEFINER`)

Ambas funciones se ejecutan con los privilegios del dueño (el rol que las creó), independientemente
de quién las invoque. Esto permite que `rol_soporte` o `app_web` puedan resetear/validar
credenciales sin acceder directamente a la columna `contrasena`.

### 3.1. `fn_autenticar(p_mail TEXT, p_pass TEXT) → BIGINT`

- **Propósito:** Valida credenciales de un cliente y retorna su `id_cliente`, o `NULL` si la
  autenticación falla.
- **Hash:** `pgcrypto.crypt()` con sal `bcrypt` (`gen_salt('bf')`).
- **Mitigación de timing attacks:** Si el mail no existe, se ejecuta de todas formas un
  `crypt()` con sal generada para que el tiempo de respuesta sea indistinguible al del caso
  exitoso.
- **Revocación:** `REVOKE ALL … FROM PUBLIC`; `GRANT EXECUTE … TO app_web`.

### 3.2. `fn_resetear_password(p_cliente_id BIGINT, p_nueva TEXT) → VOID`

- **Propósito:** Actualiza el hash de contraseña de un cliente activo.
- **Hash:** `pgcrypto.crypt(p_nueva, gen_salt('bf'))`.
- **Revocación:** `REVOKE ALL … FROM PUBLIC`; `GRANT EXECUTE … TO rol_soporte`.

---

## 4. Política de Idempotencia

El deploy completo requiere dos scripts ejecutados en orden:

```
1. sql/05_procedimientos.sql  → crea sp_crear_pedido (debe existir antes del GRANT)
2. roles.sql           → todo lo demás, en una única transacción BEGIN…COMMIT
```

El flujo interno de `roles.sql` es:

```
1. Revoca todos los permisos de los roles de aplicación (objetos existentes + default privileges)
2. Elimina membresías previas de los grupos
3. Crea los roles si no existen; corrige atributos (NOLOGIN/LOGIN) si ya existían
4. Crea o reemplaza las funciones SECURITY DEFINER
5. Revoca PUBLIC de las funciones y del esquema
6. Otorga los permisos finales de forma explícita
7. Otorga EXECUTE a rol_app_escritura sobre sp_crear_pedido (búsqueda dinámica en pg_proc)
8. Otorga membresías
9. Configura DEFAULT PRIVILEGES para objetos futuros
10. COMMIT
11. Bloque de verificación (fuera de la transacción): \du, \ddp, consultas a information_schema
```

---

## 5. Dependencia del Esquema Real

Este diseño está alineado con `sql/01_schema.sql` del proyecto. Las tablas y vistas que existen son:

| Objeto | Tipo | Existe en sql/01_schema.sql / sql/03_views.sql |
|---|---|---|
| `categoria` | Tabla | existe |
| `producto` | Tabla | existe |
| `cliente` | Tabla | existe (entidad de identidad del cliente) |
| `pedido` | Tabla | existe |
| `detalle_pedido` | Tabla | existe |
| `vw_productos_vigentes` | Vista | existe |
| `vw_pedidos_cliente_segura` | Vista | existe |
| `mv_facturacion_categoria_mes` | Vista Materializada | existe |
| `sp_crear_pedido(BIGINT, forma_pago_enum, JSONB)` | Procedimiento | existe — definido en `sql/05_procedimientos.sql` |
| `usuario` | Tabla | no existe en `sql/01_schema.sql` |
| `mv_ventas_categoria_diario` | Vista Materializada | existe — definida en `unidad_4/tp_desnormalizacion_top_categorias.sql` |

> Cualquier referencia a `usuario` en los scripts de la Unidad 5 es incorrecta para este
> esquema y debe reemplazarse por `cliente`.
