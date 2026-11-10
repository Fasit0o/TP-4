# Verificación de Equivalencia — Parte D
## TP Unidad 5: Anonimización de Datos Personales

---

## 1. Tabla anonimizada: cliente_anon

La tabla `cliente_anon` se construye a partir de `cliente` aplicando sustituciones
deterministas: para un mismo `id_cliente` siempre se genera el mismo valor sintético,
lo que permite reproducir el script sin alterar los resultados agregados.

| Columna original | Técnica aplicada | Ejemplo resultado |
|---|---|---|
| `nombre` | 'cliente_anon_' + id | cliente_anon_1 |
| `email` | 'anon_' + id + '@anon.local' | anon_1@anon.local |
| `telefono` | '000' + id con padding a 7 dígitos | 0000000001 |
| `direccion` | 'Direccion Anonima ' + id | Direccion Anonima 1 |
| `contrasena_hash` | NULL (no se expone ni el hash) | NULL |
| `id_cliente` | Sin cambio (necesario para JOIN con pedido) | 1 |

Verificación de conteo post-creación:
```
NOTICE: Verificación OK: cliente=20000 filas, cliente_anon=20000 filas.
```

---

## 2. Consulta de equivalencia

Pregunta de negocio: distribución de clientes según el mes de su primer pedido
y el rango de volumen de actividad (cantidad de pedidos).

Esta consulta permite analizar patrones de incorporación y frecuencia de compra
sin necesidad de acceder a ningún dato personal.

### Consulta A — tabla real (cliente)

```sql
SELECT
    EXTRACT(YEAR  FROM primer_pedido)::INT   AS anio,
    EXTRACT(MONTH FROM primer_pedido)::INT   AS mes,
    CASE
        WHEN total_pedidos BETWEEN 1  AND 5  THEN '1-5'
        WHEN total_pedidos BETWEEN 6  AND 10 THEN '6-10'
        WHEN total_pedidos BETWEEN 11 AND 15 THEN '11-15'
        ELSE '16+'
    END                                      AS rango_pedidos,
    COUNT(*)                                 AS cantidad_clientes
FROM (
    SELECT
        c.id_cliente,
        MIN(p.fecha_hora)  AS primer_pedido,
        COUNT(p.id_pedido) AS total_pedidos
    FROM cliente c
    JOIN pedido p ON p.id_cliente = c.id_cliente
    GROUP BY c.id_cliente
) sub
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3;
```

### Consulta B — tabla anonimizada (cliente_anon)

Idéntica en estructura; solo se reemplaza `cliente` por `cliente_anon`.
El JOIN con `pedido` usa `id_cliente`, que se conservó sin alteración.

```sql
SELECT
    EXTRACT(YEAR  FROM primer_pedido)::INT   AS anio,
    EXTRACT(MONTH FROM primer_pedido)::INT   AS mes,
    CASE
        WHEN total_pedidos BETWEEN 1  AND 5  THEN '1-5'
        WHEN total_pedidos BETWEEN 6  AND 10 THEN '6-10'
        WHEN total_pedidos BETWEEN 11 AND 15 THEN '11-15'
        ELSE '16+'
    END                                      AS rango_pedidos,
    COUNT(*)                                 AS cantidad_clientes
FROM (
    SELECT
        ca.id_cliente,
        MIN(p.fecha_hora)  AS primer_pedido,
        COUNT(p.id_pedido) AS total_pedidos
    FROM cliente_anon ca
    JOIN pedido p ON p.id_cliente = ca.id_cliente
    GROUP BY ca.id_cliente
) sub
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3;
```

---

## 3. Resultados comparados

### Resultado Consulta A (tabla real)

```
 anio | mes | rango_pedidos | cantidad_clientes
------+-----+---------------+------------------
 2026 |   7 | 11-15         |              2634
 2026 |   7 | 6-10          |             14996
 2026 |   8 | 11-15         |               365
 2026 |   8 | 6-10          |              1999
 2026 |   9 | 11-15         |                 1
 2026 |   9 | 6-10          |                 5
(6 rows)
```

### Resultado Consulta B (tabla anonimizada)

```
 anio | mes | rango_pedidos | cantidad_clientes
------+-----+---------------+------------------
 2026 |   7 | 11-15         |              2634
 2026 |   7 | 6-10          |             14996
 2026 |   8 | 11-15         |               365
 2026 |   8 | 6-10          |              1999
 2026 |   9 | 11-15         |                 1
 2026 |   9 | 6-10          |                 5
(6 rows)
```

Los resultados son idénticos fila por fila.

### Verificación por EXCEPT (ambas direcciones)

```
-- Consulta A EXCEPT Consulta B:
(0 rows)

-- Consulta B EXCEPT Consulta A:
(0 rows)
```

0 filas en ambas direcciones confirma equivalencia total.

---

## 4. Información de Food Store que no debe salir sin anonimizar

Los datos de la tabla `cliente` — nombre completo, email, teléfono y dirección — son datos
personales directamente identificables amparados por la Ley 25.326 (Argentina) y el RGPD.
Compartirlos con un asistente de IA expone a personas reales a riesgos de phishing, spam
o ingeniería social, aun cuando el objetivo sea solo analizar patrones de compra.

Tampoco debe salir `contrasena_hash`: aunque es un hash bcrypt y no la contraseña en
texto plano, exponer hashes permite ataques de diccionario offline sin límite de intentos,
especialmente si el atacante conoce el algoritmo y los parámetros de sal.

El historial de pedidos combinado con datos de identificación personal (nombre + email +
fecha + monto) es igualmente sensible: permite reconstruir perfiles de comportamiento
individuales. Cualquier consulta que combine `cliente` con `pedido` o `detalle_pedido`
debe pasar primero por la capa de anonimización antes de ser compartida fuera del
entorno de desarrollo.
