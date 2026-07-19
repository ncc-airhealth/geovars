# /// script
# requires-python = ">=3.12"
# dependencies = [
#   "geovars",
#   "httpx==0.28.1",
#   "pystac==1.15.1",
# ]
#
# [tool.uv.sources]
# geovars = { path = "..", editable = true }
# ///

from __future__ import annotations

import zipfile
from pathlib import Path
from io import BytesIO

import httpx
import geovars as gv


SRC_URL = "https://sgis.mods.go.kr/contents/include/download.jsp?filename=ref_code.zip&path=/board/&type=board"


class Processor(gv.CollectionProcessor):
    collection = "sgis-code-manual"
    version = "3.0.1"
    description = f"""
    SGIS에서 제공하는 코드표 및 이용설명서.
    
    # 수동 획득 방법
    SGIS 홈페이지 (https://sgis.mods.go.kr/view/index)
     → 자료제공 (https://sgis.mods.go.kr/view/pss/dataProvdIntrcn)
     → 신청자료 다운로드 (https://sgis.mods.go.kr/view/pss/downloadList)
     → 코드표 및 이용설명서 (https://sgis.mods.go.kr/contents/include/download.jsp?filename=ref_code.zip&path=/board/&type=board)
     → 다운로드 후 압축 해제
    """

    @classmethod
    def run(cls) -> None:
        p = cls()
        p.download_source()
        p.save_metadata()
        p.upload_assets()
    
    def download_source(self) -> None:
        """Download the source file from the URL and extract it to the collection asset directory."""
        local_dir = self.collection_asset_dir(mode="local", mkdir=True)

        with httpx.Client() as client:
            resp = client.get(SRC_URL)
            resp.raise_for_status()
            buffer = BytesIO(resp.content)
        
        with zipfile.ZipFile(buffer, "r") as zf:
            zf.extractall(self.collection_asset_dir)
        
        for asset_path in local_dir.rglob("*"):
            self.assets.append(asset_path)
    
    def upload_assets(self) -> None:
        """Upload the assets to the collection asset directory."""
        for asset in self.assets:
            asset.upload()


if __name__ == "__main__":
    Processor.run()
