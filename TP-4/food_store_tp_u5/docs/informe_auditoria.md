# Informe de Auditoría — Parte B  
## TP Unidad 5: Administración y Seguridad — Food Store

---

## 1. Parámetros de auditoría activados

Los siguientes parámetros fueron modificados en `postgresql.auto.conf` mediante `ALTER SYSTEM`
y aplicados sin reinicio con `SELECT pg_reload_conf()`.

| Parámetro | Valor anterior | Valor nuevo | Efecto |
|---|---|---|---|
| `log_connections` | `off` | `on` | Registra cada conexión entrante al servidor. |
| `log_disconnections` | `off` | `on` | Registra el cierre de sesión con duración total. |
| `log_statement` | `none` | `mod` | Registra todas las sentencias de modificación: `INSERT`, `UPDATE`, `DELETE`, `TRUNCATE` y DDL. Los `SELECT` no quedan registrados con esta configuración. |
| `log_line_prefix` | `%t` | `%t [%p] %u@%d %r` | Agrega al prefijo de cada línea: timestamp, PID del proceso, usuario, base de datos y host:puerto de origen. |

El parámetro `logging_collector` ya estaba en `on`, por lo que los logs se escriben a archivo en
`C:/Program Files/PostgreSQL/17/data/log/`.

### Justificación de `log_statement = 'mod'`

El nivel `mod` es el mínimo razonable para auditoría operativa: registra todo lo que cambia datos
sin el volumen de `all` (que incluye cada `SELECT`). Para un sistema transaccional como Food Store,
donde los `SELECT` son frecuentes y de bajo riesgo, `mod` ofrece el mejor balance entre visibilidad
y tamaño de log.

---

## 2. Secuencia de operaciones de prueba

Se ejecutaron cuatro tipos de operación para verificar el comportamiento del log:

1. **Lectura** (`SELECT`) — ejecutada como `postgres`; **no queda en el log** con `log_statement='mod'`.
2. **Inserción** (`INSERT`) — registrada.
3. **Actualización** (`UPDATE`) — registrada.
4. **Eliminación** (`DELETE`) — registrada (limpieza del dato de prueba).
5. **Login fallido** — intento de conexión como `app_web` con contraseña incorrecta.

El fragmento de log capturado se encuentra en `log_auditoria_prueba.txt`.

---

## 3. Análisis del fragmento de log

### Qué información aporta a los fines de auditoría

El nuevo `log_line_prefix` (`%t [%p] %u@%d %r`) permite responder las cuatro preguntas
fundamentales de auditoría en cada entrada:

| Pregunta | Campo en el log | Ejemplo del fragmento |
|---|---|---|
| **¿Cuándo?** | `%t` — timestamp con zona horaria | `2026-10-13 14:59:54 -03` |
| **¿Quién?** | `%u@%d` — usuario y base de datos | `postgres@foodstore_dev` |
| **¿Desde dónde?** | `%r` — host y puerto del cliente | `::1(55833)` |
| **¿Qué?** | Texto completo de la sentencia | `INSERT INTO cliente ...` |

El log también registra:
- Conexiones y desconexiones con duración de sesión (`log_connections/disconnections`).
- Errores de permiso junto a la sentencia que los causó (el intento de `app_web` sobre `cliente`).
- Intentos de autenticación fallidos con el método de autenticación y la línea de `pg_hba.conf` que coincidió.

### Qué queda fuera del alcance de este mecanismo nativo

El logging nativo de PostgreSQL con `log_statement = 'mod'` tiene limitaciones importantes:

- **Sin detalle a nivel de fila:** se registra la sentencia SQL completa, pero no qué filas
  específicas fueron afectadas ni cuáles eran sus valores antes y después del cambio. Para eso
  se necesita `pgaudit` (extensión) o triggers de auditoría propios.
- **Sin auditoría de `SELECT`:** con `mod`, las lecturas de datos sensibles (ej. consultar
  `contrasena_hash` o datos personales) no dejan rastro. Para auditarlas habría que usar `all`
  (muy costoso en volumen) o `pgaudit` con granularidad por objeto.
- **Sin registro de valores anteriores/nuevos:** un `UPDATE SET telefono = '...'` aparece en el
  log, pero no el valor que tenía antes. Los triggers de auditoría en tablas sensibles resuelven
  esto almacenando el before/after en una tabla de auditoría.
- **Log manipulable por el DBA:** quien tiene acceso al sistema operativo puede modificar o
  eliminar los archivos de log. `pgaudit` con destino a `syslog` o un SIEM externo mitiga esto.

---

## 4. El archivo de log como activo sensible

Sí, el archivo de log es en sí mismo un activo sensible. Contiene el texto completo de las
sentencias SQL ejecutadas —incluyendo potencialmente valores de datos personales, parámetros de
rutinas y patrones de acceso— lo que lo convierte en un vector de exposición si cae en manos
incorrectas.

Solo el usuario del sistema operativo que ejecuta el proceso PostgreSQL (típicamente `postgres`)
y los administradores del sistema deberían poder leerlo. En Linux, esto se traduce en permisos
`640` o `600` sobre los archivos de log, con propietario `postgres:postgres`. En Windows, el
directorio `data/log/` debería tener ACLs restringidas al usuario de servicio de PostgreSQL y
al grupo de administradores locales, excluyendo explícitamente a usuarios de aplicación.
A nivel del motor, ningún rol de base de datos —ni siquiera `admin_datos`— debería tener acceso
directo al sistema de archivos del servidor.
