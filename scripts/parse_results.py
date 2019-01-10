#!/usr/bin/env python3

import os
import re
import sys

import numpy
import scipy.stats

P_VALUE = 0.01

OUT_FILENAME = 'out.txt'

SKIP_EXAMPLES = ['simple-acquaintances', 'user-modeling']

HEADERS = [
    'Example', 'Method',
    'Mean Rewrite Time', 'StdDev Rewrite Time',
    'Mean Query Time', 'StdDev Query Time',
    'Mean Query Size', 'StdDev Query Size',
    'Mean Instantiation Time', 'StdDev Instantiation Time',
    'Mean Ground Rules', 'StdDev Ground Rules',
    'Compared to No Rewrite', 'p - Student-T vs Baseline', 'p - Welch-T vs Baseline',
    'Query Time Per Tuple', 'Instantiation Time Per Tuple', 'Instantiation / Query Cost Ratio'
]

LOG_INDEX_REWRITE_TIME = 0
LOG_INDEX_QUERY_TIME = 1
LOG_INDEX_QUERY_RESULTS = 2
LOG_INDEX_INSTANTIATION_TIME = 3
LOG_INDEX_GROUND_RULES = 4
NUM_LOG_STATS = 5

INDEX_EXAMPLE = 0
INDEX_ESTIMATOR = 1
INDEX_MEAN_QUERY_TIME = 4
INDEX_STDDEV_QUERY_TIME = 5
INDEX_MEAN_QUERY_SIZE = 6
INDEX_MEAN_INSTANTIATION_TIME = 8
INDEX_BASELINE_COMPARISON = 12
INDEX_STUDENT_P = 13
INDEX_QUERY_TIME_PER_TUPLE = 15
INDEX_INSTANTIATION_TIME_PER_TUPLE = 16

INDENT = '   '

def cleanName(text):
    if (text == 'knowledge-graph-identification'):
        return 'KGI'

    return text.replace('-', ' ').replace('_', ' ').title()

# Gives two args to the block: dirent name and dirent path.
# Does not include '.' or '..'.
def listdir(dir):
    dirents = os.listdir(dir)
    return [(dirent, os.path.join(dir, dirent)) for dirent in dirents]

def parseFile(path):
    results = [0] * NUM_LOG_STATS

    numberOfGroundingRules = None
    startTime = None
    hasRewrite = False

    with open(path, 'r') as file:
        for line in file:
            line = line.strip()
            if (line == ''):
                continue

            match = re.search(r'^(\d+)\s', line)
            if (match != None):
                time = int(match.group(1))

            match = re.search(r'- Found value true for option grounding.rewritequeries.$', line)
            if (match != None):
                startTime = time
                hasRewrite = True
                continue

            match = re.search(r'- Grounding (\d+) rules with query:', line)
            if (match != None):
                if (hasRewrite):
                    hasRewrite = False
                    results[LOG_INDEX_REWRITE_TIME] += time - startTime

                numberOfGroundingRules = int(match.group(1))
                startTime = time
                continue

            match = re.search(r'- Got (\d+) results from query', line)
            if (match != None):
                results[LOG_INDEX_QUERY_RESULTS] += numberOfGroundingRules * int(match.group(1))
                results[LOG_INDEX_QUERY_TIME] += time - startTime
                startTime = time
                continue

            match = re.search(r'- Generated (\d+) ground rules with query:', line)
            if (match != None):
                results[LOG_INDEX_GROUND_RULES] += numberOfGroundingRules * int(match.group(1))
                results[LOG_INDEX_INSTANTIATION_TIME] += time - startTime
                continue

    return results

def aggregateResults(raw_rows):
    # {'example\tmethod' => [[stat1_value1, stat1_value2, ...], ...]
    aggregates = {}

    for raw_row in raw_rows:
        key = "\t".join([raw_row[0], raw_row[1]])

        # Take only the stats.
        raw_row = raw_row[3:]

        if (key not in aggregates):
            aggregates[key] = []
            for i in range(len(raw_row)):
                aggregates[key].append([])

        for i in range(len(raw_row)):
            aggregates[key][i].append(raw_row[i])

    # Keep track of the time without rewrites so we can make a column for it.
    # {'example' => meanQueryTime, ...}
    baselineMeans = {}
    baselineTimes = {}

    # Keep track of the full results so we can test for significance against the baseline.
    # {"example\tmethod" => [time, ...], ...}
    queryTimes = {}

    results = []

    for (key, stats) in aggregates.items():
        example, method = key.split("\t")
        row = [example, method]

        for i in range(len(stats)):
            stat = stats[i]

            row.append(numpy.mean(stat))
            row.append(numpy.std(stat))

            # We keep special stats for qurey times.
            if (i == 1):
                queryTimes[key] = stat

                if (method == 'no_rewrites'):
                    baselineMeans[example] = numpy.mean(stat)
                    baselineTimes[example] = stat

        results.append(row)

    for row in results:
        baselineVals = baselineTimes[row[INDEX_EXAMPLE]]
        vals = queryTimes["\t".join([row[INDEX_EXAMPLE], row[INDEX_ESTIMATOR]])]

        row.append(row[INDEX_MEAN_QUERY_TIME] / baselineMeans[row[INDEX_EXAMPLE]])

        # Student-T against baseline.
        t, p = scipy.stats.ttest_ind(baselineVals, vals)
        row.append(p)

        # Welch-T against baseline.
        t, p = scipy.stats.ttest_ind(baselineVals, vals, equal_var = False)
        row.append(p)

        # Query time per tuple
        row.append(row[INDEX_MEAN_QUERY_TIME] / row[INDEX_MEAN_QUERY_SIZE])

        # Instantiation time per tuple.
        row.append(row[INDEX_MEAN_INSTANTIATION_TIME] / row[INDEX_MEAN_QUERY_SIZE])

        row.append(row[INDEX_INSTANTIATION_TIME_PER_TUPLE] / row[INDEX_QUERY_TIME_PER_TUPLE])

    return results

def parseDir(resultDir):
    results = []

    for (example, examplePath) in listdir(resultDir):
        if (example in SKIP_EXAMPLES):
            continue

        for (method, methodPath) in listdir(examplePath):
            for (run, runPath) in listdir(methodPath):
                result = parseFile(os.path.join(runPath, OUT_FILENAME))
                if (result == None):
                    continue

                result = [example, method, run] + result
                results.append(result)

    results = aggregateResults(results)

    return results

# Note: This function makes some strong assumptions about the structure of the rows.
def makeTables(rows):
    makeDatasetTable(rows)
    print("\n%%%%%\n")
    makeEstimatorTable(rows)

def makeEstimatorTable(rows):
    # for row in rows:

    print(INDENT * 1 + '\\begin{table}[h]')
    print(INDENT * 2 + '\\tiny')
    print()
    print(INDENT * 2 + '\\begin{center}')
    print(INDENT * 3 + '\\caption{Qualitative performance of different query cost estimators compared to the baseline aggregated over datasets.}')
    print()
    print(INDENT * 3 + '\\begin{tabular}{ l | r | r | r }')
    print(INDENT * 4 + '\\toprule')
    print(INDENT * 5 + 'Cost Estimator & Improved & No Change & Worsened \\\\')
    print()
    print(INDENT * 4 + '\\midrule')
    print()

    # {estimator: [improved, noChange, worsened], ...}
    stats = {}

    for row in rows:
        estimator = row[INDEX_ESTIMATOR]
        comparedToBaseline = row[INDEX_BASELINE_COMPARISON]
        significant = row[INDEX_STUDENT_P] < P_VALUE

        if (estimator == 'no_rewrites'):
            continue

        if (estimator not in stats):
            stats[estimator] = [0, 0, 0]

        if (not significant):
            stats[estimator][1] += 1
        elif (comparedToBaseline < 1.0):
            stats[estimator][0] += 1
        else:
            stats[estimator][2] += 1

    # Enforce order.
    for estimator in ['size_rewrites', 'selectivity_rewrites', 'histogram_rewrites']:
        [improved, noChange, worsened] = stats[estimator]

        tableRow = [
            cleanName(estimator),
            improved,
            noChange,
            worsened
        ]

        print(INDENT * 5 + ' & '.join([str(val) for val in tableRow]) + ' \\\\')

    print()
    print(INDENT * 4 + '\\bottomrule')
    print(INDENT * 3 + '\\end{tabular}')
    print(INDENT * 3 + '\\label{table:estimator-results}')
    print(INDENT * 2 + '\\end{center}')
    print(INDENT * 1 + '\\end{table}')

def makeDatasetTable(rows):
    # for row in rows:

    print(INDENT * 1 + '\\begin{table}[h]')
    print(INDENT * 2 + '\\tiny')
    print()
    print(INDENT * 2 + '\\begin{center}')
    print(INDENT * 3 + '\\caption{Grounding time using different query rewriting.}')
    print()
    print(INDENT * 3 + '\\begin{tabular}{ l | l | r }')
    print(INDENT * 4 + '\\toprule')
    print(INDENT * 5 + 'Dataset & Cost Estimator & Query Time (ms) \\\\')
    print()
    print(INDENT * 4 + '\\midrule')
    print()

    oldExample = None
    for row in rows:
        tableRow = []

        # Only the first row of each example gets the example printed.
        if (row[INDEX_EXAMPLE] != oldExample):
            if (oldExample != None):
                print()
                print(INDENT * 5 + '\\hline')
                print()

            oldExample = row[INDEX_EXAMPLE]
            tableRow.append(cleanName(row[INDEX_EXAMPLE]))
        else:
            tableRow.append('  ')

        tableRow.append(cleanName(row[INDEX_ESTIMATOR]))
        tableRow.append("%d$\\pm$%d" % (int(row[INDEX_MEAN_QUERY_TIME]), int(row[INDEX_STDDEV_QUERY_TIME])))

        if (row[INDEX_BASELINE_COMPARISON] < 1.0 and row[INDEX_STUDENT_P] < P_VALUE):
            tableRow[-1] = "\\textbf{%s}" % (tableRow[-1])

        print(INDENT * 5 + ' & '.join(tableRow) + ' \\\\')

    print()
    print(INDENT * 4 + '\\bottomrule')
    print(INDENT * 3 + '\\end{tabular}')
    print(INDENT * 3 + '\\label{table:results}')
    print(INDENT * 2 + '\\end{center}')
    print(INDENT * 1 + '\\end{table}')

def loadArgs(args):
    executable = args.pop(0)
    if (len(args) < 1 or len(args) > 2 or ({'h', 'help'} & {arg.lower().strip().replace('-', '') for arg in args})):
        print("USAGE: python3 %s <result dir> [--table]" % (executable), file = sys.stderr)
        print("   Unlike the Ruby one, this is only aggregates.")
        sys.exit(1)

    resultDir = args.pop(0)

    table = False
    if (len(args) > 0):
        flag = args.pop(0)
        if (flag != '--table'):
            print("Unknown flag: '%s'.", flag)
            sys.exit(3)
        table = True

    return resultDir, table

def main(args):
    resultDir, table = loadArgs(args)
    rows = parseDir(resultDir)

    # Replace methods with the specific index we want to see them in.
    sort_key = lambda sort_row: sort_row[0] + sort_row[1].replace('no_rewrites', '0').replace('size_rewrites', '1').replace('selectivity_rewrites', '2').replace('histogram_rewrites', '3')

    rows = sorted(rows, key = sort_key)

    if (table):
        makeTables(rows)
    else:
        print("\t".join(HEADERS))
        for row in rows:
            print("\t".join([str(val) for val in row]))

if (__name__ == '__main__'):
    main(sys.argv)
