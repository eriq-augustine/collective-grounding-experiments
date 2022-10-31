#!/bin/bash

# Fetch all the PSL examples and modify the CLI configuration for these experiments.
# Note that you can change the version of PSL used with the PSL_VERSION option here.
# BASE_PSL_OPTIONS can be used to apply optional globally to a run scripts.
# This is a good script to use when setting up experiments.

# This script has been modified for these experiments from the base psl-examples script.

readonly POSTGRES_DB='psl'
readonly BASE_PSL_OPTIONS="--postgres ${POSTGRES_DB} -D runtimestats.collect=true -D runtime.log.level=TRACE -D inference.skip=true"

# Basic configuration options.
readonly PSL_VERSION='2.3.2'

readonly BASE_DIR=$(realpath "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"/..)

readonly PSL_EXAMPLES_DIR="${BASE_DIR}/psl-examples"
readonly PSL_EXAMPLES_REPO='https://github.com/linqs/psl-examples.git'
readonly PSL_EXAMPLES_BRANCH="${PSL_VERSION}"

readonly SKIP_EXAMPLES='friendship knowledge-graph-identification simple-acquaintances social-network-analysis stance-4forums trust-prediction user-modeling'
# To avoid running the large IMDB example, use the following instead:
# readonly SKIP_EXAMPLES='friendship knowledge-graph-identification simple-acquaintances social-network-analysis stance-4forums trust-prediction user-modeling imdb-er'

readonly AVAILABLE_MEM_KB=$(cat /proc/meminfo | grep 'MemTotal' | sed 's/^[^0-9]\+\([0-9]\+\)[^0-9]\+$/\1/')
# Floor by multiples of 5 and then reserve an additional 5 GB.
readonly JAVA_MEM_GB=$((${AVAILABLE_MEM_KB} / 1024 / 1024 / 5 * 5 - 5))

readonly ER_DATA_FILE='entity-resolution-large.zip'

function fetch_psl_examples() {
   if [ -e ${PSL_EXAMPLES_DIR} ]; then
      return
   fi

   git clone ${PSL_EXAMPLES_REPO} ${PSL_EXAMPLES_DIR}

   pushd . > /dev/null
      cd "${PSL_EXAMPLES_DIR}"

      git checkout ${PSL_EXAMPLES_BRANCH}
      rm -rf ${SKIP_EXAMPLES}
   popd > /dev/null
}

# Special fixes for select examples.
function special_fixes() {
   # Change the size of the ER example to the max size.
   sed -i "s/entity-resolution-\(\w\+\).zip/${ER_DATA_FILE}/" "${PSL_EXAMPLES_DIR}/entity-resolution/data/fetchData.sh"
}

# Common to all examples.
function standard_fixes() {
    for exampleDir in `find ${PSL_EXAMPLES_DIR} -maxdepth 1 -mindepth 1 -type d -not -name '.*' -not -name '_*'`; do
        local baseName=`basename ${exampleDir}`

        pushd . > /dev/null
            cd "${exampleDir}/cli"

            # Increase memory allocation.
            sed -i "s/java -jar/java -Xmx${JAVA_MEM_GB}G -Xms${JAVA_MEM_GB}G -jar/" run.sh

            # Set the PSL version.
            sed -i "s/^readonly PSL_VERSION='.*'$/readonly PSL_VERSION='${PSL_VERSION}'/" run.sh

            # Add in the additional options.
            sed -i "s/^readonly ADDITIONAL_PSL_OPTIONS='\\(.*\\)'$/readonly ADDITIONAL_PSL_OPTIONS='\\1 ${BASE_PSL_OPTIONS}'/" run.sh

            # Experiment-specific modifications.

            # Always create a -leared version of the model in case this example has weight learning.
            cp "${baseName}.psl" "${baseName}-learned.psl"

            # Disable weight learning.
            sed -i 's/^\(\s\+\)run_weight_learning/\1# run_weight_learning/' run.sh

            # Disable evaluation, we are only looking for objective values.
            sed -i "s/^readonly ADDITIONAL_EVAL_OPTIONS='.*'$/readonly ADDITIONAL_EVAL_OPTIONS='--infer'/" run.sh
        popd > /dev/null

    done
}

function fetch_data() {
    for fetchScript in `find ${PSL_EXAMPLES_DIR} -type f -name 'fetchData.sh'`; do
        "${fetchScript}"
    done
}

function main() {
    trap exit SIGINT

    fetch_psl_examples
    special_fixes
    standard_fixes
    fetch_data

    exit 0
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"
