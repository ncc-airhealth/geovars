/*
주어진 위치가 속한 시군구의 자동차 등록대수
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

-- code
CREATE OR REPLACE TEMP TABLE _code AS (
    SELECT code::UINT16 AS code
    FROM UNNEST([110, 120, 130, 140, 150, 160, 200, 310, 320, 330, 400, 500, 600, 710]) AS t(code)
);


-- data filtering
CREATE OR REPLACE TEMP TABLE _aoi_h3 AS (
    SELECT 
        c.geom
        .ST_Buffer(5000, quad_segs:=16)
        .ST_Transform('EPSG:5179', 'EPSG:4326', always_xy:=true)
        .ST_AsText()
        .h3_polygon_wkt_to_cells_experimental(7, 'overlap')
        .LIST()
        .FLATTEN()
        .LIST_DISTINCT()
        .UNNEST()
        AS h3
    FROM _chunk c
    ORDER BY h3
);

CREATE OR REPLACE TEMP TABLE _aoi_landcover AS (
    WITH _aoi_buffer AS (
        SELECT geom.ST_Union_Agg().ST_Buffer(5000, quad_segs:=16) AS geom
        FROM _chunk
    ), _h3_filtered AS (
        SELECT t.year, t.code, t.geom
        FROM landcover t
        INNER JOIN _aoi_h3 h ON h.h3 = t.h3
        INNER JOIN _aoi_buffer a ON ST_Intersects(t.geom, a.geom)
    )
    SELECT t.year, t.code, t.geom FROM _h3_filtered t
);

CREATE OR REPLACE TEMP TABLE _overlap_area AS (
    SELECT 
        c.id, 
        b.radius, 
        y.gv_year, 
        d.code,
        c.geom
            .ST_Buffer(b.radius, quad_segs:=16)
            .ST_Intersection(t.geom)
            .ST_Area()
            .SUM()
            AS area
    FROM _chunk c
    CROSS JOIN _buffer b
    CROSS JOIN _year y
    CROSS JOIN _code d
    LEFT JOIN _aoi_landcover t ON
        y.gv_year = t.year
        AND d.code = t.code
        AND ST_Intersects(t.geom, c.geom)
    GROUP BY c.id, b.radius, y.gv_year, d.code
    ORDER BY c.id, b.radius, y.gv_year, d.code
);

WITH result_a AS (
    SELECT 
        id, 
        gv_year,
        'LS_' || code::VARCHAR || '_' || LPAD(radius::VARCHAR, 4, '0') || '_a' AS gv_name, 
        area AS gv_value
    FROM _overlap_area
), result_p AS (
    SELECT 
        id, 
        gv_year,
        'LS_' || code::VARCHAR || '_' || LPAD(radius::VARCHAR, 4, '0') || '_p' AS gv_name, 
        area / SUM(area) OVER (PARTITION BY id, gv_year) AS gv_value
    FROM _overlap_area
)
SELECT id, gv_year, gv_name, IFNULL(gv_value, 0) AS gv_value FROM result_a
UNION ALL
SELECT id, gv_year, gv_name, IFNULL(gv_value, 0) AS gv_value FROM result_p
;



-- SELECT NULL AS id, NULL AS gv_year, NULL AS gv_name, NULL AS gv_value
-- FROM _chunk c;





-- WITH _area_stat AS (
--     SELECT 
--         c.id, 
--         y.gv_year, 
--         'LS_' || d.code::VARCHAR || '_' || LPAD(b.radius::VARCHAR, 4, '0') AS prefix, 
--         t.geom
--             .ST_Intersection(c.geom.ST_Buffer(b.radius))
--             .ST_Area() 
--             .SUM()
--             AS area
--     FROM _chunk c
--     CROSS JOIN _year y
--     CROSS JOIN _buffer b
--     CROSS JOIN _code d
--     LEFT JOIN _aoi_landcover t
--         ON t.year = y.gv_year 
--         AND t.code = d.code
--         AND t.geom.ST_DWithin(c.geom, b.radius)
--     GROUP BY c.id, y.gv_year, d.code, b.radius
-- ), _area_result AS (
--     SELECT 
--         id, 
--         gv_year, 
--         prefix || '_a' AS gv_name, 
--         IFNULL(area, 0) AS gv_value
--     FROM _area_stat
-- ), _ratio_result AS (
--     SELECT 
--         id, 
--         gv_year, 
--         prefix || '_p' AS gv_name, 
--         IFNULL(area, 0) / SUM(IFNULL(area, 0)) OVER (PARTITION BY id, gv_year) AS gv_value
--     FROM _area_stat
-- )
-- SELECT * FROM _area_result
-- UNION ALL
-- SELECT * FROM _ratio_result
-- ;
