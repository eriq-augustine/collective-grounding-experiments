#!/bin/bash

BASE_OUT_DIR=`realpath 'results/individual-query'`
AGGREGATE_OUT_FILENAME='all.out'
CLEAR_CACHE_SCRIPT='/home/eriq/code/psl-grounding-experiments/scripts/clear_cache.sh'
TIMEOUT_DURATION='5m'

function clearPostgresCache() {
    sudo "${CLEAR_CACHE_SCRIPT}"
}

function run() {
    local cliDir=$1
    local outDir=$2
    local queryNumber=$3

    mkdir -p "${outDir}"

    local outPath="${outDir}/out.txt"
    local errPath="${outDir}/out.err"

    if [[ -e "${outPath}" ]]; then
        echo "Output file already exists, skipping: ${outPath}"
        return
    fi

    clearPostgresCache

    pushd . > /dev/null
    cd "${cliDir}"

        timeout -s 9 ${TIMEOUT_DURATION} ./run.sh -D experiment.query=$queryNumber > "${outPath}" 2> "${errPath}"
        # ./run.sh -D experiment.query=$queryNumber > "${outPath}" 2> "${errPath}"

    popd > /dev/null
}

function fetchQueryCount() {
    local path=$1

    echo $(grep "org.linqs.psl.application.util.Grounding  - Found " "${path}" | sed 's/.*Found \([0-9]\+\) candidate queries\.$/\1/')
}

function run_example() {
    local exampleDir=$1

    local exampleName=`basename "${exampleDir}"`
    local cliDir="$exampleDir/cli"
    local baseOutDir="${BASE_OUT_DIR}/${exampleName}"
    local aggregateOutPath="${baseOutDir}/${AGGREGATE_OUT_FILENAME}"

    # First run to fetch the number of queries.
    local outDir="${baseOutDir}/-1"
    run "${cliDir}" "${outDir}" "-1"

    local queryCount=$(fetchQueryCount "${outDir}/out.txt")
    echo "Found ${queryCount} queries."

    echo "" > "${aggregateOutPath}"

    for i in `seq -w 000 $((${queryCount} - 1))`; do
        echo "Running query ${i}."

        local outDir="${baseOutDir}/q_${i}"
        run "${cliDir}" "${outDir}" "${i}"
    done

    # Append all output to a single file for more convenient parsing.
    cat ${baseOutDir}/q_*/out.txt >> "${aggregateOutPath}"
}

function main() {
    if [[ $# -ne 1 ]]; then
        echo "USAGE: $0 <example dir>"
        exit 1
    fi

   trap exit SIGINT

   local exampleDir=$1

   run_example "${exampleDir}"
}

main "$@"
