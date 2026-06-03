/*
주어진 위치로부터 가자 가까운 도로 까지의 거리(m)
*/

--------------------------------------------------------------------------------
-- params
--------------------------------------------------------------------------------

-- years
CREATE OR REPLACE TEMP TABLE year AS (
    SELECT year::UINT16 AS gv_year
    FROM UNNEST([{{ year | join(', ') }}]) AS t(year)
);


--------------------------------------------------------------------------------
-- main query
--------------------------------------------------------------------------------

CREATE INDEX chunk_rtree ON chunk USING RTREE(geom);

WITH distance AS (
    SELECT 
        c.id AS id,
        y.gv_year,
        r.is_mr1,
        r.is_mr2,
        ST_Distance(c.geom, r.geom) AS distance,
    FROM chunk c
    CROSS JOIN year y
    LEFT JOIN road r ON c.geom.ST_DWithin(r.geom, 10000) AND y.gv_year = r.year
), distance_road AS (
    SELECT id, gv_year, 'D_Road' AS gv_name, distance.MIN() AS gv_value
    FROM distance
    GROUP BY id, gv_year
), distance_mr1 AS (
    SELECT id, gv_year, 'D_MR1' AS gv_name, distance.MIN() AS gv_value
    FROM distance
    WHERE is_mr1
    GROUP BY id, gv_year
), distance_mr2 AS (
    SELECT id, gv_year, 'D_MR2' AS gv_name, distance.MIN() AS gv_value
    FROM distance
    WHERE is_mr2
    GROUP BY id, gv_year
)
SELECT * FROM distance_road
UNION ALL 
SELECT * FROM distance_mr1
UNION ALL 
SELECT * FROM distance_mr2
;
