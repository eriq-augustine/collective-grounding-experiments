#!/usr/bin/ruby

# Parse the multiple versions of FSSE experiments (like for scripts/parse_query_results.rb),
# and give a short aggregated summary if them.

require 'set'

require_relative 'parse_query_results'

# gem install descriptive_statistics
require 'descriptive_statistics'

COLUMNS = ['Misrank', 'Base Time', 'Best Time', 'Chosen Time']
SUMMARY_SIG_PLACES = 1

def combineResults(allResults)
   # {[ruleId, rewriteId] => [row, ...], ...}
   rewriteStats = Hash.new{|hash, key| hash[key] = []}

   # {stat => [per experiment, ...], ...}
   aggregateData = Hash.new{|hash, key| hash[key] = []}

   allResults.each{|result|
      misrank = 0
      baseTime = 0
      bestTime = 0
      chosenTime = 0

      result.each{|row|
         # Note that all these cases can overlap.
         if (row[HEADERS.index('Rewrite ID')] == 0)
            baseTime += row[HEADERS.index('Total Time (ms)')]
         end

         if (row[HEADERS.index('Actual Rank')] == 0)
            bestTime += row[HEADERS.index('Total Time (ms)')]
            misrank += row[HEADERS.index('s Misrank')]
         end

         if (row[HEADERS.index('s Rank')] == 0)
            chosenTime += row[HEADERS.index('Total Time (ms)')]
         end
      }

      aggregateData['Misrank'] << misrank
      aggregateData['Base Time'] << baseTime
      aggregateData['Best Time'] << bestTime
      aggregateData['Chosen Time'] << chosenTime
   }

   combinedRow = []
   COLUMNS.each{|column|
      values = aggregateData[column]
      combinedRow << "#{values.mean().round(SUMMARY_SIG_PLACES)} ± #{values.standard_deviation().round(SUMMARY_SIG_PLACES)}"
   }

   return combinedRow
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
      allResults << parseFile(path)
   }

   combinedRow = combineResults(allResults)

   puts COLUMNS.join("\t")
   puts combinedRow.join("\t")
end

if ($0 == __FILE__)
    main(loadArgs(ARGV))
end
