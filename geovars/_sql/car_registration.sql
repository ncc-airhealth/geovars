/*
주어진 위치가 속한 시군구의 자동차 등록대수
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
    'Car_Mean' AS gv_name,
    t.c_car_sgg_mean.ARGMIN(ST_Distance(o.geom, c.geom)) gv_value,
FROM _chunk c
LEFT JOIN output_area o ON ST_DWithin(c.geom, o.geom, 5000)
CROSS JOIN _year y 
INNER JOIN output_area_stat t 
    ON y.gv_year = t.year AND o.tot_reg_cd = t.tot_reg_cd

GROUP BY id, gv_year
;