#!/usr/bin/ruby

# Get the full run time and aggregate them.

# gem install descriptive_statistics
require 'descriptive_statistics'

HEADERS = ['Dataset', 'Base Time', 'Optimal Time', 'Chosen Time']
RUN_TYPE_NAME_MAP = {
   'full_run_base' => 'Base Time',
   'full_run_fastest' => 'Optimal Time',
   'full_run_s_score' => 'Chosen Time',
}

SIG_PLACES = 0

def parseFile(path)
   time = nil

   File.open(path, 'r'){|file|
      file.each{|line|
         line = line.strip()
         if (line == '')
            next
         end

         if (match = line.match(/^(\d+)\s/))
            time = match[1].to_i()
         end
      }
   }

   return time
end

def loadArgs(args)
   if (args.size == 0 || args.map{|arg| arg.gsub('-', '').downcase()}.include?('help'))
      puts "USAGE: ruby #{$0} <output file> ..."
      exit(1)
   end

   return args
end

def main(paths)
   # {dataset => {runType => [time, ...], ...}, ...}
   allTimes = Hash.new{|outerHash, outerKey| outerHash[outerKey] = Hash.new{|hash, key| hash[key] = []}}

   paths.each{|path|
      runType = RUN_TYPE_NAME_MAP[File.basename(File.dirname(path))]
      dataset = File.basename(File.dirname(File.dirname(path)))

      allTimes[dataset][runType] << parseFile(path)
   }

   puts HEADERS.join("\t")

   allTimes.each_pair{|dataset, datasetTimes|
      row = [dataset]

      datasetTimes.keys().sort().each{|runType|
         times = datasetTimes[runType]
         row << "#{times.mean().round(SIG_PLACES)} ± #{times.standard_deviation().round(SIG_PLACES)}"
      }

      puts row.join("\t")
   }
end

if ($0 == __FILE__)
   main(loadArgs(ARGV))
end
