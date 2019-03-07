#!/bin/bash

echo -e "Experiment\tMisrank\tBase Time\tOptimal Time\tChosen Time"
echo -e "Friendship\t$(./scripts/summarize_fsse_results.rb results/individual-query-*/friendship/all.out | tail -n +2)"
echo -e "Trust\t$(./scripts/summarize_fsse_results.rb results/individual-query-*/trust-prediction/all.out | tail -n +2)"
echo -e "ER\t$(./scripts/summarize_fsse_results.rb results/individual-query-*/entity-resolution/all.out | tail -n +2)"
