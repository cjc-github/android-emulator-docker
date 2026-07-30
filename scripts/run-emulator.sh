#!/usr/bin/env bash

set -Eeuo pipefail

IMAGE_NAME="${IMAGE_NAME:-android-emulator:api31}"
CONTAINER_NAME="${CONTAINER_NAME:-android-emulator}"
SHM_SIZE="${SHM_SIZE:-2g}"
BOOT_TIMEOUT="${BOOT_TIMEOUT:-300}"

docker image inspect "${IMAGE_NAME}" >/dev/null
EXPECTED_IMAGE_ID="$(docker image inspect --format '{{.Id}}' "${IMAGE_NAME}")"

if [ ! -e /dev/kvm ]; then
    echo "ERROR: /dev/kvm does not exist on the host" >&2
    exit 1
fi

if docker container inspect "${CONTAINER_NAME}" >/dev/null 2>&1; then
    RUNNING="$(docker inspect --format '{{.State.Running}}' "${CONTAINER_NAME}")"
    if [ "${RUNNING}" = "true" ]; then
        CURRENT_IMAGE_ID="$(docker inspect --format '{{.Image}}' "${CONTAINER_NAME}")"
        if [ "${CURRENT_IMAGE_ID}" = "${EXPECTED_IMAGE_ID}" ]; then
            echo "Container ${CONTAINER_NAME} is already running the requested image"
            exit 0
        fi
        echo "ERROR: container ${CONTAINER_NAME} is running a different image" >&2
        echo "Remove it first with: CONTAINER_NAME=${CONTAINER_NAME} ./scripts/remove-emulator.sh" >&2
        exit 1
    fi
    docker rm "${CONTAINER_NAME}" >/dev/null
fi

docker run -d \
    --name "${CONTAINER_NAME}" \
    --device /dev/kvm \
    --shm-size "${SHM_SIZE}" \
    --env BOOT_TIMEOUT="${BOOT_TIMEOUT}" \
    "${IMAGE_NAME}"

echo "Container ${CONTAINER_NAME} started"
echo "Follow startup logs with: docker logs -f ${CONTAINER_NAME}"
