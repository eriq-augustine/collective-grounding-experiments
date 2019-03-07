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

FEATURE_COLUMNS = ['Atom Count', 'Explain Time (ms)', 'Estimated Cost', 'Startup Cost', 'Estimated Rows']
SHORT_FEATURE_COLUMNS = ['Estimated Cost', 'Estimated Rows']

TARGET_COLUMN = 'Total Time (ms)'

TEST_SIZE = 0.1
SEED = 4

def fitLinearRegressor(rows, useIntercept, featureColumns)
   # Drop rows that are incomplete.
   rows.delete_if{|row| row.size() < BASE_HEADERS.size()}

   # Get labels.
   labels = rows.map{|row| row[HEADERS.index(TARGET_COLUMN)]}

   # Only keep our feature columns.
   columnsToRemove = []
   (Set.new(HEADERS) - Set.new(featureColumns)).each{|removeHeader|
      columnsToRemove << HEADERS.index(removeHeader)
   }
   columnsToRemove = columnsToRemove.sort().reverse()

   rows.each{|row|
      columnsToRemove.each{|removeIndex|
         row.delete_at(removeIndex)
      }
   }

   model = LinearRegression.new(fit_intercept: useIntercept)

   xTrain, xTest, yTrain, yTest = train_test_split(rows, labels, test_size: TEST_SIZE, random_state: SEED)

   model.fit(xTrain, yTrain)

   return model, model.score(xTest, yTest)
end

def loadArgs(args)
   if (args.size() < 1 || args.map{|arg| arg.gsub('-', '').downcase()}.include?('help'))
      puts "USAGE: ruby #{$0} [--short] [--use-intercept] <output file> ..."
      exit(1)
   end

   useShort = false
   if (args.size() > 0 && args[0] == '--short')
      useShort = true
      args.shift()
   end

   useIntercept = false 
   if (args.size() > 0 && args[0] == '--use-intercept')
      useIntercept = true
      args.shift()
   end

   if (args.size() == 0)
      puts "No output file specified."
      exit(2)
   end

   return useShort, useIntercept, args
end

def main(useShortFeatures, useIntercept, paths)
   allResults = []
   paths.each{|path|
      allResults += parseFile(path)
   }

   featureColumns = FEATURE_COLUMNS
   if (useShortFeatures)
      featureColumns = SHORT_FEATURE_COLUMNS
   end

   model, score = fitLinearRegressor(allResults, useIntercept, featureColumns)

   headers = ['Score', 'Intercept'] + featureColumns
   values = [score, model.intercept_.round(SIGNIFICANT_PLACES)] + model.coef_.tolist()

   puts headers.join("\t")
   puts values.map{|val| val.round(SIGNIFICANT_PLACES)}.join("\t")
end

if ($0 == __FILE__)
    main(*loadArgs(ARGV))
end
