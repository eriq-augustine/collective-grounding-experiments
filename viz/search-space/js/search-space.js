'use strict';

const NODE_SIZE = 125;
const NODE_MARGIN = 10;
const LEVEL_HEIGHT = NODE_SIZE + 75;
const PADDING = 50;

const COLOR_HOT = [255, 0, 0];
const COLOR_COLD = [0, 0, 255];

const GRADIENT_LOW = 'blue';
const GRADIENT_HIGH = 'red';

const OPTIMISTIC_QUERY_COST_MULTIPLIER = 0.018;
const OPTIMISTIC_INSTANTIATION_COST_MULTIPLIER = 0.0010;
const PESSIMISTIC_QUERY_COST_MULTIPLIER = 0.020;
const PESSIMISTIC_INSTANTIATION_COST_MULTIPLIER = 0.0020;

window.searchspace = window.searchspace || {};

function main() {
    let maxWidth = parseMaxWidth();

    let height = window.searchspace.data.count * (LEVEL_HEIGHT + NODE_SIZE);
    let width = Math.trunc(maxWidth * (NODE_SIZE + NODE_MARGIN));

    let tree = d3.layout.tree()
        .size([height, width])
    ;

    let dataNodes = parseNodes(tree);
    let dataLinks = tree.links(dataNodes);

    window.searchspace.dataNodes = dataNodes;

    let svg = d3.select(".tree-area").append("svg")
        .attr("width", width + PADDING)
        .attr("height", height + PADDING)
        .append("g")
        .attr("transform", `translate(${PADDING}, ${PADDING * 2})`)
    ;

    let graphicalNodes = svg.selectAll("g.node")
        .data(dataNodes, function(node) { return node.id; })
    ;

    let displayNodes = graphicalNodes.enter()
        .append("g")
        .attr("class", "node")
        .attr('data-id', function(node) { return node.id; })
        .attr("transform", function(node) { return `translate(${node.x - (NODE_SIZE / 2)}, ${node.y - (NODE_SIZE / 2)})`; })
    ;

    // Declare the links…
    let graphicalLinks = svg.selectAll("path.link")
        .data(dataLinks, function(link) { return link.target.id; })
    ;

    let diagonal = d3.svg.diagonal()
        .projection(function(element) { return [element.x, element.y]; })
    ;

    graphicalLinks.enter().insert("path", "g")
        .attr("class", "link")
        .attr("d", diagonal)
    ;

    // Establish the gradient legend.

    let defs = svg.append("defs");

    let linearGradient = defs.append("linearGradient")
        .attr("id", "linear-gradient");

    linearGradient
        .attr("x1", "0%")
        .attr("y1", "0%")
        .attr("x2", "100%")
        .attr("y2", "0%");

    linearGradient.append("stop")
        .attr("offset", "0%")
        .attr("stop-color", GRADIENT_LOW);

    linearGradient.append("stop")
        .attr("offset", "100%")
        .attr("stop-color", GRADIENT_HIGH);

    svg.append("rect")
        .attr("width", 300)
        .attr("height", 20)
        .style("fill", "url(#linear-gradient)");

    let colorScale = d3.scale.linear()
        .range([GRADIENT_LOW, GRADIENT_HIGH])
        .domain(window.searchspace.range);

    // Color the nodes.

    displayNodes.append("rect")
        .attr("y", 0)
        .attr("width", NODE_SIZE)
        .attr("height", NODE_SIZE / 2)
        .style("fill", function(node) { return colorScale(node.pessimisticCost) })
    ;

    displayNodes.append("rect")
        .attr("y", NODE_SIZE / 2)
        .attr("width", NODE_SIZE)
        .attr("height", NODE_SIZE / 2)
        .style("fill", function(node) { return colorScale(node.optimisticCost) })
    ;
}

function parseNodes(tree) {
    let levels = parseLevels();

    let dataNodes = tree.nodes(window.searchspace.data);

    window.searchspace.range = [null, null];

    let id = 0;
    dataNodes.forEach(function(node) {
        node.y = node.depth * LEVEL_HEIGHT;

        node.name = node.index;
        node.id = id++;

        node.optimisticCost =
            node.count * (OPTIMISTIC_QUERY_COST_MULTIPLIER * node.cost + OPTIMISTIC_INSTANTIATION_COST_MULTIPLIER * node.rows);
        node.pessimisticCost =
            node.count * (PESSIMISTIC_QUERY_COST_MULTIPLIER * node.cost + PESSIMISTIC_INSTANTIATION_COST_MULTIPLIER * node.rows);

        if (window.searchspace.range[0] == null || window.searchspace.range[0] > node.optimisticCost) {
            window.searchspace.range[0] = node.optimisticCost;
        }

        if (window.searchspace.range[1] == null || window.searchspace.range[1] < node.pessimisticCost) {
            window.searchspace.range[1] = node.pessimisticCost;
        }
    });

    // Extra layout needs to be done for horizontal spacing.
    dataNodes.sort(function(a, b) {
        return a.x - b.x;
    });

    let maxWidth = parseMaxWidth(levels);
    let width = Math.trunc(maxWidth * (NODE_SIZE + NODE_MARGIN));

    for (let count in levels) {
        let widthPerNode = width / levels[count];

        let i = 0;
        dataNodes.forEach(function(dataNode) {
            if (dataNode.count != count) {
                return;
            }

            dataNode.x = Math.trunc(i * widthPerNode + (widthPerNode / 2));
            i++;
        });
    }

    return dataNodes;
}

function parseMaxWidth(levels) {
    levels = levels || parseLevels();

    let maxWidth = 0;
    for (let count in levels) {
        if (levels[count] > maxWidth) {
            maxWidth = levels[count];
        }
    }

    return maxWidth;
}

function parseLevels() {
    let levels = {};
    parseLevelsHelper(levels, window.searchspace.data);
    return levels;
}

function parseLevelsHelper(levels, node) {
    if (!(node.count in levels)) {
        levels[node.count] = 0;
    }
    levels[node.count]++;

    node.children.forEach(function(child) {
        parseLevelsHelper(levels, child);
    });
}

document.addEventListener("DOMContentLoaded", function(event) {
    main();
});
