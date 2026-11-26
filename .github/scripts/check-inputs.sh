#!/usr/bin/env bash
# Refuses workflow inputs that aren't plain versions or build numbers.
#   check-inputs.sh version <x.y.z> build <n> ...
set -euo pipefail
while [ $# -ge 2 ]; do
  kind=$1 value=$2; shift 2
  case "$kind" in
    version) [[ "$value" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || { echo "::error title=inputs::not a version: $value"; exit 1; } ;;
    build) [[ "$value" =~ ^[0-9]{1,4}$ ]] || { echo "::error title=inputs::not a build number: $value"; exit 1; } ;;
    *) echo "::error title=inputs::unknown kind $kind"; exit 1 ;;
  esac
done
