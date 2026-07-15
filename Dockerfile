# syntax=docker/dockerfile:1

# --- build stage: install the pinned pixi environment (gdal/geos/proj/uv) ---
FROM ghcr.io/prefix-dev/pixi:0.65.0 AS build
WORKDIR /app
COPY pixi.toml pixi.lock ./
RUN pixi install --locked --environment default

# --- runtime stage: thin base image + only the resolved pixi environment ---
FROM ubuntu:24.04 AS runtime
WORKDIR /app

COPY --from=build /app/.pixi/envs/default /app/.pixi/envs/default
ENV PATH="/app/.pixi/envs/default/bin:${PATH}"

COPY . .

# R2 credentials are provided at runtime via a volume-mounted `.env`
# (see docs/refactoring-plan.md) — nothing secret is baked into the image.
# Python package versions are NOT pinned here; each scripts/**/processing.py
# resolves its own dependencies via PEP 723 + `uv run --script`.
CMD ["bash"]
