from pathlib import Path
from uuid import uuid4

import duckdb
from duckdb import DuckDBPyConnection

from geovars._common import ConnectionConfig, RESULT_TABLE

def connect_database(config: ConnectionConfig) -> DuckDBPyConnection:
    con = duckdb.connect(config.database, read_only=config.read_only)
    cache_path = Path(config.cache_dir) / uuid4().hex
    cache_path.mkdir(exist_ok=True, parents=True)
    con.execute(f"""
    SET enable_progress_bar = false;
    SET threads = 1;
    SET memory_limit = '{config.memory_limit}';
    SET temp_directory = '{cache_path}';
    INSTALL spatial; LOAD spatial;
    INSTALL h3 FROM community; LOAD h3;
    CREATE TEMP TABLE {RESULT_TABLE} (
        id         VARCHAR,
        gv_year    UINT16,
        gv_name    VARCHAR,
        gv_value   DOUBLE
    );
    """)
    return con
