# Collective Grounding Experiments

The code in this repository runs experiments on collective grounding.
For experiments specific to VLDB 2023, use the `vldb23` tag.

Note that running all experiments involves tens of thousands of runs and is expected to take more than a week.
A simplified set of experiments can be run using the `simple` subset of experiments.

Linux is assumed when running these scripts, but they only rely on core Linux utils also found in OSX and WSL.

The general workflow to run experiments is as follows:
 - Clone this repository.
 - Fetch the data and models: `./scripts/setup_psl_examples.sh`.
 - Run the desired experiments (this workflow assumes `simple`).
   - via Docker: `./scripts/docker/run.sh simple`
   - via script: `./scripts/run-experiment.sh simple`
 - Parse the results into a single TSV file: `./scripts/parse-results.py > results.txt`.
 - Analyze the results: `./scripts/analyze-results-by-iteration.py results.txt BEST_RUNS`.
   - The analysis scripts provide many different analyses of the results, use `--help` to view all available options.

## Experiment Run Scripts

There are three different experimental setups/scripts provided:
 - `all-splits` - Runs all datasets, splits, iterations, and hyperparameters. This involves about 80K runs and is expected to take between 1 and 2 months to run (depending on the hardware).
 - `first-split` - Runs all datasets, iterations, and hyperparameters. But, only runs the first split of each dataset. This is about 7.5K runs and takes about a week to run.
 - `simple` - Runs the first split of all datasets for 10 iterations. This is only 100 runs and should just take a few hours to run.

Once runs are complete, the output is placed in the `./results` directory.
The `./script/parse-results.sh` script can be used to parse these results into a single TSV file (printed to stdout).
It it recommended to save the results in a file to be used in analysis scripts.
Any reference in this doc to `results.txt` is assumed to be the output of this script.

Analysis scripts provide the required analysis of the results.
The are invoked with the following pattern:
```
./script/analyze-*.py results.txt <mode>
```
Where `<mode>` is the type of analysis you want to do.
You can see the different types of analysis by invoking `--help` on the analysis script:
```
./script/analyze-*.py --help
```

The `analyze-results-by-iteration.py` script is recommended for the `first-split` and `simple` experiments,
while the `analyze-results-by-split.py` script is recommended for the `all-splits` experiment.

## Data & Models

Both the data and models for this experiments are pulled directly from the canonical [psl-examples](https://github.com/linqs/psl-examples) repository.
Note that there is one example (`imdb-er`) that requires about 100 GB of RAM to run.
All other examples can run within 32GB of RAM.

There are two ways to avoid running the IMDB example:
 - Add `imdb-er` to the `SKIP_EXAMPLES` variable in `./scripts/setup_psl_examples.sh` before running it.
 - Remove the `./psl-examples/imdb-er` directory.

## Docker

For convenience, a Docker container is provided that is capable of running all experiments.
The dockerfile is located at `./scripts/docker/Dockerfile`.
It is assumed that the invoking user has permissions to run docker commands.

The `./scripts/docker/run.sh` script will handle both building the image and running the container.
The `./scripts`, `./results`, and `./psl-examples` directories will all be mounted as volumes in the container.
So all the existing data will be exposed to the image and all the results will persist after the run is complete.
The ./scripts/run-experiment.sh` will be invoked inside the container with the same arguments passed to `./scripts/docker/run.sh`.

Example usage:
```
./scripts/docker/run.sh simple
```

## System Setup

The suggested method of running experiments is by using the docker container,
but the fastest times will be seen when running locally (all published times are run locally).
However, these experiments can also be easily run locally.
The only requirements are Java (8 or greater), curl or wget, and PostgreSQL.
The experiment scripts must also have the authority to clear PostgreSQL and disk caches without manual intervention.
The easiest way is probably adding an exception in your sudoers file (assuming `wheel` is the sudoers group):
```
%wheel ALL=(ALL) NOPASSWD: /path/to/repo/psl-grounding-experiments/scripts/clear_cache.sh
```
