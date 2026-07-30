#!/usr/bin/env bash

set -Eeuo pipefail

CONTAINER_NAME="${CONTAINER_NAME:-android-emulator}"
VERIFY_TIMEOUT="${VERIFY_TIMEOUT:-360}"
START_TIME=${SECONDS}

docker container inspect "${CONTAINER_NAME}" >/dev/null

echo "Waiting for ${CONTAINER_NAME} to become healthy..."
while true; do
    STATE="$(docker inspect --format '{{.State.Status}}' "${CONTAINER_NAME}")"
    HEALTH="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "${CONTAINER_NAME}")"

    if [ "${STATE}" = "exited" ] || [ "${STATE}" = "dead" ]; then
        docker logs --tail 100 "${CONTAINER_NAME}" >&2
        echo "ERROR: container stopped before the emulator became ready" >&2
        exit 1
    fi

    if [ "${HEALTH}" = "healthy" ]; then
        break
    fi

    if (( SECONDS - START_TIME >= VERIFY_TIMEOUT )); then
        docker logs --tail 100 "${CONTAINER_NAME}" >&2
        echo "ERROR: verification timed out after ${VERIFY_TIMEOUT}s" >&2
        exit 1
    fi

    sleep 3
done

docker exec "${CONTAINER_NAME}" bash -lc '
    serial="emulator-${EMULATOR_CONSOLE_PORT:-5554}"
    adb -s "${serial}" get-state
    release="$(adb -s "${serial}" shell getprop ro.build.version.release | tr -d "\r")"
    api="$(adb -s "${serial}" shell getprop ro.build.version.sdk | tr -d "\r")"
    model="$(adb -s "${serial}" shell getprop ro.product.model | tr -d "\r")"
    printf "Android %s (API %s), model=%s, serial=%s\n" "${release}" "${api}" "${model}" "${serial}"
'

echo "Verification passed"
