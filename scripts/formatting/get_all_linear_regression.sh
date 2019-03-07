#!/bin/bash

for short in '--short' ''; do
    for intercept in '--use-intercept' ''; do
        echo -e "All\t${short}\t${intercept}"
        ./scripts/linear_regressor_cost_estimator.rb ${short} ${intercept} \
            results/individual-query-*/friendship/all.out \
            results/individual-query-*/trust-prediction/all.out \
            results/individual-query-*/entity-resolution/all.out
        echo ""

        echo -e "Friendship\t${short}\t${intercept}"
        ./scripts/linear_regressor_cost_estimator.rb ${short} ${intercept} results/individual-query-*/friendship/all.out
        echo ""

        echo -e "Trust\t${short}\t${intercept}"
        ./scripts/linear_regressor_cost_estimator.rb ${short} ${intercept} results/individual-query-*/trust-prediction/all.out
        echo ""

        echo -e "ER\t${short}\t${intercept}"
        ./scripts/linear_regressor_cost_estimator.rb ${short} ${intercept} results/individual-query-*/entity-resolution/all.out
        echo ""
    done
done
