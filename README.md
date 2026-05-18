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
   - [Extract: detección de encoding](#51-extract--detección-de-encoding)
   - [Tablas staging](#52-tablas-staging)
   - [Transform & Load: COPY con conversión de encoding](#53-transform--load--copy-con-conversión-de-encoding)
6. [Levantar el entorno](#6-levantar-el-entorno)
7. [Consultas SQL](#7-consultas-sql)

---

## 1. Requisitos

- Los archivos CSV en la carpeta `csv/` del proyecto (ver en la sección 3)

No se requiere instalar PostgreSQL ni ninguna otra dependencia localmente.

---

## 2. Estructura del proyecto

```
TP-ETL/
├── csv/                      # datasets descargados de datos.gob.ar
│   ├── trigo-serie-1927-2025.csv
│   ├── maiz-serie-1923-2024.csv
│   └── molienda-de-granos-a-diciembre-2017.csv
├── initdb/
│   └── 01_init.sql           # esquema + tablas temporables + copy + inserts
├── scripts/
│   └── consultas.sql         # consultas SQL sobre la base de datos
├── docker-compose.yml
└── password.txt              # contraseña de postgres (no hacer commit)
```

El directorio `initdb/` es montado en `/docker-entrypoint-initdb.d/` dentro del contenedor. PostgreSQL ejecuta automáticamente todos los `.sql` que encuentre ahí al inicializarse por primera vez.

---

## 3. Datasets utilizados

| Archivo | Descripción | Filas |
|---|---|---|
| `trigo-serie-1927-2025.csv` | Detalle por departamento y campaña de trigo | 25.232 |
| `maiz-serie-1923-2024.csv` | Detalle por departamento y campaña de maíz | 33.519 |
| `molienda-de-granos-a-diciembre-2017.csv` | Molienda por país hasta 2017 | 69 |

---

## 4. Modelo de base de datos

Las entidades principales son:

- **paises / provincias / departamentos** — jerarquía geográfica
- **cultivos** — catálogo de cultivos (trigo, maíz, etc.)
- **siembras / cosechas** — datos de superficie por campaña
- **campanias** — unidad central que vincula cultivo, departamento, siembra y cosecha
- **unidades\_de\_medida / moliendas** — datos de molienda industrial por país

---

## 5. Proceso ETL

### 5.1 Extract: detección de encoding

El primer paso del proceso fue inspeccionar los archivos fuente para determinar su codificación real, ya que los datos públicos argentinos no siempre vienen en UTF-8.

Se utilizó el comando `file` de Linux sobre cada CSV:

```bash
file csv/*.csv
```

Resultado:

```
csv/maiz-serie-1923-2024.csv:                CSV ISO-8859 text
csv/molienda-de-granos-a-diciembre-2017.csv: CSV ISO-8859 text
csv/trigo-serie-1927-2025.csv:               CSV ISO-8859 text
```

Los archivos detectados como `ISO-8859` presentaban caracteres corruptos cuando se intentaba leerlos como UTF-8. Esto se debe a que ISO-8859-1 (también llamado LATIN1) utiliza un esquema de un byte por carácter donde los valores por encima de 127 no coinciden con los del estándar UTF-8.

### 5.2 Tablas staging

Antes de cargar los datos al modelo final se creó una tabla staging por cada archivo CSV, por los siguientes motivos:

**Separación de responsabilidades:** El staging actúa como zona intermedia cuyo único objetivo es recibir el archivo tal como viene, sin imponer ninguna restricción. La validación, limpieza y transformación ocurren en la etapa posterior.

**Sin claves primarias ni foráneas:** Las tablas staging no representan entidades del dominio, son solo una copia del archivo fuente.

**Una tabla por CSV:** Cada archivo tiene una estructura de columnas diferente.

### 5.3 Transform & Load: COPY con conversión de encoding

La carga al staging se realiza con el comando `COPY` de PostgreSQL, que es la forma más eficiente de importar archivos CSV con datos masivos.

El parámetro clave en este caso es el `ENCODING`, que le indica a PostgreSQL en qué codificación está escrito el archivo original. PostgreSQL lee los bytes con ese esquema y los convierte automáticamente a UTF-8, el encoding por defecto de la base de datos, durante la carga. El archivo original no se modifica.

**Ejemplo:**
```sql
COPY tmp_trigo_serie
FROM '/csv/trigo-serie-1923-2025.csv'
WITH (FORMAT CSV, HEADER true, DELIMITER ',', ENCODING 'LATIN1');
```

> `LATIN1` es el nombre que usa PostgreSQL para referirse al estándar ISO-8859-1.

---

## 6. Levantar el entorno

```bash
# Primera vez, construye y carga todo
docker compose up -d

# Para ver los logs del contenedor de base de datos
docker compose logs db

# Conectarse con psql desde la terminal
docker exec -it practicoetl-db-1 psql -U postgres

# Detener sin borrar los datos
docker compose down

# Detener y borrar los volúmenes
docker compose down -v
```

> **Importante:** los scripts en `initdb/` se ejecutan **una sola vez**, cuando el volumen de datos está vacío. Si ya existe el volumen de una ejecución anterior (por haber hecho `docker compose down`), Docker no los vuelve a correr. Para forzar una reinicialización completa se debe usar `docker compose down -v` antes de volver a levantar el contenedor.

---

## 7. Consultas SQL

> El análisis de los datos mediante las consultas SQL puede realizarse desde la terminal, conectándose al contenedor mediante el comando anterior, o bien desde pgAdmin conectándose a la url http://localhost:80, o al puerto que se haya configurado en el `docker-compose.yml`.

```yml
pgadmin:
   image: dpage/pgadmin4
      environment:
         - PGADMIN_DEFAULT_EMAIL=postgresql@postgresql.com
         - PGADMIN_DEFAULT_PASSWORD_FILE=/run/secrets/db-password
      secrets:
         - db-password
      ports:
         - 80:80 # <-- Puerto para la url
      depends_on:
         db:
            condition: service_healthy
```

