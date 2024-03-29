#!/usr/bin/env python3

# Parse out the results.
# TODO(eriq): This does not properly parse number of query results for IG runs (but we only need that data in one place).

import glob
import os
import re
import sys

THIS_DIR = os.path.abspath(os.path.dirname(os.path.realpath(__file__)))
RESULTS_DIR = os.path.join(THIS_DIR, '..', 'results')

LOG_FILENAME = 'out.txt'

HEADER = [
    # Identifiers
    'example',
    'iteration',
    'split',
    'collective',
    'candidate_count',
    'search_budget',
    'search_type',
    # Results
    'runtime',
    'search_time',
    'query_time',
    'grounding_time',
    'memory',
    'num_rules',
    'num_queries',
    'num_query_results',
    'num_ground_rules',
]

def parseLog(logPath):
    results = {}

    # Fetch the run identifiers off of the path.
    for (key, value) in re.findall(r'([\w\-]+)::([\w\-]+)', logPath):
        results[key] = value

    groundTimeStart = None
    searchTimeStart = None
    queryTimeStart = None

    rules = 0
    queries = 0
    queryResults = 0
    groundRules = 0

    with open(logPath, 'r') as file:
        for line in file:
            line = line.strip()
            if (line == ''):
                continue

            match = re.search(r'^(\d+)\s+\[', line)
            if (match is not None):
                time = int(match.group(1))

            match = re.search(r'INFO  org.linqs.psl.application.inference.InferenceApplication  - Grounding out model.', line)
            if (match is not None):
                groundTimeStart = time

            match = re.search(r'DEBUG org.linqs.psl.grounding.Grounding  - Generating candidates.', line)
            if (match is not None):
                searchTimeStart = time

            match = re.search(r'DEBUG org.linqs.psl.grounding.Grounding  - Generated (\d+) candidates', line)
            if (match is not None and searchTimeStart is not None):
                results['search_time'] = time - searchTimeStart
                queryTimeStart = time

            match = re.search(r'DEBUG org.linqs.psl.grounding.Grounding  - Grounding (\d+) rule\(s\) with query:', line)
            if (match is not None):
                queries += 1
                rules += int(match.group(1))

            match = re.search(r'DEBUG org.linqs.psl.grounding.Grounding  - Generated (\d+) ground rules from (\d+) query results.', line)
            if (match is not None):
                queryResults += int(match.group(2))

            match = re.search(r'org.linqs.psl.application.inference.InferenceApplication  - Generated (\d+) ground rules.', line)
            if (match is not None):
                groundRules = int(match.group(1))

            match = re.search(r'INFO  org.linqs.psl.application.inference.InferenceApplication  - Grounding complete.', line)
            if (match is not None):
                results['grounding_time'] = time - groundTimeStart

                if (queryTimeStart is None):
                    # IG
                    results['search_time'] = 0
                    results['query_time'] = time - groundTimeStart
                else:
                    # CG
                    results['query_time'] = time - queryTimeStart

            match = re.search(r'INFO  org.linqs.psl.util.RuntimeStats  - Used Memory \(bytes\)  -- Min:\s*(\d+), Max:\s*(\d+), Mean:\s*(\d+), Count:\s*(\d+)$', line)
            if (match is not None):
                results['runtime'] = time
                results['memory'] = int(match.group(2))

    # Check for an unfinished run.
    if ('runtime' not in results):
        return None

    results['num_rules'] = rules
    results['num_queries'] = queries
    results['num_query_results'] = queryResults
    results['num_ground_rules'] = groundRules

    return results

# [{key, value, ...}, ...]
def fetchResults():
    runs = []

    for logPath in glob.glob("%s/**/%s" % (RESULTS_DIR, LOG_FILENAME), recursive = True):
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
