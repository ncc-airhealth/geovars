/*
주어진 위치로부터 주어진 반경 이내의 버스정류장 개수
*/

--------------------------------------------------------------------------------
-- params
--------------------------------------------------------------------------------

-- years
CREATE OR REPLACE TEMP TABLE year AS (
    SELECT year::UINT16 AS gv_year
    FROM UNNEST([{{ year | join(', ') }}]) AS t(year)
);

-- buffer
CREATE OR REPLACE TEMP TABLE buffer AS (
    SELECT buffer::DOUBLE AS buffer
    FROM UNNEST([{{ buffer | join(', ') }}]) AS t(buffer)
);


--------------------------------------------------------------------------------
-- main query
--------------------------------------------------------------------------------

CREATE INDEX chunk_rtree ON chunk USING RTREE(geom);

SELECT 
    c.id,
    d.buffer,
    COUNT(b.geom) AS cnt,
FROM 
    chunk c
CROSS JOIN 
    buffer d
LEFT JOIN 
    bus_stop b ON ST_DWithin(c.geom, b.geom, d.buffer)
GROUP BY
    c.id, d.buffer
-- WITH
-- dist AS (
--     SELECT 
--         c.id AS id,
--         'D_bus' AS gv_name,
--         ST_Distance(b.geom, c.geom).MIN() AS gv_value,
--     FROM 
--         chunk c
--     LEFT JOIN bus_stop b ON ST_DWithin(c.geom, b.geom, 10000)
--     GROUP BY id
-- )
-- SELECT d.id, y.gv_year, d.gv_name, d.gv_value
-- FROM dist d, year y