/*
주어진 위치가 속한 시군구의 자동차 등록대수
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

CREATE OR REPLACE TEMP TABLE chunk AS (
    SELECT * FROM chunk LIMIT 5
);

CREATE INDEX chunk_rtree ON chunk USING RTREE(geom);

CREATE OR REPLACE TEMP TABLE chunk_buffer AS (
    SELECT c.id, b.radius, c.geom.ST_Buffer(b.radius) AS geom
    FROM chunk c, buffer b
);
CREATE INDEX chunk_buffer_rtree ON chunk_buffer USING RTREE(geom);

CREATE OR REPLACE TEMP TABLE output_area AS (
    SELECT DISTINCT ON (tot_reg_cd, geom) tot_reg_cd, geom
    FROM output_area_stat
);
CREATE INDEX output_area_rtree ON output_area USING RTREE(geom);


WITH overlap_area AS (
    SELECT 
        c.id, 
        c.radius, 
        o.tot_reg_cd, 
        c.geom.ST_Intersection(o.geom).ST_Area() AS area
    FROM chunk_buffer c
    LEFT JOIN output_area o ON ST_Intersects(o.geom, c.geom)
), overlap_weight AS (
    SELECT 
        id, 
        radius, 
        tot_reg_cd, 
        area / SUM(area) OVER (PARTITION BY id, radius) AS weight
    FROM overlap_area
    ORDER BY id, radius, tot_reg_cd
), stat_wide AS (
    SELECT 
        o.id,
        y.gv_year,
        o.radius,
        (s.pop * o.weight).SUM() AS POP,
        (s.pop_m * o.weight).SUM() AS POP_M,
        (s.pop_f * o.weight).SUM() AS POP_F,
        (s.ho_gb_001 * o.weight).SUM() AS H_gb_1,
        (s.ho_gb_002 * o.weight).SUM() AS H_gb_2,
        (s.ho_gb_003 * o.weight).SUM() AS H_gb_3,
        (s.ho_gb_004 * o.weight).SUM() AS H_gb_4,
        (s.ho_gb_005 * o.weight).SUM() AS H_gb_5,
        (s.ho_gb_006 * o.weight).SUM() AS H_gb_6,
        (s.ga * o.weight).SUM() AS ga,
        IF(
            y.gv_year IN [2000, 2005, 2010],
            s.ho_yr_001 + s.ho_yr_002 + s.ho_yr_003,
            s.ho_yr_001
        ).MULTIPLY(o.weight).SUM() AS H_yr_1,
        IF(
            y.gv_year IN [2000, 2005, 2010],
            s.ho_yr_004,
            s.ho_yr_002
        ).MULTIPLY(o.weight).SUM() AS H_yr_2,
        IF(
            y.gv_year IN [2000, 2005, 2010],
            s.ho_yr_005 + s.ho_yr_006,
            s.ho_yr_003
        ).MULTIPLY(o.weight).SUM() AS H_yr_3,
        IF(
            y.gv_year IN [2000, 2005, 2010],
            s.ho_yr_007,
            s.ho_yr_004
        ).MULTIPLY(o.weight).SUM() AS H_yr_4,
        IF(
            y.gv_year IN [2000, 2005, 2010],
            s.ho_yr_008 + s.ho_yr_009 + s.ho_yr_010 + s.ho_yr_011 + s.ho_yr_012,
            s.ho_yr_005
        ).MULTIPLY(o.weight).SUM() AS H_yr_5,
        IF(
            y.gv_year IN [2000, 2005, 2010],
            s.ho_yr_013,
            s.ho_yr_006 + s.ho_yr_007 + s.ho_yr_008 + s.ho_yr_009 + s.ho_yr_010
        ).MULTIPLY(o.weight).SUM() AS H_yr_6,
        IF(
            y.gv_year IN [2000, 2005, 2010],
            0,
            s.ho_yr_011 + s.ho_yr_012 + s.ho_yr_013 + s.ho_yr_014 + s.ho_yr_015
        ).MULTIPLY(o.weight).SUM() AS H_yr_7,
        IF(
            y.gv_year IN [2000, 2005, 2010],
            0,
            s.ho_yr_016
        ).MULTIPLY(o.weight).SUM() AS H_yr_8,
        CASE
            WHEN y.gv_year IN [2000, 2005] THEN (cp_bnu_001 + cp_bnu_002).MULTIPLY(o.weight).SUM()
            WHEN y.gv_year IN [2010, 2015] THEN (cp_bnu_001).MULTIPLY(o.weight).SUM()
            WHEN y.gv_year IN [2020] THEN (cp_bnu_001).MULTIPLY(o.weight).SUM()
            ELSE 0
        END AS bnu_01,
        CASE
            WHEN y.gv_year IN [2000, 2005] THEN (cp_bnu_003 + cp_bnu_004).MULTIPLY(o.weight).SUM()
            WHEN y.gv_year IN [2010, 2015] THEN (cp_bnu_002 + cp_bnu_003).MULTIPLY(o.weight).SUM()
            WHEN y.gv_year IN [2020] THEN (cp_bnu_002 + cp_bnu_003).MULTIPLY(o.weight).SUM()
            ELSE 0
        END AS bnu_02,
        CASE
            WHEN y.gv_year IN [2000, 2005] THEN (cp_bnu_005).MULTIPLY(o.weight).SUM()
            WHEN y.gv_year IN [2010, 2015] THEN (cp_bnu_004 + cp_bnu_005).MULTIPLY(o.weight).SUM()
            WHEN y.gv_year IN [2020] THEN (cp_bnu_004 + cp_bnu_005).MULTIPLY(o.weight).SUM()
            ELSE 0
        END AS bnu_03,
        CASE
            WHEN y.gv_year IN [2000, 2005] THEN (cp_bnu_006).MULTIPLY(o.weight).SUM()
            WHEN y.gv_year IN [2010, 2015] THEN (cp_bnu_006).MULTIPLY(o.weight).SUM()
            WHEN y.gv_year IN [2020] THEN (cp_bnu_006).MULTIPLY(o.weight).SUM()
            ELSE 0
        END AS bnu_04,
        CASE
            WHEN y.gv_year IN [2000, 2005] THEN (cp_bnu_007).MULTIPLY(o.weight).SUM()
            WHEN y.gv_year IN [2010, 2015] THEN (cp_bnu_007).MULTIPLY(o.weight).SUM()
            WHEN y.gv_year IN [2020] THEN (cp_bnu_007).MULTIPLY(o.weight).SUM()
            ELSE 0
        END AS bnu_05,
        CASE
            WHEN y.gv_year IN [2000, 2005] THEN (cp_bnu_009).MULTIPLY(o.weight).SUM()
            WHEN y.gv_year IN [2010, 2015] THEN (cp_bnu_008).MULTIPLY(o.weight).SUM()
            WHEN y.gv_year IN [2020] THEN (cp_bnu_008).MULTIPLY(o.weight).SUM()
            ELSE 0
        END AS bnu_06,
        CASE
            WHEN y.gv_year IN [2000, 2005] THEN (cp_bnu_008).MULTIPLY(o.weight).SUM()
            WHEN y.gv_year IN [2010, 2015] THEN (cp_bnu_009).MULTIPLY(o.weight).SUM()
            WHEN y.gv_year IN [2020] THEN (cp_bnu_009).MULTIPLY(o.weight).SUM()
            ELSE 0
        END AS bnu_07,
        CASE
            WHEN y.gv_year IN [2000, 2005] THEN (cp_bnu_010 + cp_bnu_011 + cp_bnu_013 + cp_bnu_014 + cp_bnu_015 + cp_bnu_016 + cp_bnu_017 + cp_bnu_018).MULTIPLY(o.weight).SUM()
            WHEN y.gv_year IN [2010, 2015] THEN (cp_bnu_010 + cp_bnu_011 + cp_bnu_013 + cp_bnu_014 + cp_bnu_015 + cp_bnu_016 + cp_bnu_017 + cp_bnu_018 + cp_bnu_019).MULTIPLY(o.weight).SUM()
            WHEN y.gv_year IN [2020] THEN (cp_bnu_010 + cp_bnu_011 + cp_bnu_013 + cp_bnu_014 + cp_bnu_015 + cp_bnu_016 + cp_bnu_017 + cp_bnu_018 + cp_bnu_019).MULTIPLY(o.weight).SUM()
            ELSE 0
        END AS bnu_08,
        CASE
            WHEN y.gv_year IN [2000, 2005] THEN (cp_bem_001 + cp_bem_002).MULTIPLY(o.weight).SUM()
            WHEN y.gv_year IN [2010, 2015] THEN (cp_bem_001).MULTIPLY(o.weight).SUM()
            WHEN y.gv_year IN [2020] THEN (cp_bem_001).MULTIPLY(o.weight).SUM()
            ELSE 0
        END AS bem_01,
        CASE
            WHEN y.gv_year IN [2000, 2005] THEN (cp_bem_003 + cp_bem_004).MULTIPLY(o.weight).SUM()
            WHEN y.gv_year IN [2010, 2015] THEN (cp_bem_002 + cp_bem_003).MULTIPLY(o.weight).SUM()
            WHEN y.gv_year IN [2020] THEN (cp_bem_002 + cp_bem_003).MULTIPLY(o.weight).SUM()
            ELSE 0
        END AS bem_02,
        CASE
            WHEN y.gv_year IN [2000, 2005] THEN (cp_bem_005).MULTIPLY(o.weight).SUM()
            WHEN y.gv_year IN [2010, 2015] THEN (cp_bem_004 + cp_bem_005).MULTIPLY(o.weight).SUM()
            WHEN y.gv_year IN [2020] THEN (cp_bem_004 + cp_bem_005).MULTIPLY(o.weight).SUM()
            ELSE 0
        END AS bem_03,
        CASE
            WHEN y.gv_year IN [2000, 2005] THEN (cp_bem_006).MULTIPLY(o.weight).SUM()
            WHEN y.gv_year IN [2010, 2015] THEN (cp_bem_006).MULTIPLY(o.weight).SUM()
            WHEN y.gv_year IN [2020] THEN (cp_bem_006).MULTIPLY(o.weight).SUM()
            ELSE 0
        END AS bem_04,
        CASE
            WHEN y.gv_year IN [2000, 2005] THEN (cp_bem_007).MULTIPLY(o.weight).SUM()
            WHEN y.gv_year IN [2010, 2015] THEN (cp_bem_007).MULTIPLY(o.weight).SUM()
            WHEN y.gv_year IN [2020] THEN (cp_bem_007).MULTIPLY(o.weight).SUM()
            ELSE 0
        END AS bem_05,
        CASE
            WHEN y.gv_year IN [2000, 2005] THEN (cp_bem_009).MULTIPLY(o.weight).SUM()
            WHEN y.gv_year IN [2010, 2015] THEN (cp_bem_008).MULTIPLY(o.weight).SUM()
            WHEN y.gv_year IN [2020] THEN (cp_bem_008).MULTIPLY(o.weight).SUM()
            ELSE 0
        END AS bem_06,
        CASE
            WHEN y.gv_year IN [2000, 2005] THEN (cp_bem_008).MULTIPLY(o.weight).SUM()
            WHEN y.gv_year IN [2010, 2015] THEN (cp_bem_009).MULTIPLY(o.weight).SUM()
            WHEN y.gv_year IN [2020] THEN (cp_bem_009).MULTIPLY(o.weight).SUM()
            ELSE 0
        END AS bem_07,
        CASE
            WHEN y.gv_year IN [2000, 2005] THEN (cp_bem_010 + cp_bem_011 + cp_bem_013 + cp_bem_014 + cp_bem_015 + cp_bem_016 + cp_bem_017 + cp_bem_018).MULTIPLY(o.weight).SUM()
            WHEN y.gv_year IN [2010, 2015] THEN (cp_bem_010 + cp_bem_011 + cp_bem_013 + cp_bem_014 + cp_bem_015 + cp_bem_016 + cp_bem_017 + cp_bem_018 + cp_bem_019).MULTIPLY(o.weight).SUM()
            WHEN y.gv_year IN [2020] THEN (cp_bem_010 + cp_bem_011 + cp_bem_013 + cp_bem_014 + cp_bem_015 + cp_bem_016 + cp_bem_017 + cp_bem_018 + cp_bem_019).MULTIPLY(o.weight).SUM()
            ELSE 0
        END AS bem_08,
    FROM overlap_weight o
    CROSS JOIN year y
    LEFT JOIN output_area_stat s ON y.gv_year = s.year AND o.tot_reg_cd = s.tot_reg_cd
    GROUP BY o.id, y.gv_year, o.radius
), result_long AS (
    UNPIVOT stat_wide
    ON * EXCLUDE (id, gv_year, radius)
    INTO NAME gv_name VALUE gv_value
), result AS (
    SELECT
        id,
        gv_year,
        gv_name || '_' || LPAD(radius::VARCHAR, 4, '0') AS gv_name,
        gv_value,
    FROM result_long
)
SELECT * FROM result;
