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
    FROM VALUES ('dem'), ('dsm', ) AS t(elev_type)
);


--------------------------------------------------------------------------------
-- main query
--------------------------------------------------------------------------------

CREATE OR REPLACE TEMP TABLE chunk AS (
    SELECT * FROM chunk LIMIT 100
);

CREATE INDEX chunk_rtree ON chunk USING RTREE(geom);

CREATE OR REPLACE TEMP TABLE aoi_elevation AS (
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
    SELECT t.elev_type, t.value, ST_Point(t.x, t.y) AS geom
    FROM aoi_h3 h
    INNER JOIN elevation t ON h.h3 = t.h3
);
CREATE INDEX rtree_aoi_elevation
ON aoi_elevation
USING RTREE(geom);

WITH abs_alt AS (
    SELECT 
        c.id, 
        et.elev_type,
        'Altitude_' || IF(et.elev_type = 'dem', 'k', 'a') AS gv_name, 
        IFNULL(t.value.ARGMIN(ST_Distance(c.geom, t.geom)), 0) AS gv_value
    FROM chunk c
    CROSS JOIN elev_type et
    LEFT JOIN aoi_elevation t ON ST_DWithin(c.geom, t.geom, 100) AND et.elev_type = t.elev_type
    GROUP BY c.id, et.elev_type
), rel_alt_long AS (
    SELECT 
        c.id, 
        b.radius,
        h.height,
        ab.sign,
        -- (((t.value - a.gv_value) > +h.height)::INT).MEAN() AS above_mean,
        -- (((t.value - a.gv_value) < -h.height)::INT).MEAN() AS below_mean,
        ((ab.sign * (t.value - a.gv_value) > h.height)::INT).MEAN() AS gv_value,
    FROM chunk c
    INNER JOIN abs_alt a ON c.id = c.id 
    CROSS JOIN buffer b
    CROSS JOIN rel_height h
    CROSS JOIN ab
    LEFT JOIN aoi_elevation t ON 
        NOT ST_DWithin(c.geom, t.geom, b.radius)
        AND ST_DWithin(c.geom, t.geom, b.radius + 30)
        AND t.elev_type = a.elev_type
    GROUP BY c.id, b.radius, h.height, ab.sign,
),  rel_alt AS (
    SELECT 
        id, 
        'Alt_' || IF(sign = 1, 'above_', 'below_') || height::VARCHAR || '_' || radius::VARCHAR AS gv_name,
        gv_value,
    FROM rel_alt_long
), result AS (
    SELECT a.id, y.gv_year, a.gv_name, a.gv_value FROM abs_alt a, year y
    UNION ALL
    SELECT a.id, y.gv_year, a.gv_name, a.gv_value FROM rel_alt a, year y
)
SELECT * FROM result
ORDER BY id, gv_name, gv_year;
