#!/usr/bin/env bash

set -Eeuo pipefail

: "${AVD_NAME:=docker-emulator}"
: "${EMULATOR_CONSOLE_PORT:=5554}"
: "${BOOT_TIMEOUT:=300}"
: "${REQUIRE_KVM:=true}"

case "${EMULATOR_CONSOLE_PORT}:${BOOT_TIMEOUT}" in
    *[!0-9:]*)
        echo "EMULATOR_CONSOLE_PORT and BOOT_TIMEOUT must be integers" >&2
        exit 2
        ;;
esac

EMULATOR_SERIAL="emulator-${EMULATOR_CONSOLE_PORT}"
EMULATOR_PID=""
SHUTTING_DOWN=0

shutdown() {
    if [ "${SHUTTING_DOWN}" -eq 1 ]; then
        return
    fi
    SHUTTING_DOWN=1

    echo "Stopping Android emulator..."
    adb -s "${EMULATOR_SERIAL}" emu kill >/dev/null 2>&1 || true
    if [ -n "${EMULATOR_PID}" ]; then
        kill "${EMULATOR_PID}" >/dev/null 2>&1 || true
        wait "${EMULATOR_PID}" 2>/dev/null || true
    fi
}

handle_signal() {
    shutdown
    exit 0
}

trap shutdown EXIT
trap handle_signal SIGINT SIGTERM

ACCEL_ARGS=()
if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    echo "KVM acceleration is available"
    ACCEL_ARGS=(-accel on)
elif [ "${REQUIRE_KVM}" = "true" ]; then
    echo "ERROR: /dev/kvm is unavailable or not writable" >&2
    echo "Start the container with: --device /dev/kvm" >&2
    exit 1
else
    echo "WARNING: KVM is unavailable; using slow software emulation"
    ACCEL_ARGS=(-accel off)
fi

echo "Starting Android emulator: ${AVD_NAME} (${EMULATOR_SERIAL})"
adb start-server >/dev/null

emulator \
    -avd "${AVD_NAME}" \
    -port "${EMULATOR_CONSOLE_PORT}" \
    -no-window \
    -no-audio \
    -no-boot-anim \
    -no-snapshot \
    -no-metrics \
    -gpu swiftshader_indirect \
    -camera-back none \
    -camera-front none \
    "${ACCEL_ARGS[@]}" &
EMULATOR_PID=$!

START_TIME=${SECONDS}
wait_until_ready() {
    local description="$1"
    shift

    echo "Waiting for ${description}..."
    until "$@"; do
        if ! kill -0 "${EMULATOR_PID}" 2>/dev/null; then
            echo "ERROR: Android emulator exited before ${description}" >&2
            wait "${EMULATOR_PID}" || true
            exit 1
        fi
        if (( SECONDS - START_TIME >= BOOT_TIMEOUT )); then
            echo "ERROR: timed out after ${BOOT_TIMEOUT}s waiting for ${description}" >&2
            exit 1
        fi
        sleep 2
    done
}

adb_online() {
    adb -s "${EMULATOR_SERIAL}" get-state 2>/dev/null | grep -q '^device$'
}

android_booted() {
    [ "$(adb -s "${EMULATOR_SERIAL}" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]
}

wait_until_ready "ADB" adb_online
wait_until_ready "Android boot completion" android_booted

adb -s "${EMULATOR_SERIAL}" shell input keyevent 82 >/dev/null 2>&1 || true
adb -s "${EMULATOR_SERIAL}" shell settings put global window_animation_scale 0 || true
adb -s "${EMULATOR_SERIAL}" shell settings put global transition_animation_scale 0 || true
adb -s "${EMULATOR_SERIAL}" shell settings put global animator_duration_scale 0 || true

echo "Android emulator is ready"
adb devices -l

if wait "${EMULATOR_PID}"; then
    STATUS=0
else
    STATUS=$?
fi

trap - EXIT SIGINT SIGTERM
shutdown
exit "${STATUS}"
