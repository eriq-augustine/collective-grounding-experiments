#!/bin/bash

readonly BASE_DIR=$(realpath "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"/..)
readonly BASE_OUT_DIR="${BASE_DIR}/results"

readonly PSL_EXAMPLES_DIR="${BASE_DIR}/psl-examples"
readonly PSL_EXAMPLES_REPO='https://github.com/linqs/psl-examples.git'
readonly PSL_EXAMPLES_BRANCH='develop'

readonly SPECIAL_DATA_DIR="${BASE_DIR}/special-data"
readonly FRIENDSHIP_PAIRWISE_DIR="${SPECIAL_DATA_DIR}/other-examples/friendship-pairwise"
readonly AUGMENTED_FRIENDSHIP_DIR="${SPECIAL_DATA_DIR}/augmented-data/friendship"
readonly FAMILIAL_ER_DIR="${SPECIAL_DATA_DIR}/other-examples/familial-er"
readonly IMDB_ER_DIR="${SPECIAL_DATA_DIR}/other-examples/imdb-er"

readonly POSTGRES_DB='psl'
readonly BASE_PSL_OPTION="--postgres ${POSTGRES_DB} -D log4j.threshold=TRACE -D persistedatommanager.throwaccessexception=false -D grounding.serial=true"

# Examples that cannot use int ids.
readonly STRING_IDS='entity-resolution simple-acquaintances user-modeling'

readonly NUM_RUNS=20

readonly STDOUT_FILE='out.txt'
readonly STDERR_FILE='out.err'

readonly ER_DATA_SZIE='large'

readonly MEM_GB='25'

function fetch_psl_examples() {
   if [ -e ${PSL_EXAMPLES_DIR} ]; then
      return
   fi

   git clone ${PSL_EXAMPLES_REPO} ${PSL_EXAMPLES_DIR}

   pushd . > /dev/null
      cd "${PSL_EXAMPLES_DIR}"
      git checkout ${PSL_EXAMPLES_BRANCH}
   popd > /dev/null
}

# Special fixes for select examples.
function special_fixes() {
   # Change the size of the ER example to the max size.
   sed -i "s/^readonly SIZE='.*'$/readonly SIZE='${ER_DATA_SZIE}'/" "${PSL_EXAMPLES_DIR}/entity-resolution/data/fetchData.sh"

   # Replace the data in friendship
   rm -rf "${PSL_EXAMPLES_DIR}/friendship/data/friendship"
   cp -r "${AUGMENTED_FRIENDSHIP_DIR}" "${PSL_EXAMPLES_DIR}/friendship/data/friendship"

   # Copy in other examples
   cp -r "${FRIENDSHIP_PAIRWISE_DIR}" "${PSL_EXAMPLES_DIR}/"
   cp -r "${FAMILIAL_ER_DIR}" "${PSL_EXAMPLES_DIR}/"
   cp -r "${IMDB_ER_DIR}" "${PSL_EXAMPLES_DIR}/"
}

# Common to all examples.
function standard_fixes() {
    for exampleDir in `find ${PSL_EXAMPLES_DIR} -maxdepth 1 -mindepth 1 -type d -not -name '.git'`; do
        local baseName=`basename ${exampleDir}`
        local options=''

        # Check for int ids.
        if [[ "${STRING_IDS}" != *"${baseName}"* ]]; then
            options="--int-ids ${options}"
        fi

        pushd . > /dev/null
            cd "${exampleDir}/cli"

            # Always create a -leared version of the model in case this example has weight learning.
            cp "${baseName}.psl" "${baseName}-learned.psl"

            # Increase memory allocation.
            sed -i "s/java -jar/java -Xmx${MEM_GB}G -Xms${MEM_GB}G -jar/" run.sh

            # Disable weight learning.
            sed -i 's/^\(\s\+\)runWeightLearning/\1# runWeightLearning/' run.sh

            # Add in the additional options.
            sed -i "s/^readonly ADDITIONAL_PSL_OPTIONS='.*'$/readonly ADDITIONAL_PSL_OPTIONS='${BASE_PSL_OPTION} ${options}'/" run.sh

            # Disable evaluation, we only really want grounding.
            sed -i "s/^readonly ADDITIONAL_EVAL_OPTIONS='.*'$/readonly ADDITIONAL_EVAL_OPTIONS='--infer'/" run.sh
        popd > /dev/null

    done
}

function main() {
   trap exit SIGINT

   fetch_psl_examples
   special_fixes
   standard_fixes

   exit 0
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"
