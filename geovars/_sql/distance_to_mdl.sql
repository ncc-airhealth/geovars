/*
주어진 위치로부터 군사분계선 까지의 거리(m)
*/

-- years
CREATE OR REPLACE TEMP TABLE _year AS (
    SELECT year::UINT16 AS gv_year
    FROM UNNEST([{{ year | join(', ') }}]) AS t(year)
);


-- main query
SELECT 
    c.id AS id,
    y.gv_year,
    'D_North' AS gv_name,
    ST_Distance(t.geom, c.geom).MIN() AS gv_value,
FROM _chunk c
CROSS JOIN _year y
LEFT JOIN mdl t ON y.gv_year = t.year
GROUP BY c.id, y.gv_year
;