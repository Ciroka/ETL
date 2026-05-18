-- CONSULTA 1
-- Determinar el porcentaje del maiz cosechado que se llevo a molienda

SELECT
    co.anio,
    co.cultivo,
    SUM(co.produccion_tm) AS produccion_total,
    m.cantidad AS cantidad_molienda_total,
   	ROUND((m.cantidad) * 100 / SUM(co.produccion_tm)::NUMERIC, 2) AS porcentaje_molienda
FROM cosechas co
JOIN moliendas m ON co.anio = m.anio AND co.cultivo = m.cultivo 
GROUP BY co.anio, co.cultivo, m.cantidad
ORDER BY co.anio;

-- CONSULTA 2
-- Determinar el porcentaje del trigo cosechado que se llevo a molienda

SELECT
    co.anio,
    co.cultivo,
    SUM(co.produccion_tm) AS produccion_total,
	m.cantidad_molienda_total,
    ROUND((m.cantidad_molienda_total * 100 / SUM(co.produccion_tm))::NUMERIC, 2)  AS porcentaje_molienda
FROM cosechas co
JOIN (
    SELECT anio, SUM(cantidad) AS cantidad_molienda_total
    FROM moliendas
    WHERE cultivo ILIKE 'trigo%'
    GROUP BY anio
    ) AS m ON co.anio = m.anio AND co.cultivo = 'trigo'
GROUP BY co.anio, co.cultivo, cantidad_molienda_total
ORDER BY co.anio;

-- CONSULTA 3
-- Comparar los valores obtenidos anteriormente con las superficie cosechadas de ambos cereales y ver la relacion de cual es mayor, menor, etc