/*
주어진 위치로부터 가자 가까운 도로 까지의 거리(m)
*/

-- years
CREATE OR REPLACE TEMP TABLE _year AS (
    SELECT year::UINT16 AS gv_year
    FROM UNNEST([{{ year | join(', ') }}]) AS t(year)
);

-- main query
WITH _distance AS (
    SELECT 
        c.id AS id,
        y.gv_year,
        r.is_mr1,
        r.is_mr2,
        ST_Distance(c.geom, r.geom) AS distance,
    FROM _chunk c
    CROSS JOIN _year y
    LEFT JOIN road r ON y.gv_year = r.year 
), _result_wide AS (
    SELECT 
        id, 
        gv_year, 
        distance.MIN() AS D_Road,
        distance.MIN() FILTER (WHERE is_mr1) AS D_MR1,
        distance.MIN() FILTER (WHERE is_mr2) AS D_MR2,
    FROM _distance
    GROUP BY id, gv_year
), _result AS (
    UNPIVOT _result_wide
    ON D_Road, D_MR1, D_MR2
    INTO NAME gv_name VALUE gv_value
)
SELECT * FROM _result
;
