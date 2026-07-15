from __future__ import annotations

from abc import ABC, abstractmethod
from datetime import datetime
from typing import Any, Iterable, TYPE_CHECKING

from pystac import Asset, Collection, Extent, Item, SpatialExtent, TemporalExtent

from geovars._stac.root import root_catalog

class CollectionProcessor(ABC):
    collection_id: str
    version: str
    description: str
    title: str = None
    keywords: Iterable[str] = None
    spatial_bboxes: list[list[float]]
    temporal_intervals: list[list[datetime | None]]
    license: str = None
    providers: Iterable[Provider] = None
    extra_fields: dict[str, Any] = None
    _collection: Collection = None


    @classmethod
    def run(cls) -> None:
        cls.download_source()
        cls.save_metadata()
        cls.upload_assets()

    @property
    def collection(self) -> Collection:
        if self._collection is not None:
            return self._collection
        
        _collection = Collection(
            id=self.collection_id,
            title=self.title or self.collection_id,
            description=self.description,
            extent=Extent(
                spatial=SpatialExtent(bboxes=self.spatial_bboxes),
                temporal=TemporalExtent(intervals=self.temporal_intervals),
            ),
            license=self.license,
            providers=self.providers,
            extra_fields=self.extra_fields,
        )
        _collection.ext.add("version")
        version_ext.apply(
            version=self.version,
            deprecated=False,
        )
        
        root_catalog.add_child(_collection)
        _collection.validate()
        self._collection = _collection
        return self._collection
    