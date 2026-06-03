/*
주어진 위치로부터 가자 가까운 공항 까지의 거리(m)
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

CREATE OR REPLACE TEMP TABLE aoi_ndvi_stat AS (
    WITH aoi_h3 AS (
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
        FROM chunk c, buffer b
    )
    SELECT 
        t.year, 
        t.ndvi_mean, 
        t.ndvi_min, 
        t.ndvi_max, 
        t.ndvi_median, 
        t.ndvi_08_median, 
        t.geom,
    FROM aoi_h3 h
    CROSS JOIN year y
    INNER JOIN ndvi_stat t ON h.h3 = t.h3 AND y.gv_year = t.year
    WHERE t.geom.ST_X() > 0
);
CREATE INDEX rtree_aoi_ndvi_stat
ON aoi_ndvi_stat
USING RTREE(geom);

WITH point_stat_wide AS (
    SELECT
        c.id,
        y.gv_year,
        t.ndvi_mean.ARGMIN(ST_Distance(c.geom, t.geom)) AS NDVI_Y1_Mean, 
        t.ndvi_min.ARGMIN(ST_Distance(c.geom, t.geom)) AS NDVI_Y1_Min, 
        t.ndvi_max.ARGMIN(ST_Distance(c.geom, t.geom)) AS NDVI_Y1_Max, 
        t.ndvi_08_median.ARGMIN(ST_Distance(c.geom, t.geom)) AS NDVI_M08_Median, 
    FROM chunk c
    CROSS JOIN year y
    LEFT JOIN aoi_ndvi_stat t ON y.gv_year = t.year AND ST_DWithin(c.geom, t.geom, 1000)
    GROUP BY c.id, y.gv_year
), point_stat AS (
    UNPIVOT point_stat_wide
    ON * EXCLUDE (id, gv_year)
    INTO NAME gv_name VALUE gv_value
), area_stat AS (
    SELECT
        c.id,
        y.gv_year,
        'NDVI_MM_' || LPAD(b.radius::VARCHAR, 4, '0') AS gv_name,
        ndvi_median.MEAN() AS value, 
    FROM chunk c
    CROSS JOIN year y
    CROSS JOIN buffer b
    LEFT JOIN aoi_ndvi_stat t ON y.gv_year = t.year AND ST_DWithin(c.geom, t.geom, b.radius)
    GROUP BY c.id, y.gv_year, b.radius
)

SELECT * FROM point_stat
UNION ALL
SELECT * FROM area_stat
