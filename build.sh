#!/usr/bin/env bash
# Build the image. Override the tag with PI_IMAGE=name ./build.sh
# Requires BuildKit (docker 23+): the Dockerfile uses --mount=type=cache.
set -euo pipefail
cd "$(dirname "$0")"
exec env DOCKER_BUILDKIT=1 docker build -t "${PI_IMAGE:-pi-sandbox}" -f Dockerfile.pi .
