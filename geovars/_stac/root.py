from pathlib import Path

from pystac import Catalog
from pystac.catalog import CatalogType
from pystac.layout import TemplateLayoutStrategy
from textwrap import dedent

CATALOG_ID = "geovariable-data-pipeline"
CATALOG_DESCRIPTION = "Geovariable data pipeline catalog."
CATALOG_ROOT_DIR = Path(__file__).parent.parent / "_stac_metadata"
HREF_STRATEGY = TemplateLayoutStrategy(
    collection_template="collections/${version}/${id}",
    item_template="items/${id}",
)


root_catalog = Catalog(
    id=CATALOG_ID,
    description=CATALOG_DESCRIPTION,
    catalog_type=CatalogType.SELF_CONTAINED,
    strategy=HREF_STRATEGY,
    href=CATALOG_ROOT_DIR / f"{CATALOG_ID}.json",
)

if __name__ == "__main__":
    root_catalog.save()  # save to the catalog root directory