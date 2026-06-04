/*
주어진 위치로부터 주어진 거리 이내의 배출량
*/

-- years
CREATE OR REPLACE TEMP TABLE _year AS (
    SELECT year::UINT16 AS gv_year
    FROM UNNEST([{{ year | join(', ') }}]) AS t(year)
);

-- buffer
CREATE OR REPLACE TEMP TABLE _buffer AS (
    SELECT radius::UINT16 AS radius
    FROM UNNEST([{{ buffer | join(', ') }}]) AS t(radius)
);

-- main query
WITH _wide_result AS (
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
    FROM _chunk c
    CROSS JOIN _year y
    CROSS JOIN _buffer b
    LEFT JOIN emission t ON y.gv_year = t.year AND ST_DWithin(c.geom, t.geom, b.radius)
    GROUP BY c.id, y.gv_year, b.radius
), _long_result AS (
    UNPIVOT _wide_result
    ON CO, NOx, SOx, TSP, VOC, NH3, PM10
    INTO NAME gv_name VALUE gv_value
), _result AS (
    SELECT
        id,
        gv_year,
        gv_name || '_' || (radius / 1000)::INT::VARCHAR || 'km' AS gv_name,
        gv_value,
    FROM _long_result
)
SELECT * FROM _result