from __future__ import annotations

import multiprocessing as mp
import queue
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterable

import duckdb
import pandas as pd

from .._common import CHUNK_TABLE


SENTINEL = "__SENTINEL__"
SUCCESS = "__SUCCESS__"

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
        """)
        self.result = self.con.sql(self.query).df()
        self.con.unregister(view_name="chunk_df")
        return self


def _worker(
    database: str | Path,
    queue_start: mp.Queue[ChunkQueryTask], 
    queue_done: mp.Queue[ChunkQueryTask]
) -> None:
    con = duckdb.connect(database=database, read_only=True)
    con.execute("""
    SET enable_progress_bar = false;
    SET threads = 1;
    LOAD spatial;
    LOAD h3;
    """)
    # work
    while True:
        try:
            cqt = queue_start.get(timeout=0.1)
            if cqt.status == SENTINEL:
                queue_done.put(cqt)
                break
            else:
                cqt.con = con
                cqt.run()
                cqt.status = SUCCESS
                cqt.con = None
                queue_done.put(obj=cqt)
        except queue.Empty:
            continue
    # close connection
    con.close()
    return

def calculate_chunks(
        tasks: Iterable[ChunkQueryTask], 
        database: str | Path, 
        workers: int
    ):
    """TODO: docstring 추가"""
    # run queue
    mp.set_start_method("spawn", force=True)
    queue_start: mp.Queue[ChunkQueryTask] = mp.Queue()
    queue_done: mp.Queue[ChunkQueryTask] = mp.Queue()
    # spawn workers
    worker_pool: list[Any] = []
    for _ in range(workers):
        kwargs: dict[str, Any] = {
            "database": database,
            "queue_start": queue_start, 
            "queue_done": queue_done,
        }
        p = mp.Process(target=_worker, kwargs=kwargs)
        p.start()
        worker_pool.append(p)
    # add tasks
    for cqt in tasks:
        queue_start.put(obj=cqt)
    for _ in range(workers):
        queue_start.put(obj=ChunkQueryTask(status=SENTINEL))
    # get results
    alive_workers = workers
    while alive_workers > 0:
        cqt = queue_done.get()
        if cqt.status == SENTINEL:
            alive_workers -= 1
            continue
        yield cqt
    # clean
    for p in worker_pool:
        p.join()
    queue_start.close()
    queue_done.close()
