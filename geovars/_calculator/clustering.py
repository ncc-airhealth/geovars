from typing import Any

from duckdb import DuckDBPyRelation

from geovars._common import CLUSTER_COL


def cluster_hilbert(rel: DuckDBPyRelation, size: int = 1000):
    query = f"""
    SELECT 
        *, 
        (ROW_NUMBER() OVER ( ORDER BY geom.ST_Hilbert() ))
        .ADD(-1).FDIV({size})::UBIGINT
        AS {CLUSTER_COL}
    FROM temp
    """
    return rel.query("temp", query)

def cluster_kdtree(rel: DuckDBPyRelation, group_size: int):
    raise NotImplementedError

cluster_funcs: dict[str, Any] = {
    "hilbert": cluster_hilbert,
    "kdtree": cluster_kdtree,
}

def get_cluster_func(algorithm: str):
    if algorithm not in cluster_funcs.keys():
        raise ValueError(f"not supported algorithm: `{algorithm}`")
    return cluster_funcs[algorithm]

def cluster_xy(
    rel: DuckDBPyRelation, 
    algorithm: str, 
    **kwargs: dict[str, Any],
) -> DuckDBPyRelation:
    cluster_func = get_cluster_func(algorithm)
    cluster_df = cluster_func(rel=rel, **kwargs)
    return cluster_df