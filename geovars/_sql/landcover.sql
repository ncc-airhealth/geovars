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
CREATE OR REPLACE TEMP TABLE _aoi_landcover AS (
    WITH _aoi_h3 AS (
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
        FROM _chunk c, _buffer b
    )
    SELECT t.h3, t.year, t.code, t.geom,
    FROM _aoi_h3 h
    CROSS JOIN _year y
    INNER JOIN landcover t ON h.h3 = t.h3 AND y.gv_year = t.year
);
CREATE INDEX _rtree_aoi_landcover
ON _aoi_landcover
USING RTREE(geom) WITH (max_node_capacity = 8);

-- main query
WITH _overlap_area AS (
    SELECT 
        c.id, 
        y.gv_year, 
        'LS_' || t.code::VARCHAR || '_' || LPAD(b.radius::VARCHAR, 4, '0') AS gv_prefix,
        c.geom
            .ST_Buffer(b.radius, quad_segs:=16)
            .ST_Intersection(t.geom)
            .ST_Area().SUM()
            AS gv_value
    FROM _chunk c
    CROSS JOIN _year y
    CROSS JOIN _buffer b
    CROSS JOIN _code d
    LEFT JOIN _aoi_landcover t 
        ON y.gv_year = t.year AND d.code = t.code AND ST_DWithin(c.geom, t.geom, b.radius)
    GROUP BY c.id, y.gv_year, b.radius, t.code
), _area_result AS (
    SELECT 
        id, 
        gv_year, 
        gv_prefix || '_a' AS gv_name, 
        IFNULL(gv_value, 0) AS gv_value
    FROM _overlap_area
), _ratio_result AS (
    SELECT
        id, 
        gv_year, 
        gv_prefix || '_p' AS gv_name, 
        IFNULL(gv_value, 0) / SUM(gv_value) OVER (PARTITION BY id, gv_year) AS gv_value
    FROM _overlap_area
)
SELECT * FROM _area_result
UNION ALL
SELECT * FROM _ratio_result
;
