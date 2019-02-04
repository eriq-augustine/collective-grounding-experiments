#!/usr/bin/ruby

# Deprecated for the python one.

OUT_FILENAME = 'out.txt'
SKIP_DIRS = ['.', '..']

HEADERS = [
    'ID', 'Formula', 'Atom Count',
    'Explain Time', 'Estimated Cost', 'Estimated Rows',
    'First Query Response', 'Actual Time', 'Actual Rows',
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

            if (match = line.match(/^Running PSL Inference$/) && row.size() != 0)
                # We started a new log/run without the other one finishing.
                # This probably meant that a run was timed-out.
                results << row
                row = []
            elsif (match = line.match(/- Query (\d+) -- Formula: (.+)$/))
                # ID
                row << match[1]
                # Formula
                row << match[2]
            elsif (match = line.match(/- Query \d+ -- Atom Count: (.+)$/))
                # Atom Count
                row << match[1]
            elsif (match = line.match(/- Begin EXPLAIN$/))
                startTime = time
            elsif (match = line.match(/- Estimated Cost: ([^,]+), Estimated Rows: (.+)$/))
                # Explain Time
                row << time - startTime
                # Estimated Cost
                row << match[1].to_i()
                # Estimated Rows
                row << match[2]

                startTime = time
            elsif (match = line.match(/- First Query Response/))
                # First Query Response
                row << time - startTime
            elsif (match = line.match(/- Query Complete/))
                # Actual Time
                row << time - startTime
            elsif (match = line.match(/- Got (\d+) results from query/))
                # Actual Rows
                row << match[1]
                
                startTime = time
            elsif (match = line.match(/- Generated (\d+) ground rules with query:/))
                # Instantiation Time
                row << time - startTime
                # Final Ground Count
                row << match[1]

                if (row.size() != HEADERS.size())
                    puts "Size Mismatch. Got #{row.size()}, Expected #{HEADERS.size()}. Number: #{results.size()}."
                    exit(1)
                end

                results << row
                row = []
            end
        }
    }

    if (row.size() != 0)
        # This probably meant that the last run timed-out.
        results << row
    end

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
