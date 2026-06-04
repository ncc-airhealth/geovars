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

-- code
CREATE OR REPLACE TEMP TABLE code AS (
    SELECT code::UINT16 AS code
    FROM UNNEST([110, 120, 130, 140, 150, 160, 200, 310, 320, 330, 400, 500, 600, 710]) AS t(code)
);


--------------------------------------------------------------------------------
-- main query
--------------------------------------------------------------------------------

CREATE INDEX chunk_rtree ON chunk USING RTREE(geom);

CREATE OR REPLACE TEMP TABLE aoi_landcover AS (
    WITH aoi_h3 AS (
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
        FROM chunk c, buffer b
    )
    SELECT t.h3, t.year, t.code, t.geom,
    FROM aoi_h3 h
    CROSS JOIN year y
    INNER JOIN landcover t ON h.h3 = t.h3 AND y.gv_year = t.year
);
CREATE INDEX rtree_aoi_landcover
ON aoi_landcover
USING RTREE(geom) WITH (max_node_capacity = 8);

SELECT 
    c.id, 
    y.gv_year, 
    'LS_' || t.code::VARCHAR || '_' || LPAD(b.radius::VARCHAR, 4, '0') AS gv_name,
    ST_Intersection(c.geom, t.geom).ST_Area().SUM() AS gv_value
FROM chunk c
CROSS JOIN year y
CROSS JOIN buffer b
CROSS JOIN code d
LEFT JOIN aoi_landcover t 
    ON y.gv_year = t.year AND d.code = t.code AND ST_DWithin(c.geom, t.geom, b.radius)
GROUP BY c.id, y.gv_year, b.radius, t.code