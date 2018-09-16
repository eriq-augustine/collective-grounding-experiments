#!/usr/bin/ruby

OUT_FILENAME = 'out.txt'
SKIP_DIRS = ['.', '..']

HEADERS = ['Example', 'Method', 'Run', 'Rewrite Time', 'Query Time', 'Query Size', 'Instantiation Time', 'Ground Rules']

INDEX_REWRITE_TIME = 0
INDEX_QUERY_TIME = 1
INDEX_QUERY_RESULTS = 2
INDEX_INSTANTIATION_TIME = 3
INDEX_GROUND_RULES = 4
NUM_LOG_STATS = 5

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

def parseDir(resultDir)
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

   return results
end

def loadArgs(args)
   if (args.size != 1 || args.map{|arg| arg.gsub('-', '').downcase()}.include?('help'))
      puts "USAGE: ruby #{$0} <result dir>"
      exit(1)
   end

   resultDir = args.shift()

   return resultDir
end

def main(args)
   resultDir = loadArgs(args)
   rows = parseDir(resultDir)

   puts HEADERS.join("\t")
   rows.sort().each{|row|
      puts row.join("\t")
   }
end

if ($0 == __FILE__)
   main(ARGV)
end
