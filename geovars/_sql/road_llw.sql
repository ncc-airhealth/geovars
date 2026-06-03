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

-- buffer
CREATE OR REPLACE TEMP TABLE buffer AS (
    SELECT radius::UINT16 AS radius
    FROM UNNEST([{{ buffer | join(', ') }}]) AS t(radius)
);

--------------------------------------------------------------------------------
-- main query
--------------------------------------------------------------------------------

CREATE INDEX chunk_rtree ON chunk USING RTREE(geom);

CREATE OR REPLACE TEMP TABLE aoi_road AS (
    WITH chunk_merged AS (
        SELECT geom.ST_Union_Agg() AS geom FROM chunk 
    )
    SELECT r.year, r.is_mr1, r.is_mr2, r.lanes, r.width, r.geom
    FROM chunk_merged c
    CROSS JOIN year y
    LEFT JOIN road r ON y.gv_year = r.year AND ST_DWithin(r.geom, c.geom, 5000)
);
CREATE INDEX rtree_aoi_road
ON aoi_road
USING RTREE(geom);

WITH overlap AS (
    SELECT
        c.id,
        y.gv_year,
        b.radius,
        t.lanes,
        t.width,
        t.is_mr1, 
        t.is_mr2,
        c.geom.ST_Buffer(b.radius).ST_Intersection(t.geom).ST_Length() AS L
    FROM chunk c
    CROSS JOIN year y
    CROSS JOIN buffer b
    LEFT JOIN aoi_road t ON y.gv_year = t.year AND ST_DWithin(c.geom, t.geom, b.radius)
), result_wide AS (
    SELECT
        id,
        gv_year,
        radius,
        IFNULL((L).SUM(), -1) AS Road_L,
        IFNULL((L * lanes).SUM(), -1) AS Road_LL,
        IFNULL((L * lanes * width).SUM(), -1) AS Road_LLW,
        IFNULL((L * is_mr1::INT).SUM(), -1) AS MR1_L,
        IFNULL((L * lanes * is_mr1::INT).SUM(), -1) AS MR1_LL,
        IFNULL((L * lanes * width * is_mr1::INT).SUM(), -1) AS MR1_LLW,
        IFNULL((L * is_mr2::INT).SUM(), -1) AS MR2_L,
        IFNULL((L * lanes * is_mr2::INT).SUM(), -1) AS MR2_LL,
        IFNULL((L * lanes * width * is_mr2::INT).SUM(), -1) AS MR2_LLW,
    FROM overlap
    GROUP BY id, gv_year, radius
), result_long AS (
    UNPIVOT result_wide
    ON Road_L, Road_LL, Road_LLW, MR1_L, MR1_LL, MR1_LLW, MR2_L, MR2_LL, MR2_LLW
    INTO NAME gv_name VALUE gv_value
), result AS (
    SELECT
        id,
        gv_year,
        gv_name || '_' || LPAD(radius::VARCHAR, 4, '0') AS gv_name,
        IF(gv_value = -1, NULL, gv_value) AS gv_value,
    FROM result_long
)
SELECT * FROM result
;