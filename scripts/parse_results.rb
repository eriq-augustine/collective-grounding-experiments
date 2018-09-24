#!/usr/bin/ruby

OUT_FILENAME = 'out.txt'
SKIP_DIRS = ['.', '..']

ALL_HEADERS = ['Example', 'Method', 'Run', 'Rewrite Time', 'Query Time', 'Query Size', 'Instantiation Time', 'Ground Rules']
AGGREGATE_HEADERS = ['Example', 'Method', 'Mean Rewrite Time', 'StdDev Rewrite Time', 'Mean Query Time', 'StdDev Query Time', 'Mean Query Size', 'StdDev Query Size', 'Mean Instantiation Time', 'StdDev Instantiation Time', 'Mean Ground Rules', 'StdDev Ground Rules', 'Compared to No Rewrite']

INDEX_REWRITE_TIME = 0
INDEX_QUERY_TIME = 1
INDEX_QUERY_RESULTS = 2
INDEX_INSTANTIATION_TIME = 3
INDEX_GROUND_RULES = 4
NUM_LOG_STATS = 5

def stddev(vals)
   sum = 0.0
   mean = mean(vals)

   vals.each{|val|
      sum += (val - mean) ** 2
   }

   return Math.sqrt(sum / vals.size())
end

def mean(vals)
   sum = 0.0

   vals.each{|val|
      sum += val
   }

   return sum / vals.size()
end

# Gives two args to the block: dirent name and dirent path.
# Does not include '.' or '..'.
def listdir(dir, &block)
   Dir.entries(dir).each{|name|
      if (SKIP_DIRS.include?(name))
         next
      end

      block.call(name, File.join(dir, name))
   }
end

def parseFile(path)
   results = [0] * NUM_LOG_STATS

   numberOfGroundingRules = nil
   startTime = nil
   hasRewrite = false

   File.open(path, 'r'){|file|
      file.each{|line|
         line = line.strip()
         if (line == '')
            next
         end

         if (match = line.match(/^(\d+)\s/))
            time = match[1].to_i()
         end

         if (match = line.match(/- Found value true for option grounding.rewritequeries.$/))
            startTime = time
            hasRewrite = true
         elsif (match = line.match(/- Grounding (\d+) rules with query:/))
            if (hasRewrite)
               hasRewrite = false
               results[INDEX_REWRITE_TIME] += time - startTime
            end

            numberOfGroundingRules = match[1].to_i()
            startTime = time
         elsif (match = line.match(/- Got (\d+) results from query/))
            results[INDEX_QUERY_RESULTS] += numberOfGroundingRules * match[1].to_i()
            results[INDEX_QUERY_TIME] += time - startTime
            startTime = time
         elsif (match = line.match(/- Generated (\d+) ground rules with query:/))
            results[INDEX_GROUND_RULES] += numberOfGroundingRules * match[1].to_i()
            results[INDEX_INSTANTIATION_TIME] += time - startTime
         end
      }
   }

   return results
end

def aggregateResults(rows)
   # {'example\tmethod' => [[stat1_value1, stat1_value2, ...], ...]
   aggregates = {}

   rows.each{|row|
      key = "#{row[0]}\t#{row[1]}"
      # Take only the stats.
      row = row[3..-1]

      if (!aggregates.include?(key))
         aggregates[key] = []
         for i in 0...row.size()
            aggregates[key] << []
         end
      end

      row.each_index{|i|
         aggregates[key][i] << row[i]
      }
   }

   # Keep track of the time without rewrites so we can make a column for it.
   # {'example\tmethod' => meanQueryTime, ...}
   referenceTimes = {}

   results = []

   aggregates.each{|key, stats|
      example, method = key.split("\t")
      row = [example, method]

      stats.each_with_index{|stat, i|
         row << mean(stat)
         row << stddev(stat)

         if (method == 'no_rewrites' && i == 1)
            referenceTimes[example] = mean(stat)
         end
      }

      results << row
   }

   results.each{|row|
      row << row[4] / referenceTimes[row[0]]
   }

   return results
end

def parseDir(resultDir, aggregate)
   results = []

   listdir(resultDir){|example, examplePath|
      listdir(examplePath){|method, methodPath|
         listdir(methodPath){|run, runPath|
            result = parseFile(File.join(runPath, OUT_FILENAME))
            if (result == nil)
               next
            end

            result = [example, method, run] + result
            results << result
         }
      }
   }

   if (aggregate)
      results = aggregateResults(results)
   end

   return results
end

def loadArgs(args)
   if (args.size != 2 || args.map{|arg| arg.gsub('-', '').downcase()}.include?('help'))
      puts "USAGE: ruby #{$0} <result dir> --all|--aggregate"
      exit(1)
   end

   resultDir = args.shift()
   flag = args.shift()

   if (!['--all', '--aggregate'].include?(flag))
      puts "Unknown flag: '#{flag}'."
      exit(2)
   end

   return resultDir, (flag == '--aggregate')
end

def main(args)
   resultDir, aggregate = loadArgs(args)
   rows = parseDir(resultDir, aggregate)

   if (aggregate)
      puts AGGREGATE_HEADERS.join("\t")
   else
      puts ALL_HEADERS.join("\t")
   end

   rows.sort().each{|row|
      puts row.join("\t")
   }
end

if ($0 == __FILE__)
   main(ARGV)
end
