# Instrucciones y Guía Técnica para Agentes de IA — Proyecto FoodStore

Este documento establece el marco operativo y las restricciones técnicas obligatorias para guiar a los agentes de asistencia en el desarrollo, prueba y validación de scripts sobre el proyecto de base de datos PostgreSQL. Su propósito es prevenir errores comunes de sintaxis, violaciones de integridad y problemas de concurrencia.

### 1. Entorno de Trabajo y Especificaciones del Stack

- **Base de datos de pruebas (Sandbox):** `foodstore_dev` (aislada de cualquier esquema de producción o plantilla original).
- **Comando de creación en terminal:** `createdb -U postgres foodstore_dev`
- **Aplicación de esquema:** `psql -U postgres -d foodstore_dev -f sql/01_schema.sql`
- **Carga de datos:** `psql -U postgres -d foodstore_dev -f sql/02_data.sql`
- **Unidad 4:** scripts en `unidad_4/`, en el orden indicado en `README.md`.
- **Naturaleza del repositorio:** Proyecto puramente de base de datos SQL. No cuenta con servidores de aplicación, ORMs ni frameworks de backend (como Node.js, Python o Django). Toda validación, prueba e inserción de datos se verifica mediante comandos y consultas directas en la terminal de `psql` o gestores compatibles (como DBeaver).

### 2. Protocolo de Seguridad Operativa e Ineludible

Antes de confirmar o ejecutar cualquier script de Definición de Datos (DDL) o Manipulación de Datos (DML) generado por herramientas de asistencia:

1. **Aislamiento absoluto:** Todo script debe ejecutarse exclusivamente en la base de datos de desarrollo `foodstore_dev`.
2. **Prueba transaccional preventiva:** Ninguna modificación o inserción se ejecuta directamente sin un contenedor transaccional de prueba. Se debe utilizar obligatoriamente el flujo de transacciones con `ROLLBACK` para inspeccionar errores de sintaxis y efectos colaterales antes de un `COMMIT`:

```PostgreSQL
BEGIN;
-- Bloque de código o inserción a probar
ROLLBACK;


```

### 3. Restricciones Críticas y Reglas del Esquema (`sql/01_schema.sql`)

Los agentes de IA suelen omitir o infringir estas reglas estructurales al proponer consultas o datos de prueba. Deben respetarse strictly:

* **Columnas Autoincrementales (`IDENTITY`):**
* Todas las claves primarias (`id_*`) se encuentran definidas mediante `GENERATED ALWAYS AS IDENTITY`.
* *Error frecuente a evitar:* Intentar insertar un valor explícito en una clave primaria (ej: `INSERT INTO cliente (id_cliente, ...) VALUES (1, ...)`) generará un error directo en PostgreSQL, a menos que se anteponga la cláusula `OVERRIDING SYSTEM VALUE`. Por defecto, se debe omitir la columna en el `INSERT` y dejar que el motor asigne el identificador automáticamente.
* **Integridad Referencial y Cascada (`ON DELETE RESTRICT`):**
* Todas las claves foráneas del esquema tienen configurada una política restrictiva de borrado (`ON DELETE RESTRICT`).
* *Error frecuente a evitar:* Intentar eliminar un registro padre (como una categoría, un cliente, un producto o un pedido principal) que posea registros hijos asociados fallará por violación de llave foránea. Es obligatorio limpiar o eliminar primero los registros dependientes.
* **Tipos de Datos Enumerados (`forma_pago_enum`):**
* El dominio de formas de pago acepta exclusivamente los valores literales: `'EFECTIVO'`, `'TARJETA'`, `'TRANSFERENCIA'`.
* *Error frecuente a evitar:* Los tipos `ENUM` en PostgreSQL son estrictamente sensibles a mayúsculas y minúsculas. Enviar variaciones como `'efectivo'` o `'Tarjeta'` provocará un rechazo inmediato por parte del motor.
* **Restricciones de Verificación lógicas (`CHECK`):**
* `chk_producto_stock`: El stock del producto debe ser mayor o igual a cero (`stock >= 0`).
* `chk_producto_precio`: El precio de lista debe ser mayor o igual a cero (`precio_lista >= 0`).
* `chk_detalle_cantidad`: La cantidad en el detalle del pedido es **estrictamente mayor a cero** (`cantidad > 0`). Ingresar un valor de `cantidad = 0` o negativo disparará un error de validación.
* `chk_detalle_precio`: El precio unitario histórico registrado en el detalle debe ser mayor o igual a cero.
* **Manejo de Fechas y Marcas de Tiempo (`TIMESTAMPTZ`):**
* Todas las columnas temporales emplean tipos con zona horaria (`TIMESTAMPTZ`). Se deben utilizar funciones compatibles como `now()` o literales de intervalo precisos al simular transacciones o cargas de pedidos.

### 4. Enfoque Avanzado en Concurrencia y Transaccionalidad

* **Objetivo de la materia:** El foco central del proyecto reside en la gestión analítica de la concurrencia, el análisis de anomalías y la correcta utilización de los niveles de aislamiento definidos por el estándar SQL (`Read Committed`, `Repeatable Read`, `Serializable`).
* **Mecanismos de bloqueo explícito:** Se debe dominar el uso de bloqueos a nivel de fila mediante cláusulas de control de concurrencia pesimista como `SELECT ... FOR UPDATE` y `SELECT ... FOR SHARE`.
* **Metodología de prueba en paralelo:** Para simular escenarios reales de condiciones de carrera (por ejemplo, reservas simultáneas de stock o modificaciones concurrentes de precios), se deben abrir y mantener activas múltiples sesiones de terminal independientes en `psql`, ejecutando los pasos de las transacciones de forma intercalada (Sesión A y Sesión B).

### 4.1 Unidad 4: Normalización y Desnormalización

* **Ubicación:** todos los entregables de la Unidad 4 viven en `unidad_4/`.
* **Orden de ejecución:** `unidad_4/tp_fnbc_control_lote.sql`, `data_u4_pruebas.sql`, `unidad_4/tp_desnormalizacion_top_categorias.sql` y `validar_u4.sql`.
* **Prohibido `DROP DOMAIN ... CASCADE`:** ese patrón elimina columnas dependientes (`lote.codigo_producto`, `responsable_control.dni`) y rompe la reejecución. Los dominios se crean condicionalmente con `to_regtype(...)`.
* **Tabla original:** `control_lote_almacen` se conserva como evidencia y oráculo de comparación. No eliminarla salvo indicación humana explícita.
* **Datos U4:** los registros FNBC van en `unidad_4/data_u4_pruebas.sql`, no en `sql/02_data.sql`. Los 3.000 pedidos del día permanecen en `sql/02_data.sql` porque sostienen los conteos de U6.
* **Conteos de referencia:** `pedido = 203.000`, `detalle_pedido = 306.700`.
* **Mediciones:** no inventar tiempos ni planes. Registrar solo salidas reales de `EXPLAIN (ANALYZE, BUFFERS)`; si no hay credenciales, dejar la sección como pendiente.
* **Dependencias:** no romper `food_store_tp_u5/sql/roles.sql` (grant sobre `mv_ventas_categoria_diario`) ni `food_store_tp_u6/scripts/health_check_pre.sql` (tablas FNBC).

### 5. Ámbito de Trabajo para la Unidad 5 (Administración y Seguridad)

* **Aislamiento de la entrega:** Todo nuevo desarrollo, especificación de Kiro, script DDL (roles, permisos, auditoría, anonimización) e informe debe crearse **exclusivamente dentro de la carpeta `food_store_tp_u5/**`.
* **Estructura obligatoria de la Unidad 5:**

```text
food_store_tp_u5/
├── sql/
│   ├── roles.sql
│   ├── auditoria_test.sql
│   ├── simulacro_incidente.sql
│   └── usuario_anon.sql
├── docs/
│   ├── kiro_roles_spec/
│   ├── informe_auditoria.md
│   ├── log_auditoria_prueba.txt
│   ├── log_simulacro_anonimizado.txt
│   ├── informe_incidente.md
│   └── verificacion_equivalencia.md
└── BITACORA.md


```

* **Inmutabilidad del histórico:** Bajo ninguna circunstancia los agentes modificarán los scripts consolidados (`sql/01_schema.sql`, `sql/02_data.sql`, `sql/06_consultas.sql`, `sql/03_views.sql`, etc.) salvo indicación humana explícita.
> **Excepción registrada — Unidad 5 (autorizada por el equipo):**
> * **Qué:** se agregó la columna `contrasena_hash TEXT NULL` a la tabla `cliente` en `sql/01_schema.sql`.
> * **Por qué:** las funciones `fn_autenticar` y `fn_resetear_password` definidas en la Unidad 5 dependen de esa columna para almacenar y comparar hashes bcrypt. Sin ella, el schema no es autosuficiente para recrear la BD desde cero y las funciones fallan con error interno.
> * **Cómo:** modificación directa del DDL de `cliente` en `sql/01_schema.sql`, con comentario explicativo en el propio archivo.
> * **Dónde queda registrado:** commit `0960d18` (`feat(schema): agrega contrasena_hash a tabla cliente`) y entrada en `food_store_tp_u5/BITACORA.md`.
> 
> 


* **Registro de asistencia IA:** Para esta unidad, la interacción con la IA se documentará **exclusivamente en `food_store_tp_u5/BITACORA.md**` respetando el formato de tabla de 3 columnas exigido por la cátedra.

### 6. Unidad 6: Mantenimiento y Automatización

* **Entorno de Ejecución:** Windows x86_64, PowerShell desde la CLI integrada de VS Code / Kiro.
* **Motor de BD:** PostgreSQL 17.11.
* **Bases de Datos:**
  * `foodstore`: Base de datos principal (producción).
  * `foodstore_restore_test`: Base de datos auxiliar / descartable para pruebas de restauración.
* **Identidad y Permisos:** Operaciones ejecutadas exclusivamente con el rol `admin_datos` (propietario de los objetos).
* **Uso de Herramientas de Mantenimiento:** Se descarta el uso de `pg_maintain`.
  > **Aclaración:** No se utiliza `pg_maintain` por no ser una herramienta nativa del core de PostgreSQL, por el riesgo de generar bloqueos exclusivos (`locks`) e impacto desmedido en I/O sobre la base principal, y para priorizar el mantenimiento nativo vía `Autovacuum` junto con scripts de PowerShell auditables y bajo control directo.
* **Manejo de Credenciales:** Prohibido incluir contraseñas en texto plano dentro de scripts (`.ps1`/`.sql`). Se utiliza autenticación automática mediante `%APPDATA%\postgresql\pgpass.conf`.
* **Seguridad Operativa:** Queda estrictamente prohibido ejecutar `DROP DATABASE foodstore` o cualquier script destructivo sobre la base principal.
* **Manejo de Errores y Logging:** Todo script de PowerShell debe auditar `$LASTEXITCODE` tras invocar binarios externos (`pg_dump.exe`, `pg_restore.exe`, `psql.exe`), abortar inmediatamente ante cualquier código distinto de 0 y registrar el resultado (OK/ERROR) en `food_store_tp_u6/logs/`.
* **Estructura Interna de la Carpeta `food_store_tp_u6/`:**

  ```text
  food_store_tp_u6/
  ├── BITACORA_U6.md             <-- Registro de decisiones, cambios y validaciones
  ├── scripts/                   <-- TODOS LOS SCRIPTS AUTOMATIZADOS
  │   ├── backup_foodstore.ps1    <-- Respaldo diario en PowerShell
  │   ├── restore_test.ps1       <-- Prueba semanal de restauración en PowerShell
  │   ├── health_check.sql       <-- Monitoreo diario de la base
  │   ├── health_check_pre.sql   <-- Chequeo inicial de integridad
  │   ├── maintenance.sql        <-- Revisión de autovacuum y ANALYZE condicional
  │   └── setup_ownership.sql    <-- Transferencia de propiedad de objetos
  ├── backups/                   <-- Respaldo custom y checksum SHA-256
  │   ├── foodstore_dev_<fecha_hora>.dump
  │   └── foodstore_dev_<fecha_hora>.dump.sha256
  ├── docs/                      <-- Especificaciones
  │   └── kiro_maintain_specs/
  │       └── SPEC_U6.md
  └── logs/                      <-- Logs de ejecuciones y evidencias
      ├── .gitkeep
      ├── log_backup_foodstore_dev_<fecha_hora>.txt
      ├── log_health_check.txt
      ├── log_health_check_pre.txt
      ├── log_maintenance.txt
      ├── log_restore_test_<fecha_hora>.txt
      └── log_setup_ownership.txt
  ```