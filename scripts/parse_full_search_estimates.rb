#!/usr/bin/ruby

require 'bigdecimal'
require 'json'
require 'set'

# Take in a single output file and parse out the full search estimates.

INDEX_INDEX = 0
INDEX_QUERY = 1
INDEX_COUNT = 2
INDEX_COST = 3
INDEX_ROWS = 4

def dupNode(node)
    newNode = node.clone()
    newNode['children'] = []
    return newNode
end

def makeNode(row)
    return {
        'index' => row[INDEX_INDEX],
        'count' => row[INDEX_COUNT],
        'cost' => row[INDEX_COST],
        'rows' => row[INDEX_ROWS],
        'query' => row[INDEX_QUERY],
        'children' => [],
    }
end

def tokenize(formula)
    # First, strip the extra parens.
    formula = formula.strip().gsub(/^\( | \)$/, '')

    # Now just split on conjunction.
    return Set.new(formula.split(' & '))
end

def buildTree(rows)
    # Each tree level we go down, there will be one less atom.
    # The tokens of a child will be a substring of the tokens of the parent.
    # Allow duplicates.

    rowTokens = rows.map{|row| tokenize(row[INDEX_QUERY])}

    maxAtoms = rows.map{|row| row[INDEX_COUNT]}.max()
    level = 0

    tree = nil
    lastNodes = nil

    (0...maxAtoms).each{|level|
        atomCount = maxAtoms - level

        # All rows that will be nodes that this level.
        levelRows = rows.select{|row| row[INDEX_COUNT] == atomCount}
        levelNodes = levelRows.map{|row| makeNode(row)}

        if (level == 0)
            # Root
            tree = levelNodes[0]
            lastNodes = levelNodes
        else
            # Check which parents each new node can have.
            # Note that we will make copies to represent nodes that were already cut out in PSL.
            # (Hence this strange-looking usage of usedNodes.)
            usedNodes = []

            levelNodes.each{|node|
                tokens = rowTokens[node['index']]

                lastNodes.each{|parent|
                    parentTokens = rowTokens[parent['index']]
                    if (parentTokens.superset?(tokens))
                        newNode = dupNode(node)
                        usedNodes << newNode
                        parent['children'] << newNode
                    end
                }
            }

            lastNodes = usedNodes
        end
    }

    return tree
end

# Convert from strings.
# Returns the same row.
def typeRow(row)
    row[INDEX_INDEX] = row[INDEX_INDEX].to_i()
    row[INDEX_COUNT] = row[INDEX_COUNT].to_i()
    row[INDEX_COST] = BigDecimal(row[INDEX_COST]).truncate().to_i()
    row[INDEX_ROWS] = BigDecimal(row[INDEX_ROWS]).truncate().to_i()

    return row
end

def parseFile(path)
    headers = nil
    rows = []

    File.open(path, 'r'){|file|
        file.each{|line|
            line = line.strip()
            if (line == '')
                next
            end

            if (match = line.match(/^(\d+)\s/))
                time = match[1].to_i()
            end

            match = line.match(/FullEstimate -- (.+)$/)
            if (match == nil)
                next
            end

            parts = match[1].split("\t")

            if (headers == nil)
                headers = parts
            else
                row = typeRow(parts)
                if (row[INDEX_INDEX] != rows.size())
                    raise "Bad index (#{row[INDEX_INDEX]}), expected (#{rows.size()})."
                end

                rows << row
            end
        }
    }

    return headers, rows
end

def loadArgs(args)
   if (args.size != 1 || args.map{|arg| arg.gsub('-', '').downcase()}.include?('help'))
      puts "USAGE: ruby #{$0} <output file>"
      exit(1)
   end

   return args.shift()
end

def main(path)
    headers, rows = parseFile(path)
    tree = buildTree(rows)
    puts JSON.pretty_generate(tree, {:indent => '    '})
end

if ($0 == __FILE__)
    main(loadArgs(ARGV))
end
