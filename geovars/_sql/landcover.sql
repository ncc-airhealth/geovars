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

-- buffer
CREATE OR REPLACE TEMP TABLE buffer AS (
    SELECT radius::UINT16 AS radius
    FROM UNNEST([{{ buffer | join(', ') }}]) AS t(radius)
);


--------------------------------------------------------------------------------
-- main query
--------------------------------------------------------------------------------

CREATE OR REPLACE TEMP TABLE aoi_landcover AS (
    WITH aoi_h3 AS (
        SELECT 
            c.geom
                .ST_Buffer(5000)
                .ST_Transform('EPSG:5179', 'EPSG:4326', always_xy:=true)
                .ST_AsText()
                .h3_polygon_wkt_to_cells_experimental(7, 'overlap')
                .LIST()
                .FLATTEN()
                .LIST_DISTINCT()
                .UNNEST()
                AS h3
        FROM chunk c, buffer b
    )
    SELECT t.h3, t.year, t.code, t.geom,
    FROM aoi_h3 h
    CROSS JOIN year y
    INNER JOIN landcover t ON h.h3 = t.h3 AND y.gv_year = t.year
);
CREATE INDEX rtree_aoi_landcover
ON aoi_landcover
USING RTREE(geom);


WITH overlap AS (
    SELECT 
        c.id, 
        y.gv_year, 
        b.radius, 
        t.code, 
        ST_Intersection(c.geom, t.geom).ST_Area().SUM() AS area
    FROM chunk c
    CROSS JOIN year y
    CROSS JOIN buffer b
    LEFT JOIN aoi_landcover t ON y.gv_year = t.year AND ST_DWithin(c.geom, t.geom, b.radius)
    GROUP BY c.id, y.gv_year, b.radius, t.code
), wide AS (
    SELECT
        id, 
        gv_year, 
        radius, 
        (code = 110)::INT * area AS LS_110,
        (code = 120)::INT * area AS LS_120,
        (code = 130)::INT * area AS LS_130,
        (code = 140)::INT * area AS LS_140,
        (code = 150)::INT * area AS LS_150,
        (code = 160)::INT * area AS LS_160,
        (code = 200)::INT * area AS LS_200,
        (code = 310)::INT * area AS LS_310,
        (code = 320)::INT * area AS LS_320,
        (code = 330)::INT * area AS LS_330,
        (code = 400)::INT * area AS LS_400,
        (code = 500)::INT * area AS LS_500,
        (code = 600)::INT * area AS LS_600,
        (code = 710)::INT * area AS LS_710,
    FROM overlap
), long AS (
    UNPIVOT wide
    ON * EXCLUDE (id, gv_year, radius)
    INTO NAME gv_name VALUE gv_value
), result AS (
    SELECT
        id,
        gv_year,
        gv_name || '_' || LPAD(radius::VARCHAR, 4, '0') AS gv_name,
        gv_value,
    FROM long
)
SELECT * FROM result
;
