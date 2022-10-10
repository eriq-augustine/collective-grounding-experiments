#!/usr/bin/env python3

# Parse out the results for the DDI similarity comparison.
# We will need DDI per-rule information for both IG and a specific run of CG (whatever final hyperparams are chosen).

import glob
import os
import re
import sys

THIS_DIR = os.path.abspath(os.path.dirname(os.path.realpath(__file__)))
RESULTS_DIR = os.path.join(THIS_DIR, '..', 'results', 'experiment::first-split', 'example::drug-drug-interaction')

COLLECTIVE_HYPERPARAMS = {
    'candidate_count': '05',
    'search_budget': '05',
    'search_type': 'BoundedDFS',
}

LOG_FILENAME = 'out.txt'

SIMILARITIES = [
    'ATC',
    'CHEMICAL',
    'DIST',
    'GO',
    'LIGAND',
    'SEQ',
    'SIDEEFFECT',
]

HEADER = [
    # Identifiers
    'example',
    'iteration',
    'split',
    'collective',
    'candidate_count',
    'search_budget',
    'search_type',
]

# Results
HEADER += [sim + suffix for sim in SIMILARITIES for suffix in ['_query_time', '_num_results']]

def parseLog(logPath):
    results = getIdentifiersFromPath(logPath)

    sims = []
    currentSim = None
    queryStartTime = None

    with open(logPath, 'r') as file:
        for line in file:
            line = line.strip()
            if (line == ''):
                continue

            match = re.search(r'^(\d+)\s+\[', line)
            if (match is not None):
                time = int(match.group(1))

            match = re.search(r'TRACE org.linqs.psl.database.rdbms.RDBMSDatabase  - SELECT .* (\w+)SIMILARITY_PREDICATE .*$', line)
            if (match is not None):
                currentSim = match.group(1)
                queryStartTime = time

            match = re.search(r'DEBUG .* - Generated (\d+) ground rules from (\d+) query results.', line)
            if (match is not None and currentSim is not None):
                results[currentSim + '_query_time'] = time - queryStartTime
                results[currentSim + '_num_results'] = int(match.group(2))

                sims.append(currentSim)
                currentSim = None
                queryStartTime = None

    # Check for incomplete runs.
    if (len(sims) != len(SIMILARITIES)):
        return None

    return results

def getIdentifiersFromPath(logPath):
    results = {}

    # Fetch the run identifiers off of the path.
    for (key, value) in re.findall(r'([\w\-]+)::([\w\-]+)', logPath):
        results[key] = value

    return results

# [{key, value, ...}, ...]
def fetchResults():
    runs = []

    for logPath in glob.glob("%s/**/%s" % (RESULTS_DIR, LOG_FILENAME), recursive = True):
        props = getIdentifiersFromPath(logPath)

        if (props['example'] != 'drug-drug-interaction'):
            continue

        if (props['collective'] == 'true'):
            keep = True

            for (key, value) in COLLECTIVE_HYPERPARAMS.items():
                if (props[key] != value):
                    keep = False
                    break

            if (not keep):
                continue

        run = parseLog(logPath)
        if (run is not None):
            runs.append(run)

    return runs

def main():
    runs = fetchResults()
    if (len(runs) == 0):
        return

    rows = []
    for run in runs:
        rows.append([run.get(key, '') for key in HEADER])

    print("\t".join(HEADER))
    for row in rows:
        print("\t".join(map(str, row)))

def _load_args(args):
    executable = args.pop(0)
    if (len(args) != 0 or ({'h', 'help'} & {arg.lower().strip().replace('-', '') for arg in args})):
        print("USAGE: python3 %s" % (executable), file = sys.stderr)
        sys.exit(1)

if (__name__ == '__main__'):
    _load_args(sys.argv)
    main()
