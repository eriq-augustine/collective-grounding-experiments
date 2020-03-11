#!/bin/bash

# For each rule, run all rewrites and gather performance stats.

readonly THIS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
readonly BASE_OUT_DIR="${THIS_DIR}/../../results/individual-query"

readonly AGGREGATE_OUT_FILENAME='all.out'
readonly CLEAR_CACHE_SCRIPT=$(realpath "${THIS_DIR}/../clear_cache.sh")
readonly BSOE_CLEAR_CACHE_SCRIPT=$(realpath "${THIS_DIR}/../bsoe_clear_cache.sh")
readonly TIMEOUT_DURATION='30m'

# A directory that only exists on BSOE servers.
readonly BSOE_DIR='/soe'

function clearPostgresCache() {
    if [[ -d "${BSOE_DIR}" ]]; then
        "${BSOE_CLEAR_CACHE_SCRIPT}"
    else
        sudo "${CLEAR_CACHE_SCRIPT}"
    fi
}

function run() {
    local cliDir=$1
    local outDir=$2
    local queryId=$3

    mkdir -p "${outDir}"

    local outPath="${outDir}/out.txt"
    local errPath="${outDir}/out.err"

    if [[ -e "${outPath}" ]]; then
        echo "Output file already exists, skipping: ${outPath}"
        return 0
    fi

    local extraOptions="-D runtimestats.collect=true -D grounding.experiment=true -D grounding.experiment.rulequeries=${queryId}"

    clearPostgresCache

    pushd . > /dev/null
        cd "${cliDir}"

        timeout -s 9 ${TIMEOUT_DURATION} ./run.sh ${extraOptions} > "${outPath}" 2> "${errPath}"

    popd > /dev/null
}

function fetchQueryCount() {
    local path=$1

    echo $(grep "org.linqs.psl.grounding.SingleRuleExperiment  - Found " "${path}" | sed 's/.*Found \([0-9]\+\) candidate queries\.$/\1/')
}

function fetchRuleCount() {
    local path=$1

    echo $(grep "Single rule experiment total available rules:" "${path}" | sed 's/.*rules: \([0-9]\+\)$/\1/')
}

function run_single_rule() {
    local exampleDir=$1
    local rule=$2

    local exampleName=`basename "${exampleDir}"`
    local cliDir="$exampleDir/cli"
    local baseOutDir="${BASE_OUT_DIR}/${exampleName}/rule_${rule}"
    local aggregateOutPath="${baseOutDir}/${AGGREGATE_OUT_FILENAME}"

    # First run to fetch the number of queries.
    local outDir="${baseOutDir}/base"
    run "${cliDir}" "${outDir}" "${rule}:-1"

    local queryCount=$(fetchQueryCount "${outDir}/out.txt")
    echo "Found ${queryCount} queries."

    # Also fetch the number of rules.
    # We will always start with the first rule, but we will need to know how many rules there are after that.
    local ruleCount=$(fetchRuleCount "${outDir}/out.txt")

    echo "" > "${aggregateOutPath}"

    for i in `seq -w 000 $((${queryCount} - 1))`; do
        echo "Running query ${rule}:${i}."

        local outDir="${baseOutDir}/query_${i}"
        run "${cliDir}" "${outDir}" "${rule}:${i}"
    done

    # Append all output to a single file for more convenient parsing.
    cat ${baseOutDir}/query_*/out.txt > "${aggregateOutPath}"

    return "${ruleCount}"
}

function run_example() {
    local exampleDir=$1

    local exampleName=`basename "${exampleDir}"`
    local baseOutDir="${BASE_OUT_DIR}/${exampleName}"
    local cliDir="$exampleDir/cli"

    # We don't know how many rules there are until we run,
    # but there should be at least one rule.
    run_single_rule "${exampleDir}" 000
    local ruleCount=$?
    echo "Found ${ruleCount} rules."

    for i in `seq -w 001 $((${ruleCount} - 1))`; do
        run_single_rule "${exampleDir}" "${i}"
    done

    local aggregateOutPath="${BASE_OUT_DIR}/${exampleName}/${AGGREGATE_OUT_FILENAME}"

    # Append all output to a single file for more convenient parsing.
    cat ${baseOutDir}/*/${AGGREGATE_OUT_FILENAME} > "${aggregateOutPath}"
}

function main() {
    if [[ $# -eq 0 ]]; then
        echo "USAGE: $0 <example dir> ..."
        exit 1
    fi

    trap exit SIGINT

    local exampleDir=$1

    for exampleDir in "$@"; do
        run_example "${exampleDir}"
    done
}

main "$@"
