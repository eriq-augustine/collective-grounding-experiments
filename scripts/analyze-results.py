#!/usr/bin/env python3

'''
Analyze the results.
The input to this script should be the output from parse-results.py, ex:
```
./scripts/parse-results.py > results.txt
./scripts/analyze-results.py AGGREGATE results.txt
```
'''

import math
import os
import sqlite3
import sys

# Get the "baseline" (non-collective) rows.
BASELINE_QUERY = '''
    SELECT *
    FROM Stats
    WHERE collective = FALSE
'''

# Compare runs against their relevant baseline (non-collective) run.
PROPORTIONAL_QUERY = '''
    SELECT
        S.example,
        S.iteration,
        S.split,
        S.collective,
        S.candidate_count,
        S.search_budget,
        S.search_type,
        S.runtime,
        S.runtime / CAST(B.runtime AS FLOAT) AS runtime_proportional,
        S.memory,
        S.memory / CAST(B.memory AS FLOAT) AS memory_proportional
    FROM
        Stats S
        JOIN (
            ''' + BASELINE_QUERY + '''
        ) B ON
            S.example = B.example
            AND S.iteration = B.iteration
            AND S.split = B.split
    ORDER BY
        S.example,
        S.iteration,
        S.split,
        S.collective,
        S.candidate_count,
        S.search_budget,
        S.search_type
'''

# Aggregate over splits and iterations.
AGGREGATE_QUERY = '''
    SELECT
        S.example,
        S.collective,
        S.candidate_count,
        S.search_budget,
        S.search_type,
        COUNT(*) AS aggregate_count,
        AVG(S.runtime) AS runtime_mean,
        STDEV(S.runtime) AS runtime_std,
        AVG(S.runtime_proportional) AS runtime_proportional_mean,
        STDEV(S.runtime_proportional) AS runtime_proportional_std,
        AVG(S.memory) AS memory_mean,
        STDEV(S.memory) AS memory_std,
        AVG(S.memory_proportional) AS memory_proportional_mean,
        STDEV(S.memory_proportional) AS memory_proportional_std
    FROM
        (
            ''' + PROPORTIONAL_QUERY + '''
        ) S
    GROUP BY
        S.example,
        S.collective,
        S.candidate_count,
        S.search_budget,
        S.search_type
    ORDER BY
        S.example,
        S.collective,
        S.candidate_count,
        S.search_budget,
        S.search_type
'''

# Aggregate over iterations/splits, and pull out the best hyperparam collection per example.
AGGREGATE_BEST_PER_EXAMPLE_QUERY = '''
    SELECT
        A.example,
        ROW_NUMBER() OVER ExampleWindow AS example_rank,
        A.collective,
        A.candidate_count,
        A.search_budget,
        A.search_type,
        A.aggregate_count,
        A.runtime_mean,
        A.runtime_std,
        A.runtime_proportional_mean,
        A.runtime_proportional_std,
        A.memory_mean,
        A.memory_std,
        A.memory_proportional_mean,
        A.memory_proportional_std
    FROM
        (
            ''' + AGGREGATE_QUERY + '''
        ) A
    WHERE A.collective = TRUE
    WINDOW ExampleWindow AS (
        PARTITION BY A.example
        ORDER BY A.runtime_proportional_mean ASC
    )
'''

# Like the previous query, but also aggregate over examples.
# Only report proportional numbers (since flat ones don't make sense across examples).
EXAMPLE_AGGREGATE_QUERY = '''
    SELECT
        S.collective,
        S.candidate_count,
        S.search_budget,
        S.search_type,
        COUNT(*) AS aggregate_count,
        AVG(S.runtime_proportional) AS runtime_proportional_mean,
        STDEV(S.runtime_proportional) AS runtime_proportional_std,
        AVG(S.memory_proportional) AS memory_proportional_mean,
        STDEV(S.memory_proportional) AS memory_proportional_std
    FROM
        (
            ''' + PROPORTIONAL_QUERY + '''
        ) S
    GROUP BY
        S.collective,
        S.candidate_count,
        S.search_budget,
        S.search_type
    ORDER BY
        S.collective,
        S.candidate_count,
        S.search_budget,
        S.search_type
'''

BOOL_COLUMNS = {
    'collective',
}

INT_COLUMNS = {
    'candidate_count',
    'search_budget',
    'runtime',
    'memory',
}

# {key: (query, description), ...}
RUN_MODES = {
    'PROPORTIONAL': (
        PROPORTIONAL_QUERY,
        'Just add proportional columns to the results.',
    ),
    'AGGREGATE': (
        AGGREGATE_QUERY,
        'Aggregate over iteration and split.',
    ),
    'AGGREGATE_BEST_PER_EXAMPLE': (
        AGGREGATE_BEST_PER_EXAMPLE_QUERY,
        'Aggregate over iteration and split, and show the best hyperparams for each example.',
    ),
    'EXAMPLE_AGGREGATE': (
        EXAMPLE_AGGREGATE_QUERY,
        'Aggregate over iteration, split, and example.',
    ),
    'AGGREGATE_BEST_PER_EXAMPLE': (
        AGGREGATE_BEST_PER_EXAMPLE_QUERY,
        'Aggregate over iteration and split, and show the best hyperparams for each example.',
    ),
}

# ([header, ...], [[value, ...], ...])
def fetchResults(path):
    rows = []
    header = None

    with open(path, 'r') as file:
        for line in file:
            line = line.strip("\n ")
            if (line == ''):
                continue

            row = line.split("\t")

            # Get the header first.
            if (header is None):
                header = row
                continue

            assert(len(header) == len(row))

            for i in range(len(row)):
                if (row[i] == ''):
                    row[i] = None
                elif (header[i] in BOOL_COLUMNS):
                    row[i] = (row[i].upper() == 'TRUE')
                elif (header[i] in INT_COLUMNS):
                    row[i] = int(row[i])

            rows.append(row)

    return header, rows

# Standard deviation UDF for sqlite3.
# Taken from: https://www.alexforencich.com/wiki/en/scripts/python/stdev
class StdevFunc:
    def __init__(self):
        self.M = 0.0
        self.S = 0.0
        self.k = 1

    def step(self, value):
        if value is None:
            return
        tM = self.M
        self.M += (value - tM) / self.k
        self.S += (value - tM) * (value - self.M)
        self.k += 1

    def finalize(self):
        if self.k < 3:
            return None
        return math.sqrt(self.S / (self.k-2))

def main(mode, resultsPath):
    columns, data = fetchResults(resultsPath)
    if (len(data) == 0):
        return

    columnDefs = []
    for column in columns:
        if (column in BOOL_COLUMNS):
            columnDefs.append("%s INTEGER" % (column))
        elif (column in INT_COLUMNS):
            columnDefs.append("%s INTEGER" % (column))
        else:
            columnDefs.append("%s TEXT" % (column))


    connection = sqlite3.connect(":memory:")
    connection.create_aggregate("STDEV", 1, StdevFunc)

    connection.execute("CREATE TABLE Stats(%s)" % (', '.join(columnDefs)))

    connection.executemany("INSERT INTO Stats(%s) VALUES (%s)" % (', '.join(columns), ', '.join(['?'] * len(columns))), data)

    query = RUN_MODES[mode][0]
    rows = connection.execute(query)

    print("\t".join([column[0] for column in rows.description]))
    for row in rows:
        print("\t".join(map(str, row)))

    connection.close()

def _load_args(args):
    executable = args.pop(0)
    if (len(args) != 2 or ({'h', 'help'} & {arg.lower().strip().replace('-', '') for arg in args})):
        print("USAGE: python3 %s <mode> <results path>" % (executable), file = sys.stderr)
        print("modes:", file = sys.stderr)
        for (key, (query, description)) in RUN_MODES.items():
            print("    %s - %s" % (key, description), file = sys.stderr)
        sys.exit(1)

    mode = args.pop(0).upper()
    if (mode not in RUN_MODES):
        raise ValueError("Unknown mode: '%s'." % (mode))

    resultsPath = args.pop(0)
    if (not os.path.isfile(resultsPath)):
        raise ValueError("Can't find the specified results path: " + resultsPath)

    return mode, resultsPath

if (__name__ == '__main__'):
    main(*_load_args(sys.argv))
