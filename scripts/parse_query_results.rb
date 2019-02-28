#!/usr/bin/ruby

# Deprecated for the python one.

require 'bigdecimal'

OUT_FILENAME = 'out.txt'
SKIP_DIRS = ['.', '..']

SIGNIFICANT_PLACES = 5

RUN_IDENTIFIERS = [
    'Rule ID', 'Rewrite ID',
    'Formula', 'Atom Count'
]

RUN_OBSERVED_STATS = [
    'Explain Time (ms)', 'Estimated Cost', 'Startup Cost', 'Estimated Rows',
    'First Query Response (ms)', 'Actual Time (ms)', 'Actual Rows',
    'Instantiation Time (ms)', 'Final Ground Count'
]

BASE_HEADERS = RUN_IDENTIFIERS + RUN_OBSERVED_STATS

BASE_COMPUTED_COLUMNS = [
    'Combined Estimate',
    'Non-Startup Time',
    'Width',
    'D',
    'D_r',
    'D_s',
    'D_rs',
    'D_ns',
    'D_ce',
    'M',
    'M_s',
    'M * W',
    'M_s * W',
    'Total Time (ms)'
]

SCORE_COLUMNS = [
    'Ideal Score',
    'Ideal Row Score',
    'Score_s',
    'Score_rs',
    'Score_ns',
    'Score_ce'
]

RANK_COLUMNS = [
    'Actual Rank',
    'i Rank',
    'ir Rank',
    's Rank',
    'rs Rank',
    'ns Rank',
    'ce Rank'
]

MISRANK_COLUMNS = [
    # Score Evalaution.
    # How many positions away from 0 did you rank the best.
    'i Misrank',
    'ir Misrank',
    's Misrank',
    'rs Misrank',
    'ns Misrank',
    'ce Misrank'
]

BEST_TIME_DELTA_COLUMNS = [
    # How much time did you lose from the best.
    'i Best Time Δ',
    'ir Best Time Δ',
    's Best Time Δ',
    'rs Best Time Δ',
    'ns Best Time Δ',
    'ce Best Time Δ'
]

BASE_TIME_DELTA_COLUMNS = [
    # How much time did you lose from the base (no rewrite).
    'i Base Time Δ',
    'ir Base Time Δ',
    's Base Time Δ',
    'rs Base Time Δ',
    'ns Base Time Δ',
    'ce Base Time Δ',
]

# Computed Columns.
COMPUTED_HEADERS =
  BASE_COMPUTED_COLUMNS +
  SCORE_COLUMNS +
  RANK_COLUMNS +
  MISRANK_COLUMNS +
  BEST_TIME_DELTA_COLUMNS +
  BASE_TIME_DELTA_COLUMNS

HEADERS = BASE_HEADERS + COMPUTED_HEADERS

STATIC_D = 0.018
STATIC_D_R = 0.0006
STATIC_D_CE = 0.0036
STATIC_M = 0.0015

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
            elsif (match = line.match(/- Grounding experiment on rule (\d+) -- /))
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
                row << BigDecimal(match[1]).truncate().to_i()
                # Startup Cost
                row << BigDecimal(match[2]).truncate().to_i()
                # Estimated Rows
                row << BigDecimal(match[3]).truncate().to_i()

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
                    puts "Size Mismatch. Got #{row.size()}, Expected #{BASE_HEADERS.size()}. Result Number: #{results.size()}."
                    puts "Row: #{row.join("\t")}"
                    exit(1)
                end

                results << row
                row = []
            end
        }
    }

    if (row.size() < 0)
        # This probably meant that the last run timed-out.
        results << row
    end

    # Now comput the remaining columns.

    results.each{|row|
        # Skip incomplete runs.
        if (row.size() < BASE_HEADERS.size())
            next
        end

        # Non-Startup Cost
        nonStartupCost = row[HEADERS.index('Estimated Cost')].to_i() - row[HEADERS.index('Startup Cost')].to_i()
        row << nonStartupCost

        # Combined Estimate
        combinedEstimate = Math.sqrt(row[HEADERS.index('Estimated Cost')].to_i() * row[HEADERS.index('Estimated Rows')].to_i()).to_i()
        row << nonStartupCost

        # Scoring

        w = ruleWidths[row[HEADERS.index('Rule ID')]]
        d = row[HEADERS.index('Actual Time (ms)')].to_f() / row[HEADERS.index('Estimated Cost')].to_f()
        d_r = row[HEADERS.index('Actual Time (ms)')].to_f() / row[HEADERS.index('Estimated Rows')].to_f()
        d_ns = row[HEADERS.index('Actual Time (ms)')].to_f() / nonStartupCost.to_f()
        d_ce = row[HEADERS.index('Actual Time (ms)')].to_f() / combinedEstimate.to_f()
        m = row[HEADERS.index('Instantiation Time (ms)')].to_f() / row[HEADERS.index('Actual Rows')].to_f()

        # Width (W)
        row << w

        # D
        row << d.round(SIGNIFICANT_PLACES)
        # D computed from estimated rows instead of cost (D_r).
        row << d_r.round(SIGNIFICANT_PLACES)
        # Static D (D_s)
        row << STATIC_D.round(SIGNIFICANT_PLACES)
        # Static D_r (D_rs)
        row << STATIC_D_R.round(SIGNIFICANT_PLACES)
        # Non-Startup D (D_ns)
        row << d_ns.round(SIGNIFICANT_PLACES)
        # Combined Estimate D (D_ce)
        row << d_ce.round(SIGNIFICANT_PLACES)

        # M
        row << m.round(SIGNIFICANT_PLACES)
        # Static M (M_s)
        row << STATIC_M.round(SIGNIFICANT_PLACES)

        # M * W
        row << (m * w).round(SIGNIFICANT_PLACES)
        # M_s * W
        row << (STATIC_M * w).round(SIGNIFICANT_PLACES)

        # Total Time
        row << row[HEADERS.index('Actual Time (ms)')].to_i() + row[HEADERS.index('Instantiation Time (ms)')].to_i()
        # Ideal Score (Score_i)
        row << (row[HEADERS.index('Estimated Cost')].to_f() * d + row[HEADERS.index('Estimated Rows')].to_f() * m * w).to_i()
        # Ideal Row-based Score (Score_ir)
        row << (row[HEADERS.index('Estimated Rows')].to_f() * d_r + row[HEADERS.index('Estimated Rows')].to_f() * STATIC_M * w).to_i()
        # Static Score (Score_s)
        row << (row[HEADERS.index('Estimated Cost')].to_f() * STATIC_D + row[HEADERS.index('Estimated Rows')].to_f() * STATIC_M * w).to_i()
        # Static Row-Based Score (Score_rs)
        row << (row[HEADERS.index('Estimated Rows')].to_f() * STATIC_D_R + row[HEADERS.index('Estimated Rows')].to_f() * STATIC_M * w).to_i()
        # Non-Startup Score (Score_ns)
        row << (row[HEADERS.index('Estimated Cost')].to_f() * d_ns + row[HEADERS.index('Estimated Rows')].to_f() * STATIC_M * w).to_i()
        # Static Combined Estimate Score (Score_ce)
        row << (combinedEstimate * STATIC_D_CE + row[HEADERS.index('Estimated Rows')].to_f() * STATIC_M * w).to_i()
    }

    scoringMetrics = ['Total Time (ms)'] + SCORE_COLUMNS
    scoreRankingMetrics = RANK_COLUMNS - ['Actual Rank']
    allRankingMetrics = RANK_COLUMNS

    # After all rows have their base computed stats, compute ranks.
    # {metricName => {rule => [[metricValue, rowIndex], ...], ...}, ...}
    ranks = Hash.new{|metricHash, metricKey| metricHash[metricKey] = Hash.new{|ruleHash, ruleKey| ruleHash[ruleKey] = []}}

    results.each_with_index{|row, i|
        # Skip incomplete runs.
        if (row.size() < BASE_HEADERS.size())
            next
        end

        scoringMetrics.each{|metric|
            ranks[metric][row[HEADERS.index('Rule ID')]] << [row[HEADERS.index(metric)], i]
        }
    }

    scoringMetrics.each{|metric|
        ranks[metric].each_pair{|rule, runs|
            runs.sort!()

            runs.each_with_index{|values, rank|
                rowIndex = values[1]
                results[rowIndex] << rank
            }
        }
    }

    # Best total times for the best of each rule.
    # {rule: totalTime, ...}
    totalTimes = {}
    baseTimes = {}

    results.each{|row|
        # Skip incomplete runs.
        if (row.size() < BASE_HEADERS.size())
            next
        end

        rule = row[HEADERS.index('Rule ID')]

        if (row[HEADERS.index('Rewrite ID')] == 0)
            baseTimes[rule] = row[HEADERS.index('Total Time (ms)')]
        end

        # How far off from ideal was each score.
        scoreRankingMetrics.each{|ranking|
            if (row[HEADERS.index('Actual Rank')] == 0)
                row << row[HEADERS.index(ranking)]
                totalTimes[rule] = row[HEADERS.index('Total Time (ms)')]
            else
                row << 0
            end
        }
    }

    # How much time was lost choosing a suboptimal query.
    results.each{|row|
        # Skip incomplete runs.
        if (row.size() < BASE_HEADERS.size())
            next
        end

        rule = row[HEADERS.index('Rule ID')]

        scoreRankingMetrics.each{|ranking|
            if (row[HEADERS.index(ranking)] == 0)
                row << row[HEADERS.index('Total Time (ms)')] - totalTimes[rule]
            else
                row << 0
            end
        }

        scoreRankingMetrics.each{|ranking|
            if (row[HEADERS.index(ranking)] == 0)
                row << row[HEADERS.index('Total Time (ms)')] - baseTimes[rule]
            else
                row << 0
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
