#!/usr/bin/env bash
# Run pure-logic tests (SwoopCore). Desktop integration is verified manually / via probes.
set -euo pipefail
cd "$(dirname "$0")/../Packages/SwoopCore"
swift test "$@"
