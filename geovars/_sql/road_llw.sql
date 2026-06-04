/*
주어진 위치로부터 버퍼영역 이내의 도로 연장과 폭과 관련된 정보
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

-- aoi data filtering
CREATE OR REPLACE TEMP TABLE _aoi_road AS (
    WITH _chunk_merged AS (
        SELECT geom.ST_Union_Agg() AS geom FROM _chunk 
    )
    SELECT r.year, r.is_mr1, r.is_mr2, r.lanes, r.width, r.geom
    FROM _chunk_merged c
    CROSS JOIN _year y
    LEFT JOIN road r ON y.gv_year = r.year AND ST_DWithin(r.geom, c.geom, 5_000)
);
CREATE INDEX _rtree_aoi_road
ON _aoi_road
USING RTREE(geom) WITH (max_node_capacity = 8);

-- main query
WITH _overlap AS (
    SELECT
        c.id,
        y.gv_year,
        b.radius,
        t.lanes,
        t.width,
        t.is_mr1, 
        t.is_mr2,
        c.geom.ST_Buffer(b.radius).ST_Intersection(t.geom).ST_Length() AS L
    FROM _chunk c
    CROSS JOIN _year y
    CROSS JOIN _buffer b
    LEFT JOIN _aoi_road t ON y.gv_year = t.year AND ST_DWithin(c.geom, t.geom, b.radius)
), _result_wide AS (
    SELECT
        id,
        gv_year,
        radius,
        IFNULL( (L).SUM(), -1 ) AS Road_L,
        IFNULL( (L * lanes).SUM(), -1 ) AS Road_LL,
        IFNULL( (L * lanes * width).SUM(), -1 ) AS Road_LLW,
        IFNULL( (L * is_mr1::INT).SUM(), -1 ) AS MR1_L,
        IFNULL( (L * lanes * is_mr1::INT).SUM(), -1 ) AS MR1_LL,
        IFNULL( (L * lanes * width * is_mr1::INT).SUM(), -1 ) AS MR1_LLW,
        IFNULL( (L * is_mr2::INT).SUM(), -1 ) AS MR2_L,
        IFNULL( (L * lanes * is_mr2::INT).SUM(), -1 ) AS MR2_LL,
        IFNULL( (L * lanes * width * is_mr2::INT).SUM(), -1 ) AS MR2_LLW,
    FROM _overlap
    GROUP BY id, gv_year, radius
), _result_long AS (
    UNPIVOT _result_wide
    ON Road_L, Road_LL, Road_LLW, MR1_L, MR1_LL, MR1_LLW, MR2_L, MR2_LL, MR2_LLW
    INTO NAME gv_name VALUE gv_value
), _result AS (
    SELECT
        id,
        gv_year,
        gv_name || '_' || LPAD(radius::VARCHAR, 4, '0') AS gv_name,
        IF(gv_value = -1, NULL, gv_value) AS gv_value,
    FROM _result_long
)
SELECT * FROM _result
;