#!/usr/bin/ruby

# Deprecated for the python one.

require 'bigdecimal'

OUT_FILENAME = 'out.txt'
SKIP_DIRS = ['.', '..']

HEADERS = [
    'Rule ID', 'Rewrite ID', 'Formula', 'Atom Count',
    'Explain Time (ms)', 'Estimated Cost', 'Startup Cost', 'Estimated Rows',
    'First Query Response (ms)', 'Actual Time (ms)', 'Actual Rows',
    'Instantiation Time (ms)', 'Final Ground Count',
    'Total Time (ms)'
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
            elsif (match = line.match(/- Found value (\d+) for option grounding.experiment.rule/))
                # Rule ID
                row << match[1]
            elsif (match = line.match(/- Query (\d+) -- Formula: (.+)$/))
                # Query ID
                row << match[1]
                # Formula
                row << match[2]
            elsif (match = line.match(/- Query \d+ -- Atom Count: (.+)$/))
                # Atom Count
                row << match[1]
            elsif (match = line.match(/- Begin EXPLAIN$/))
                startTime = time
            elsif (match = line.match(/- Estimated Cost: ([^,]+), Startup Cost: ([^,]+), Estimated Rows: (.+)$/))
                # Explain Time
                row << time - startTime
                # Estimated Cost
                row << BigDecimal(match[1]).truncate().to_s()
                # Startup Cost
                row << BigDecimal(match[2]).truncate().to_s()
                # Estimated Rows
                row << BigDecimal(match[3]).truncate().to_s()

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

                if (row.size() != HEADERS.size() - 1)
                    puts "Size Mismatch. Got #{row.size()}, Expected #{HEADERS.size() - 1}. Number: #{results.size()}."
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

    # We left out the final column, since it is computed.
    results.each{|row|
        row << row[HEADERS.index('Actual Time (ms)')].to_i() + row[HEADERS.index('Instantiation Time (ms)')].to_i()
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
