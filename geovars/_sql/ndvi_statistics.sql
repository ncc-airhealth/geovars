/*
주어진 위치의 NDVI 연간 통계
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


-- ndvi_stat in aoi
CREATE OR REPLACE TEMP TABLE _aoi_ndvi_stat AS (
    WITH _aoi_h3 AS (
        SELECT 
            c.geom
                .ST_Buffer(5000)
                .ST_Transform('EPSG:5179', 'EPSG:4326', always_xy:=true)
                .ST_AsText()
                .h3_polygon_wkt_to_cells_experimental(6, 'overlap')
                .LIST()
                .FLATTEN()
                .LIST_DISTINCT()
                .UNNEST()
                AS h3
        FROM _chunk c
        CROSS JOIN _buffer b
    )
    SELECT 
        t.year, 
        t.ndvi_mean, 
        t.ndvi_min, 
        t.ndvi_max, 
        t.ndvi_median, 
        t.ndvi_08_median, 
        t.geom,
    FROM _aoi_h3 h
    CROSS JOIN _year y
    INNER JOIN ndvi_stat t ON h.h3 = t.h3 AND y.gv_year = t.year
    WHERE t.geom.ST_X() > 0
);
CREATE INDEX _rtree_aoi_ndvi_stat
ON _aoi_ndvi_stat
USING RTREE(geom) WITH (max_node_capacity = 16);

-- main query
WITH _point_stat_wide AS (
    SELECT
        c.id,
        y.gv_year,
        t.ndvi_mean.ARGMIN(ST_Distance(c.geom, t.geom)) AS NDVI_Y1_Mean, 
        t.ndvi_min.ARGMIN(ST_Distance(c.geom, t.geom)) AS NDVI_Y1_Min, 
        t.ndvi_max.ARGMIN(ST_Distance(c.geom, t.geom)) AS NDVI_Y1_Max, 
        IF (
            y.gv_year = 2000,
            NULL,
            t.ndvi_08_median.ARGMIN(ST_Distance(c.geom, t.geom))
        ) AS NDVI_M08_Median, -- 전년도 MODIS 데이터 부재
    FROM _chunk c
    CROSS JOIN _year y
    LEFT JOIN _aoi_ndvi_stat t ON y.gv_year = t.year AND ST_DWithin(c.geom, t.geom, 500)
    GROUP BY c.id, y.gv_year
), _point_stat AS (
    UNPIVOT _point_stat_wide
    ON * EXCLUDE (id, gv_year)
    INTO NAME gv_name VALUE gv_value
), _area_stat AS (
    SELECT
        c.id,
        y.gv_year,
        'NDVI_MM_' || LPAD(b.radius::VARCHAR, 4, '0') AS gv_name,
        ndvi_median.MEAN() AS value, 
    FROM _chunk c
    CROSS JOIN _year y
    CROSS JOIN _buffer b
    LEFT JOIN _aoi_ndvi_stat t ON y.gv_year = t.year AND ST_DWithin(c.geom, t.geom, b.radius)
    GROUP BY c.id, y.gv_year, b.radius
)
SELECT * FROM _point_stat
UNION ALL
SELECT * FROM _area_stat
