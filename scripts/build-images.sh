#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export DOCKER_BUILDKIT=1

echo "==> Dang build tmv-qms-be:latest"
docker build \
  -f "${ROOT_DIR}/Dockerfile.backend" \
  --build-context "qms-docker=${ROOT_DIR}" \
  -t tmv-qms-be:latest \
  "${ROOT_DIR}/../tmv-qms-be"

echo "==> Dang build tmv-qms-fe:latest"
docker build \
  -f "${ROOT_DIR}/Dockerfile.frontend" \
  -t tmv-qms-fe:latest \
  "${ROOT_DIR}/../tmv-qms"

echo "==> Hoan tat. Image: tmv-qms-be:latest, tmv-qms-fe:latest"