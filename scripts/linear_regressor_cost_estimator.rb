#!/usr/bin/ruby

# Parse the multiple FSSE experiments (like for scripts/parse_query_results.rb),
# and combine use all the results to fit a linear regressor to precict total time.

require 'set'

# gem install pycall
require 'pycall/import'

require_relative 'parse_query_results'

# Python imports
include PyCall::Import
pyfrom :'sklearn.linear_model', import: :LinearRegression
pyfrom :'sklearn.model_selection', import: :train_test_split

FEATURE_COLUMNS = [
    'Explain Time (ms)', 'Estimated Cost', 'Startup Cost', 'Estimated Rows',
    'First Query Response (ms)', 'Non-Startup Time', 'Combined Estimate'
]

TARGET_COLUMN = 'Total Time (ms)'

TEST_SIZE = 0.1
SEED = 4

def fitLinearRegressor(rows)
   # Drop rows that are incomplete.
   rows.delete_if{|row| row.size() < BASE_HEADERS.size()}

   # Get labels.
   labels = rows.map{|row| row[HEADERS.index(TARGET_COLUMN)]}

   # Only keep our feature columns.
   columnsToRemove = []
   (Set.new(HEADERS) - Set.new(FEATURE_COLUMNS)).each{|removeHeader|
      columnsToRemove << HEADERS.index(removeHeader)
   }
   columnsToRemove = columnsToRemove.sort().reverse()

   rows.each{|row|
      columnsToRemove.each{|removeIndex|
         row.delete_at(removeIndex)
      }
   }

   model = LinearRegression.new()

   xTrain, xTest, yTrain, yTest = train_test_split(rows, labels, test_size: TEST_SIZE, random_state: SEED)

   model.fit(xTrain, yTrain)

   return model, model.score(xTest, yTest)
end

def loadArgs(args)
   if (args.size < 1 || args.map{|arg| arg.gsub('-', '').downcase()}.include?('help'))
      puts "USAGE: ruby #{$0} <output file> ..."
      exit(1)
   end

   return args
end

def main(paths)
   allResults = []
   paths.each{|path|
      allResults += parseFile(path)
   }

   model, score = fitLinearRegressor(allResults)

   headers = ['Score'] + FEATURE_COLUMNS
   values = [score] + model.coef_.tolist()

   puts headers.join("\t")
   puts values.map{|val| val.round(SIGNIFICANT_PLACES)}.join("\t")
end

if ($0 == __FILE__)
    main(loadArgs(ARGV))
end
