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

-- overlapping area
CREATE OR REPLACE TEMP TABLE _oa_intersecting_weight AS (
    WITH _output_area_geom AS (
        SELECT DISTINCT ON (tot_reg_cd) tot_reg_cd, geom
        FROM output_area_stat
    )
    SELECT 
        c.id, 
        o.tot_reg_cd, 
        b.radius,
        c.geom
            .ST_Buffer(b.radius, quad_segs:=16)
            .ST_Intersection(o.geom)
            .ST_Area()
            .MULTIPLY(1 / o.geom.ST_Area())
            AS weight,
    FROM _chunk c
    CROSS JOIN _buffer b
    LEFT JOIN _output_area_geom o ON ST_Intersects(c.geom, o.geom)
);

-- statistics
CREATE OR REPLACE TEMP TABLE _result AS (
    WITH _stat_wide AS (
        SELECT
            c.id, 
            y.gv_year,
            c.radius,
            s.pop.multiply(c.weight).SUM()          AS POP,     -- 인구 수
            s.pop_m.multiply(c.weight).SUM()        AS POP_M,   -- 인구 수: 남성
            s.pop_f.multiply(c.weight).SUM()        AS POP_F,   -- 인구 수: 여성
            s.ho_gb_001.multiply(c.weight).SUM()    AS H_gb_1,  -- 주택유형별 주택 수: 다세대
            s.ho_gb_002.multiply(c.weight).SUM()    AS H_gb_2,  -- 주택유형별 주택 수: 단독주택
            s.ho_gb_003.multiply(c.weight).SUM()    AS H_gb_3,  -- 주택유형별 주택 수: 아파트
            s.ho_gb_004.multiply(c.weight).SUM()    AS H_gb_4,  -- 주택유형별 주택 수: 연립주택
            s.ho_gb_005.multiply(c.weight).SUM()    AS H_gb_5,  -- 주택유형별 주택 수: 영업용 건물 내 주택
            s.ho_gb_006.multiply(c.weight).SUM()    AS H_gb_6,  -- 주택유형별 주택 수: 주택 이외의 거처
            s.ga.multiply(c.weight).SUM()           AS GA,      -- 총 가구수
            CASE y.gv_year
                WHEN 2000 THEN ho_yr_001 + ho_yr_002 + ho_yr_003
                WHEN 2005 THEN ho_yr_001 + ho_yr_002 + ho_yr_003
                WHEN 2010 THEN ho_yr_001 + ho_yr_002 + ho_yr_003
                ELSE ho_yr_001
            END .multiply(c.weight).SUM()           AS H_yr_1,  -- 건축년도별 주택: ~1959
            CASE y.gv_year
                WHEN 2000 THEN ho_yr_004
                WHEN 2005 THEN ho_yr_004
                WHEN 2010 THEN ho_yr_004
                ELSE ho_yr_002
            END .multiply(c.weight).SUM()           AS H_yr_2,  -- 건축년도별 주택: 1960~1969
            CASE y.gv_year
                WHEN 2000 THEN ho_yr_005 + ho_yr_006
                WHEN 2005 THEN ho_yr_005 + ho_yr_006
                WHEN 2010 THEN ho_yr_005 + ho_yr_006
                ELSE ho_yr_003
            END .multiply(c.weight).SUM()           AS H_yr_3,  -- 건축년도별 주택: 1970~1979
            CASE y.gv_year
                WHEN 2000 THEN ho_yr_007
                WHEN 2005 THEN ho_yr_007
                WHEN 2010 THEN ho_yr_007
                ELSE ho_yr_004
            END .multiply(c.weight).SUM()           AS H_yr_4,   -- 건축년도별 주택: 1980~1989
            CASE y.gv_year
                WHEN 2000 THEN ho_yr_008 + ho_yr_009 + ho_yr_010 + ho_yr_011 + ho_yr_012
                WHEN 2005 THEN ho_yr_008 + ho_yr_009 + ho_yr_010 + ho_yr_011 + ho_yr_012
                WHEN 2010 THEN ho_yr_008 + ho_yr_009 + ho_yr_010 + ho_yr_011 + ho_yr_012
                ELSE ho_yr_005
            END .multiply(c.weight).SUM()           AS H_yr_5,   -- 건축년도별 주택: 1990~1999
            CASE y.gv_year
                WHEN 2000 THEN ho_yr_013
                WHEN 2005 THEN ho_yr_013
                WHEN 2010 THEN ho_yr_013
                ELSE ho_yr_006 + ho_yr_007 + ho_yr_008 + ho_yr_009 + ho_yr_010
            END .multiply(c.weight).SUM()           AS H_yr_6,   -- 건축년도별 주택: 2000~2009
            CASE y.gv_year
                WHEN 2000 THEN 0
                WHEN 2005 THEN 0
                WHEN 2010 THEN 0
                ELSE ho_yr_011 + ho_yr_012 + ho_yr_013 + ho_yr_014 + ho_yr_015
            END .multiply(c.weight).SUM()           AS H_yr_7,   -- 건축년도별 주택: 2010~2019
            CASE y.gv_year
                WHEN 2000 THEN 0
                WHEN 2005 THEN 0
                WHEN 2010 THEN 0
                ELSE ho_yr_016
            END .multiply(c.weight).SUM()           AS H_yr_8,   -- 건축년도별 주택: 2020~
            CASE y.gv_year
                WHEN 2000 THEN cp_bnu_001 + cp_bnu_002
                WHEN 2005 THEN cp_bnu_001 + cp_bnu_002
                ELSE cp_bnu_001
            END .multiply(c.weight).SUM()           AS B_bnu_1,  -- 산업분류별 사업체수: 농업,임업,어업
            CASE y.gv_year
                WHEN 2000 THEN cp_bnu_003 + cp_bnu_004
                WHEN 2005 THEN cp_bnu_003 + cp_bnu_004
                ELSE cp_bnu_002 + cp_bnu_003
            END .multiply(c.weight).SUM()           AS B_bnu_2,  -- 산업분류별 사업체수: 광업 및 제조업
            CASE y.gv_year
                WHEN 2000 THEN cp_bnu_005
                WHEN 2005 THEN cp_bnu_005
                ELSE cp_bnu_004 + cp_bnu_005
            END .multiply(c.weight).SUM()           AS B_bnu_3,  -- 산업분류별 사업체수: 전기,가스,수도사업 등
            s.cp_bnu_006.multiply(c.weight).SUM()   AS B_bnu_4,  -- 산업분류별 사업체수: 건설업
            s.cp_bnu_007.multiply(c.weight).SUM()   AS B_bnu_5,  -- 산업분류별 사업체수: 도매 및 소매업
            CASE y.gv_year
                WHEN 2000 THEN cp_bnu_009
                WHEN 2005 THEN cp_bnu_009
                ELSE cp_bnu_008
            END .multiply(c.weight).SUM()           AS B_bnu_6,  -- 산업분류별 사업체수: 운수업
            CASE y.gv_year
                WHEN 2000 THEN cp_bnu_008
                WHEN 2005 THEN cp_bnu_008
                ELSE cp_bnu_009
            END .multiply(c.weight).SUM()           AS B_bnu_7,  -- 산업분류별 사업체수: 숙박 및 음식점업
            CASE y.gv_year
                WHEN 2000 THEN cp_bnu_010 + cp_bnu_011 + cp_bnu_013 + cp_bnu_014 + cp_bnu_015 + cp_bnu_016 + cp_bnu_017 + cp_bnu_018
                WHEN 2005 THEN cp_bnu_010 + cp_bnu_011 + cp_bnu_013 + cp_bnu_014 + cp_bnu_015 + cp_bnu_016 + cp_bnu_017 + cp_bnu_018
                ELSE cp_bnu_010 + cp_bnu_011 + cp_bnu_013 + cp_bnu_014 + cp_bnu_015 + cp_bnu_016 + cp_bnu_017 + cp_bnu_018 + cp_bnu_019
            END .multiply(c.weight).SUM()           AS B_bnu_8,  -- 산업분류별 사업체수: 금융 및 기타 산업
            CASE y.gv_year
                WHEN 2000 THEN cp_bem_001 + cp_bem_002
                WHEN 2005 THEN cp_bem_001 + cp_bem_002
                ELSE cp_bem_001
            END .multiply(c.weight).SUM()           AS B_bem_1,  -- 산업분류별 종사자수: 농업,임업,어업
            CASE y.gv_year
                WHEN 2000 THEN cp_bem_003 + cp_bem_004
                WHEN 2005 THEN cp_bem_003 + cp_bem_004
                ELSE cp_bem_002 + cp_bem_003
            END .multiply(c.weight).SUM()           AS B_bem_2,  -- 산업분류별 종사자수: 광업 및 제조업
            CASE y.gv_year
                WHEN 2000 THEN cp_bem_005
                WHEN 2005 THEN cp_bem_005
                ELSE cp_bem_004 + cp_bem_005
            END .multiply(c.weight).SUM()           AS B_bem_3,  -- 산업분류별 종사자수: 전기,가스,수도사업 등
            s.cp_bem_006.multiply(c.weight).SUM()   AS B_bem_4,  -- 산업분류별 종사자수: 건설업
            s.cp_bem_007.multiply(c.weight).SUM()   AS B_bem_5,  -- 산업분류별 종사자수: 도매 및 소매업
            CASE y.gv_year
                WHEN 2000 THEN cp_bem_009
                WHEN 2005 THEN cp_bem_009
                ELSE cp_bem_008
            END .multiply(c.weight).SUM()           AS B_bem_6,  -- 산업분류별 종사자수: 운수업
            CASE y.gv_year
                WHEN 2000 THEN cp_bem_008
                WHEN 2005 THEN cp_bem_008
                ELSE cp_bem_009
            END .multiply(c.weight).SUM()           AS B_bem_7,  -- 산업분류별 종사자수: 숙박 및 음식점업
            CASE y.gv_year
                WHEN 2000 THEN cp_bem_010 + cp_bem_011 + cp_bem_013 + cp_bem_014 + cp_bem_015 + cp_bem_016 + cp_bem_017 + cp_bem_018
                WHEN 2005 THEN cp_bem_010 + cp_bem_011 + cp_bem_013 + cp_bem_014 + cp_bem_015 + cp_bem_016 + cp_bem_017 + cp_bem_018
                ELSE cp_bem_010 + cp_bem_011 + cp_bem_013 + cp_bem_014 + cp_bem_015 + cp_bem_016 + cp_bem_017 + cp_bem_018 + cp_bem_019
            END .multiply(c.weight).SUM()           AS B_bem_8,  -- 산업분류별 종사자수: 금융 및 기타 산업
        FROM _oa_intersecting_weight c
        CROSS JOIN _year y
        LEFT JOIN output_area_stat s 
            ON y.gv_year = s.year AND c.tot_reg_cd = s.tot_reg_cd
        GROUP BY c.id, y.gv_year, c.radius
    )
    SELECT
        id,
        gv_year,
        gv_prefix || '_' || LPAD(radius::VARCHAR, 4, '0') AS gv_name,
        gv_value,
    FROM (
        UNPIVOT _stat_wide
        ON * EXCLUDE (id, gv_year, radius)
        INTO NAME gv_prefix VALUE gv_value
    )
);

-- clean cache
DROP TABLE IF EXISTS _oa_intersecting_weight;

SELECT * FROM _result;
