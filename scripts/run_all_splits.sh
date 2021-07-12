#!/bin/bash

# Run all the splits of all the specified psl-examples.

readonly THIS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
readonly BASE_OUT_DIR="${THIS_DIR}/../results"

readonly CLEAR_CACHE_SCRIPT=$(realpath "${THIS_DIR}/clear_cache.sh")
readonly BSOE_CLEAR_CACHE_SCRIPT=$(realpath "${THIS_DIR}/bsoe_clear_cache.sh")

readonly ADDITIONAL_PSL_OPTIONS=''

# An identifier to differentiate the output of this script/experiment from other scripts.
readonly RUN_ID='all-splits'

# A directory that only exists on BSOE servers.
readonly BSOE_DIR='/soe'

readonly NUM_RUNS=10

function clearPostgresCache() {
    if [[ -d "${BSOE_DIR}" ]]; then
        "${BSOE_CLEAR_CACHE_SCRIPT}"
    else
        sudo "${CLEAR_CACHE_SCRIPT}"
    fi
}

function run_psl() {
    local cliDir=$1
    local outDir=$2
    local extraOptions=$3

    mkdir -p "${outDir}"

    local outPath="${outDir}/out.txt"
    local errPath="${outDir}/out.err"
    local timePath="${outDir}/time.txt"

    if [[ -e "${outPath}" ]]; then
        echo "Output file already exists, skipping: ${outPath}"
        return 0
    fi

    clearPostgresCache

    pushd . > /dev/null
        cd "${cliDir}"

        # Run PSL.
        /usr/bin/time -v --output="${timePath}" ./run.sh ${extraOptions} > "${outPath}" 2> "${errPath}"

        # Copy any artifacts into the output directory.
        cp -r inferred-predicates "${outDir}/"
        cp *.data "${outDir}/"
        cp *.psl "${outDir}/"
    popd > /dev/null
}

function run_example() {
    local cliDir=$1
    local baseOutDir=$2

    local baseOptions="${ADDITIONAL_PSL_OPTIONS}"
    baseOptions="${baseOptions} -D admmreasoner.maxiterations=10"

    local outDir=''
    local options=''

    # Run base, without any rewrites.
    echo "Running base."
    outDir="${baseOutDir}/base"
    options="${baseOptions} -D grounding.rewritequeries=false"
    run_psl "${cliDir}" "${outDir}" "${options}"

    # Run with full rewrites.
    echo "Running full."
    outDir="${baseOutDir}/full"
    options="${baseOptions} -D grounding.rewritequeries=true"
    run_psl "${cliDir}" "${outDir}" "${options}"
}

function run_example_splits() {
    local exampleDir=$1
    local iterationID=$2

    local exampleName=`basename "${exampleDir}"`
    local cliDir="$exampleDir/cli"

    for splitId in $(ls -1 "${exampleDir}/data/${exampleName}") ; do
        local splitDir="${exampleDir}/data/${exampleName}/${splitId}"
        if [ ! -d "${splitDir}" ]; then
            continue
        fi

        echo "Running ${exampleName} -- Iteration: ${iterationID}, Split: ${splitId}."
        local baseOutDir="${BASE_OUT_DIR}/${RUN_ID}/${iterationID}/${exampleName}/${splitId}"

        # Change the split used in the data files.
        sed -i "s#data/${exampleName}/[0-9]\\+#data/${exampleName}/${splitId}#g" "${cliDir}/${exampleName}"*.data

        run_example "${cliDir}" "${baseOutDir}"
    done

    # Reset the data files back to split zero.
    sed -i "s#data/${exampleName}/[0-9]\\+#data/${exampleName}/0#g" "${cliDir}/${exampleName}"*.data
}

function main() {
    if [[ $# -eq 0 ]]; then
        echo "USAGE: $0 <example dir> ..."
        exit 1
    fi

    trap exit SIGINT

    for i in `seq -w 1 ${NUM_RUNS}`; do
        for exampleDir in "$@"; do
            run_example_splits "${exampleDir}" "${i}"
        done
    done
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"
