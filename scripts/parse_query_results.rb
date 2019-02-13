#!/usr/bin/ruby

# Deprecated for the python one.

require 'bigdecimal'

OUT_FILENAME = 'out.txt'
SKIP_DIRS = ['.', '..']

BASE_HEADERS = [
    'Rule ID', 'Rewrite ID', 'Formula', 'Atom Count',
    'Explain Time (ms)', 'Estimated Cost', 'Startup Cost', 'Estimated Rows',
    'First Query Response (ms)', 'Actual Time (ms)', 'Actual Rows',
    'Instantiation Time (ms)', 'Final Ground Count'
]

# Computed Columns.
COMPUTED_HEADERS = [
    'Non-Startup Time',
    'Width',
    'D',
    'D_s',
    'D_ns',
    'M',
    'M_s',
    'M * W',
    'M_s * W',
    'Total Time (ms)',
    'Ideal Score',
    'Score_s',
    'Score_ns',
    # Comparative Columns.
    'Actual Rank',
    'Score_i Rank',
    'Score_s Rank',
    'Score_ns Rank'
]

HEADERS = BASE_HEADERS + COMPUTED_HEADERS

STATIC_D = 0.0341
STATIC_M = 0.0122

def parseFile(path)
   results = []

    row = []
    startTime = nil

    # {ruleId => width, ...}
    ruleWidths = {}

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
                row << match[1].to_i()
            elsif (match = line.match(/- Query (\d+) -- Formula: (.+)$/))
                # Query ID
                row << match[1].to_i()
                # Formula
                row << match[2]
            elsif (match = line.match(/- Query \d+ -- Atom Count: (.+)$/))
                # Atom Count
                row << match[1].to_i()

                # If the rewrite id is zero, then this is the base query and the atom count is the full width.
                if (row[1] == 0)
                    ruleWidths[row[0]] = match[1].to_i()
                end
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
                row << match[1].to_i()
                
                startTime = time
            elsif (match = line.match(/- Generated (\d+) ground rules with query:/))
                # Instantiation Time
                row << time - startTime
                # Final Ground Count
                row << match[1].to_i()

                if (row.size() != BASE_HEADERS.size())
                    puts "Size Mismatch. Got #{row.size()}, Expected #{BASE_HEADERS.size()}. Number: #{results.size()}."
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

    # Now comput the remaining columns.

    results.each{|row|
        # Skip incomplete runs.
        if (row.size() != BASE_HEADERS.size())
            next
        end

        # Non-Startup Cost
        nonStartupCost = row[HEADERS.index('Estimated Cost')].to_i() - row[HEADERS.index('Startup Cost')].to_i()
        row << nonStartupCost

        # Scoring

        w = ruleWidths[row[HEADERS.index('Rule ID')]]
        d = row[HEADERS.index('Actual Time (ms)')].to_f() / row[HEADERS.index('Estimated Cost')].to_f()
        d_ns = row[HEADERS.index('Actual Time (ms)')].to_f() / nonStartupCost.to_f()
        m = row[HEADERS.index('Instantiation Time (ms)')].to_f() / row[HEADERS.index('Actual Rows')].to_f()

        # Width (W)
        row << w

        # D
        row << d
        # Static D (D_s)
        row << STATIC_D
        # Non-Startup D (D_ns)
        row << d_ns

        # M
        row << m
        # Static M (M_s)
        row << STATIC_M

        # M * W
        row << m * w
        # M_s * W
        row << STATIC_M * w

        # Total Time
        row << row[HEADERS.index('Actual Time (ms)')].to_i() + row[HEADERS.index('Instantiation Time (ms)')].to_i()
        # Ideal Score (Score_i)
        row << (row[HEADERS.index('Estimated Cost')].to_f() * d + row[HEADERS.index('Estimated Rows')].to_f() * m * w).to_i()
        # Static Score (Score_s)
        row << (row[HEADERS.index('Estimated Cost')].to_f() * STATIC_D + row[HEADERS.index('Estimated Rows')].to_f() * STATIC_M * w).to_i()
        # Non-Startup Score (Score_ns)
        row << (row[HEADERS.index('Estimated Cost')].to_f() * d_ns + row[HEADERS.index('Estimated Rows')].to_f() * STATIC_M * w).to_i()
    }

    # After all rows have their base computed stats, compute ranks.
    # {metricName => {rule => [[metricValue, rowIndex], ...], ...}, ...}
    ranks = Hash.new{|metricHash, metricKey| metricHash[metricKey] = Hash.new{|ruleHash, ruleKey| ruleHash[ruleKey] = []}}

    results.each_with_index{|row, i|
        # Skip incomplete runs.
        if (row.size() < BASE_HEADERS.size())
            next
        end

        ['Total Time (ms)', 'Ideal Score', 'Score_s', 'Score_ns'].each{|metric|
            ranks[metric][row[HEADERS.index('Rule ID')]] << [row[HEADERS.index(metric)], i]
        }
    }

    ['Total Time (ms)', 'Ideal Score', 'Score_s', 'Score_ns'].each{|metric|
        ranks[metric].each_pair{|rule, runs|
            runs.sort!()

            runs.each_with_index{|values, rank|
                rowIndex = values[1]
                results[rowIndex] << rank
            }
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
