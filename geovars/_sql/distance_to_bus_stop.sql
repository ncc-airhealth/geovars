/*
주어진 위치로부터 가장 가까운 버스정류장 까지의 거리(m)
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


SELECT
    c.id AS id,
    y.gv_year,
    'D_Bus' AS gv_name,
    ST_Distance(t.geom, c.geom).MIN() AS gv_value,
FROM chunk c
CROSS JOIN year y
LEFT JOIN bus_stop t ON t.geom.ST_DWithin(c.geom, 10000)
GROUP BY c.id, y.gv_year
;