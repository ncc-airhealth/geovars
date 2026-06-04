/*
주어진 위치의 x, y 좌표
*/


-- years
CREATE OR REPLACE TEMP TABLE _year AS (
    SELECT year::UINT16 AS gv_year
    FROM UNNEST([{{ year | join(', ') }}]) AS t(year)
);

-- main query
WITH _chunk_transform AS (
    SELECT
        c.id AS id,
        c.geom AS geom_tm,
        c.geom.ST_Transform('EPSG:5179', 'EPSG:4326', always_xy:=true) AS geom_wgs,
    FROM
        _chunk c
), _result_wide AS (
    SELECT
        g.id AS id,
        g.geom_wgs.ST_X() AS WGS_X,
        g.geom_wgs.ST_Y() AS WGS_Y,
        g.geom_tm.ST_X() AS TM_X,
        g.geom_tm.ST_Y() AS TM_Y,
    FROM _chunk_transform g
), _result AS (
    UNPIVOT _result_wide
    ON WGS_X, WGS_Y, TM_X, TM_Y
    INTO NAME gv_name VALUE gv_value
)
-- result
SELECT r.id, y.gv_year, r.gv_name, r.gv_value
FROM _result r
CROSS JOIN _year y
;
