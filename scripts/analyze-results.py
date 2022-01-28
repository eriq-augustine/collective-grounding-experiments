#!/usr/bin/env python3

'''
Analyze the results.
The input to this script should be the output from parse-results.py, ex:
```
./scripts/parse-results.py > results.txt
./scripts/analyze-results.py AGGREGATE results.txt
```
'''

import os
import statistics
import sys

BOOL_COLUMNS = {
    'collective',
}

INT_COLUMNS = {
    'candidate_count',
    'search_budget',
    'runtime',
    'memory',
}

# Rows that match these columns are baselines.
BASELINE_STATIC_COLUMNS = {
    'collective': False,
    'candidate_count': None,
    'search_budget': None,
    'search_type': None,
}

RESULT_COLUMNS = {
    'runtime',
    'memory',
}

AGGREGATE_COLUMNS = {
    'iteration',
    'split',
}

COUNT_COLUMN = 'count'
PROPORTIONAL_SUFFIX = '_proportional'
MEAN_SUFFIX = '_mean'
STD_SUFFIX = '_std'

RUN_MODE_PROPORTIONAL = 'PROPORTIONAL'
RUN_MODE_AGGREGATE = 'AGGREGATE'

RUN_MODES = [
    RUN_MODE_PROPORTIONAL,
    RUN_MODE_AGGREGATE,
]

RUN_MODE_DESCRIPTIONS = [
    'Just add proportional columns to the results.',
    'Aggregate over [%s].' % (', '.join(list(sorted(AGGREGATE_COLUMNS)))),
]

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

# Note that the keys are value for columns that are not results or baseline columns.
# So, for a row to find it's baseline, it just needs to match on these columns.
# Return: ([match column, ...], {(match value, ...): index, ...}
def getBaselineIndexes(header, rows, resultColumns):
    baselineColumns = list(sorted(BASELINE_STATIC_COLUMNS.keys()))
    matchColumns = list(sorted(set(header) - set(baselineColumns) - set(resultColumns)))

    baselines = {}

    for i in range(len(rows)):
        baselineMatch = True
        for baselineColumn in baselineColumns:
            if (rows[i][header.index(baselineColumn)] != BASELINE_STATIC_COLUMNS[baselineColumn]):
                baselineMatch = False
                break

        if (not baselineMatch):
            continue

        matchValues = []
        for matchColumn in matchColumns:
            matchValues.append(rows[i][header.index(matchColumn)])

        baselines[tuple(matchValues)] = i

    return matchColumns, baselines

# Compute the proportional results columns and insert them into |header| and |rows|.
def createProportionalResults(header, rows, resultColumns):
    matchColumns, baselines = getBaselineIndexes(header, rows, resultColumns)

    newColumns = [header + PROPORTIONAL_SUFFIX for header in resultColumns]

    for i in range(len(rows)):
        matchValues = tuple([rows[i][header.index(matchColumn)] for matchColumn in matchColumns])
        baselineIndex = baselines[matchValues]
        assert(baselineIndex is not None)

        for resultColumn in resultColumns:
            value = rows[i][header.index(resultColumn)]
            baselineValue = rows[baselineIndex][header.index(resultColumn)]

            if (baselineValue == 0):
                rows[i].append(None)
            else:
                rows[i].append(value / baselineValue)

    resultColumns.extend(newColumns)
    header.extend(newColumns)

    return resultColumns + newColumns

# Aggregate rows.
# Will not modify the passed-in structures, and instead pass out new versions.
def aggregate(header, rows, resultColumns, aggregateColumns = AGGREGATE_COLUMNS):
    assert(COUNT_COLUMN not in header)

    newResultColumns = [COUNT_COLUMN]
    newResultColumns += [resultColumn + MEAN_SUFFIX for resultColumn in resultColumns]
    newResultColumns += [resultColumn + STD_SUFFIX for resultColumn in resultColumns]
    newResultColumns = list(sorted(newResultColumns))

    newColumns = list(header)
    for resultColumn in (list(resultColumns) + list(aggregateColumns)):
        newColumns.remove(resultColumn)
    newColumns += newResultColumns

    matchColumns = list(sorted(set(header) - set(resultColumns) - set(aggregateColumns)))

    # {(match value, ...): {column: value, ...}, ...}
    # The old result columns will be used to hold all values, e.g., `{runtime: [value, ...], ...}`.
    aggregateData = {}

    for row in rows:
        matchValues = tuple([row[header.index(matchColumn)] for matchColumn in matchColumns])
        if (matchValues not in aggregateData):
            newEntry = {column: row[header.index(column)] for column in matchColumns}
            newEntry.update({column: 0 for column in newResultColumns})
            newEntry.update({column: [] for column in resultColumns})
            aggregateData[matchValues] = newEntry

        aggregateData[matchValues][COUNT_COLUMN] += 1

        for resultColumn in resultColumns:
            aggregateData[matchValues][resultColumn].append(row[header.index(resultColumn)])

    newRows = []
    for aggregateRow in aggregateData.values():
        newRow = [aggregateRow[column] for column in newColumns]

        for resultColumn in resultColumns:
            meanColumn = resultColumn + MEAN_SUFFIX
            stdColumn = resultColumn + STD_SUFFIX

            newRow[newColumns.index(meanColumn)] = statistics.mean(aggregateRow[resultColumn])
            newRow[newColumns.index(stdColumn)] = statistics.stdev(aggregateRow[resultColumn])

        newRows.append(newRow)

    return newColumns, newRows, newResultColumns

def output(header, rows):
    print("\t".join(header))
    for row in rows:
        print("\t".join(map(str, row)))

def mainProportional(resultColumns, header, rows):
    createProportionalResults(header, rows, resultColumns)
    output(header, rows)

def mainAggregate(resultColumns, header, rows):
    createProportionalResults(header, rows, resultColumns)
    aggregateHeader, aggregateRows, aggregateResultColumns = aggregate(header, rows, resultColumns)
    output(aggregateHeader, aggregateRows)

def main(mode, resultsPath):
    resultColumns = list(sorted(RESULT_COLUMNS))

    header, rows = fetchResults(resultsPath)
    if (len(rows) == 0):
        return

    if (mode == RUN_MODE_PROPORTIONAL):
        mainProportional(resultColumns, header, rows)
    elif (mode == RUN_MODE_AGGREGATE):
        mainAggregate(resultColumns, header, rows)
    else:
        raise ValueError("Unknown mode: '%s'." % (mode))

def _load_args(args):
    executable = args.pop(0)
    if (len(args) != 2 or ({'h', 'help'} & {arg.lower().strip().replace('-', '') for arg in args})):
        print("USAGE: python3 %s <mode> <results path>" % (executable), file = sys.stderr)
        print("modes:", file = sys.stderr)
        for i in range(len(RUN_MODES)):
            print("    %s - %s" % (RUN_MODES[i], RUN_MODE_DESCRIPTIONS[i]), file = sys.stderr)
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
