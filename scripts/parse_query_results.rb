#!/usr/bin/ruby

# Deprecated for the python one.

OUT_FILENAME = 'out.txt'
SKIP_DIRS = ['.', '..']

HEADERS = [
    'ID', 'Formula', 'Atom Count',
    'Explain Time', 'Estimated Cost', 'Estimated Rows',
    'Actual Time', 'Actual Rows',
    'Instantiation Time', 'Final Ground Count'
]

def parseFile(path)
   results = []

    row = []
    startTime = nil

    File.open(path, 'r'){|file|
        file.each{|line|
            line = line.strip()
            if (line == '')
                next
            end

            if (match = line.match(/^(\d+)\s/))
                time = match[1].to_i()
            end

            if (match = line.match(/- Query \d+ -- Formula: (.+)$/))
                row << results.size()
                row << match[1]
            elsif (match = line.match(/- Query \d+ -- Atom Count: (.+)$/))
                row << match[1]
            elsif (match = line.match(/- Begin EXPLAIN$/))
                startTime = time
            elsif (match = line.match(/- Estimated Cost: (\d+\.?\d*), Estimated Rows: (\d+)$/))
                row << time - startTime
                row << match[1]
                row << match[2]

                startTime = time
            elsif (match = line.match(/- Got (\d+) results from query/))
                row << time - startTime
                row << match[1]
                
                startTime = time
            elsif (match = line.match(/- Generated (\d+) ground rules with query:/))
                row << time - startTime
                row << match[1]

                results << row
                row = []
            end
        }
    }

   return results
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

    puts HEADERS.join("\t")
    results.each{|result|
        puts result.join("\t")
    }
end

if ($0 == __FILE__)
    main(loadArgs(ARGV))
end
