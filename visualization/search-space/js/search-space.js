'use strict';

const NODE_SIZE = 125;
const NODE_MARGIN = 10;
const LEVEL_HEIGHT = NODE_SIZE + 75;
const PADDING = 50;

const COLOR_HOT = [255, 0, 0];
const COLOR_COLD = [0, 0, 255];

const METRICS = ['count', 'cost', 'rows'];
const DISPLAY_STATS = ['index'].concat(METRICS);

const CUBIC_HEAT = true;

window.searchspace = window.searchspace || {};

function main() {
    addButtons();

    let maxWidth = parseMaxWidth();

    let height = window.searchspace.data.count * (LEVEL_HEIGHT + NODE_SIZE);
    let width = Math.trunc(maxWidth * (NODE_SIZE + NODE_MARGIN));

    let tree = d3.layout.tree()
        .size([height, width])
    ;

    let dataNodes = parseNodes(tree);
    let dataLinks = tree.links(dataNodes);

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
        .attr("transform", function(node) { return `translate(${node.x - (NODE_SIZE / 2)}, ${node.y - (NODE_SIZE / 2)})`; })
    ;

    METRICS.forEach(function(metric) {
        displayNodes.attr(`data-${metric}`, function(node) { return node[metric]; });
    });

    displayNodes.append("rect")
        .attr("width", NODE_SIZE)
        .attr("height", NODE_SIZE)
        .style("fill", "#ffffff")
    ;

    let i = 0;
    DISPLAY_STATS.forEach(function(stat) {
        let y = Math.trunc((NODE_SIZE / (DISPLAY_STATS.length + 1)) * (i + 1));

        displayNodes.append("text")
            .attr("y", y)
            .attr("x", 5)
            .text(function(node) { return `${stat}: ${node[stat]}`; })
            .style("fill-opacity", 1)
        ;

        i++;
    });

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
}

function addButtons() {
    METRICS.forEach(function(metric) {
        let button = document.createElement('button');
        button.classList.add('heat-button');
        button.innerHTML = `Heat: ${metric}`;
        button.onclick = heatmap.bind(self, metric);

        document.querySelector('.button-area').appendChild(button);
    });
}

function parseNodes(tree) {
    let levels = parseLevels();

    let dataNodes = tree.nodes(window.searchspace.data);

    window.searchspace.ranges = {};
    METRICS.forEach(function(metric) {
        window.searchspace.ranges[metric] = [null, null];
    });

    let id = 0;
    dataNodes.forEach(function(node) {
        node.y = node.depth * LEVEL_HEIGHT;

        node.name = node.index;
        node.id = id++;

        METRICS.forEach(function(metric) {
            if (window.searchspace.ranges[metric][0] == null || node[metric] < window.searchspace.ranges[metric][0]) {
                window.searchspace.ranges[metric][0] = node[metric];
            }

            if (window.searchspace.ranges[metric][1] == null || node[metric] > window.searchspace.ranges[metric][1]) {
                window.searchspace.ranges[metric][1] = node[metric];
            }
        });
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

function heatmap(metric) {
    if (!(metric in window.searchspace.ranges)) {
        return;
    }

    let [min, max] = window.searchspace.ranges[metric];

    document.querySelectorAll('.node').forEach(function(node) {
        let value = node.dataset[metric];
        let color = getColor(value, min, max);

        node.querySelector('rect').style.fill = color;
    });
}

function getColor(value, min, max) {
    let weight = (value - min) / (max - min);

    if (CUBIC_HEAT) {
        weight = Math.pow(weight, 1 / 3);
    }

    let colorString = '';

    for (let i = 0; i < COLOR_COLD.length; i++) {
        let cold = COLOR_COLD[i];
        let hot = COLOR_HOT[i];

        let range = Math.abs(hot - cold);
        let direction = cold < hot ? +1 : -1;

        let intensity = Math.trunc(cold + direction * weight * range);
        intensity = Math.max(0, Math.min(255, intensity));

        colorString += intensity.toString(16).padStart(2, '0');
    }

    return '#' + colorString;
}

document.addEventListener("DOMContentLoaded", function(event) {
    main();
});
