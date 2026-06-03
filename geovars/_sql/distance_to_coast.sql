/*
주어진 위치로부터 가장 가까운 해안선까지의 거리(m)를 계산하는 스크립트
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

-- WITH simple_coastline AS (
--     SELECT year, geom, geom.ST_Simplify(10) AS geom_simple
--     FROM coastline
-- )

SELECT 
    c.id AS id,
    y.gv_year,
    'D_Coast' AS gv_name,
    ST_Distance(c.geom, t.geom).MIN() AS gv_value,
FROM chunk c
CROSS JOIN year y 
LEFT JOIN coastline t ON t.year = y.gv_year AND ST_DWithin(c.geom, t.geom, 200_000)
GROUP BY c.id, y.gv_year
;