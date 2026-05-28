/*
주어진 위치로부터 가자 가까운 버스정류장 까지의 거리(m)를 계산하는 스크립트
*/

--------------------------------------------------------------------------------
-- params
--------------------------------------------------------------------------------

-- years
CREATE OR REPLACE TEMP TABLE year AS (
    SELECT year::UINT16 AS gv_year
    FROM UNNEST([{{ year | join(', ') }}]) AS t(year)
);


--------------------------------------------------------------------------------
-- main query
--------------------------------------------------------------------------------

WITH
dist AS (
    SELECT 
        c.id AS id,
        'D_bus' AS gv_name,
        ST_Distance(b.geom, c.geom).MIN() AS gv_value,
    FROM 
        chunk c
    LEFT JOIN bus_stop b ON ST_DWithin(c.geom, b.geom, 10000)
    GROUP BY id
)
SELECT d.id, y.gv_year, d.gv_name, d.gv_value
FROM dist d, year y