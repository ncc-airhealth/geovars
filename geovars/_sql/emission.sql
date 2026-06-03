/*
주어진 위치로부터 주어진 거리 이내의 배출량
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
    SELECT radius::UINT16 AS radius
    FROM UNNEST([{{ buffer | join(', ') }}]) AS t(radius)
);

--------------------------------------------------------------------------------
-- main query
--------------------------------------------------------------------------------

CREATE INDEX chunk_rtree ON chunk USING RTREE(geom);

WITH wide AS (
    SELECT
        c.id, 
        y.gv_year, 
        b.radius, 
        t.co.SUM() AS CO, 
        t.nox.SUM() AS NOx, 
        t.sox.SUM() AS SOx,
        t.tsp.SUM() AS TSP,
        t.voc.SUM() AS VOC, 
        t.nh3.SUM() AS NH3, 
        t.pm10.SUM() AS PM10,
    FROM chunk c
    CROSS JOIN year y
    CROSS JOIN buffer b
    LEFT JOIN emission t ON y.gv_year = t.year AND ST_DWithin(c.geom, t.geom, b.radius)
    GROUP BY c.id, y.gv_year, b.radius
), long AS (
    UNPIVOT wide
    ON * EXCLUDE (id, gv_year, radius)
    INTO NAME gv_name VALUE gv_value
), result AS (
    SELECT
        id,
        gv_year,
        gv_name || '_' || (radius / 1000)::INT::VARCHAR || 'km' AS gv_name,
        gv_value,
    FROM long
)
SELECT * FROM result