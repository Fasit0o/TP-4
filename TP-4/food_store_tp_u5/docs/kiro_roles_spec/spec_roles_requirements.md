# Requirements Specification: Sistema de Roles y Permisos — Food Store (Unidad 5)

## 1. Objetivo General

Diseñar e implementar el modelo de identidades y permisos para la base de datos `foodstore_dev`
aplicando estrictamente el **principio de mínimo privilegio**: cada sujeto interactúa con el motor
SQL a través del nivel de acceso estrictamente necesario para su función operativa, sin
solapamiento ni escalada lateral de privilegios.

---

## 2. Requerimientos de Roles y Justificación Funcional

### 2.1. Roles de Grupo (`NOLOGIN`)

Los roles de grupo **no se autentican directamente**: concentran únicamente los privilegios sobre
objetos de base de datos y los delegan a los roles de login mediante membresía (`GRANT <grupo> TO
<login>`). Esto garantiza que un cambio de permisos sobre un grupo se propague de forma inmediata
a todos los logins miembros, sin necesidad de reescribir los `GRANT` individuales.

| ID | Rol | Operaciones habilitadas | Por qué esa operación y no otra |
|---|---|---|---|
| REQ-R1 | `rol_app_lectura` | `SELECT` sobre `vw_productos_vigentes` y `categoria` | El catálogo público solo necesita ser leído; cualquier permiso de escritura abriría superficie de ataque innecesaria. |
| REQ-R2 | `rol_app_escritura` | `SELECT`, `INSERT`, `UPDATE` sobre `pedido` y `detalle_pedido`; `EXECUTE` sobre `sp_crear_pedido` | La app crea y actualiza pedidos mediante la rutina empaquetada; `DELETE` y `TRUNCATE` son deliberadamente omitidos porque la baja es lógica (campo `activo`). |
| REQ-R3 | `rol_soporte` | `SELECT` (columnas no sensibles) sobre `cliente`; `SELECT` sobre `vw_pedidos_cliente_segura`; `EXECUTE` sobre `fn_resetear_password` y `fn_autenticar` | El equipo de soporte atiende reclamos y puede resetear claves, pero no puede ver columnas de contacto adicional (`direccion`, `telefono`) ni manipular transacciones. |
| REQ-R4 | `rol_reportes` | `SELECT` sobre `mv_facturacion_categoria_mes` | Los analistas consumen exclusivamente el agregado ya calculado; el acceso directo a las tablas base introduciría cargas innecesarias y exposición de datos crudos. |

### 2.2. Roles de Login (`WITH LOGIN`)

| ID | Rol | Operaciones habilitadas | Por qué esa operación y no otra |
|---|---|---|---|
| REQ-R5 | `app_web` | Hereda `rol_app_lectura` + `rol_app_escritura`; `EXECUTE` sobre `fn_autenticar` | El backend de la aplicación necesita servir el catálogo, registrar pedidos y validar credenciales; no requiere permisos administrativos. |
| REQ-R6 | `admin_datos` | `CREATEDB`, `CREATEROLE`, propietario del esquema `public` | El DBA administra la estructura sin necesitar `SUPERUSER`, reduciendo el radio de explosión ante una credencial comprometida. |

---

## 3. Requerimientos de Seguridad Transversales

### REQ-SEC1 — Minimización de Datos (Permiso por Columna)

El rol `rol_soporte` **no** recibe un `GRANT SELECT` global sobre la tabla `cliente`. Se otorgan
permisos únicamente sobre las columnas operativamente necesarias:

```sql
GRANT SELECT (id_cliente, nombre, email) ON cliente TO rol_soporte;
```

Las columnas `telefono` y `direccion` quedan excluidas, en concordancia con los principios de
protección de datos personales (Ley 25.326 / RGPD).

> **Nota de implementación:** La tabla `cliente` es la entidad de identidad del esquema real de
> `foodstore_dev`. No existe tabla `usuario` en `sql/01_schema.sql`; las referencias a esa tabla en
> scripts de otras unidades son conceptuales o de ejercicio y no aplican aquí.

### REQ-SEC2 — Herencia de Permisos por Defecto (`ALTER DEFAULT PRIVILEGES`)

Para que los objetos creados a futuro por `admin_datos` o `postgres` en `public` **no** hereden
permisos automáticamente, se aplica una revocación preventiva:

```sql
ALTER DEFAULT PRIVILEGES FOR ROLE admin_datos IN SCHEMA public
  REVOKE ALL ON TABLES FROM rol_app_lectura, rol_app_escritura, rol_soporte, rol_reportes;
ALTER DEFAULT PRIVILEGES FOR ROLE admin_datos
  REVOKE EXECUTE ON ROUTINES FROM PUBLIC;
```

Esto rompe el comportamiento por defecto de PostgreSQL (que otorga `EXECUTE` a `PUBLIC` en cada
nueva función) y fuerza a que cada nuevo objeto reciba sus permisos de forma explícita y
deliberada.

### REQ-SEC3 — Idempotencia y Despliegue Seguro

El deploy se realiza en dos pasos, en este orden:

1. `sql/05_procedimientos.sql` — crea `sp_crear_pedido(BIGINT, forma_pago_enum, JSONB)`. Debe existir antes de que `roles.sql` intente otorgarle permisos.
2. `roles.sql` — reejecutable en una única transacción `BEGIN … COMMIT`. Limpia permisos previos, crea roles solo si no existen y corrige atributos si ya existían.

`roles.sql` localiza `sp_crear_pedido` por nombre en `pg_proc` (búsqueda dinámica) para no depender de la firma exacta. Si el procedimiento no existe emite `WARNING` y continúa sin bloquear el resto del deploy.

### REQ-SEC4 — Seguridad en Funciones con Elevado Privilegio (`SECURITY DEFINER`)

Las funciones `fn_autenticar` y `fn_resetear_password` operan con los privilegios del dueño de la
función (el rol que las creó), no del invocador. Para evitar la escalada de privilegios mediante
manipulación del `search_path`, ambas funciones deben declarar:

```sql
SECURITY DEFINER
SET search_path = public, pg_temp
```

Y deben revocar su ejecución a `PUBLIC` de forma explícita:

```sql
REVOKE ALL ON FUNCTION fn_… FROM PUBLIC;
```

La ejecución de `fn_autenticar` se delega a `app_web`; la de `fn_resetear_password`, a
`rol_soporte`.

---

## 4. Restricciones de Inmutabilidad

- Ningún agente ni script de esta unidad puede modificar los archivos de la raíz del proyecto
  (`sql/01_schema.sql`, `sql/02_data.sql`, `sql/06_consultas.sql`, `sql/03_views.sql`, etc.).
- Todo el desarrollo de la Unidad 5 reside exclusivamente en `food_store_tp_u5/`.
