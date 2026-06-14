#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_NAME="${IMAGE_NAME:-museum-caper}"
TAG="${TAG:-$(date +%Y%m%d-%H%M%S)}"
PLATFORM="${PLATFORM:-linux/amd64}"
PHX_HOST="${PHX_HOST:-museum-caper.local}"
HOST_PORT="${HOST_PORT:-4000}"
PHX_FORCE_SSL="${PHX_FORCE_SSL:-false}"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/deploy/synology/dist}"

platform_slug="${PLATFORM//\//-}"
image_ref="${IMAGE_NAME}:${TAG}"
tar_path="${OUT_DIR}/${IMAGE_NAME}-${TAG}-${platform_slug}.tar"

mkdir -p "${OUT_DIR}"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required to build the Synology image." >&2
  exit 1
fi

if ! docker buildx version >/dev/null 2>&1; then
  echo "docker buildx is required. Install/enable Docker Buildx and try again." >&2
  exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "openssl is required to generate SECRET_KEY_BASE." >&2
  exit 1
fi

secret_key_base="$(openssl rand -base64 64 | tr -d '\n')"

echo "Building ${image_ref} for ${PLATFORM}..."
docker buildx build \
  --platform "${PLATFORM}" \
  --build-arg PHX_FORCE_SSL="${PHX_FORCE_SSL}" \
  -t "${image_ref}" \
  --load \
  "${ROOT_DIR}"

echo "Saving ${image_ref} to ${tar_path}.gz..."
docker save "${image_ref}" -o "${tar_path}"
gzip -f "${tar_path}"

cp "${ROOT_DIR}/deploy/synology/docker-compose.yml" "${OUT_DIR}/docker-compose.yml"

cat >"${OUT_DIR}/.env" <<EOF
IMAGE_NAME=${IMAGE_NAME}
TAG=${TAG}
HOST_PORT=${HOST_PORT}
PHX_HOST=${PHX_HOST}
PHX_URL_SCHEME=http
PHX_URL_PORT=${HOST_PORT}
PHX_SERVER=true
PORT=4000
SECRET_KEY_BASE=${secret_key_base}
EOF

cat <<EOF

Synology bundle written to:
  ${OUT_DIR}

Files:
  $(basename "${tar_path}").gz
  docker-compose.yml
  .env

Next:
  NAS_HOST=your-nas.local NAS_USER=your-user scripts/synology-deploy-ssh.sh

EOF
