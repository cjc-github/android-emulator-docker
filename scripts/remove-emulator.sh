#!/usr/bin/env bash

set -Eeuo pipefail

CONTAINER_NAME="${CONTAINER_NAME:-android-emulator}"

if docker container inspect "${CONTAINER_NAME}" >/dev/null 2>&1; then
    docker rm -f "${CONTAINER_NAME}"
else
    echo "Container ${CONTAINER_NAME} does not exist"
fi
