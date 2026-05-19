\set ON_ERROR_STOP on

-- #################################################################
-- Paso 1: Eliminación de tablas para re-inicilización del contenedor

DROP TABLE IF EXISTS moliendas CASCADE;
DROP TABLE IF EXISTS siembras CASCADE;
DROP TABLE IF EXISTS cosechas CASCADE;
DROP TABLE IF EXISTS cultivos CASCADE;
DROP TABLE IF EXISTS provincias CASCADE;
DROP TABLE IF EXISTS paises CASCADE;
DROP TABLE IF EXISTS departamentos CASCADE;
DROP TABLE IF EXISTS unidades_de_medida CASCADE;

-- #################################################################
-- Paso 2: Creación de las tablas de entidad

CREATE TABLE paises (
    id BIGINT PRIMARY KEY,
    nombre VARCHAR(50)
);

CREATE TABLE provincias (
    id BIGINT PRIMARY KEY,
    nombre VARCHAR(50),
    pais_id BIGINT,
    CONSTRAINT fk_provincia_pais FOREIGN KEY (pais_id) REFERENCES paises(id) ON DELETE CASCADE  
);

CREATE TABLE departamentos (
    id BIGINT PRIMARY KEY,
    nombre VARCHAR (50),
    provincia_id BIGINT,
    CONSTRAINT fk_departamento_provincia FOREIGN KEY (provincia_id) REFERENCES provincias(id) ON DELETE CASCADE
);

CREATE TABLE cultivos (
    nombre VARCHAR(50) PRIMARY KEY
);

CREATE TABLE siembras (
    id SERIAL PRIMARY KEY,
    superficie_sembrada_ha BIGINT,
    cultivo VARCHAR(50),
    departamento_id INT,
    anio INT,
    CONSTRAINT fk_siembra_cultivo FOREIGN KEY (cultivo) REFERENCES cultivos(nombre),
    CONSTRAINT fk_siembra_departamento FOREIGN KEY (departamento_id) REFERENCES departamentos(id)
);

CREATE TABLE cosechas (
    id SERIAL PRIMARY KEY,
    superficie_cosechada_ha BIGINT,
    cultivo VARCHAR(50),
    departamento_id INT,
    anio INT,
    produccion_tm DOUBLE PRECISION,
    CONSTRAINT fk_cosecha_cultivo FOREIGN KEY (cultivo) REFERENCES cultivos(nombre),
    CONSTRAINT fk_cosecha_departamento FOREIGN KEY (departamento_id) REFERENCES departamentos(id)
);

CREATE TABLE unidades_de_medida (
    id VARCHAR(10) PRIMARY KEY,
    nombre VARCHAR(50)
);

CREATE TABLE moliendas (
    id SERIAL PRIMARY KEY,
    anio INT,
    cantidad BIGINT,
    pais_id BIGINT,
    cultivo VARCHAR(50),
    unidad_medida_id VARCHAR(10),
    CONSTRAINT fk_moliendas_pais FOREIGN KEY (pais_id) REFERENCES paises(id),
    CONSTRAINT fk_moliendas_unidad_medida FOREIGN KEY (unidad_medida_id) REFERENCES unidades_de_medida(id),
    CONSTRAINT fk_moliendas_cultivo FOREIGN KEY (cultivo) REFERENCES cultivos(nombre)
);

-- #################################################################
-- Paso 3: Creación de tablas temporales para datos csv.

CREATE TEMP TABLE tmp_maiz_serie (
    cultivo TEXT,
    anio INT,
    campania TEXT,
    provincia TEXT,
    provincia_id INT,
    departamento TEXT,
    departamento_id INT,
    superficie_sembrada_ha INT,
    superficie_cosechada_ha INT,
    produccion_tm DOUBLE PRECISION,
    rendimiento_kgxha INT
);

CREATE TEMP TABLE tmp_trigo_serie (
    cultivo TEXT,
    anio INT,
    campania TEXT,
    provincia TEXT,
    provincia_id INT,
    departamento TEXT,
    departamento_id INT,
    superficie_sembrada_ha INT,
    superficie_cosechada_ha INT,
    produccion_tm DOUBLE PRECISION,
    rendimiento_kgxha INT
);

CREATE TEMP TABLE tmp_molienda_granos (
    pais_id INT,
    nom_pais TEXT,
    anio INT,
    uni_med_id TEXT,
    nom_unimed TEXT,
    lino INT,
    girasol INT,
    mani INT,
    trigo_candeal INT,
    trigo_pan INT,
    maiz INT,
    sorgo_granifero INT,
    soja INT,
    arroz INT
);

-- #################################################################
-- Paso 4: Inserción de datos a las tablas temporales
-- Se utiliza COPY para mayor eficiencia con datos masivos.

COPY tmp_maiz_serie
FROM '/csv/maiz-serie-1923-2024.csv'
WITH (FORMAT csv, HEADER true, DELIMITER ',', ENCODING 'UTF-8');

COPY tmp_trigo_serie 
FROM '/csv/trigo-serie-1927-2025.csv'
WITH (FORMAT csv, HEADER true, DELIMITER ',', ENCODING 'UTF-8');

COPY tmp_molienda_granos
FROM '/csv/molienda-de-granos-a-diciembre-2017.csv'
WITH (FORMAT csv, HEADER true, DELIMITER ',', ENCODING 'UTF-8');

-- El ENCODING indica la codificación del archivo original. PostgreSQL lo lee en base
-- a ese formato y luego lo transforma a UTF-8 para almacenar los datos.


-- #################################################################
-- Paso 5: Inserción de los datos temporales a las tablas de entidad.
-- Algunos datos se desprecian por ser calculables o irrelevantes.

-- NOTAS:
-- * Utilizamos DISTINCT para no almacenar datos duplicados, por su aparición repetida en los .csv.
-- * Utilizamos UNION ALL para juntar la información de varias tablas con campos idénticos.
-- * COALESCE(campo, valor_por_defecto) se utilizó para reemplazar valores NULL por un valor por defecto.
-- * REPLACE(campo, valor_original, valor_final) se utilizó para corregir errores de codificación y almacenar
--   los datos correctamente en las tablas de entidad.
-- * Los cultivos se insertaron de forma directa ya que solo trabajaremos con los 4 especificados.

INSERT INTO paises (
    id,
    nombre
)
SELECT DISTINCT ON (pais_id)
    pais_id,
    nom_pais
FROM tmp_molienda_granos;

INSERT INTO provincias (
    id,
    nombre,
    pais_id
)
SELECT DISTINCT ON (provincia_id)
    provincia_id,
    provincia,
    (SELECT id FROM paises WHERE LOWER(nombre) = 'argentina')
FROM (
    SELECT 
        provincia_id,
        provincia
    FROM tmp_maiz_serie
    UNION ALL
    SELECT
        provincia_id,
        provincia
    FROM tmp_trigo_serie
) AS datos_provincias;


INSERT INTO departamentos (
    id,
    nombre,
    provincia_id
)
SELECT DISTINCT ON (departamento_id)
    departamento_id,
    departamento,
    provincia_id
FROM (
    SELECT 
        departamento_id,
        departamento,
        provincia_id
    FROM tmp_maiz_serie 
    WHERE departamento_id IS NOT NULL AND departamento IS NOT NULL
    UNION ALL
    SELECT
        departamento_id,
        departamento,
        provincia_id
    FROM tmp_trigo_serie 
    WHERE departamento_id IS NOT NULL AND departamento IS NOT NULL
) AS datos_departamentos;


INSERT INTO cultivos (nombre)
VALUES 
    ('trigo'),
    ('trigo pan'),
    ('trigo candeal'),
    ('maíz');


INSERT INTO siembras (
    superficie_sembrada_ha,
    departamento_id,
    anio,
    cultivo
)
SELECT
    COALESCE(superficie_sembrada_ha, 0),
    departamento_id,
    anio,
    cultivo
FROM (
    SELECT
        superficie_sembrada_ha,
        departamento_id,
        anio,
        cultivo
    FROM tmp_maiz_serie
    UNION ALL
    SELECT 
        superficie_sembrada_ha,
        departamento_id,
        anio,
        cultivo
    FROM tmp_trigo_serie
) AS datos_siembra;


INSERT INTO cosechas (
    superficie_cosechada_ha,
    anio,
    cultivo,
    departamento_id,
    produccion_tm  
)
SELECT
    COALESCE(superficie_cosechada_ha, 0),
    anio,
    cultivo,
    departamento_id,
    produccion_tm
FROM (
    SELECT
        superficie_cosechada_ha,
        anio,
        cultivo,
        departamento_id,
        produccion_tm
    FROM tmp_maiz_serie
    UNION ALL
    SELECT 
        superficie_cosechada_ha,
        anio,
        cultivo,
        departamento_id,
        produccion_tm
    FROM tmp_trigo_serie
) AS datos_cosechas;


INSERT INTO unidades_de_medida (
    id,
    nombre
)
SELECT DISTINCT ON (uni_med_id)
    uni_med_id,
    nom_unimed
FROM tmp_molienda_granos;


-- Inserción de datos de molienda sobre maíz
INSERT INTO moliendas (
    anio,
    cantidad,
    pais_id,
    cultivo,
    unidad_medida_id)
SELECT 
    anio,
    COALESCE(maiz, 0),
    pais_id,
    'maíz',
    uni_med_id
FROM tmp_molienda_granos;

-- Inserción de datos de molienda sobre trigo candeal
INSERT INTO moliendas (
    anio,
    cantidad,
    pais_id,
    cultivo,
    unidad_medida_id
)
SELECT 
    anio,
    COALESCE(trigo_candeal, 0),
    pais_id,
    'trigo candeal',
    uni_med_id
FROM tmp_molienda_granos;

-- Inserción de datos de molienda sobre trigo pan
INSERT INTO moliendas (
    anio,
    cantidad,
    pais_id,
    cultivo,
    unidad_medida_id
)
SELECT 
    anio,
    COALESCE(trigo_pan, 0),
    pais_id,
    'trigo pan',
    uni_med_id
FROM tmp_molienda_granos;