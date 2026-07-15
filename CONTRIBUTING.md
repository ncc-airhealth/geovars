# 개발 워크플로우

이 레포는 두 축을 하나로 관리합니다.

- `geovars/` — 지리변수 계산(`Calculator`) + STAC 카탈로그 유틸(`_catalog`) +
  파이프라인 공통 유틸(`_pipeline`)을 담은 파이썬 패키지
- `scripts/geovariable-data-pipeline/<collection-id>/version=<version>/` —
  STAC Collection 단위로 데이터를 수집·가공해 Cloudflare R2에 업로드하는
  PEP 723 스크립트 + `collection.yaml` 메타데이터

의사결정 배경은 [`docs/refactoring-plan.md`](docs/refactoring-plan.md) 참고.

## 의존성 관리: 두 개의 독립된 축

| | 관리 대상 | 도구 | 잠금 파일 |
|---|---|---|---|
| `geovars` 패키지 | duckdb, pandas, pystac 등 | `uv` | `pyproject.toml` / `uv.lock` |
| 시스템 의존성(GDAL/GEOS/PROJ/uv) | Docker 실행 환경 | `pixi` | `pixi.toml` / `pixi.lock` |
| 각 `processing.py` | 그 스크립트만의 파이썬 의존성 | PEP 723 | 스크립트 상단 인라인 (`uv lock --script`로 `.lock` 생성 가능) |

세 번째 축(PEP 723)은 스크립트마다 독립적으로 버전을 고정하므로, 오래된
스크립트를 건드리지 않고도 새 스크립트에서 최신 라이브러리를 바로 쓸 수
있습니다.

## `geovars` 패키지 개발

```bash
uv sync                    # 코어 의존성만
uv sync --extra pipeline   # + boto3, python-dotenv (R2 업로드/`.env` 로딩 쓸 때)
uv run python -c "import geovars"
```

`Calculator`만 쓸 거면 `pipeline` extra는 필요 없습니다.

## 파이프라인 스크립트 실행 (Docker)

시스템 의존성(GDAL/GEOS/PROJ)과 실행 OS를 고정하기 위해 파이프라인
스크립트는 항상 Docker 컨테이너 안에서 실행합니다. 별도 `Dockerfile`은
없고, `docker-compose.yml`에 인라인으로 정의돼 있습니다.

```bash
docker compose build          # pixi.toml/pixi.lock이 바뀌었을 때만 필요
docker compose run --rm pipeline bash
```

컨테이너 안에서 원하는 스크립트로 이동해 실행합니다.

```bash
cd scripts/geovariable-data-pipeline/<collection-id>/version=<version>/
uv run --script processing.py
```

- 리포 전체가 `/app`에 bind mount 되어 있어서, `geovars/`나 `scripts/`를
  고쳐도 **재빌드 없이** 바로 반영됩니다.
- `docker compose build`가 다시 필요한 경우는 `pixi.toml`/`pixi.lock`(즉
  GDAL/GEOS/PROJ/uv 버전)이 바뀌었을 때뿐입니다.
- `docker compose run --rm`은 매번 새 컨테이너를 만들고 끝나면 지웁니다.
  이미지 자체는 캐시되어 재사용되지만, `uv run --script`가 받는 패키지
  다운로드 캐시(`/root/.cache/uv`)는 리포 하위 `cache/uv-cache/`에
  bind mount 해뒀습니다 — 컨테이너가 지워져도 유지되어 두 번째 실행부터는
  같은 의존성을 다시 받지 않습니다. `cache/`는 uv 캐시 외에도 앞으로
  DuckDB temp/spill, S3·httpfs 캐시 등을 한 곳에 모아두는 용도이고
  `.gitignore` 처리되어 있습니다.
- `.env`가 있으면 자동으로 로드되고(`docker-compose.yml`의 `env_file`,
  `required: false`), 없어도 에러 없이 실행됩니다 — 다만 R2 업로드가 필요한
  스크립트는 `.env` 없이는 실패합니다.

## R2 자격 증명

```bash
cp .env.example .env
# R2_ENDPOINT_URL / R2_ACCESS_KEY_ID / R2_SECRET_ACCESS_KEY / R2_BUCKET 채우기
```

`.env`는 `.gitignore` 처리되어 있어 커밋되지 않습니다. `processing.py`에서는
`geovars._pipeline.load_env()`(python-dotenv)로 로드하고,
`geovars._pipeline.upload_file`/`download_file`(boto3)로 R2에 접근합니다.

## 새 collection 추가하기

1. 템플릿을 복사합니다.

   ```bash
   cp -r scripts/geovariable-data-pipeline/_template/version=0.1.0 \
         scripts/geovariable-data-pipeline/<collection-id>/version=<version>
   ```

2. `collection.yaml`을 채웁니다 — `id`, `title`, `description`, `keywords`,
   `providers`, `extent`, `table:columns`, `proj:code`. `assets.*.href`에는
   **R2 object key(절대경로)를 그대로 저장**합니다 (버킷명은 별도 env로
   관리). `processing.py`가 업로드하는 key와 반드시 일치해야 합니다.
3. `processing.py`의 `COLLECTION_ID`/`VERSION`과 `query`를 실제 소스·쿼리로
   바꿉니다.
4. 컨테이너 안에서 `uv run --script processing.py`로 실행해 R2 업로드까지
   확인합니다.

## 카탈로그 조회

`scripts/geovariable-data-pipeline/**/collection.yaml`을 스캔해 검색합니다.
루트 `catalog.json`을 따로 관리하지 않고 항상 그때그때 재생성합니다.

```python
import geovars

geovars.search_catalog("scripts", collection_id="geovariable-input-landcover")
geovars.search_catalog("scripts", keyword="landcover")
geovars.build_catalog("scripts")  # pystac.Catalog
```

## 테스트/CI

`_catalog`/`_pipeline`에 대한 pytest 유닛 테스트와 GitHub Actions workflow는
아직 작성 전입니다 (방향만 확정: push 시 `uv run pytest`). 추가되면 이
섹션에 실행 방법을 기록합니다.
