#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"${SCRIPT_DIR}/check-host.sh"
"${SCRIPT_DIR}/build-image.sh"
"${SCRIPT_DIR}/run-emulator.sh"
"${SCRIPT_DIR}/verify-emulator.sh"
