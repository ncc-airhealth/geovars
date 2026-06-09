"""
TODO: docstring 작성
"""

from dataclasses import dataclass
from enum import StrEnum
from os import PathLike

RESULT_TABLE = "_result"
REFERENCE_CRS = "EPSG:5179"
CHUNK_TABLE = "_chunk"
INPUT_TABLE = "_input"
CLUSTER_COL = "_cluster_id"
CLUSTER_TABLE = "_cluster"

@dataclass(frozen=True)
class ConnectionConfig:
    database: PathLike
    cache_dir: PathLike = ".geovars_cache/"
    memory_limit: str = "6GB"
    read_only: bool = True


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
