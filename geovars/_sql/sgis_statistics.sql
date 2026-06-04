/*
주어진 버퍼 영억에서 SGIS 집계구 통계값의 면적 가중 평균
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


-- main query
WITH _output_area AS (
    SELECT tot_reg_cd, geom
    FROM output_area_stat
    WHERE year = 2000
), _overlap_area AS (
    SELECT 
        c.id, 
        o.tot_reg_cd, 
        b.radius, 
        c.geom
            .ST_Buffer(b.radius, quad_segs:=16)
            .ST_Intersection(o.geom)
            .ST_Area()
            AS area
    FROM _chunk c
    CROSS JOIN _buffer b
    LEFT JOIN _output_area o ON ST_DWithin(o.geom, c.geom, b.radius)
), _overlap_weight AS (
    SELECT 
        id, 
        radius, 
        tot_reg_cd, 
        area / SUM(area) OVER (PARTITION BY id, radius) AS weight
    FROM _overlap_area
), _stat_wide AS (
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
        (s.ga * o.weight).SUM() AS GA,
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
    FROM _overlap_weight o
    CROSS JOIN _year y
    LEFT JOIN output_area_stat s ON y.gv_year = s.year AND o.tot_reg_cd = s.tot_reg_cd
    GROUP BY o.id, y.gv_year, o.radius
), _result_long AS (
    UNPIVOT _stat_wide
    ON * EXCLUDE (id, gv_year, radius)
    INTO NAME gv_name VALUE gv_value
), _result AS (
    SELECT
        id,
        gv_year,
        gv_name || '_' || LPAD(radius::VARCHAR, 4, '0') AS gv_name,
        gv_value,
    FROM _result_long
)
SELECT * FROM _result;
