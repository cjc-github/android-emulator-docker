#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

IMAGE_NAME="${IMAGE_NAME:-android-emulator:api31}"
BUILD_NETWORK="${BUILD_NETWORK:-host}"
BUILD_NO_CACHE="${BUILD_NO_CACHE:-false}"
CMDLINE_TOOLS_VERSION="${CMDLINE_TOOLS_VERSION:-11076708}"
EMULATOR_CHANNEL="${EMULATOR_CHANNEL:-0}"
ANDROID_API_LEVEL="${ANDROID_API_LEVEL:-31}"
SYSTEM_IMAGE="${SYSTEM_IMAGE:-google_apis}"
AVD_NAME="${AVD_NAME:-docker-emulator}"
DEVICE_PROFILE="${DEVICE_PROFILE:-pixel_5}"

docker info >/dev/null

case "${BUILD_NO_CACHE}" in
    true|false) ;;
    *)
        echo "ERROR: BUILD_NO_CACHE must be true or false" >&2
        exit 2
        ;;
esac

case "${EMULATOR_CHANNEL}" in
    0|1|2|3) ;;
    *)
        echo "ERROR: EMULATOR_CHANNEL must be 0 (stable), 1 (beta), 2 (dev), or 3 (canary)" >&2
        exit 2
        ;;
esac

BUILD_OPTIONS=(--network "${BUILD_NETWORK}")
if [ "${BUILD_NO_CACHE}" = "true" ]; then
    BUILD_OPTIONS+=(--no-cache)
fi

echo "Building ${IMAGE_NAME}"
echo "Android API: ${ANDROID_API_LEVEL}"
echo "System image: ${SYSTEM_IMAGE};x86_64"
echo "Device profile: ${DEVICE_PROFILE}"
echo "Emulator channel: ${EMULATOR_CHANNEL}"
echo "No-cache build: ${BUILD_NO_CACHE}"

docker build \
    "${BUILD_OPTIONS[@]}" \
    --build-arg CMDLINE_TOOLS_VERSION="${CMDLINE_TOOLS_VERSION}" \
    --build-arg EMULATOR_CHANNEL="${EMULATOR_CHANNEL}" \
    --build-arg ANDROID_API_LEVEL="${ANDROID_API_LEVEL}" \
    --build-arg SYSTEM_IMAGE="${SYSTEM_IMAGE}" \
    --build-arg AVD_NAME="${AVD_NAME}" \
    --build-arg DEVICE_PROFILE="${DEVICE_PROFILE}" \
    --tag "${IMAGE_NAME}" \
    "${ROOT_DIR}"

docker image inspect "${IMAGE_NAME}" \
    --format 'Built image {{.RepoTags}} ({{.Id}}, {{.Size}} bytes)'
