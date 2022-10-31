#!/bin/bash

# A general script to control which experiment is to be run.
# Before invoking this script, you should run ./scripts/setup_psl_examples.sh to prep the data.
# This script can be run both in and out of docker.

readonly THIS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
readonly SCRIPTS_DIR="${THIS_DIR}"
readonly RESULTS_DIR="${THIS_DIR}/../results"
readonly PSL_EXAMPLES_DIR="${THIS_DIR}/../psl-examples"

readonly EXPERIMENTS="all-splits first-split simple"

function main() {
    trap exit SIGINT
    set -e

    if [[ $# -ne 1 ]]; then
        echo "USAGE: $0 <experiment>"
        echo "Available experimiments: ${EXPERIMENTS}"
        exit 1
    fi

    local experiment=$1

    if [[ ! "${EXPERIMENTS}" == *"${experiment}"* ]]; then
        echo "Unknown experiment: '${experiment}'."
        echo "Available experimiments: ${EXPERIMENTS}"
        exit 2
    fi

    mkdir -p "${RESULTS_DIR}"
    if [[ ! -e "${PSL_EXAMPLES_DIR}" ]]; then
        echo "Could not find the PSL examples dir. Did you run ./scripts/setup_psl_examples.sh ?"
        exit 1
    fi

    local runScript="${SCRIPTS_DIR}/run-${experiment}.sh"

    echo "Running ${runScript}."
    "${runScript}"
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"
