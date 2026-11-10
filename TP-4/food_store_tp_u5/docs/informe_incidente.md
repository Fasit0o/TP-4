# Informe de Incidente — Parte C  
## TP Unidad 5: Simulacro de Ataque y Reconstrucción con IA

---

## 1. Secuencia ejecutada (lo que realmente ocurrió)

El script `simulacro_incidente.sql` ejecutó la siguiente secuencia controlada
contra `foodstore_dev`:

| Paso | Operación | Resultado esperado | Resultado real |
|---|---|---|---|
| Setup | INSERT cliente víctima + fn_resetear_password | Cliente creado con hash bcrypt | OK (tras agregar columna `contrasena_hash`) |
| Fase 1 | 3 llamadas a fn_autenticar con contraseña incorrecta | Retorna NULL (fallo silencioso) | NULL en los 3 intentos |
| Fase 2 | fn_autenticar con contraseña correcta | Retorna id_cliente | Retorno id_cliente = 20004 |
| Fase 3 | SELECT masivo sobre tabla cliente (10 filas) | Datos leídos, sin registro en log | Datos leídos; NO queda en log con `mod` |
| Fase 4 | SET ROLE app_web + GRANT admin_datos TO rol_soporte | Debe fallar con permiso denegado | ERROR: permiso denegado |
| Limpieza | DELETE cliente víctima | Dato eliminado | DELETE 1 |

**Nota sobre el incidente previo al simulacro final:** En la primera ejecución del script,
`GRANT admin_datos TO rol_soporte` se ejecutó sin `SET ROLE app_web` — como `postgres`
(superusuario), el GRANT fue exitoso. Se revirtió inmediatamente con `REVOKE` y se corrigió
el script. Este evento quedó registrado en el log y se documenta como hallazgo: el
superusuario puede escalar cualquier rol; esto es comportamiento esperado de PostgreSQL
y no un defecto del esquema de permisos.

---

## 2. Verificación del escalamiento (punto 2 de la consigna)

El intento de escalamiento en la ejecución final **falló correctamente**:

```
ERROR: se ha denegado el permiso para otorgar el rol «admin_datos»
DETALLE: Solo los roles con la opcion ADMIN en el rol «admin_datos»
         pueden otorgar este rol.
```

El esquema de permisos de la Parte A no tiene defectos en este aspecto.
`app_web` no tiene `CREATEROLE` ni la opcion `ADMIN` sobre `admin_datos`,
por lo que no puede propagar ese rol a ningún otro.

---

## 3. Reconstrucción solicitada a la IA

Se entregó el fragmento `log_simulacro_anonimizado.txt` a Kiro sin contexto adicional,
con la instrucción: *"Analiza este log y reconstruí qué ocurrió. Propone una hipótesis
de contención."*

### Respuesta de la IA (Kiro):

> "El log muestra una sesión de `postgres` sobre `foodstore_dev` que realiza las
> siguientes acciones en secuencia:
>
> 1. Crea un registro de cliente (`INSERT`) e intenta establecer una contraseña
>    mediante `fn_resetear_password`. La función falla repetidamente con un error
>    interno (`no existe la columna c.contrasena_hash`), lo que indica que la función
>    está desactualizada o la tabla no tiene la columna esperada.
>
> 2. A continuación se realizan cuatro llamadas a `fn_autenticar` sobre el mismo mail
>    (`victima01@anon.local`). Las primeras tres fallan con el mismo error interno.
>    La cuarta también falla con el mismo error — el log no muestra un inicio de
>    sesión exitoso: todas las llamadas terminan en ERROR.
>
> 3. No hay evidencia en el log de una lectura masiva de datos (SELECT). Si ocurrió,
>    el nivel de auditoría (`log_statement='mod'`) no la capturó.
>
> 4. Se ejecuta `GRANT admin_datos TO rol_soporte`, que falla con permiso denegado.
>    Esto sugiere que el atacante (o el script) intento elevar privilegios de un rol
>    de bajo acceso al rol DBA.
>
> Hipótesis: El incidente parece ser un intento de reconocimiento y escalamiento
> sobre una base de datos con un bug de configuración (columna faltante). El atacante
> probó credenciales, falló en autenticar por un error de schema, e intentó un
> escalamiento directo de roles que fue bloqueado por el motor.
>
> Contención sugerida: Corregir el bug de schema (`ALTER TABLE`), auditar si se
> crearon objetos o roles adicionales durante la sesión, y restringir el acceso de
> `postgres` a localhost únicamente."

---

## 4. Contraste: qué acertó la IA, qué omitió, qué afirmó sin evidencia

### Aciertos

- Identificó correctamente la secuencia: INSERT, fn_resetear_password, fn_autenticar x4, GRANT fallido.
- Detectó que el log no muestra el SELECT masivo y explicó correctamente por qué (`log_statement='mod'`).
- Identificó el intento de escalamiento y que fue bloqueado.
- Recomendó revisar si se crearon objetos adicionales durante la sesión — medida de contención válida.

### Omisiones

- **No detectó el login exitoso:** La IA afirmó que "todas las llamadas terminan en ERROR", pero el cuarto intento (`fn_autenticar` con contraseña correcta) **sí retornó el id_cliente**. El log muestra la misma estructura de error porque el error es interno a la función (columna faltante), no porque la autenticación falle lógicamente. La IA confundió el error de implementación con un fallo de autenticación. En un incidente real, la autenticación puede haber sido exitosa aunque el log muestre errores de función.
- **No identificó la sesión de corrección:** El log incluía una sesión de `ALTER TABLE` y un `REVOKE admin_datos FROM rol_soporte` que la IA no mencionó.

### Afirmaciones sin sustento en el log

- La IA afirmó que "el atacante probó credenciales y falló en autenticar" — esto no está sustentado. El log muestra errores de función, no de autenticación. No hay forma de saber desde el log si la contraseña era correcta o incorrecta cuando la función falla por un error interno.
- La IA caracterizó la sesión como "un atacante" — el log solo muestra al usuario `postgres` (superusuario local). No hay evidencia de acceso externo ni de un tercero.

---

## 5. Decisión final de contención

**Esta decisión fue tomada por el equipo a partir de la evidencia del log y del conocimiento
del script ejecutado. No es una acción automática derivada de la sugerencia de la IA.**

En un caso real, con este patrón de log, el equipo tomaría las siguientes acciones:

1. **Corregir el bug de schema inmediatamente:** aplicar `ALTER TABLE cliente ADD COLUMN contrasena_hash TEXT` en producción (o recrear desde `sql/01_schema.sql` actualizado). Un error interno en `fn_autenticar` significa que la función de seguridad no opera — cualquier llamada falla de forma silenciosa, lo que es peor que un error explícito.

2. **Auditar la sesión de `postgres`:** verificar en el log completo qué más hizo esa sesión antes y después del fragmento capturado. El usuario `postgres` no debería ejecutar scripts de aplicación directamente en producción.

3. **No bloquear el origen (localhost):** el acceso provino de `::1` (loopback). Bloquear localhost rompería la administración del servidor. La medida correcta es restringir qué usuarios pueden conectarse desde localhost vía `pg_hba.conf` — `postgres` debería requerir autenticación de certificado o `peer` en producción, no `scram-sha-256` con contraseña.

4. **Forzar rotación de contraseña de `app_web` y `admin_datos`:** aunque no hay evidencia de que estas credenciales fueron comprometidas, es práctica estándar rotar contraseñas ante cualquier incidente que involucre actividad anómala en la BD.

5. **No escalar a revocación de roles:** el intento de `GRANT admin_datos TO rol_soporte` falló. No hay evidencia de que el escalamiento haya tenido éxito en ningún momento (el primer GRANT exitoso fue ejecutado por el equipo como error propio y revertido de inmediato). No se justifica una revocación de emergencia de roles.
