#!/usr/bin/env bash

set -uo pipefail

FAILURES=0

ok() {
    printf '[OK] %s\n' "$1"
}

warn() {
    printf '[WARN] %s\n' "$1" >&2
}

fail() {
    printf '[ERROR] %s\n' "$1" >&2
    FAILURES=$((FAILURES + 1))
}

if [ "$(uname -s)" = "Linux" ]; then
    ok "Linux host detected"
else
    fail "this image requires a Linux host so that /dev/kvm can be passed to Docker"
fi

case "$(uname -m)" in
    x86_64|amd64)
        ok "x86-64 host architecture detected"
        ;;
    *)
        fail "x86-64 is required; current architecture is $(uname -m)"
        ;;
esac

if command -v docker >/dev/null 2>&1; then
    ok "docker CLI is installed"
    if docker info >/dev/null 2>&1; then
        ok "Docker Engine is reachable"
        DOCKER_ARCH="$(docker info --format '{{.Architecture}}' 2>/dev/null || true)"
        case "${DOCKER_ARCH}" in
            x86_64|amd64)
                ok "Docker Engine architecture is amd64"
                ;;
            *)
                fail "Docker Engine must run amd64 containers; reported architecture is ${DOCKER_ARCH:-unknown}"
                ;;
        esac
        SECURITY_OPTIONS="$(docker info --format '{{json .SecurityOptions}}' 2>/dev/null || true)"
        if [[ "${SECURITY_OPTIONS}" == *rootless* ]]; then
            fail "rootless Docker cannot reliably pass /dev/kvm; use a rootful Docker Engine"
        fi
    else
        fail "Docker Engine is not reachable; start Docker or fix the current user's permissions"
    fi
else
    fail "docker CLI is not installed"
fi

if [ -r /proc/cpuinfo ] && grep -Eq '\<(vmx|svm)\>' /proc/cpuinfo; then
    ok "CPU virtualization flags (vmx/svm) are available"
else
    fail "CPU virtualization is unavailable; enable VT-x/AMD-V or nested virtualization"
fi

if [ -c /dev/kvm ]; then
    ok "/dev/kvm exists"
    if [ ! -r /dev/kvm ] || [ ! -w /dev/kvm ]; then
        warn "the current user cannot directly read/write /dev/kvm; re-login after joining the kvm group if direct access is needed"
    fi
else
    fail "/dev/kvm does not exist; load the KVM modules and enable virtualization"
fi

if [ "${FAILURES}" -ne 0 ]; then
    printf '\nHost prerequisite check failed with %d error(s).\n' "${FAILURES}" >&2
    exit 1
fi

printf '\nHost prerequisites passed.\n'
