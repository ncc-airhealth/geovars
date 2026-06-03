/*
주어진 위치로부터 항만 까지의 거리(m)
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
    'D_Port' AS gv_name,
    ST_Distance(t.geom, c.geom).MIN() AS gv_value,
FROM chunk c
CROSS JOIN year y
LEFT JOIN port t ON y.gv_year = t.year
GROUP BY c.id, y.gv_year
;