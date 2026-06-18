/*
주어진 위치 주변 영역의 토지피복 면적과 비율
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


-- main query
WITH 
_aoi_h3 AS (
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
),
_aoi_buffer AS (
    SELECT geom.ST_Union_Agg().ST_Buffer(5000, quad_segs:=16) AS geom
    FROM _chunk
), _aoi_landcover AS (
    SELECT t.year, t.code, t.geom, t.geom.ST_Area() AS area
    FROM landcover t
    INNER JOIN _aoi_h3 h ON h.h3 = t.h3
    INNER JOIN _aoi_buffer a ON ST_Intersects(t.geom, a.geom)
    INNER JOIN _year y ON y.gv_year = t.year
),
_chunk_buffer AS (
    SELECT 
        c.id, 
        b.radius,
        c.geom.ST_Buffer(b.radius, quad_segs:=16) AS geom
    FROM _chunk c
    CROSS JOIN _buffer b
), 
_intersecting_area AS (
    SELECT 
        c.id, 
        c.radius, 
        t.year,
        t.code,
        CASE
            WHEN c.geom.ST_Contains(t.geom)  -- geos 활성화로 인한 메모리 과부하 방지
            THEN t.area
            ELSE c.geom.ST_Intersection(t.geom).ST_Area()
        END .SUM() AS area
    FROM _chunk_buffer c
    INNER JOIN _aoi_landcover t ON ST_Intersects(t.geom, c.geom)
    GROUP BY c.id, c.radius, t.year, t.code
), 
_result_area_stat AS (
    SELECT
        c.id,
        y.gv_year,
        c.radius,
        d.code,
        IFNULL(a.area, 0) AS a,
        IFNULL(a.area, 0) / c.geom.ST_Area() AS p
    FROM _chunk_buffer c
    CROSS JOIN _year y
    CROSS JOIN _code d
    LEFT JOIN _intersecting_area a
        ON c.id = a.id 
        AND c.radius = a.radius 
        AND y.gv_year = a.year
        AND d.code = a.code
), 
_result AS (
    SELECT
        id,
        gv_year,
        CONCAT_WS(
            '_',
            'LS' || code::VARCHAR,
            LPAD(radius::VARCHAR, 4, '0'),
            ap
        ) AS gv_name, 
        gv_value,
    FROM (
        UNPIVOT _result_area_stat
        ON a, p
        INTO NAME ap VALUE gv_value
    )
    ORDER BY id, gv_year, gv_name
)
SELECT * FROM _result;
