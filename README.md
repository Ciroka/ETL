# TP ETL — Datos Agrícolas Argentina

> **Trabajo Práctico:** Implementación de un flujo de datos ETL para el almacenamiento y análisis de datos masivos.
> **Fuente de datos:** [Portal de Datos Abiertos de la República Argentina](https://www.datos.gob.ar/dataset)
> **Motor:** PostgreSQL 17
> **Entorno:** Docker

---

## Índice

1. [Requisitos](#1-requisitos)
2. [Estructura del proyecto](#2-estructura-del-proyecto)
3. [Datasets utilizados](#3-datasets-utilizados)
4. [Modelo de base de datos](#4-modelo-de-base-de-datos)
5. [Proceso ETL](#5-proceso-etl)
   - [Extract: detección y corrección de encoding](#51-extract-detección-y-corrección-de-encoding)
   - [Tablas staging](#52-tablas-staging)
   - [Transform & Load](#53-transform--load)
6. [Levantar el entorno](#6-levantar-el-entorno)
7. [Consultas SQL](#7-consultas-sql)

---

## 1. Requisitos

- Los archivos CSV en la carpeta `csv/` del proyecto (ver sección 3)

No se requiere instalar PostgreSQL ni ninguna otra dependencia localmente.

---

## 2. Estructura del proyecto

```
practicoetl/
├── csv/
│   ├── trigo-serie-1927-2025.csv
│   ├── maiz-serie-1923-2024.csv
│   └── molienda-de-granos-a-diciembre-2017.csv
├── initdb/
│   └── 000_initdb.sql        # esquema + tablas temp + COPY + inserts (script de inicialización de la base de datos)
├── scripts/
│   └── consultas.sql         # consultas SQL de análisis de datos
├── docker-compose.yml
└── password.txt              # contraseña de postgres (no hacerle commit)
```

El directorio `initdb/` es montado en `/docker-entrypoint-initdb.d/` dentro del contenedor. PostgreSQL ejecuta automáticamente todos los `.sql` que encuentre ahí al inicializarse por primera vez.

---

## 3. Datasets utilizados

| Archivo | Descripción | Filas |
|---|---|---|
| `trigo-serie-1927-2025.csv` | Detalle por departamento y campaña de trigo | 25.232 |
| `maiz-serie-1923-2024.csv` | Detalle por departamento y campaña de maíz | 33.518 |
| `molienda-de-granos-a-diciembre-2017.csv` | Molienda por país hasta 2017 | 68 |


---

## 4. Modelo de base de datos

Las entidades principales son:

- **paises / provincias / departamentos** — jerarquía geográfica
- **cultivos** — catálogo de cultivos (trigo, maíz, trigo pan, trigo candeal)
- **siembras / cosechas** — datos de superficie y producción por campaña y departamento
- **unidades\_de\_medida / moliendas** — datos de molienda industrial por país y año

---

## 5. Proceso ETL

### 5.1 Extract: verificación de encoding
 
El primer paso fue inspeccionar los archivos fuente para determinar su codificación, utilizando el comando `file` de Linux:
 
```bash
file csv/*.csv
```
 
Resultado:

```
csv/maiz-serie-1923-2024.csv:                CSV ISO-8859 text
csv/molienda-de-granos-a-diciembre-2017.csv: CSV ISO-8859 text
csv/trigo-serie-1927-2025.csv:               CSV ISO-8859 text
```
Como había presentes errores de codificación en los archivos, e intentando solucionarlo con varios métodos, ya sea especificando el encoding en el comando copy, haciendo un script de Python, siempre llegábamos al mismo resultado, la solución era arreglarlo manualmente. Debido a esto hicimos uso de la IA en esta parte y le solicitamos que nos cambiara el archivo a codificación UTF-8. Debido a eso, si se ejecuta dicho comando el resultado será:
```
csv/maiz-serie-1923-2024.csv:                CSV Unicode text, UTF-8 text
csv/molienda-de-granos-a-diciembre-2017.csv: CSV Unicode text, UTF-8 text
csv/trigo-serie-1927-2025.csv:               CSV Unicode text, UTF-8 text
```
 
Los tres archivos están en UTF-8, por lo que no requirieron conversión de encoding. Se cargan directamente con `ENCODING 'UTF-8'` en el comando `COPY`.
 
### 5.2 Tablas staging
 
Antes de cargar los datos al modelo final se creó una tabla staging temporal `TEMP TABLE` por cada archivo CSV. Estas tablas actúan como zona intermedia con las siguientes características:
 
**Separación de responsabilidades.** El staging es el paso Extract del ETL, su único objetivo es recibir el archivo tal como viene.
 
**Sin claves primarias ni foráneas.** Las tablas staging no representan entidades del dominio, son una copia fiel del archivo fuente.
 
### 5.3 Transform & Load
 
La carga al staging se realiza con el comando `COPY` de PostgreSQL, la forma más eficiente de importar archivos CSV masivos — trabaja en modo bulk con mínimo overhead:
 
```sql
COPY tmp_maiz_serie
FROM '/csv/maiz-serie-1923-2024.csv'
WITH (FORMAT csv, HEADER true, DELIMITER ',', ENCODING 'UTF-8');
```
 
El parámetro `HEADER true` indica que la primera fila del archivo contiene los nombres de columna. PostgreSQL los usa para mapear cada valor a la columna correspondiente de la tabla staging, por lo que los nombres de columna en el `CREATE TEMP TABLE` deben coincidir exactamente con los headers del CSV.
 
Una vez en el staging, los datos se insertan en las tablas de entidad. Se tomaron las siguientes decisiones de diseño:
 
**DISTINCT ON** para evitar duplicados al poblar las tablas de dimensión, ya que los mismos departamentos y provincias aparecen repetidos en miles de filas de los CSV:
 
```sql
INSERT INTO provincias (id, nombre, pais_id)
SELECT DISTINCT ON (provincia_id)
    provincia_id,
    provincia,
    (SELECT id FROM paises WHERE LOWER(nombre) = 'argentina')
FROM (
    SELECT provincia_id, provincia FROM tmp_maiz_serie
    UNION ALL
    SELECT provincia_id, provincia FROM tmp_trigo_serie
) AS datos_provincias;
```
 
**UNION ALL** para combinar los datos de trigo y maíz en una sola inserción hacia siembras y cosechas, dado que ambos CSV tienen exactamente la misma estructura de columnas.
 
**COALESCE** para reemplazar valores nulos por cero en los campos numéricos, ya que algunos registros históricos no tienen datos de superficie o producción:
 
```sql
COALESCE(superficie_sembrada_ha, 0)
```
 
**Datos descartados deliberadamente.** Durante el Transform se omiten las columnas calculables, ya que pueden derivarse de los datos almacenados mediante consultas SQL.
 
---
 
## 6. Levantar el entorno
 
```bash
# Primera vez: construye y carga todo automáticamente
docker compose up -d
 
# Ver logs del contenedor de base de datos
docker compose logs db
 
# Conectarse con psql desde la terminal
docker exec -it practicoetl-db-1 psql -U postgres
 
# Detener sin borrar datos
docker compose down
 
# Detener y borrar volúmenes, re-ejecuta el initdb
docker compose down -v
```

---
 
## 7. Consultas SQL
 
Las consultas pueden ejecutarse desde psql en la terminal o desde pgAdmin en `http://localhost:80`. Para conectarse desde pgAdmin, agregar un servidor con host `db`, puerto `5432` y usuario `postgres`.
 
---
 
### Consulta 1: Porcentaje de maíz cosechado llevado a molienda
 
**Pregunta:** ¿Qué porcentaje de la producción de maíz de cada año terminó siendo molido?
 
```sql
SELECT
    co.anio,
    co.cultivo,
    SUM(co.produccion_tm) AS produccion_total,
    m.cantidad AS cantidad_molienda_total,
    ROUND((m.cantidad) * 100 / SUM(co.produccion_tm)::NUMERIC, 2) AS porcentaje_molienda
FROM cosechas co
JOIN moliendas m ON co.anio = m.anio AND co.cultivo = m.cultivo
GROUP BY co.anio, co.cultivo, m.cantidad
ORDER BY co.anio DESC;
```
 
**Técnicas utilizadas:** `JOIN` entre `cosechas` y `moliendas` por año y cultivo, `SUM` para agregar la producción total por año a nivel nacional, `ROUND` para presentar el porcentaje con dos decimales. El porcentaje se calcula como `cantidad_molienda / produccion_total * 100`.
 
---
 
### Consulta 2: Porcentaje de trigo cosechado llevado a molienda
 
**Pregunta:** ¿Qué porcentaje de la producción total de trigo se destinó a molienda cada año?
 
```sql
SELECT
    co.anio,
    co.cultivo,
    SUM(co.produccion_tm) AS produccion_total,
    m.cantidad_molienda_total,
    ROUND((m.cantidad_molienda_total * 100 / SUM(co.produccion_tm))::NUMERIC, 2) AS porcentaje_molienda
FROM cosechas co
JOIN (
    SELECT anio, SUM(cantidad) AS cantidad_molienda_total
    FROM moliendas
    WHERE cultivo ILIKE 'trigo%'
    GROUP BY anio
) AS m ON co.anio = m.anio AND co.cultivo = 'trigo'
GROUP BY co.anio, co.cultivo, cantidad_molienda_total
ORDER BY co.anio DESC;
```
 
**Técnicas utilizadas:** subquery en el `JOIN` para pre-agregar la molienda de todos los tipos de trigo (`trigo pan` y `trigo candeal`) usando `ILIKE 'trigo%'` antes de cruzarla con la producción. Esto permite comparar la producción total de trigo contra el total molido independientemente del subtipo.
 
---
 
### Consulta 3: TOP 10 departamentos con mayor producción en 2017
 
**Pregunta:** ¿Cuáles fueron los 10 departamentos con mayor producción de cada cultivo en el último año registrado?
 
```sql
SELECT
    co.anio,
    co.cultivo,
    de.nombre AS nombre_departamento,
    SUM(co.produccion_tm) AS produccion_total
FROM cosechas co
JOIN departamentos de ON co.departamento_id = de.id AND co.anio = 2017
GROUP BY de.nombre, co.anio, co.cultivo
ORDER BY SUM(co.produccion_tm) DESC
LIMIT 10;
```
 
**Técnicas utilizadas:** `JOIN` entre `cosechas` y `departamentos` filtrando directamente en la condición del JOIN por `anio = 2017`, `GROUP BY` por departamento y cultivo, `ORDER BY` descendente sobre la producción agregada y `LIMIT 10` para quedarse con los mayores productores.
 
---
 
### Consulta 4: Relación siembra-cosecha por cultivo y año
 
**Pregunta:** ¿Qué porcentaje de la superficie sembrada logró cosecharse efectivamente cada año, para cada cultivo?
 
```sql
SELECT
    co.anio,
    co.cultivo,
    SUM(co.superficie_cosechada_ha) AS superficie_cosechada_total,
    superficie_sembrada_total,
    ROUND(SUM(co.superficie_cosechada_ha) * 100 / (superficie_sembrada_total)::NUMERIC, 2) AS porcentaje_cosecha_de_lo_sembrado
FROM cosechas co
JOIN (
    SELECT cultivo, anio, SUM(superficie_sembrada_ha) AS superficie_sembrada_total
    FROM siembras
    GROUP BY anio, cultivo
) AS s ON co.anio = s.anio AND co.cultivo = s.cultivo
GROUP BY co.anio, co.cultivo, superficie_sembrada_total
ORDER BY co.anio DESC;
```
 
**Técnicas utilizadas:** subquery en el `JOIN` para pre-agregar la superficie sembrada desde la tabla `siembras` por año y cultivo, que luego se cruza con `cosechas`. El porcentaje resultante indica la tasa de éxito de cada campaña: valores cercanos a 100% significan que casi todo lo sembrado se cosechó, valores bajos indican pérdidas por heladas, sequías u otras causas. Esta consulta cruza las tres tablas centrales del modelo (`siembras`, `cosechas`, y el JOIN implícito por cultivo/año).
