#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_DIST="${LOCAL_DIST:-${ROOT_DIR}/deploy/synology/dist}"
NAS_HOST="${NAS_HOST:?Set NAS_HOST to your Synology hostname or IP.}"
NAS_USER="${NAS_USER:-admin}"
NAS_PATH="${NAS_PATH:-/volume1/docker/museum-caper}"

if ! command -v ssh >/dev/null 2>&1 || ! command -v scp >/dev/null 2>&1; then
  echo "ssh and scp are required for automated deployment." >&2
  exit 1
fi

if [[ -z "${IMAGE_TAR:-}" ]]; then
  IMAGE_TAR="$(find "${LOCAL_DIST}" -maxdepth 1 -name 'museum-caper-*.tar.gz' -print 2>/dev/null | sort | tail -n 1)"
fi

COMPOSE_FILE="${COMPOSE_FILE:-${LOCAL_DIST}/docker-compose.yml}"
ENV_FILE="${ENV_FILE:-${LOCAL_DIST}/.env}"

if [[ -z "${IMAGE_TAR}" || ! -f "${IMAGE_TAR}" ]]; then
  echo "No image tarball found. Run scripts/synology-build-image.sh first." >&2
  exit 1
fi

if [[ ! -f "${COMPOSE_FILE}" || ! -f "${ENV_FILE}" ]]; then
  echo "Missing docker-compose.yml or .env in ${LOCAL_DIST}. Run scripts/synology-build-image.sh first." >&2
  exit 1
fi

remote="${NAS_USER}@${NAS_HOST}"
remote_tar="$(basename "${IMAGE_TAR}")"

echo "Creating ${NAS_PATH} on ${remote}..."
ssh "${remote}" "mkdir -p '${NAS_PATH}'"

echo "Copying image, compose file, and environment file..."
scp "${IMAGE_TAR}" "${COMPOSE_FILE}" "${ENV_FILE}" "${remote}:${NAS_PATH}/"

echo "Loading image and starting project on Synology..."
ssh "${remote}" "cd '${NAS_PATH}' \
  && gzip -dc '${remote_tar}' | docker load \
  && if docker compose version >/dev/null 2>&1; then compose='docker compose'; else compose='docker-compose'; fi \
  && \${compose} --env-file .env up -d"

echo
echo "Deployed. Open:"
echo "  http://${NAS_HOST}:$(grep '^HOST_PORT=' "${ENV_FILE}" | cut -d= -f2)"
