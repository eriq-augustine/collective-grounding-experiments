#!/usr/bin/env python3

'''
Analyze the results.
This script assumes that the 11th iteration is used for hyperparameter selection.
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

SIMILARITIES = [
    'ATC',
    'CHEMICAL',
    'DIST',
    'GO',
    'LIGAND',
    'SEQ',
    'SIDEEFFECT',
]

# Get the "baseline" (non-collective) rows.
BASELINE_QUERY = '''
    SELECT *
    FROM Stats
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
        ''' + ', '.join(["AVG(S.%s_query_time) AS %s_query_time_mean" % (sim, sim) for sim in SIMILARITIES]) + ''',
        ''' + ', '.join(["STDEV(S.%s_query_time) AS %s_query_time_std" % (sim, sim) for sim in SIMILARITIES]) + ''',
        ''' + ', '.join(["AVG(S.%s_num_results) AS %s_num_results_mean" % (sim, sim) for sim in SIMILARITIES]) + ''',
        ''' + ', '.join(["STDEV(S.%s_num_results) AS %s_num_results_std" % (sim, sim) for sim in SIMILARITIES]) + '''
    FROM
        (
            ''' + BASELINE_QUERY + '''
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

PIVOT_QUERY = '''
    ''' + ' UNION ALL '.join(['''
    SELECT
        collective,
        '%s' AS sim,
        %s_query_time_mean AS 'query_time_mean',
        %s_query_time_std AS 'query_time_std',
        %s_num_results_mean AS 'num_results_mean',
        %s_num_results_std AS 'num_results_std'
    FROM (''' % (sim, sim, sim, sim, sim) + AGGREGATE_QUERY + ''')
    ''' for sim in SIMILARITIES]) + '''
'''

TABLE_QUERY = '''
    SELECT
        I.sim AS 'Similarity Measure',

        CAST(CAST(I.query_time_mean AS INT) AS TEXT)
            || ' ± '
            || CAST(CAST(I.query_time_std AS INT) AS TEXT)
            AS 'Base Query Runtime',

        CAST(CAST(I.num_results_mean AS INT) AS TEXT)
            || ' ± '
            || CAST(CAST(I.num_results_std AS INT) AS TEXT)
            AS 'Base Query Num Results',

        CAST(CAST(C.query_time_mean AS INT) AS TEXT)
            || ' ± '
            || CAST(CAST(C.query_time_std AS INT) AS TEXT)
            AS 'CG Query Runtime',

        CAST(CAST(C.num_results_mean AS INT) AS TEXT)
            || ' ± '
            || CAST(CAST(C.num_results_std AS INT) AS TEXT)
            AS 'CG Query Num Results'
    FROM
        (
            ''' + PIVOT_QUERY + '''
        ) I
        JOIN (
            ''' + PIVOT_QUERY + '''
        ) C ON I.sim = C.sim
    WHERE
        I.collective = FALSE
        AND C.collective = TRUE
'''

BOOL_COLUMNS = {
    'collective',
}

INT_COLUMNS = {
    'iteration',
    'candidate_count',
    'search_budget',
}
INT_COLUMNS |= set([sim + suffix for sim in SIMILARITIES for suffix in ['_query_time', '_num_results']])

FLOAT_COLUMNS = {
}

# {key: (query, description), ...}
RUN_MODES = {
    'BASE': (
        BASELINE_QUERY,
        'Just get the base results.',
    ),
    'AGGREGATE': (
        AGGREGATE_QUERY,
        'Aggregate over iteration and split.',
    ),
    'PIVOT': (
        PIVOT_QUERY,
        'Pivot sims.',
    ),
    'TABLE': (
        TABLE_QUERY,
        'Get the results in a more table-ready form.',
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
                elif (header[i] in FLOAT_COLUMNS):
                    row[i] = float(row[i])

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

    quotedColumns = ["'%s'" % column for column in columns]

    columnDefs = []
    for i in range(len(columns)):
        column = columns[i]
        quotedColumn = quotedColumns[i]

        if (column in BOOL_COLUMNS):
            columnDefs.append("%s INTEGER" % (quotedColumn))
        elif (column in INT_COLUMNS):
            columnDefs.append("%s INTEGER" % (quotedColumn))
        elif (column in FLOAT_COLUMNS):
            columnDefs.append("%s FLOAT" % (quotedColumn))
        else:
            columnDefs.append("%s TEXT" % (quotedColumn))

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
        print("USAGE: python3 %s <results path> <mode>" % (executable), file = sys.stderr)
        print("modes:", file = sys.stderr)
        for (key, (query, description)) in RUN_MODES.items():
            print("    %s - %s" % (key, description), file = sys.stderr)
        sys.exit(1)

    resultsPath = args.pop(0)
    if (not os.path.isfile(resultsPath)):
        raise ValueError("Can't find the specified results path: " + resultsPath)

    mode = args.pop(0).upper()
    if (mode not in RUN_MODES):
        raise ValueError("Unknown mode: '%s'." % (mode))

    return mode, resultsPath

if (__name__ == '__main__'):
    main(*_load_args(sys.argv))
