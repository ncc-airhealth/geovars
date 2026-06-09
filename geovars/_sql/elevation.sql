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
    SELECT radius::UINT16 AS radius
    FROM UNNEST([{{ buffer | join(', ') }}]) AS t(radius)
);

CREATE OR REPLACE TEMP TABLE _rel_height AS (
    SELECT height::UINT16 AS height
    FROM UNNEST([{{ rel_height | join(', ') }}]) AS t(height)
);

CREATE OR REPLACE TEMP TABLE _ab AS (
    SELECT *
    FROM (
        VALUES ('above',  1), ('below', -1)
    ) AS t(label, sign)
);
CREATE OR REPLACE TEMP TABLE _elev_type AS (
    SELECT *
    FROM VALUES ('dem', 'k'), ('dsm', 'a') AS t(elev_type, alias)
);


-- data filtering
CREATE OR REPLACE TEMP TABLE _aoi_elevation AS (
    WITH _cte1 AS (
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
        FROM _chunk c, _buffer b
    ), _cte2 AS (
        SELECT t.elev_type, t.value, ST_Point(t.x, t.y) AS geom
        FROM _cte1 h
        INNER JOIN elevation t ON h.h3 = t.h3
    ), _cte3 AS (
        SELECT geom.ST_Union_Agg() AS geom FROM _chunk
    ), _cte4 AS (
        SELECT _cte2.elev_type, _cte2.value, _cte2.geom
        FROM _cte2
        INNER JOIN _cte3 ON ST_DWithin(_cte2.geom, _cte3.geom, 5000)
    )
    SELECT * FROM _cte4
);

CREATE OR REPLACE TEMP TABLE _aoi_dem AS (
    SELECT value, geom 
    FROM _aoi_elevation
    WHERE elev_type = 'dem' AND value IS NOT NULL
);
CREATE INDEX _rtree_aoi_dem 
ON _aoi_dem 
USING RTREE(geom) WITH (max_node_capacity = 16);

CREATE OR REPLACE TEMP TABLE _aoi_dsm AS (
    SELECT value, geom 
    FROM _aoi_elevation 
    WHERE elev_type = 'dsm' AND value IS NOT NULL
);
CREATE INDEX _rtree_aoi_dsm 
ON _aoi_dsm 
USING RTREE(geom) WITH (max_node_capacity = 16);


-- main query
WITH _altitude_k AS (
    SELECT 
        c.id,
        'Altitude_k' AS gv_name,
        value.ARGMIN(ST_Distance(c.geom, e.geom)).GREATEST(0) AS gv_value,
    FROM _chunk c
    LEFT JOIN _aoi_dem e ON ST_DWithin(c.geom, e.geom, 30)
    GROUP BY c.id
), _altitude_a AS (
    SELECT 
        c.id,
        'Altitude_a' AS gv_name,
        value.ARGMIN(ST_Distance(c.geom, e.geom)).GREATEST(0) AS gv_value,
    FROM _chunk c
    LEFT JOIN _aoi_dsm e ON ST_DWithin(c.geom, e.geom, 30)
    GROUP BY c.id
), _rel_alt_k_wide AS (
    SELECT 
        c.id, 
        b.radius, 
        h.height,
        ((e.value > a.gv_value + h.height)::INT).MEAN() AS above, 
        ((e.value < a.gv_value - h.height)::INT).MEAN() AS below,
    FROM _chunk c
    CROSS JOIN _buffer b
    LEFT JOIN _aoi_dem e 
        ON NOT ST_DWithin(c.geom, e.geom, b.radius)
        AND ST_DWithin(c.geom, e.geom, b.radius + 30)
    LEFT JOIN _altitude_k a ON c.id = a.id
    CROSS JOIN _rel_height h
    GROUP BY c.id, b.radius, h.height
), _rel_alt_k AS (
    SELECT
        id, 
        'Alt_k_' || ab || '_' || height::VARCHAR || '_' || radius::VARCHAR AS gv_name,
        gv_value,
    FROM (UNPIVOT _rel_alt_k_wide ON above, below INTO NAME ab VALUE gv_value)
), _rel_alt_a_wide AS (
    SELECT 
        c.id, 
        b.radius, 
        h.height,
        ((e.value > a.gv_value + h.height)::INT).MEAN() AS above, 
        ((e.value < a.gv_value - h.height)::INT).MEAN() AS below,
    FROM _chunk c
    CROSS JOIN _buffer b
    LEFT JOIN _aoi_dsm e
        ON NOT ST_DWithin(c.geom, e.geom, b.radius)
        AND ST_DWithin(c.geom, e.geom, b.radius + 30)
    LEFT JOIN _altitude_a a ON c.id = a.id
    CROSS JOIN _rel_height h
    GROUP BY c.id, b.radius, h.height
), _rel_alt_a AS (
    SELECT
        id, 
        'Alt_a_' || ab || '_' || height::VARCHAR || '_' || radius::VARCHAR AS gv_name,
        gv_value,
    FROM (UNPIVOT _rel_alt_k_wide ON above, below INTO NAME ab VALUE gv_value)
), _result AS (
    SELECT * FROM _altitude_k
    UNION ALL
    SELECT * FROM _altitude_a
    UNION ALL
    SELECT * FROM _rel_alt_k
    UNION ALL
    SELECT * FROM _rel_alt_a
)
SELECT id, gv_year, gv_name, gv_value 
FROM _result, _year;
