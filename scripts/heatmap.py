#!/usr/bin/env python3

import os
import sys

import matplotlib
import pandas
import seaborn

def load_data(path):
    headers = None
    data = []

    row_labels = set()
    col_labels = set()

    raw_data = {}

    with open(path, 'r') as file:
        for line in file:
            line = line.strip()
            if (line == ''):
                continue

            parts = line.split("\t")

            if headers is None:
                headers = parts
                continue

            x, y, val = [float(part) for part in parts]

            row_labels.add(x)
            col_labels.add(y)

            if (x not in raw_data):
                raw_data[x] = {}

            if (y not in raw_data[x]):
                raw_data[x][y] = {}

            raw_data[x][y] = val

    data = []

    row_labels = sorted(list(row_labels))
    col_labels = sorted(list(col_labels))

    for row_label in row_labels:
        row = []

        for col_label in col_labels:
            val = 0
            if (row_label in raw_data and col_label in raw_data[row_label]):
                val = raw_data[row_label][col_label]

            row.append(val)

        data.append(row)

    return pandas.DataFrame(data = data, index = row_labels, columns = col_labels)

def main(path):
    data = load_data(path)

    # HACK(eriq): Fix Tkinter issue.
    sys.argv = ['']

    seaborn.heatmap(data, cmap = 'Blues')
    matplotlib.pyplot.show()

def _load_args(args):
    executable = args.pop(0)
    if (len(args) != 1 or ({'h', 'help'} & {arg.lower().strip().replace('-', '') for arg in args})):
        print("USAGE: python3 %s <data file>" % (executable), file = sys.stderr)
        sys.exit(1)

    path = os.path.abspath(args.pop(0))

    return path

if (__name__ == '__main__'):
    main(_load_args(sys.argv))
