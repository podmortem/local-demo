#!/bin/sh

# Usage: ./log-runner.sh <scenario-name>

SCENARIO=${1:-"quarkus-complex-failure"}
LOG_FILE="/logs/${SCENARIO}.log"

if [ ! -f "$LOG_FILE" ]; then
    exit 1
fi

cat "$LOG_FILE"

exit 1
