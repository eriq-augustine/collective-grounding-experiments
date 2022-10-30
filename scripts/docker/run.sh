#!/bin/bash

# Run the ./scripts/run-experiment.sh script inside of a docker image.
# The existing psl-examples and results directories will be used.
# The running user's identity will be used as the docker user.

readonly THIS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
readonly SCRIPTS_DIR="${THIS_DIR}/.."
readonly RESULTS_DIR="${SCRIPTS_DIR}/../results"
readonly PSL_EXAMPLES_DIR="${SCRIPTS_DIR}/../psl-examples"

readonly IN_DOCKER_RUN_SCRIPT="/home/${USER}/scripts/run-experiment.sh"

readonly IMAGE_NAME='collective-grounding'

function main() {
    if [[ $# -ne 1 ]]; then
        echo "USAGE: $0 <experiment>"
        exit 1
    fi

    trap exit SIGINT

    pushd . > /dev/null
    cd "${THIS_DIR}"
        docker build -t ${IMAGE_NAME} --build-arg BASEUSER=$USER --build-arg UID=$(id -u) --build-arg GID=$(id -g) .
    popd > /dev/null

    mkdir -p "${RESULTS_DIR}"
    if [[ ! -e "${PSL_EXAMPLES_DIR}" ]]; then
        echo "Could not find the PSL examples dir. Did you run ./scripts/setup_psl_examples.sh ?"
        exit 1
    fi

    docker run --rm -it \
        -v "${SCRIPTS_DIR}:/home/${USER}/scripts" \
        -v "${RESULTS_DIR}:/home/${USER}/results" \
        -v "${PSL_EXAMPLES_DIR}:/home/${USER}/psl-examples" \
        "${IMAGE_NAME}" \
        "${IN_DOCKER_RUN_SCRIPT}" $@
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"
