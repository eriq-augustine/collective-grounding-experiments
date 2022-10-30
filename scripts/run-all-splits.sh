#!/bin/bash

# Run all the splits of all the specified psl-examples.

readonly THIS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
readonly BASE_OUT_DIR="${THIS_DIR}/../results"
readonly EXAMPLES_DIR="${THIS_DIR}/../psl-examples"

readonly CLEAR_CACHE_SCRIPT=$(realpath "${THIS_DIR}/clear_cache.sh")
readonly BSOE_CLEAR_CACHE_SCRIPT=$(realpath "${THIS_DIR}/bsoe_clear_cache.sh")

readonly ADDITIONAL_PSL_OPTIONS='-D inference.skip=true'

# An identifier to differentiate the output of this script/experiment from other scripts.
readonly RUN_ID='all-splits'

# A directory that only exists on BSOE servers.
readonly BSOE_DIR='/soe'

readonly NUM_RUNS=10

readonly CANDIDATE_COUNTS='01 02 03 04 05'
readonly SEARCH_BUDGET='01 03 05 07 09'
readonly SEARCH_TYPE='BFS DFS UCS BoundedUCS BoundedDFS'

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

function run_example_splits() {
    local exampleDir=$1
    local iterationID=$2

    local exampleName=`basename "${exampleDir}"`
    local cliDir="$exampleDir/cli"

    local options=''

    for splitId in $(ls -1 "${exampleDir}/data/${exampleName}") ; do
        local splitDir="${exampleDir}/data/${exampleName}/${splitId}"
        if [ ! -d "${splitDir}" ]; then
            continue
        fi

        # Change the split used in the data files.
        sed -i "s#data/${exampleName}/[0-9]\\+#data/${exampleName}/${splitId}#g" "${cliDir}/${exampleName}"*.data

        local baseOutDir="${BASE_OUT_DIR}/example::${exampleName}/iteration::${iterationID}/split::${splitId}"
        local baseOptions="${ADDITIONAL_PSL_OPTIONS}"

        # Run non-collective.
        outDir="${baseOutDir}/collective::false"
        options="${baseOptions} -D grounding.collective=false"
        echo "Running ${exampleName} -- Iteration: ${iterationID}, Split: ${splitId}, Collectinve: False."
        run_psl "${cliDir}" "${outDir}" "${options}"

        # Run collective over options.

        for candidateCount in ${CANDIDATE_COUNTS} ; do
            for searchBudget in ${SEARCH_BUDGET} ; do
                for searchType in ${SEARCH_TYPE} ; do
                    outDir="${baseOutDir}/collective::true"
                    options="${baseOptions} -D grounding.collective=true"

                    outDir="${outDir}/candidate_count::${candidateCount}"
                    options="${options} -D grounding.collective.candidate.count=${candidateCount}"\

                    outDir="${outDir}/search_budget::${searchBudget}"
                    options="${options} -D grounding.collective.candidate.search.budget=${searchBudget}"

                    outDir="${outDir}/search_type::${searchType}"
                    options="${options} -D grounding.collective.candidate.search.type=${searchType}"

                    echo "Running ${exampleName} -- Iteration: ${iterationID}, Split: ${splitId}, Collectinve: True, Candidate Count: ${candidateCount}, Search Budget: ${searchBudget}, Search Type: ${searchType}."
                    run_psl "${cliDir}" "${outDir}" "${options}"
                done
            done
        done
    done

    # Reset the data files back to split zero.
    sed -i "s#data/${exampleName}/[0-9]\\+#data/${exampleName}/0#g" "${cliDir}/${exampleName}"*.data
}

function main() {
    if [[ $# -ne 0 ]]; then
        echo "USAGE: $0"
        exit 1
    fi

    trap exit SIGINT

    # Clear existing jars.
    find "${EXAMPLES_DIR}" -type f -name *.jar -delete

    for i in `seq -w 1 ${NUM_RUNS}`; do
        for cliDir in "${EXAMPLES_DIR}"/*/cli ; do
            local exampleDir=$(dirname "${cliDir}")
            run_example_splits "${exampleDir}" "${i}"
        done
    done
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"
