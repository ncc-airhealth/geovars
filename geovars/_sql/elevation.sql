/*
주어진 위치의 고도와 인근의 상대고도
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

CREATE OR REPLACE TEMP TABLE rel_height AS (
    SELECT height::UINT16 AS height
    FROM UNNEST([{{ rel_height | join(', ') }}]) AS t(height)
);

CREATE OR REPLACE TEMP TABLE ab AS (
    SELECT *
    FROM (
        VALUES ('above',  1), ('below', -1)
    ) AS t(label, sign)
);
CREATE OR REPLACE TEMP TABLE elev_type AS (
    SELECT *
    FROM VALUES ('dem', 'k'), ('dsm', 'a') AS t(elev_type, alias)
);


--------------------------------------------------------------------------------
-- main query
--------------------------------------------------------------------------------

CREATE INDEX chunk_rtree ON chunk USING RTREE(geom);

CREATE OR REPLACE TEMP TABLE aoi_elevation AS (
    WITH cte1 AS (
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
    ), cte2 AS (
        SELECT t.elev_type, t.value, ST_Point(t.x, t.y) AS geom
        FROM cte1 h
        INNER JOIN elevation t ON h.h3 = t.h3
    ), cte3 AS (
        SELECT geom.ST_Union_Agg() AS geom FROM chunk
    ), cte4 AS (
        SELECT cte2.elev_type, cte2.value, cte2.geom
        FROM cte2
        INNER JOIN cte3 ON ST_DWithin(cte2.geom, cte3.geom, 5000)
    )
    SELECT * FROM cte4
);

CREATE OR REPLACE TEMP TABLE aoi_dem AS (
    SELECT value, geom 
    FROM aoi_elevation
    WHERE elev_type = 'dem' AND value IS NOT NULL
);
CREATE INDEX rtree_aoi_dem 
ON aoi_dem 
USING RTREE(geom) WITH (max_node_capacity = 16);

CREATE OR REPLACE TEMP TABLE aoi_dsm AS (
    SELECT value, geom 
    FROM aoi_elevation 
    WHERE elev_type = 'dsm' AND value IS NOT NULL
);
CREATE INDEX rtree_aoi_dsm 
ON aoi_dsm 
USING RTREE(geom) WITH (max_node_capacity = 16);


WITH altitude_k AS (
    SELECT 
        c.id,
        'Altitude_k' AS gv_name,
        value.ARGMIN(ST_Distance(c.geom, e.geom)) AS gv_value,
    FROM chunk c
    LEFT JOIN aoi_dem e ON ST_DWithin(c.geom, e.geom, 30)
    GROUP BY c.id
), altitude_a AS (
    SELECT 
        c.id,
        'Altitude_a' AS gv_name,
        value.ARGMIN(ST_Distance(c.geom, e.geom)) AS gv_value,
    FROM chunk c
    LEFT JOIN aoi_dsm e ON ST_DWithin(c.geom, e.geom, 30)
    GROUP BY c.id
), rel_alt_k_wide AS (
    SELECT 
        c.id, 
        b.radius, 
        h.height,
        ((e.value > k.gv_value + h.height)::INT).MEAN() AS above, 
        ((e.value < k.gv_value - h.height)::INT).MEAN() AS below,
    FROM chunk c
    CROSS JOIN buffer b
    LEFT JOIN aoi_dsm e ON ST_DWithin(c.geom, e.geom, b.radius)
    LEFT JOIN altitude_k k ON c.id = k.id
    CROSS JOIN rel_height h
    GROUP BY c.id, b.radius, h.height
), rel_alt_k AS (
    SELECT
        id, 
        'Alt_k_' || ab || '_' || height::VARCHAR || '_' || radius::VARCHAR AS gv_name,
        gv_value,
    FROM (UNPIVOT rel_alt_k_wide ON above, below INTO NAME ab VALUE gv_value)
), rel_alt_a_wide AS (
    SELECT 
        c.id, 
        b.radius, 
        h.height,
        ((e.value > k.gv_value + h.height)::INT).MEAN() AS above, 
        ((e.value < k.gv_value - h.height)::INT).MEAN() AS below,
    FROM chunk c
    CROSS JOIN buffer b
    LEFT JOIN aoi_dsm e ON ST_DWithin(c.geom, e.geom, b.radius)
    LEFT JOIN altitude_k k ON c.id = k.id
    CROSS JOIN rel_height h
    GROUP BY c.id, b.radius, h.height
), rel_alt_a AS (
    SELECT
        id, 
        'Alt_a_' || ab || '_' || height::VARCHAR || '_' || radius::VARCHAR AS gv_name,
        gv_value,
    FROM (UNPIVOT rel_alt_k_wide ON above, below INTO NAME ab VALUE gv_value)
), result AS (
    SELECT * FROM altitude_k
    UNION ALL
    SELECT * FROM altitude_a
    UNION ALL
    SELECT * FROM rel_alt_k
    UNION ALL
    SELECT * FROM rel_alt_a
)
SELECT id, gv_year, gv_name, gv_value FROM result, year;

--EXPLAIN
-- WITH chunk_dem_match AS (
--     SELECT 
--         c.id,
--         e.value,
--         ST_Distance(c.geom, e.geom) AS distance,
--     FROM chunk c
--     LEFT JOIN aoi_dem e ON ST_DWithin(c.geom, e.geom, 30)
-- ), altitude_k AS (
--     SELECT id, 'Altitude_k' AS gv_name, value.ARGMIN(distance) AS gv_value
--     FROM chunk_dem_match
--     GROUP BY id
-- ), chunk_dsm_match AS (
--     SELECT 
--         c.id,
--         e.value,
--         ST_Distance(c.geom, e.geom) AS distance,
--     FROM chunk c
--     LEFT JOIN aoi_dsm e ON ST_DWithin(c.geom, e.geom, 30)
-- ), altitude_a AS (
--     SELECT id, 'Altitude_k' AS gv_name, value.ARGMIN(distance) AS gv_value
--     FROM chunk_dsm_match
--     GROUP BY id
-- )
-- SELECT * FROM altitude_a;
    


-- WITH altitude_k AS  (
--     SELECT 
--         c.id, 
--         'Altitude_k' AS gv_name,
--         IFNULL(t.dem.ARGMIN(ST_Distance(c.geom, t.geom)), 0) AS gv_value
--     FROM chunk c
--     LEFT JOIN aoi_elevation t ON ST_DWithin(c.geom, t.geom, 30) AND dem IS NOT NULL
--     GROUP BY c.id
-- ), altitude_a AS  (
--     SELECT 
--         c.id, 
--         'Altitude_a' AS gv_name,
--         IFNULL(t.dsm.ARGMIN(ST_Distance(c.geom, t.geom)), 0) AS gv_value
--     FROM chunk c
--     LEFT JOIN aoi_elevation t ON ST_DWithin(c.geom, t.geom, 30) AND dsm IS NOT NULL
--     GROUP BY c.id
-- )
-- SELECT * FROM altitude_k
-- UNION ALL 
-- SELECT * FROM altitude_a

-- WITH abs_alt AS (
--     SELECT 
--         c.id, 
--         et.elev_type,
--         'Altitude_' || IF(et.elev_type = 'dem', 'k', 'a') AS gv_name, 
--         IFNULL(t.value.ARGMIN(ST_Distance(c.geom, t.geom)), 0) AS gv_value
--     FROM chunk c
--     CROSS JOIN elev_type et
--     LEFT JOIN aoi_elevation t ON ST_DWithin(c.geom, t.geom, 100) AND et.elev_type = t.elev_type
--     GROUP BY c.id, et.elev_type
-- ), rel_alt_long AS (
--     SELECT 
--         c.id, 
--         b.radius,
--         h.height,
--         ab.sign,
--         -- (((t.value - a.gv_value) > +h.height)::INT).MEAN() AS above_mean,
--         -- (((t.value - a.gv_value) < -h.height)::INT).MEAN() AS below_mean,
--         ((ab.sign * (t.value - a.gv_value) > h.height)::INT).MEAN() AS gv_value,
--     FROM chunk c
--     INNER JOIN abs_alt a ON c.id = c.id 
--     CROSS JOIN buffer b
--     CROSS JOIN rel_height h
--     CROSS JOIN ab
--     LEFT JOIN aoi_elevation t ON 
--         NOT ST_DWithin(c.geom, t.geom, b.radius)
--         AND ST_DWithin(c.geom, t.geom, b.radius + 30)
--         AND t.elev_type = a.elev_type
--     GROUP BY c.id, b.radius, h.height, ab.sign,
-- ),  rel_alt AS (
--     SELECT 
--         id, 
--         'Alt_' || IF(sign = 1, 'above_', 'below_') || height::VARCHAR || '_' || radius::VARCHAR AS gv_name,
--         gv_value,
--     FROM rel_alt_long
-- ), result AS (
--     SELECT a.id, y.gv_year, a.gv_name, a.gv_value FROM abs_alt a, year y
--     UNION ALL
--     SELECT a.id, y.gv_year, a.gv_name, a.gv_value FROM rel_alt a, year y
-- )
-- SELECT * FROM result
-- -- ORDER BY id, gv_name, gv_year;
