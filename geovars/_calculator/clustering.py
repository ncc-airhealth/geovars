from typing import Any

from duckdb import DuckDBPyRelation

from geovars._common import CLUSTER_COL, Clustering, REFERENCE_CRS


def cluster_xy(
    rel: DuckDBPyRelation, 
    algorithm: str, 
    **kwargs: dict[str, Any],
) -> DuckDBPyRelation:
    cluster_func = get_cluster_func(algorithm)
    cluster_rel = cluster_func(rel=rel, **kwargs)
    return cluster_rel

def get_cluster_func(algorithm: str | Clustering):
    if algorithm not in cluster_funcs.keys():
        raise ValueError(f"not supported algorithm: `{algorithm}`")
    return cluster_funcs[algorithm]

def cluster_hilbert(rel: DuckDBPyRelation, max_size: int = 500) -> DuckDBPyRelation:
    query = f"""
    SELECT 
        *, 
        (ROW_NUMBER() OVER ( ORDER BY geom.ST_Hilbert() ))
        .ADD(-1).FDIV({max_size})::UBIGINT
        AS {CLUSTER_COL}
    FROM temp
    """
    return rel.query("temp", query)

def cluster_h3(
    rel: DuckDBPyRelation, 
    resolution: int = 7, 
    max_size: int = 500,
) -> DuckDBPyRelation:
    query = f"""
    WITH _input_wgs84 AS (
        SELECT *, geom.ST_Transform('{REFERENCE_CRS}', 'EPSG:4326', always_xy:=True) AS _geom
        FROM temp
        ORDER BY geom.ST_Hilbert()
    ), _h3_indexed AS (
        SELECT * EXCLUDE (_geom), h3_latlng_to_cell(_geom.ST_Y(), _geom.ST_X(), {resolution}) AS h3
        FROM _input_wgs84
    ), _numbered AS (
        SELECT *, ROW_NUMBER() OVER (PARTITION BY h3) AS h3n
        FROM _h3_indexed
    ), _chunked AS (
        SELECT * EXCLUDE (h3, h3n), h3::VARCHAR || '-' || (h3n // {max_size})::VARCHAR AS h3c
        FROM _numbered
    ), _clustered AS (
        SELECT *, DENSE_RANK() OVER ( ORDER BY h3c ) AS {CLUSTER_COL}
        FROM _chunked
    )
    SELECT * FROM _clustered
    """
    return rel.query("temp", query)

def cluster_mvt(
    rel: DuckDBPyRelation, 
    resolution: int = 6, 
    max_size: int = 500
) -> DuckDBPyRelation:
    raise NotImplementedError

def cluster_kdtree(rel: DuckDBPyRelation, group_size: int):
    raise NotImplementedError

cluster_funcs: dict[str, Any] = {
    Clustering.HILBERT: cluster_hilbert,
    Clustering.H3: cluster_h3,
    Clustering.MVT: cluster_mvt,
    Clustering.KDTREE: cluster_kdtree,
}

