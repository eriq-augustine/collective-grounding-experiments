#!/usr/bin/env python3

import os
import re
import sys

import numpy
import scipy.stats

P_VALUE = 0.05

OUT_FILENAME = 'out.txt'

SKIP_EXAMPLES = ['simple-acquaintances', 'user-modeling']

HEADERS = ['Example', 'Method', 'Mean Rewrite Time', 'StdDev Rewrite Time', 'Mean Query Time', 'StdDev Query Time', 'Mean Query Size', 'StdDev Query Size', 'Mean Instantiation Time', 'StdDev Instantiation Time', 'Mean Ground Rules', 'StdDev Ground Rules', 'Compared to No Rewrite', 'p - Student-T vs Baseline', 'p - Welch-T vs Baseline']

INDEX_REWRITE_TIME = 0
INDEX_QUERY_TIME = 1
INDEX_QUERY_RESULTS = 2
INDEX_INSTANTIATION_TIME = 3
INDEX_GROUND_RULES = 4
NUM_LOG_STATS = 5

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
                    results[INDEX_REWRITE_TIME] += time - startTime

                numberOfGroundingRules = int(match.group(1))
                startTime = time
                continue

            match = re.search(r'- Got (\d+) results from query', line)
            if (match != None):
                results[INDEX_QUERY_RESULTS] += numberOfGroundingRules * int(match.group(1))
                results[INDEX_QUERY_TIME] += time - startTime
                startTime = time
                continue

            match = re.search(r'- Generated (\d+) ground rules with query:', line)
            if (match != None):
                results[INDEX_GROUND_RULES] += numberOfGroundingRules * int(match.group(1))
                results[INDEX_INSTANTIATION_TIME] += time - startTime
                continue

    return results

def aggregateResults(rows):
    # {'example\tmethod' => [[stat1_value1, stat1_value2, ...], ...]
    aggregates = {}

    for row in rows:
        key = "\t".join([row[0], row[1]])

        # Take only the stats.
        row = row[3:]

        if (key not in aggregates):
            aggregates[key] = []
            for i in range(len(row)):
                aggregates[key].append([])

        for i in range(len(row)):
            aggregates[key][i].append(row[i])

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
        baselineVals = baselineTimes[row[0]]
        vals = queryTimes["\t".join([row[0], row[1]])]

        row.append(row[4] / baselineMeans[row[0]])

        # Student-T against baseline.
        t, p = scipy.stats.ttest_ind(baselineVals, vals)
        row.append(p)

        # Welch-T against baseline.
        t, p = scipy.stats.ttest_ind(baselineVals, vals, equal_var = False)
        row.append(p)

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
def makeTable(rows):
    # for row in rows:

    indent = '   '
    print(indent * 1 + '\\begin{table}[h]')
    print(indent * 2 + '\\tiny')
    print()
    print(indent * 2 + '\\begin{center}')
    print(indent * 3 + '\\caption{Grounding time using different query rewriting.}')
    print()
    print(indent * 3 + '\\begin{tabular}{ l | l | r }')
    print(indent * 4 + '\\toprule')
    print(indent * 5 + 'Dataset & Cost Estimator & Query Time (ms) \\\\')
    print()
    print(indent * 4 + '\\midrule')
    print()

    oldExample = None
    for row in rows:
        tableRow = []

        # Only the first row of each example gets the example printed.
        if (row[0] != oldExample):
            if (oldExample != None):
                print()
                print(indent * 5 + '\\hline')
                print()

            oldExample = row[0]
            tableRow.append(cleanName(row[0]))
        else:
            tableRow.append('  ')

        tableRow.append(cleanName(row[1]))
        tableRow.append("%d$\\pm$%d" % (int(row[4]), int(row[5])))

        if (row[-3] < 1.0 and row[-2] < P_VALUE):
            tableRow[-1] = "\\textbf{%s}" % (tableRow[-1])

        print(indent * 5 + ' & '.join(tableRow) + ' \\\\')

    print()
    print(indent * 4 + '\\bottomrule')
    print(indent * 3 + '\\end{tabular}')
    print(indent * 3 + '\\label{table:resutls}')
    print(indent * 2 + '\\end{center}')
    print(indent * 1 + '\\end{table}')

    '''
               Citation Categories & No Rewrite & 123$\\pm$11 \\\\
                  & Size & 85$\\pm$8 \\\\
                  & Cardinality & 85$\\pm$6 \\\\
                  & Histogram & \\textbf{76$\\pm$6} \\\\
               \\hline
               Entity Resolution & No Rewrite & 4307$\\pm$159 \\\\
                  & Size & 5381$\\pm$200 \\\\
                  & Cardinality & \\textbf{2364$\\pm$110} \\\\
                  & Histogram & 2807$\\pm$88 \\\\
               \\hline
               Friendship & No Rewrite & 25304$\\pm$295 \\\\
                  & Size & \\textbf{12315$\\pm$277} \\\\
                  & Cardinality & \\textbf{12378$\\pm$259} \\\\
                  & Histogram & \\textbf{12336$\\pm$259} \\\\
               \\hline
               Friendship Pairwise & No Rewrite & 36261$\\pm$463 \\\\
                  & Size & \\textbf{11837$\\pm$494} \\\\
                  & Cardinality & 32103$\\pm$389 \\\\
                  & Histogram & 32258$\\pm$697 \\\\
               \\hline
               KGI & No Rewrite & 2379$\\pm$76 \\\\
                  & Size & 1126$\\pm$92 \\\\
                  & Cardinality & \\textbf{904$\\pm$36} \\\\
                  & Histogram & 2362$\\pm$59 \\\\
               \\hline
               Preference Prediction & No Rewrite & 1059$\\pm$90 \\\\
                  & Size & 926$\\pm$96 \\\\
                  & Cardinality & 933$\\pm$96 \\\\
                  & Histogram & \\textbf{924$\\pm$133} \\\\
               \\hline
               Social Network Analysis & No Rewrite & 751$\\pm$69 \\\\
                  & Size & 753$\\pm$38 \\\\
                  & Cardinality & 751$\\pm$46 \\\\
                  & Histogram & 774$\\pm$66 \\\\
               \\hline
               Trust Prediction & No Rewrite & 2084$\\pm$71 \\\\
                  & Size & \\textbf{764$\\pm$60} \\\\
                  & Cardinality & 1555$\\pm$71 \\\\
                  & Histogram & 1900$\\pm$72 \\\\
   '''

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
    sort_key = lambda row: row[0] + row[1].replace('no_rewrites', '0').replace('size_rewrites', '1').replace('selectivity_rewrites', '2').replace('histogram_rewrites', '3')

    rows = sorted(rows, key = sort_key)

    if (table):
        makeTable(rows)
    else:
        print("\t".join(HEADERS))
        for row in rows:
            print("\t".join([str(val) for val in row]))

if (__name__ == '__main__'):
    main(sys.argv)
