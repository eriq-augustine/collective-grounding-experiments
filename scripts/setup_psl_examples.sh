#!/bin/bash

# Fetch all the PSL examples and modify the CLI configuration for these experiments.
# Note that you can change the version of PSL used with the PSL_VERSION option here.

readonly BASE_DIR=$(realpath "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"/..)

readonly PSL_EXAMPLES_DIR="${BASE_DIR}/psl-examples"
readonly PSL_EXAMPLES_REPO='https://github.com/linqs/psl-examples.git'
readonly PSL_EXAMPLES_BRANCH='develop'

readonly PSL_VERSION='2.3.0-SNAPSHOT'

readonly POSTGRES_DB='psl'
readonly BASE_PSL_OPTION="--postgres ${POSTGRES_DB} -D log4j.threshold=TRACE -D persistedatommanager.throwaccessexception=false"

# Examples that cannot use int ids.
readonly STRING_IDS='entity-resolution simple-acquaintances user-modeling'

readonly ER_DATA_SZIE='large'

readonly AVAILABLE_MEM_KB=$(cat /proc/meminfo | grep 'MemTotal' | sed 's/^[^0-9]\+\([0-9]\+\)[^0-9]\+$/\1/')
# Floor by multiples of 5 and then reserve an additional 5 GB.
readonly JAVA_MEM_GB=$((${AVAILABLE_MEM_KB} / 1024 / 1024 / 5 * 5 - 5))

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
}

# Common to all examples.
function standard_fixes() {
    for exampleDir in `find ${PSL_EXAMPLES_DIR} -maxdepth 1 -mindepth 1 -type d -not -name '.*'`; do
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
            sed -i "s/java -jar/java -Xmx${JAVA_MEM_GB}G -Xms${JAVA_MEM_GB}G -jar/" run.sh

            # Set the PSL version.
            sed -i "s/^readonly PSL_VERSION='.*'$/readonly PSL_VERSION='${PSL_VERSION}'/" run.sh

            # Disable weight learning.
            sed -i 's/^\(\s\+\)runWeightLearning/\1# runWeightLearning/' run.sh

            # Add in the additional options.
            sed -i "s/^readonly ADDITIONAL_PSL_OPTIONS='.*'$/readonly ADDITIONAL_PSL_OPTIONS='${BASE_PSL_OPTION} ${options}'/" run.sh

            # Disable evaluation, we are only looking for objective values.
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
