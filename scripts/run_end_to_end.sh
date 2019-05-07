#!/bin/bash

# Run various experiments that require end-to-end runs:
#  - Overall effectiveness
#  - Sensitivity of D and M
#  - Search Method Overview

readonly THIS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
readonly BASE_OUT_DIR="${THIS_DIR}/../results/end-to-end"

readonly CLEAR_CACHE_SCRIPT=$(realpath "${THIS_DIR}/clear_cache.sh")
readonly BSOE_CLEAR_CACHE_SCRIPT=$(realpath "${THIS_DIR}/bsoe_clear_cache.sh")

# A directory that only exists on BSOE servers.
readonly BSOE_DIR='/soe'

readonly SEARCH_METHODS='DFSRewriteFringe BFSRewriteFringe UCSRewriteFringe BoundedRewriteFringe'
readonly MIN_BUDGET='10'
readonly MAX_BUDGET='100'
readonly BUDGET_INCREMENT='10'

# The percentage difference between normal and optimism/pseeimism for D and M.
readonly OPTIMISM_GAP='0.10'

readonly MIN_D='0.010'
readonly MAX_D='0.020'
readonly D_INCREMENT='0.001'

readonly MIN_M='0.0010'
readonly MAX_M='0.0020'
readonly M_INCREMENT='0.0001'

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
    local extraOptions=$3

    mkdir -p "${outDir}"

    local outPath="${outDir}/out.txt"
    local errPath="${outDir}/out.err"

    if [[ -e "${outPath}" ]]; then
        echo "Output file already exists, skipping: ${outPath}"
        return 0
    fi

    clearPostgresCache

    pushd . > /dev/null
        cd "${cliDir}"

        ./run.sh ${extraOptions} > "${outPath}" 2> "${errPath}"

    popd > /dev/null
}

# Iterate over search methods and budget.
function run_search_methods() {
    local cliDir=$1
    local baseOutDir=$2

    for budget in $(seq -w ${MIN_BUDGET} ${BUDGET_INCREMENT} ${MAX_BUDGET}); do
        for searchMethod in ${SEARCH_METHODS}; do
            local outDir="${baseOutDir}/${budget}/${searchMethod}"

            local options='-D grounding.experiment.skipinference=true -D grounding.rewritequeries=true -D grounding.serial=true -D grounding.eagerinstantiation=false'
            options="${options} -D queryrewriter.searchbudget=${budget}"
            options="${options} -D queryrewriter.searchtype=org.linqs.psl.database.rdbms.QueryRewriter\$${searchMethod}"

            run "${cliDir}" "${outDir}" "${options}"
        done
    done
}

# Iterate over hyperparam (D and M) values to test for sensitivity.
function run_hyperparam_sensitivity() {
    local cliDir=$1
    local baseOutDir=$2

    local outDir=''

    for d in $(seq -w ${MIN_D} ${D_INCREMENT} ${MAX_D}); do
        for m in $(seq -w ${MIN_M} ${M_INCREMENT} ${MAX_M}); do
            local outDir="${baseOutDir}/d_${d}/m_${m}"

            # Note the zero pad.
            local optimisticD=0$(echo "${d} - ${D_INCREMENT}" | bc)
            local pessimisticD=0$(echo "${d} + ${D_INCREMENT}" | bc)
            local optimisticM=0$(echo "${m} - ${M_INCREMENT}" | bc)
            local pessimisticM=0$(echo "${m} + ${M_INCREMENT}" | bc)

            local options='-D grounding.experiment.skipinference=true -D grounding.rewritequeries=true -D grounding.serial=true -D grounding.eagerinstantiation=false'
            options="${options} -D queryrewriter.optimisticcost=${optimisticD}"
            options="${options} -D queryrewriter.pessimisticcost=${pessimisticD}"
            options="${options} -D queryrewriter.optimisticrow=${optimisticM}"
            options="${options} -D queryrewriter.pessimisticrow=${pessimisticM}"

            run "${cliDir}" "${outDir}" "${options}"
        done
    done
}

function run_example() {
    local exampleDir=$1

    local exampleName=`basename "${exampleDir}"`
    local baseOutDir="${BASE_OUT_DIR}/${exampleName}"
    local cliDir="$exampleDir/cli"

    echo "Running example: ${exampleName}."

    local outDir=''
    local options=''

    # Run base, without any rewrites.
    echo "    Running base."
    outDir="${baseOutDir}/base"
    options='-D grounding.experiment.skipinference=true -D grounding.rewritequeries=false -D grounding.serial=true -D grounding.eagerinstantiation=false'
    run "${cliDir}" "${outDir}" "${options}"

    # Run rewrites, but no sharing.
    echo "    Running rewrite."
    outDir="${baseOutDir}/rewrite"
    options='-D grounding.experiment.skipinference=true -D grounding.rewritequeries=true -D grounding.serial=true -D grounding.eagerinstantiation=false -D queryrewriter.searchbudget=10'
    run "${cliDir}" "${outDir}" "${options}"

    # Run all optimizations.
    echo "    Running full."
    outDir="${baseOutDir}/full"
    options='-D grounding.experiment.skipinference=true -D grounding.rewritequeries=true -D grounding.serial=false -D grounding.eagerinstantiation=true -D queryrewriter.searchbudget=10'
    run "${cliDir}" "${outDir}" "${options}"

    echo "    Running search methods."
    outDir="${baseOutDir}/search-methods"
    run_search_methods "${cliDir}" "${outDir}"

    echo "    Running hyperparam sensitivity."
    outDir="${baseOutDir}/hyperparam-sensitivity"
    # TEST
    # run_hyperparam_sensitivity "${cliDir}" "${outDir}"
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
