from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any
from uuid import uuid4

import duckdb
import pandas as pd
from duckdb import DuckDBPyConnection, DuckDBPyRelation
from tqdm import tqdm

from .clustering import cluster_xy
from geovars._common import (
    CLUSTER_TABLE,
    Clustering,
    CLUSTER_COL,
    ConnectionConfig,
    INPUT_TABLE,
    RESULT_TABLE,
    REFERENCE_CRS,
)
from geovars._sql import get_sql_template
from .database import connect_database
from .worker import calculate_chunks, ChunkQueryTask


@dataclass
class Calculator:
    """
    TODO: write docstring
    """
    database: str | Path
    memory_limit: str = "5GB"
    cache_dir: str | Path = ".cache/"
    workers: int = 1
    clustering: Clustering = Clustering.H3
    cluster_kwargs: dict[str, Any] = field(default_factory=dict)
    worker_max_tasks: int | None = 50
    _con: None | DuckDBPyConnection = None
    _chunk_dfs: list[pd.DataFrame] | None = None

    def calc(self, group: str, **kwargs: dict[str, Any]) -> Calculator:
        """TODO: write docstring"""
        # prepare
        query_template = get_sql_template(name=group)
        query = query_template.render(**kwargs)
        pbar = tqdm(total=self._input_count, desc=group)
        # add task
        tasks = (
            ChunkQueryTask(query=query, chunk=chunk_df)
            for chunk_df in self.chunk_dfs
        )
        for cqt in calculate_chunks(
            tasks=tasks, 
            workers=self.workers,
            connection_config=self._connection_config,
            max_tasks_per_worker=self.worker_max_tasks,
        ):
            self.con.from_df(cqt.result).insert_into(RESULT_TABLE)
            pbar.update(cqt.chunk.shape[0])
        return self
    
    def safe_calc(self, group: str, **kwargs: dict[str, Any]) -> Calculator:
        """TODO: write docstring"""
        # prepare
        query_template = get_sql_template(name=group)
        query = query_template.render(**kwargs)
        pbar = tqdm(total=self._input_count, desc=group)
        con = connect_database(self._connection_config)
        # calculate
        for chunk_df in self.chunk_dfs:
            cqt = ChunkQueryTask(
                con=con, 
                query=query, 
                chunk=chunk_df,
            ).run()
            self.con.from_df(cqt.result).insert_into(RESULT_TABLE)
            pbar.update(chunk_df.shape[0])
        con.close()
        return self
    
    def test_calc(self, group: str, **kwargs: dict[str, Any]) -> Calculator:
        """TODO: write docstring"""
        # prepare
        query_template = get_sql_template(name=group)
        query = query_template.render(**kwargs)
        con = connect_database(self._connection_config)
        # calculate
        for chunk_df in self.chunk_dfs:
            cqt = ChunkQueryTask(
                con=con, 
                query=query, 
                chunk=chunk_df,
            ).run()
            rel = self.con.from_df(cqt.result).execute()
            print(rel)
            print(rel.df().iloc[0, 1])
            raise Exception("STOP")
        con.close()
        return self

    def set_input(
            self, 
            tbl: pd.DataFrame | DuckDBPyRelation,
            pk: str = "pid",
            x: str = "x",
            y: str = "y",
            crs: str = "EPSG:4326",
        ):
        """TODO: write docstring"""
        self.input_pk = pk
        self.input_x = x
        self.input_y = y
        self.input_crs = crs
        if isinstance(tbl, DuckDBPyRelation):
            tbl = tbl.df()
        self.con.register(view_name="temp", python_object=tbl)
        self.con.execute(f"""
        CREATE TEMP TABLE {INPUT_TABLE} AS (
            SELECT 
                {pk} AS id, 
                ST_Point({x}, {y})
                    .ST_Transform('{crs}', '{REFERENCE_CRS}', always_xy:=true)
                    AS geom
            FROM 
                temp
        );
        """)
        self.con.unregister("temp")
        self._cluster()
        return self
    
    def _cluster(self) -> Calculator:
        """TODO: write docstring"""
        cluster_rel = cluster_xy(
            rel=self.con.table(INPUT_TABLE),
            algorithm=self.clustering,
            **self.cluster_kwargs,
        )
        self.con.register(view_name=CLUSTER_TABLE, python_object=cluster_rel)
        return self
    
    def df(self, as_wide: bool=False):
        """TODO: write docstring"""
        if not as_wide:
            return self.con.table(RESULT_TABLE).df()
        return self.con.sql(f"""
        PIVOT {RESULT_TABLE}
        ON gv_name
        USING FIRST(gv_value)
        """).df()
    
    @property
    def chunk_dfs(self) -> list[pd.DataFrame]:
        if self._chunk_dfs is None:
            self._chunk_dfs = []
            df = self.con.table(CLUSTER_TABLE).df()
            for _, cdf in df.groupby(CLUSTER_COL):
                self._chunk_dfs.append(cdf)
        return self._chunk_dfs
    
    @property
    def con(self) -> DuckDBPyConnection:
        """con
        TODO: implement this method
        """
        if self._con is None:
            config = ConnectionConfig(
                database=":memory:",
                cache_dir=self.cache_dir, 
                memory_limit=self.memory_limit,
                read_only=False,
            )
            self._con = connect_database(config)
        return self._con
    
    @property
    def _connection_config(self) -> ConnectionConfig:
        return ConnectionConfig(
            database=self.database,
            cache_dir=self.cache_dir, 
            memory_limit=self.memory_limit,
        )

    @property
    def _input_count(self) -> int:
        """TODO: write docstring"""
        return self.con.table(CLUSTER_TABLE).shape[0]
