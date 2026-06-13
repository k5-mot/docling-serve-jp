#!/usr/bin/env bash
set -euo pipefail

IMAGE="${IMAGE:-ghcr.io/k5-mot/docling-serve-jp}"
BUILDER="${BUILDER:-docling-multi}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"
INSTALL_BINFMT="${INSTALL_BINFMT:-1}"
MODELS_LIST="${MODELS_LIST:-}"

TAGS=(
#   v1.10.0
#   v1.11.0
#   v1.12.0
  v1.13.0
  v1.13.1
  v1.14.0
  v1.14.1
  v1.14.2
  v1.14.3
  v1.15.0
  v1.16.1
  v1.17.0
  v1.18.0
  v1.19.0
  v1.20.0
  v1.21.0
  v1.22.0
  v1.22.1
  v1.23.0
)

command -v docker >/dev/null

if [[ "${INSTALL_BINFMT}" == "1" && "${PLATFORMS}" == *"linux/arm64"* ]]; then
  docker run --privileged --rm tonistiigi/binfmt --install arm64
fi

if ! docker buildx inspect "${BUILDER}" >/dev/null 2>&1; then
  docker buildx create --name "${BUILDER}" --driver docker-container --use
else
  docker buildx use "${BUILDER}"
fi

docker buildx inspect --bootstrap "${BUILDER}" >/dev/null

for tag in "${TAGS[@]}"; do
  build_args=(--build-arg "BASE_TAG=${tag}")
  if [[ -n "${MODELS_LIST}" ]]; then
    build_args+=(--build-arg "MODELS_LIST=${MODELS_LIST}")
  fi

  echo "==> Building and pushing ${IMAGE}:${tag}"
  docker buildx build \
    --builder "${BUILDER}" \
    --platform "${PLATFORMS}" \
    "${build_args[@]}" \
    --push \
    -t "${IMAGE}:${tag}" \
    -t "${IMAGE}:latest" \
    .
  echo "==> Pushed ${IMAGE}:${tag}"
done

echo "Done. ${IMAGE}:latest was updated by the final build: ${TAGS[-1]}"
