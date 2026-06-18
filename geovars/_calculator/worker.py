from __future__ import annotations

import atexit
import multiprocessing as mp
from dataclasses import dataclass, field
from typing import Iterable

import duckdb
import pandas as pd

from .._common import CHUNK_TABLE, ConnectionConfig
from .database import connect_database


SUCCESS = "__SUCCESS__"
_WORKER_CON: duckdb.DuckDBPyConnection | None = None


@dataclass
class ChunkQueryTask:
    """TODO: docstiring 작성"""
    con: duckdb.DuckDBPyConnection | None = None
    query: str = ""
    chunk: pd.DataFrame = field(default_factory=pd.DataFrame)
    result: pd.DataFrame = field(default_factory=pd.DataFrame)
    status: str = ""

    def run(self) -> ChunkQueryTask:
        assert self.con, "connection must be defined"
        assert self.query, "query must be defined"
        self.con.register(
            view_name="chunk_df", 
            python_object=self.chunk,
        )
        self.con.execute(f"""
        CREATE OR REPLACE TEMP TABLE {CHUNK_TABLE} AS (
            SELECT id, geom.ST_GeomFromWKB() AS geom
            FROM chunk_df
        );
        CREATE INDEX _{CHUNK_TABLE}_rtree ON {CHUNK_TABLE} USING RTREE(geom);
        """)
        self.result = self.con.sql(self.query).df()
        self.con.unregister(view_name="chunk_df")
        return self


def _close_worker_connection() -> None:
    global _WORKER_CON
    if _WORKER_CON is not None:
        _WORKER_CON.close()
        _WORKER_CON = None


def _init_pool_worker(connection_config: ConnectionConfig) -> None:
    global _WORKER_CON
    # Reused within one child process until Pool maxtasksperchild recycles it.
    _WORKER_CON = connect_database(connection_config)
    atexit.register(_close_worker_connection)


def _run_pool_task(cqt: ChunkQueryTask) -> ChunkQueryTask:
    if _WORKER_CON is None:
        raise RuntimeError("worker connection is not initialized")
    cqt.con = _WORKER_CON
    cqt.run()
    cqt.status = SUCCESS
    cqt.con = None
    return cqt


def calculate_chunks(
        tasks: Iterable[ChunkQueryTask],
        workers: int,
        connection_config: ConnectionConfig,
        max_tasks_per_worker: int | None = 50,
    ):
    """TODO: docstring 추가"""
    if workers < 1:
        raise ValueError("workers must be greater than 0")
    if max_tasks_per_worker is not None and max_tasks_per_worker < 1:
        raise ValueError("max_tasks_per_worker must be greater than 0")

    context = mp.get_context("spawn")
    with context.Pool(
        processes=workers,
        initializer=_init_pool_worker,
        initargs=(connection_config,),
        maxtasksperchild=max_tasks_per_worker,
    ) as pool:
        for cqt in pool.imap_unordered(_run_pool_task, tasks, chunksize=1):
            yield cqt
