#!/usr/bin/env bash
set -euo pipefail

IMAGE="${IMAGE:-ghcr.io/k5-mot/docling-serve-jp}"
BUILDER="${BUILDER:-docling-multi}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"
INSTALL_BINFMT="${INSTALL_BINFMT:-1}"

REGISTRY="${IMAGE%%/*}"
if [[ "${REGISTRY}" != *.* && "${REGISTRY}" != *:* && "${REGISTRY}" != "localhost" ]]; then
  REGISTRY="docker.io"
fi

TAGS=(
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

if [[ "${REGISTRY}" == "ghcr.io" ]]; then
  docker_config="${DOCKER_CONFIG:-${HOME}/.docker}/config.json"
  if [[ ! -f "${docker_config}" ]] || ! grep -q '"ghcr.io"' "${docker_config}"; then
    cat >&2 <<'EOF'
ERROR: ghcr.io is not configured in Docker credentials.

Run:
  echo "$GHCR_PAT" | docker login ghcr.io -u <github-user> --password-stdin

Use a personal access token with write:packages permission.
The GitHub Actions GITHUB_TOKEN is only suitable inside the workflow that grants packages: write.
EOF
    exit 1
  fi
fi

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
#   docker image rm "docling-serve-jp:${tag}"
done

echo "Done. ${IMAGE}:latest was updated by the final build: ${TAGS[-1]}"
