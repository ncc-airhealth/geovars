/*
주어진 위치의 고도와 인근의 상대고도
*/

-- years
CREATE OR REPLACE TEMP TABLE _year AS (
    SELECT year::UINT16 AS gv_year
    FROM UNNEST([{{ year | join(', ') }}]) AS t(year)
);

-- buffer
CREATE OR REPLACE TEMP TABLE _buffer AS (
    SELECT radius::INT16 AS radius
    FROM UNNEST([{{ buffer | join(', ') }}]) AS t(radius)
);

-- gap value for relative height reference
CREATE OR REPLACE TEMP TABLE _rel_gap AS (
    SELECT gap::INT16 AS gap
    FROM UNNEST([{{ rel_height | join(', ') }}]) AS t(gap)
);

-- data filtering
CREATE OR REPLACE TEMP TABLE _aoi_elevation AS (
    WITH 
    _aoi_h3 AS (
        SELECT 
            c.geom
                .ST_Buffer(5030)
                .ST_Transform('EPSG:5179', 'EPSG:4326', always_xy:=true)
                .ST_AsText()
                .h3_polygon_wkt_to_cells_experimental(7, 'overlap')
                .LIST()
                .FLATTEN()
                .LIST_DISTINCT()
                .UNNEST()
                AS h3
        FROM _chunk c, _buffer b
    ), _elevation_h3_filtered AS (
        SELECT t.elev_type, t.value, ST_Point(t.x, t.y) AS geom
        FROM _aoi_h3 h
        INNER JOIN elevation t ON h.h3 = t.h3
    ), _chunk_agg AS (
        SELECT geom.ST_Union_Agg() AS geom FROM _chunk
    )
    SELECT e.elev_type, e.value, e.geom
    FROM _elevation_h3_filtered e 
    INNER JOIN _chunk_agg c ON ST_DWithin(e.geom, c.geom, 5030)
);
CREATE OR REPLACE TEMP TABLE _aoi_dem AS (
    SELECT value, geom 
    FROM _aoi_elevation
    WHERE elev_type = 'dem' AND value IS NOT NULL
);
CREATE OR REPLACE TEMP TABLE _aoi_dsm AS (
    SELECT value, geom 
    FROM _aoi_elevation 
    WHERE elev_type = 'dsm' AND value IS NOT NULL
);



-- main query
CREATE OR REPLACE TEMP TABLE _result AS (
    WITH _abs_alt_dem AS (
        SELECT
            c.id, 
            IFNULL(
                e.value.ARGMIN(ST_Distance(c.geom, e.geom)),
                0
            ) AS value
        FROM _chunk c
        LEFT JOIN _aoi_dem e ON ST_DWithin(c.geom, e.geom, 30)
        GROUP BY c.id
    ), _abs_alt_dsm AS (
        SELECT
            c.id, 
            IFNULL(
                e.value.ARGMIN(ST_Distance(c.geom, e.geom)),
                0
            ) AS value
        FROM _chunk c
        LEFT JOIN _aoi_dsm e ON ST_DWithin(c.geom, e.geom, 30)
        GROUP BY c.id
    ), _rel_alt_dem AS (
        SELECT
            c.id,
            b.radius,
            g.gap,
            AVG((e.value - a.value > +g.gap)::INTEGER) AS Alt_k_above,
            AVG((e.value - a.value < -g.gap)::INTEGER) AS Alt_k_below,
        FROM _chunk c
        LEFT JOIN _abs_alt_dem a ON c.id = a.id
        CROSS JOIN _buffer b
        CROSS JOIN _rel_gap g
        LEFT JOIN _aoi_dem e 
            ON NOT ST_DWithin(c.geom, e.geom, b.radius)
            AND ST_DWithin(c.geom, e.geom, b.radius + 30)
        GROUP BY c.id, b.radius, g.gap
    ), _rel_alt_dsm AS (
        SELECT
            c.id,
            b.radius,
            g.gap,
            AVG((e.value - a.value > +g.gap)::INTEGER) AS Alt_a_above,
            AVG((e.value - a.value < -g.gap)::INTEGER) AS Alt_a_below,
        FROM _chunk c
        LEFT JOIN _abs_alt_dsm a ON c.id = a.id
        CROSS JOIN _buffer b
        CROSS JOIN _rel_gap g
        LEFT JOIN _aoi_dsm e 
            ON NOT ST_DWithin(c.geom, e.geom, b.radius)
            AND ST_DWithin(c.geom, e.geom, b.radius + 30)
        GROUP BY c.id, b.radius, g.gap
    ), _altitude_k AS (
        SELECT id, 'Altitude_k' AS gv_name, value AS gv_value,
        FROM _abs_alt_dem
    ), _altitude_a AS (
        SELECT id, 'Altitude_a' AS gv_name, value AS gv_value,
        FROM _abs_alt_dsm
    ), _alt_k AS (
        SELECT
            id, 
            prefix || '_' || gap::VARCHAR || '_' || radius::VARCHAR AS gv_name,
            gv_value,
        FROM (UNPIVOT _rel_alt_dem ON Alt_k_above, Alt_k_below INTO NAME prefix VALUE gv_value)
    ), _alt_a AS (
        SELECT
            id, 
            prefix || '_' || gap::VARCHAR || '_' || radius::VARCHAR AS gv_name,
            gv_value,
        FROM (UNPIVOT _rel_alt_dsm ON Alt_a_above, Alt_a_below INTO NAME prefix VALUE gv_value)
    ), _union_result AS (
        SELECT id, gv_name, gv_value FROM _altitude_k
        UNION ALL
        SELECT id, gv_name, gv_value FROM _altitude_a
        UNION ALL
        SELECT id, gv_name, gv_value FROM _alt_k
        UNION ALL
        SELECT id, gv_name, gv_value FROM _alt_a
    )
    SELECT r.id, y.gv_year, r.gv_name, r.gv_value
    FROM _union_result r
    CROSS JOIN _year y
);

-- clean temp table
DROP TABLE IF EXISTS _aoi_dem;
DROP TABLE IF EXISTS _aoi_dsm;
DROP TABLE IF EXISTS _aoi_elevation;

SELECT id, gv_year, gv_name, gv_value 
FROM _result
;
