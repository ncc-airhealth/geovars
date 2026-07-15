# 리팩토링 계획: geovars → 데이터 파이프라인 운영 레포

- 브랜치: `refactor/pipeline-catalog`
- 작성일: 2026-07-15

## 배경 (Context)

`geovars`는 현재 "입력 포인트 + 참조 DB → 변수 계산"만 담당하는 라이브러리다
(`Calculator`, `_sql` 계산 그룹, clustering, worker 등).

이와 별개로 `/Users/hus/Library/CloudStorage/Dropbox/패밀리룸/data-pipeline-stac`
(Dropbox 데스크톱 앱으로 로컬 마운트된 경로)에 원본·가공 데이터를 STAC
Catalog/Collection/Item/Asset 구조로 관리해온 별도 저장소가 있다 (185GB, YAML
기반 메타데이터 + `processing.py`). 이 리팩토링은 **이 두 축을 하나의 git
레포로 통합**하는 작업이다.

### 왜 이 작업을 하는가

- `<데이터 파이프라인> + <지리변수 계산>` 프로젝트를 하나의 레포에서 관리
- 이 레포를 **source of truth**로 사용
- 다른 사람이 오더라도 데이터·파이프라인·변수계산의 전체 맥락(코드, 의존성,
  메타데이터)을 이 레포만으로 파악·재현 가능하게 함
- 의존성과 실행 환경을 엄격히 고정하여 **재현성**을 확보

### 기존 `data-pipeline-stac`에서 이어받는 컨벤션

- 계층: `Catalog` → `Collection`(같은 성격의 데이터셋 묶음) → `Item`(시점·위치
  단위) → `Asset`(실제 파일)
- 버전 경로: `<collection-id>/version=<version>/` (semantic version 또는
  `YYYY.MM.DD`), 버전이 바뀌면 기존 폴더를 덮어쓰지 않고 새 버전 경로 생성
- 메타데이터: `collection.yaml` — STAC 1.1.0 Collection 스키마를 따르는 YAML
  (id, title, description, providers, extent, assets, table:columns,
  proj:code 등)
- 처리 코드: `processing.py` — 이미 **PEP 723 인라인 스크립트 메타데이터**로
  의존성을 선언하고 `uv run python .../processing.py`로 실행하는 방식이 정착돼
  있음 (필요 시 `uv lock --script`로 `processing.py.lock` 생성). 이번
  리팩토링에서 이 패턴을 새로 도입하는 게 아니라 이 레포로 그대로 옮겨오는 것
- 기존에는 `<catalog-id>/<collection-id>/version=<version>/` 아래 데이터
  파일까지 함께 보관했으나(Dropbox), 앞으로는 데이터 파일만 오브젝트
  스토리지로 옮기고 코드·메타데이터는 git으로 관리

## 목표 아키텍처

### 스토리지 정책

- 데이터(무거운 asset 파일)는 **Cloudflare R2**(S3 호환 오브젝트 스토리지)로
  이전
- STAC 메타데이터(`collection.yaml` 등)는 Dropbox가 아니라 **이 git 레포에서
  직접 버전 관리**
- 카탈로그 구조는 기존의 `catalog-id` 다단계 구성(`_data`, `analysis-ready`,
  `source`, `v2-data`, `geovariable` 등 여러 개)을 없애고, **단일 catalog-id
  하나로 고정**한다. 즉 카탈로그가 완전히 없어지는 게 아니라 이름이 하나로
  통일되고, 그 아래 모든 Collection이 바로 위치 (카탈로그의 카탈로그는 없음)
- 이 고정된 catalog-id는 git의 `scripts/` 폴더 구조와 R2 버킷의 객체 키
  레이아웃에 동일하게 등장하는 **네임스페이스 prefix** 역할을 한다

### `scripts/` (catalog-id / collection / version 단위)

기존 `data-pipeline-stac`의 `<catalog-id>/<collection-id>/version=<version>/`
배치를 그대로 이어받아, 하나의 디렉터리에 코드·메타데이터를 함께 둔다:

```
scripts/
└── <catalog-id>/              # 고정값 하나 (단일 카탈로그)
    └── <collection-id>/
        └── version=<version>/
            ├── collection.yaml       # STAC Collection 메타데이터 (git 관리)
            ├── processing.py         # PEP 723 인라인 의존성 처리 코드
            └── processing.py.lock    # (선택) uv lock --script 결과
```

- 데이터 파일 자체는 여기 두지 않고 R2에 업로드
- `collection.yaml`의 asset `href`는 **S3 절대경로(key) 그대로 저장** (예:
  `<catalog-id>/<collection-id>/version=<version>/geovariable-input-landcover-2000.parquet`).
  메타데이터(git)와 실제 데이터(R2)가 물리적으로 분리되어 있으므로, git 폴더
  위치로부터 역산하지 않고 `collection.yaml` 자체가 데이터의 실제 위치를
  완전히 자기서술(self-describing)하도록 함. 버킷 이름/엔드포인트만 별도
  설정(env)으로 관리하고, key는 항상 이 절대경로 값을 그대로 사용
- 각 스크립트는 PEP 723 메타데이터로 의존성을 독립 선언 → `uv run --script`로
  실행 시점에 격리 환경 구성, 스크립트별로 최신 라이브러리 버전 채택 가능

### `geovars/` 패키지 (라이브러리)

- 기존 유지: `_calculator`, `_sql`, `_common`, `_io`
- 신규 추가: 카탈로그 유틸 — **`pystac`** 라이브러리로 루트 STAC Catalog를
  정의하고, `scripts/<catalog-id>/**/collection.yaml`을 읽어 Collection을
  검색(키워드/공간범위/시간범위 등)하고, asset href(= R2 절대 key)에 버킷/
  엔드포인트 설정을 결합해 실제 접근 가능한 위치를 반환하는 기능. 패키지
  차원에서 카탈로그 조회가 가능해야 함
- 신규 추가: 파이프라인 공통 유틸 — R2 업로드/다운로드, 좌표계 표준화, 버전
  경로 규칙, DuckDB/Parquet 입출력 헬퍼 등 여러 `processing.py`가 공유하는 로직
- 신규 의존성: `pystac` (+ 필요 시 `pystac` table/projection extension 스키마
  검증용 패키지)

### Docker (실행 환경 고정 + 작업 컨테이너)

- 목적: pip로 해결되지 않는 시스템 의존성(GDAL, GEOS, PROJ)과 실행 런타임
  (OS, Python 버전, `uv`)만 고정
- 시스템 의존성 관리 도구로 **[pixi](https://github.com/prefix-dev/pixi)**
  사용 — conda-forge 채널의 `gdal`, `geos`, `proj`, `uv`를 레포 루트의
  `pixi.toml`에 선언하고 `pixi.lock`으로 고정. Dockerfile은 얇은 base 이미지
  위에 pixi를 설치하고 `pixi install`(lock 파일 기준 재현 설치)만 수행
- Python 패키지 버전은 이미지/`pixi.toml`에 고정하지 않음 (스크립트별 PEP 723
  선언에 위임) — pixi는 어디까지나 GDAL/GEOS/PROJ/uv 같은 "시스템 레벨" 도구만
  담당
- 실제 작업은 이 Docker 컨테이너 안에서 이루어짐 (로컬에 GDAL/GEOS/PROJ를
  직접 설치하지 않음)
- R2 자격 증명은 이미지에 굽지 않고 **`.env` 파일 + `python-dotenv`**로 주입:
  `.env`를 컨테이너에 **볼륨 마운트**하고, `processing.py`(또는 geovars
  import 시점)가 이를 로드. `docker exec`로 들어가도 항상 같은 파일 위치에서
  읽으므로 재현성 유지. `.env`는 `.gitignore` 처리, `.env.example`만 커밋
- `python-dotenv`는 `geovars`의 **optional dependency**로 선언 (예:
  `geovars[pipeline]`) — Calculator만 쓰는 경우에는 불필요한 의존성을 늘리지
  않음

## 데이터 흐름

```
[공공데이터 원본]
   → scripts/<catalog-id>/<collection-id>/version=<version>/processing.py
       (PEP723 의존성, geovars 파이프라인 유틸 활용, Docker 컨테이너 내 실행)
   → collection.yaml 작성/갱신 (STAC 메타데이터, git 관리, href = R2 절대 key)
   → 데이터 asset은 Cloudflare R2 업로드 (key = collection.yaml의 href 값 그대로)
   → geovars 카탈로그 유틸(pystac 기반)로 검색·조회
   → geovariable-database / geovariable-reference-point 적재
   → geovars.Calculator (기존 계산 기능, 그대로 유지)
```

## 확정된 결정 사항

- 카탈로그 방식: STAC(SpatioTemporal Asset Catalog) 1.1.0 스펙 기반, 기존
  `data-pipeline-stac`의 YAML 컨벤션을 계승
- collection 단위: STAC Collection과 동일, 주로 정적 공공데이터 대상
- 스크립트 의존성 선언: PEP 723 인라인 메타데이터 + `uv run --script`
  (기존 `processing.py` 관례를 그대로 계승)
- STAC 카탈로그화 대상: 원본 수집 데이터 + `geovariable-database` /
  `geovariable-reference-point` 같은 산출물 모두 (전체 리니지 추적)
- 버전 관리: 기존 semantic version 규칙(`version=X.Y.Z` 경로) 유지
- 오브젝트 스토리지: **Cloudflare R2**
- 카탈로그 구조: 여러 catalog-id를 없애고 **단일 catalog-id 하나로 고정**,
  그 값이 `scripts/`와 R2 key 양쪽에서 동일한 prefix로 쓰임
- **catalog-id 값: `geovariable-data-pipeline`**
- 카탈로그 구현: **pystac** 기반으로 geovars가 루트 Catalog를 정의·활용
- 루트 `catalog.json`은 수동 관리하지 않음 — geovars 카탈로그 유틸이
  `scripts/geovariable-data-pipeline/**/collection.yaml`을 스캔해 pystac으로
  **항상 재생성**
- asset href: `collection.yaml`에는 **S3 절대경로(key)를 그대로 저장**
  (예: `<catalog-id>/<collection-id>/version=<version>/<filename>`). 메타데이터는
  git, 데이터는 R2로 물리적으로 분리되어 있어 git 폴더 위치로 역산하지 않고
  href 자체가 데이터 위치를 완전히 서술 (버킷명/엔드포인트만 별도 설정)
- R2 자격 증명 로딩: **`python-dotenv`** 사용. 실제 작업이 Docker 컨테이너
  안에서 이루어지므로, `.env`를 컨테이너에 **볼륨 마운트**하고
  `python-dotenv`가 로드 (환경변수 직접 주입 대신). `python-dotenv`는
  `geovars`의 optional dependency로 선언
- 시스템 의존성(Docker) 관리 도구: **pixi** — `pixi.toml`/`pixi.lock`으로
  conda-forge의 `gdal`/`geos`/`proj`/`uv`를 고정. Dockerfile은 pixi 설치 +
  `pixi install`만 수행
- `pixi.toml` 버전 핀 (실제 `pixi add`로 conda-forge에서 resolve, `pixi.lock`
  생성 완료): `gdal>=3.13.1,<4`, `geos>=3.14.1,<4`, `proj>=9.8.1,<10`,
  `uv>=0.11.28,<0.12`. `platforms = ["linux-64", "osx-arm64"]` (Docker용
  linux-64 + 로컬 macOS 개발용 osx-arm64 모두 lock)
- Dockerfile: 2-stage 빌드. 빌드 스테이지는 `ghcr.io/prefix-dev/pixi:0.65.0`
  이미지에서 `pixi install --locked`로 `.pixi/envs/default` 생성, 런타임
  스테이지는 `ubuntu:24.04` base에 그 결과물만 복사 (pixi 자체나 빌드 캐시는
  최종 이미지에 남기지 않음). Python 패키지 버전은 이미지에 고정하지 않고
  각 `processing.py`의 PEP 723 선언에 위임하는 원칙 그대로 유지
- `geovars` 신규 서브패키지: 기존 네이밍을 따라 `_catalog`(pystac 기반 STAC
  유틸), `_pipeline`(R2 업로드/다운로드, 좌표계 표준화 등 공유 헬퍼)
- 기존 `_sql/*.sql` 계산 그룹과 신규 `scripts/<catalog-id>/<collection-id>`는
  **1:1로 강제하지 않음** — `_sql` 그룹은 Calculator가 참조 DB에 대해 실행하는
  계산 로직이고, `scripts/` 하위 collection은 입력 데이터 수집·카탈로그화
  단계로 성격이 다름. 어떤 계산 그룹이 어떤 collection의 산출물을 입력으로
  쓰는지는 문서(collection.yaml 또는 `_sql` 템플릿 주석)로만 관계를 남김
- `scripts/usecase.py`는 그대로 유지 — Calculator 사용 예시이며, 신규
  `scripts/<catalog-id>/...`(데이터 수집·카탈로그화)와는 목적이 다름
- 테스트/CI: `_catalog`/`_pipeline` 유틸에 대한 pytest 유닛 테스트 추가,
  GitHub Actions로 push 시 `uv run pytest` 실행 (대규모 CI/CD는 범위 밖)
- 최상위 `pyproject.toml`/`uv.lock`은 계속 유지 — `geovars` 패키지 자체의
  개발/테스트용이며, PEP723 스크립트들의 독립 의존성과는 별개 축
- 마이그레이션 범위: 이번 리팩토링은 **구조·도구(스크립트 템플릿, geovars
  카탈로그 유틸, Docker)** 만 만들며, 기존 185GB 데이터/메타데이터를 R2 +
  이 레포로 옮기는 작업은 **별도 후속 작업**으로 분리
- STAC 메타데이터 저장 위치: Dropbox가 아니라 이 git 레포 (`scripts/` 하위,
  코드와 동일 디렉터리)

## 진행 상황

- [x] `geovars/_catalog` 서브패키지: `scan_collections`/`search`/`build_catalog`/
  `resolve_href` 구현. `scripts/geovariable-data-pipeline/**/collection.yaml`을
  스캔해 `pystac.Collection`으로 변환, 루트 `pystac.Catalog`를 매번
  재생성하는 방식으로 동작 확인 (`uv run python -c "..."`로 스모크 테스트 완료)
- [x] `geovars/_pipeline` 서브패키지: `load_env`(python-dotenv), `upload_file`/
  `download_file`(boto3, R2). `boto3`/`python-dotenv`는 import 시점이 아니라
  실제 호출 시점에만 필요 → optional dependency(`geovars[pipeline]`) 미설치
  상태에서도 `geovars` 코어 임포트에는 영향 없음을 확인
- [x] `geovars.__init__`에서 `search_catalog`/`build_catalog`를 최상위로 노출
  (패키지 차원에서 카탈로그 조회 가능해야 한다는 요구사항 반영)
- [x] `scripts/geovariable-data-pipeline/_template/version=0.1.0/`에
  `processing.py` + `collection.yaml` 템플릿 작성. `processing.py`는
  PEP 723 + `[tool.uv.sources]`로 로컬 `geovars[pipeline]`을 editable 참조,
  DuckDB로 계산 → 임시 파일 → `upload_file`로 R2 업로드까지의 전체 흐름을
  보여줌 (실제 소스/쿼리는 TODO로 표시)
- [x] `pixi.toml`/`pixi.lock` 작성 — `pixi add gdal geos proj uv`로 실제
  conda-forge에서 resolve (버전은 위 확정된 결정 사항 참조)
- [x] `Dockerfile`(2-stage, pixi 빌드 스테이지 + ubuntu:24.04 런타임) +
  `.dockerignore` 작성. **단, 이 환경에는 Docker 데몬이 떠 있지 않아 실제
  `docker build` 실행 검증은 못했음** — 다음에 Docker 사용 가능한 환경에서
  꼭 한번 빌드 확인 필요
- [x] `.env.example`(R2_ENDPOINT_URL/R2_ACCESS_KEY_ID/R2_SECRET_ACCESS_KEY/
  R2_BUCKET) 추가, `.gitignore`에 `.env` 추가
- [x] `pyproject.toml`: 코어 의존성에 `pystac`/`pyyaml` 추가, `python-dotenv`/
  `boto3`는 `[project.optional-dependencies] pipeline`으로 분리. `uv sync`
  및 `uv sync --extra pipeline` 모두 정상 resolve 확인

## 미정 사항 (다음 논의 필요)

- geovars 카탈로그 유틸 API 세부 스펙 확장 (extent/temporal 기반 검색 등) —
  현재는 `collection_id`/`keyword` 검색만 구현, 필요해지면 추가
- `.env` 볼륨 마운트 경로/이름 등 실제 `docker run`(또는 compose) 커맨드 확정,
  및 위에서 언급한 실제 `docker build` 실행 검증
- 기존 185GB 데이터 마이그레이션 계획 (범위 밖이지만 후속 작업으로 별도 계획
  필요)
- `_catalog`/`_pipeline`에 대한 pytest 유닛 테스트 및 GitHub Actions workflow
  파일은 아직 작성 전 (확정된 결정 사항에 방향만 기록됨)

## 다음 단계

1. Docker 데몬이 있는 환경에서 `docker build` 및 컨테이너 내 `uv run --script
   scripts/geovariable-data-pipeline/_template/version=0.1.0/processing.py`
   end-to-end 실행 검증
2. `_catalog`/`_pipeline`에 대한 pytest 테스트 작성 + GitHub Actions workflow
   파일 추가
3. 템플릿을 실제 첫 collection(예: 기존 Dropbox의 collection 중 하나)에
   적용해보며 템플릿 구조 자체를 검증
4. (별도 작업) 기존 데이터 마이그레이션 계획 수립
