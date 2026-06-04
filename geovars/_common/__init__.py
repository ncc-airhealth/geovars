"""
TODO: docstring 작성
"""

from enum import StrEnum

RESULT_TABLE = "_result"
REFERENCE_CRS = "EPSG:5179"
CHUNK_TABLE = "_chunk"
INPUT_TABLE = "_input"
CLUSTER_COL = "_cluster_id"
CLUSTER_TABLE = "_cluster"


class Clustering(StrEnum):
    H3 = "h3"
    HILBERT = "hilbert"
    MVT = "mvt"
    KDTREE = "kdtree"


__all__ = [
    "CHUNK_TABLE",
    "CLUSTER_COL",
    "CLUSTER_TABLE",
    "REFERENCE_CRS",
    "RESULT_TABLE",
    "INPUT_TABLE",
]
