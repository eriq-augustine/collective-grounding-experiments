#!/usr/bin/ruby

# Parse the standard run results (like for scripts/parse_query_results.rb),
# and compose full rule configs that should be run.
# The current configs that will be generated (one per line) are:
#  - No rewrites.
#  - The actual best performing run.
#  - The best scoring runs.

require_relative 'parse_query_results'

RULE_DELIM = '_'
REWRITE_DELIM = ':'

CONFIG_IDS = ['base', 'fastest', 's_score']

def formatConfig(config)
   return config.sort().map{|ruleId, rewriteId| "#{ruleId}#{REWRITE_DELIM}#{rewriteId}"}.join(RULE_DELIM)
end

def computeConfigs(queryResults)
   configs = []

   # First organize the rewrites by rule and remove timeouts.
   # {rule => [row, ...], ...}
   rewrites = Hash.new{|hash, key| hash[key] = []}

   queryResults.each{|row|
      if (row.size() < BASE_HEADERS.size())
         next
      end

      rewrites[row[HEADERS.index('Rule ID')]] << row
   }

   ruleIds = rewrites.keys().sort()

   # Put in the base config with no rewrites.
   baseConfig = ruleIds.map{|ruleId| [ruleId, 0]}
   configs << baseConfig

   fastestConfig = []
   bestScoringConfig = []
   
   rewrites.each_pair{|rule, rows|
      rows.each{|row|
         if (row[HEADERS.index('Actual Rank')] == 0)
            fastestConfig << [rule, row[HEADERS.index('Rewrite ID')]]
         end

         if (row[HEADERS.index('s Rank')] == 0)
            bestScoringConfig << [rule, row[HEADERS.index('Rewrite ID')]]
         end
      }
   }

   configs << fastestConfig
   configs << bestScoringConfig

   return configs.map{|config| formatConfig(config)}
end

def loadArgs(args)
   if (args.size != 1 || args.map{|arg| arg.gsub('-', '').downcase()}.include?('help'))
      puts "USAGE: ruby #{$0} <output file>"
      exit(1)
   end

   return args.shift()
end

def main(path)
   results = parseFile(path)
   configs = computeConfigs(results)

   configs.each_index{|i|
      puts "#{CONFIG_IDS[i]}\t#{configs[i]}"
   }
end

if ($0 == __FILE__)
    main(loadArgs(ARGV))
end
