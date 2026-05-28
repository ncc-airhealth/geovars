from __future__ import annotations

from dataclasses import dataclass
from os import PathLike
from typing import Any

import duckdb
import pandas as pd
from duckdb import DuckDBPyConnection, DuckDBPyRelation
from tqdm import tqdm

from .clustering import cluster_xy
from geovars._common import (
    CHUNK_TABLE,
    CLUSTER_TABLE,
    CLUSTER_COL,
    INPUT_TABLE,
    RESULT_TABLE,
    REFERENCE_CRS,
)
from geovars._sql import get_sql_template
from .worker import calculate_chunks, ChunkQueryTask


@dataclass
class Calculator:
    """
    TODO: write docstring
    """
    database: PathLike[str]
    memory_limit: str = "8GB"
    workers: int = 1
    _con: None | DuckDBPyConnection = None

    def calc(self, group: str, **kwargs: dict[str, Any]) -> Calculator:
        """TODO: write docstring"""
        # prepare
        query_template = get_sql_template(name=group)
        query = query_template.render(**kwargs)
        pbar = tqdm(total=self._input_count, desc=group)
        # add task
        tasks = [
            ChunkQueryTask(query=query, chunk=chunk_df)
            for chunk_df in self._iter_chunks()
        ]
        for cqt in calculate_chunks(tasks, workers=self.workers):
            self.con.from_df(cqt.result).insert_into(RESULT_TABLE)
            pbar.update(cqt.chunk.shape[0])
        return self
    
    def safe_calc(self, group: str, **kwargs: dict[str, Any]) -> Calculator:
        """TODO: write docstring"""
        # prepare
        query_template = get_sql_template(name=group)
        query = query_template.render(**kwargs)
        pbar = tqdm(total=self._input_count, desc=group)
        # calculate
        for chunk_df in self._iter_chunks():
            cqt = ChunkQueryTask(
                con=self.con, 
                query=query, 
                chunk=chunk_df,
            ).run()
            self.con.from_df(cqt.result).insert_into(RESULT_TABLE)
            pbar.update(chunk_df.shape[0])
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
        return self
    
    def cluster(self, algorithm: str, **kwargs: dict[str, Any]) -> Calculator:
        """TODO: write docstring"""
        cluster_df = cluster_xy(
            rel=self.con.table(INPUT_TABLE),
            algorithm=algorithm,
            **kwargs,
        )
        self.con.register(view_name=CLUSTER_TABLE, python_object=cluster_df)
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
    
    def _iter_chunks(self):
        """TODO: write docstring"""
        id_sql = f"""
        SELECT DISTINCT {CLUSTER_COL} 
        FROM {CLUSTER_TABLE} 
        ORDER BY {CLUSTER_COL}
        """
        chunk_sql = f"""
        SELECT id, geom
        FROM {CLUSTER_TABLE}
        WHERE {CLUSTER_COL} = {{cid}}
        """
        # iter clusters
        for r in self.con.sql(id_sql).fetchall():
            query = chunk_sql.format(cid=r[0])
            yield self.con.sql(query).df()
    
    @property
    def con(self) -> DuckDBPyConnection:
        """con
        TODO: implement this method
        """
        if self._con is None:
            self._con = duckdb.connect()
            self._con.execute(self._init_query)
        return self._con
    
    @property
    def _init_query(self) -> str:
        """TODO: write docstring"""
        return f"""
        INSTALL spatial;
        LOAD spatial;
        CREATE TEMP TABLE {RESULT_TABLE} (
            id         VARCHAR,
            gv_year    UINT16,
            gv_name    VARCHAR,
            gv_value   DOUBLE
        );
        """
    
    @property
    def _input_count(self) -> int:
        """TODO: write docstring"""
        return self.con.table(CLUSTER_TABLE).shape[0]
