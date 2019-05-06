#!/usr/bin/ruby

# Parse PSL output files.

HEADERS = ['Planing Time', 'Query Time', 'Grounding Time', 'Total Time']

def suffix(a, b)
    if (a.size() > b.size())
        a, b = b, a
    end

    commonLength = 0
    for i in (0...a.size())
        if (a[a.size() - 1 - i] != b[b.size() - 1 - i])
            break
        end

        commonLength = i
    end

    return a[(a.size() - i)...]
end

def prefix(a, b)
    if (a.size() > b.size())
        a, b = b, a
    end

    commonLength = 0
    for i in (0...a.size())
        if (a[i] != b[i])
            break
        end

        commonLength = i
    end

    return a[0...i]
end

# Take the strings and stip any common prefix or suffix.
def computeIds(strings)
    if (strings.size() <= 1)
        return strings
    end

    commonPrefix = strings[0]
    commonSuffix = strings[0]

    strings.each{|string|
        commonPrefix = prefix(string, commonPrefix)
        commonSuffix = suffix(string, commonSuffix)
    }

    return strings.map{|string|
        string.sub(/^#{commonPrefix}/, '').sub(/#{commonSuffix}$/, '')
    }
end

def parseFile(path)
    row = []
    startTime = nil

    planningTime = -1
    queryTime = -1
    groundingTime = 0

    File.open(path, 'r'){|file|
        file.each{|line|
            line = line.strip()
            if (line == '')
                next
            end

            if (match = line.match(/^(\d+)\s/))
                time = match[1].to_i()
            end

            if (line.match(/- Grounding \d+ rule\(s\) with query:/))
                startTime = time
            elsif (line.match(/- Generated \d+ ground rules with query:/))
                groundingTime += time - startTime
            elsif (line.match(/- Initializing objective terms for \d+ ground rules/))
                # Grounding phase complete.
                row << planningTime
                row << queryTime
                row << groundingTime
            elsif (line.match(/- Inference Complete/))
                row << time
            end
        }
    }

    return row
end

def loadArgs(args)
   if (args.size == 0 || args.map{|arg| arg.gsub('-', '').downcase()}.include?('help'))
      puts "USAGE: ruby #{$0} <output file> ..."
      exit(1)
   end

   return args
end

def main(paths)
    paths.map!{|path| File.absolute_path(path)}

    results = []
    ids = computeIds(paths)

    paths.each_index{|i|
        results << [ids[i]] + parseFile(paths[i])
    }

    puts (['ID'] + HEADERS).join("\t")
    puts results.map{|row| row.join("\t")}.join("\n")
end

if ($0 == __FILE__)
    main(loadArgs(ARGV))
end
