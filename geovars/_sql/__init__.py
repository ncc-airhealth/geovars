"""Package for storing and dynamically loading SQL scripts."""

from pathlib import Path

from jinja2 import Environment, FileSystemLoader, StrictUndefined, Template


SQL_DIR = Path(__file__).parent

env = Environment(
    loader=FileSystemLoader(str(SQL_DIR)),
    undefined=StrictUndefined
)

def get_sql_template(name: str) -> Template:
    """get_sql_template
    TODO: write docstring
    """
    _path = (SQL_DIR / name).with_suffix(".sql")
    if not _path.is_file():
        raise ValueError(f"not supported sql name: `{name}`")
    return env.get_template(f"{name}.sql")

__all__ = [
    "get_sql_template",
]