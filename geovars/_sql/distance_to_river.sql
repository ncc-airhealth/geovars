/*
주어진 위치로부터 가자 가까운 강 까지의 거리(m)
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
    'D_River' AS gv_name,
    ST_Distance(t.geom, c.geom).MIN() AS gv_value,
FROM chunk c
LEFT JOIN river t ON ST_DWithin(c.geom, t.geom, 100_000)
CROSS JOIN year y
GROUP BY c.id, y.gv_year
;