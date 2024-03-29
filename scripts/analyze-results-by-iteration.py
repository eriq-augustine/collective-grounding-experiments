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
        S.memory / CAST(B.memory AS FLOAT) AS memory_proportional,
        S.search_time,
        S.query_time,
        S.grounding_time,
        S.num_rules,
        S.num_queries,
        S.num_query_results,
        S.num_ground_rules
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
        STDEV(S.memory_proportional) AS memory_proportional_std,
        AVG(S.search_time) AS search_time_mean,
        STDEV(S.search_time) AS search_time_std,
        AVG(S.query_time) AS query_time_mean,
        STDEV(S.query_time) AS query_time_std,
        AVG(S.grounding_time) AS grounding_time_mean,
        STDEV(S.grounding_time) AS grounding_time_std,
        AVG(S.num_rules) AS num_rules_mean,
        STDEV(S.num_rules) AS num_rules_std,
        AVG(S.num_queries) AS num_queries_mean,
        STDEV(S.num_queries) AS num_queries_std,
        AVG(S.num_query_results) AS num_query_results_mean,
        STDEV(S.num_query_results) AS num_query_results_std,
        AVG(S.num_ground_rules) AS num_ground_rules_mean,
        STDEV(S.num_ground_rules) AS num_ground_rules_std
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
AGGREGATE_RANK_QUERY = '''
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
    ORDER BY
        ROW_NUMBER() OVER ExampleWindow,
        A.example,
        A.collective,
        A.candidate_count,
        A.search_budget,
        A.search_type
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

# For the validation iteration (11), aggregate and rank the hyperparams.
VALIDATION_AGGREGATEION_RANK_QUERY = '''
    SELECT
        S.example,
        ROW_NUMBER() OVER ExampleWindow AS example_rank,
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
    WHERE
        S.collective = TRUE
        AND S.iteration = 11  -- Validation iteration.
    GROUP BY
        S.example,
        S.collective,
        S.candidate_count,
        S.search_budget,
        S.search_type
    WINDOW ExampleWindow AS (
        PARTITION BY S.example
        ORDER BY AVG(S.runtime_proportional) ASC
    )
    ORDER BY
        ROW_NUMBER() OVER ExampleWindow,
        S.example,
        S.collective,
        S.candidate_count,
        S.search_budget,
        S.search_type
'''

# For the validation iteration (11), aggregate over iterations / example, and rank the hyperparams.
VALIDATION_AGGREGATEION_EXAMPLE_RANK_QUERY = '''
    SELECT
        ROW_NUMBER() OVER ParamWindow AS rank,
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
    WHERE
        S.collective = TRUE
        AND S.iteration = 11  -- Validation iteration.
    GROUP BY
        S.collective,
        S.candidate_count,
        S.search_budget,
        S.search_type
    WINDOW ParamWindow AS (
        ORDER BY AVG(S.runtime_proportional) ASC
    )
    ORDER BY
        ROW_NUMBER() OVER ParamWindow,
        S.collective,
        S.candidate_count,
        S.search_budget,
        S.search_type
'''

# Aggregate over iterations / splits, but ignore the validation split.
NO_VALIDATION_AGGREGATEION_QUERY = '''
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
        STDEV(S.memory_proportional) AS memory_proportional_std,
        AVG(S.search_time) AS search_time_mean,
        STDEV(S.search_time) AS search_time_std,
        AVG(S.query_time) AS query_time_mean,
        STDEV(S.query_time) AS query_time_std,
        AVG(S.grounding_time) AS grounding_time_mean,
        STDEV(S.grounding_time) AS grounding_time_std,
        AVG(S.num_rules) AS num_rules,
        AVG(S.num_queries) AS num_queries_mean,
        AVG(S.num_query_results) AS num_query_results_mean,
        AVG(S.num_ground_rules) AS num_ground_rules_mean
    FROM
        (
            ''' + PROPORTIONAL_QUERY + '''
        ) S
    WHERE S.iteration != 11
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

# Get the best set of hyperparams (for collective runs).
# "Best" is determined by best overall and best per-example (using the validation set).
BEST_HYPERPARAMS = '''
    SELECT
        'example' as param_type,
        R.example,
        R.candidate_count,
        R.search_budget,
        R.search_type
    FROM
        (
            ''' + VALIDATION_AGGREGATEION_RANK_QUERY + '''
        ) R
    WHERE
        R.collective = TRUE
        AND R.example_rank = 1

    UNION ALL

    SELECT
        'overall' as param_type,
        NULL AS example,
        R.candidate_count,
        R.search_budget,
        R.search_type
    FROM
        (
            ''' + VALIDATION_AGGREGATEION_EXAMPLE_RANK_QUERY + '''
        ) R
    WHERE
        R.collective = TRUE
        AND R.rank = 1
'''

# Use the results from NO_VALIDATION_AGGREGATEION_QUERY, and choose the rows using the best hyperparams (BEST_HYPERPARAMS).
BEST_RUNS_QUERY = '''
    SELECT
        H.param_type,
        A.*
    FROM
        (
            ''' + NO_VALIDATION_AGGREGATEION_QUERY + '''
        ) A
        JOIN (
            ''' + BEST_HYPERPARAMS + '''

            UNION ALL

            SELECT
                'baseline' as param_type,
                NULL AS example,
                NULL AS candidate_count,
                NULL AS search_budget,
                NULL AS search_type
        ) H ON
            (
                H.param_type = 'baseline'
                AND A.collective = FALSE
            ) OR (
                H.param_type = 'example'
                AND H.example = A.example
                AND H.candidate_count = A.candidate_count
                AND H.search_budget = A.search_budget
                AND H.search_type = A.search_type
            ) OR (
                H.param_type = 'overall'
                AND H.candidate_count = A.candidate_count
                AND H.search_budget = A.search_budget
                AND H.search_type = A.search_type
            )
    ORDER BY
        A.example,
        H.param_type
'''

BEST_SUMMARY_QUERY = '''
    SELECT
        B.example AS 'Dataset',

        CAST(CAST(B.runtime_mean AS INT) AS TEXT)
            || ' ± '
            || CAST(CAST(B.runtime_std AS INT) AS TEXT)
            AS 'Absolute Standard Grounding',
        CAST(CAST(E.runtime_mean AS INT) AS TEXT)
            || ' ± '
            || CAST(CAST(E.runtime_std AS INT) AS TEXT)
            AS 'Absolute Collective Grounding (Per-Dataset Hyperparameters)',
        CAST(CAST(O.runtime_mean AS INT) AS TEXT)
            || ' ± '
            || CAST(CAST(O.runtime_std AS INT) AS TEXT)
            AS 'Absolute Collective Grounding (Overall Hyperparameters)',

        CAST(ROUND(B.runtime_proportional_mean, 2) AS TEXT)
            || ' ± '
            || CAST(ROUND(B.runtime_proportional_std, 2) AS TEXT)
            AS 'Percentage Standard Grounding',
        CAST(ROUND(E.runtime_proportional_mean, 2) AS TEXT)
            || ' ± '
            || CAST(ROUND(E.runtime_proportional_std, 2) AS TEXT)
            AS 'Percentage Collective Grounding (Per-Dataset Hyperparameters)',
        CAST(ROUND(O.runtime_proportional_mean, 2) AS TEXT)
            || ' ± '
            || CAST(ROUND(O.runtime_proportional_std, 2) AS TEXT)
            AS 'Percentage Collective Grounding (Overall Hyperparameters)'
    FROM
        (
            ''' + BEST_RUNS_QUERY + '''
        ) B
        JOIN (
            ''' + BEST_RUNS_QUERY + ''')
        E ON E.example = B.example
        JOIN (
            ''' + BEST_RUNS_QUERY + ''')
        O ON O.example = B.example
    WHERE
        B.param_type = 'baseline'
        AND E.param_type = 'example'
        AND O.param_type = 'overall'
'''

# Get all the unaggregated data for the best runs (so it can be taken elsewhere for significance testing).
BEST_RUNS_RECORDS_QUERY_BASE = '''
    SELECT
        B.param_type,
        S.example,
        S.iteration,
        S.split,
        S.collective,
        S.candidate_count,
        S.search_budget,
        S.search_type,
        S.runtime
    FROM
        Stats S
        JOIN (
            ''' + BEST_RUNS_QUERY + '''
        ) B ON
            S.example = B.example
            AND (
                (
                    S.collective = FALSE
                    AND B.param_type = 'baseline'
                ) OR (
                    S.collective = TRUE
                    AND S.candidate_count = B.candidate_count
                    AND S.search_budget = B.search_budget
                    AND S.search_type = B.search_type
                )
            )
    WHERE S.iteration != 11
    ORDER BY
        B.param_type,
        S.example,
        S.iteration,
        S.split,
        S.collective,
        S.candidate_count,
        S.search_budget,
        S.search_type
'''

# Reformat BEST_RUNS_RECORDS_QUERY_BASE to use three parallel columns.
BEST_RUNS_RECORDS_QUERY = '''
    SELECT
        Baseline.example,
        Baseline.iteration,
        Baseline.split,
        Baseline.runtime AS 'IG',
        CGDataset.runtime AS 'CG (dataset)',
        CGOverall.runtime AS 'CG (overall)'
    FROM
        (
            ''' + BEST_RUNS_RECORDS_QUERY_BASE + '''
        ) Baseline
        JOIN (
            ''' + BEST_RUNS_RECORDS_QUERY_BASE + '''
        ) CGDataset ON
            Baseline.example = CGDataset.example
            AND Baseline.iteration = CGDataset.iteration
            AND Baseline.split = CGDataset.split
        JOIN (
            ''' + BEST_RUNS_RECORDS_QUERY_BASE + '''
        ) CGOverall ON
            Baseline.example = CGOverall.example
            AND Baseline.iteration = CGOverall.iteration
            AND Baseline.split = CGOverall.split
    WHERE
        Baseline.param_type = 'baseline'
        AND CGDataset.param_type = 'example'
        AND CGOverall.param_type = 'overall'
'''

BOOL_COLUMNS = {
    'collective',
}

INT_COLUMNS = {
    'iteration',
    'candidate_count',
    'search_budget',
    'runtime',
    'search_time',
    'query_time',
    'grounding_time',
    'memory',
    'num_rules',
    'num_queries',
    'num_query_results',
    'num_ground_rules',
}

FLOAT_COLUMNS = {
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
    'AGGREGATE_RANK': (
        AGGREGATE_RANK_QUERY,
        'Aggregate over iteration and split, and show the rank of hyperparams for each example.',
    ),
    'EXAMPLE_AGGREGATE': (
        EXAMPLE_AGGREGATE_QUERY,
        'Aggregate over iteration, split, and example.',
    ),
    'VALIDATION_AGGREGATE_RANK': (
        VALIDATION_AGGREGATEION_RANK_QUERY,
        'Use only the validation iteration (11), aggregate and rank the hyperparams.',
    ),
    'VALIDATION_AGGREGATE_EXAMPLE_RANK': (
        VALIDATION_AGGREGATEION_EXAMPLE_RANK_QUERY,
        'Use only the validation iteration (11), aggregate over iterations / example, and rank the hyperparams.',
    ),
    'NO_VALIDATION_AGGREGATE': (
        NO_VALIDATION_AGGREGATEION_QUERY,
        'Aggregate over iterations / splits, but ignore the validation split.',
    ),
    'BEST_RUNS': (
        BEST_RUNS_QUERY,
        'Use the results from NO_VALIDATION_AGGREGATE, and choose the rows using the best hyperparams overall (decided by EXAMPLE_AGGREGATE) and per-example (decided by VALIDATION_AGGREGATE_RANK).',
    ),
    'BEST_RUNS_SUMMARY': (
        BEST_SUMMARY_QUERY,
        'Provide a small summary table of BEST_RUNS.',
    ),
    'BEST_RUNS_RECORDS': (
        BEST_RUNS_RECORDS_QUERY,
        'Get the full (non-validation) records for all of BEST_RUNS. Useful for significance testing',
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
