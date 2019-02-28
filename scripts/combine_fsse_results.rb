#!/usr/bin/ruby

# Parse the multiple versions of FSSE experiments (like for scripts/parse_query_results.rb),
# and combine all the runs.

require 'set'

require_relative 'parse_query_results'

# gem install descriptive_statistics
require 'descriptive_statistics'

COMBINE_STATS = RUN_OBSERVED_STATS + ['Total Time (ms)'] + SCORE_COLUMNS + MISRANK_COLUMNS + BEST_TIME_DELTA_COLUMNS + BASE_TIME_DELTA_COLUMNS
KEEP_COLUMNS = Set.new(BASE_HEADERS + COMBINE_STATS)

COMBINED_HEADERS = Array.new(HEADERS).keep_if{|header| KEEP_COLUMNS.include?(header)}

MEAN_COLUMNS = Set.new(RUN_OBSERVED_STATS + SCORE_COLUMNS + ['Total Time (ms)'] + BEST_TIME_DELTA_COLUMNS + BASE_TIME_DELTA_COLUMNS)
SUM_COLUMNS = Set.new(MISRANK_COLUMNS)

def combineResults(allResults)
   # We will remove columns that are not either combined or part of the base columns.
   columnsToRemove = []
   (Set.new(HEADERS) - Set.new(COMBINED_HEADERS)).each{|removeHeader|
      columnsToRemove << HEADERS.index(removeHeader)
   }
   columnsToRemove = columnsToRemove.sort().reverse()

   # {[ruleId, rewriteId] => [row, ...], ...}
   rewriteStats = Hash.new{|hash, key| hash[key] = []}

   allResults.each{|result|
      result.each{|row|
         rowId = row[0...2]
         rewriteStats[rowId] << row
      }
   }

   # {[ruleId, rewriteId] => row, ...}
   combinedStats = {}

   rewriteStats.each_pair{|rowId, rows|
      # Just start with the base row, since not all values will change.
      combinedRow = Array.new(rows[0])

      COMBINE_STATS.each{|stat|
         values = []

         rows.each{|row|
            # Skip incomplete runs.
            if (row.size() < BASE_HEADERS.size())
                  next
            end

            values << row[HEADERS.index(stat)]
         }

         if (values.size() == 0)
            combinedRow[HEADERS.index(stat)] = nil
         elsif (MEAN_COLUMNS.include?(stat))
            combinedRow[HEADERS.index(stat)] = "#{values.mean()} ± #{values.standard_deviation()}"
         elsif (SUM_COLUMNS.include?(stat))
            combinedRow[HEADERS.index(stat)] = "#{values.sum()}"
         end
      }

      # Remove columns that are not either combined or part of the base columns.
      columnsToRemove.each{|removeIndex|
         combinedRow.delete_at(removeIndex)
      }

      combinedStats[rowId] = combinedRow
   }

   finalRows = []
   combinedStats.keys().sort().each{|rowId|
      finalRows << combinedStats[rowId]
   }

   return finalRows
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

   combinedRows = combineResults(allResults)

   puts COMBINED_HEADERS.join("\t")
   combinedRows.each{|row|
      puts row.join("\t")
   }
end

if ($0 == __FILE__)
    main(loadArgs(ARGV))
end
