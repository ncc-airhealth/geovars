/*
주어진 위치가 속한 시군구의 자동차 등록대수
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
    'C_Car' AS gv_name,
    c_car_sgg_mean
        .ARGMIN(ST_Distance(t.geom, c.geom)) gv_value,
FROM chunk c
CROSS JOIN year y 
LEFT JOIN output_area_stat t ON y.gv_year = t.year AND ST_DWithin(c.geom, t.geom, 5000)
GROUP BY id, gv_year
;