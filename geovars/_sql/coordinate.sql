/*
주어진 위치의 좌표값 지리변수를 계산하는 스크립트
*/

--------------------------------------------------------------------------------
-- params
--------------------------------------------------------------------------------

-- constants
CREATE OR REPLACE TEMP TABLE constants AS (
    SELECT
        'EPSG:5179' AS ref_crs,
        'EPSG:4326' AS wgs_crs,
        'EPSG:5179' AS tm_crs,
);


-- years
CREATE OR REPLACE TEMP TABLE year AS (
    SELECT year::UINT16 AS gv_year
    FROM UNNEST([{{ year | join(', ') }}]) AS t(year)
);


--------------------------------------------------------------------------------
-- main query
--------------------------------------------------------------------------------

WITH 
-- reprojection
input_geom AS (
    SELECT
        c.id AS id,
        c.geom.ST_Transform(p.ref_crs, p.wgs_crs, always_xy:=true) AS geom_wgs,
        c.geom.ST_Transform(p.ref_crs, p.tm_crs, always_xy:=true) AS geom_tm,
    FROM
        chunk c, constants p
),
-- geovariable wide format
result_wide AS (
    SELECT
        g.id AS id,
        y.gv_year AS gv_year,
        g.geom_wgs.ST_X() AS WGS_X,
        g.geom_wgs.ST_Y() AS WGS_Y,
        g.geom_tm.ST_X() AS TM_X,
        g.geom_tm.ST_Y() AS TM_Y,
    FROM
        input_geom g, year y
),
-- geovariable long format
result_long AS (
    UNPIVOT result_wide
    ON WGS_X, WGS_Y, TM_X, TM_Y
    INTO 
        NAME gv_name
        VALUE gv_value
)
-- result
SELECT 
    id, 
    gv_year, 
    gv_name, 
    gv_value,
FROM 
    result_long
;
