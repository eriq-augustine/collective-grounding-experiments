'use strict';

const LEVEL_HEIGHT = 100;
const NODE_DIAMETER = 20;

const COLOR_HOT = [255, 0, 0];
const COLOR_COLD = [0, 0, 255];

const METRICS = ['count', 'cost', 'rows'];

const CUBIC_HEAT = true;

window.searchspace = window.searchspace || {};

function main() {
    addButtons();

    let height = window.searchspace.data.count * LEVEL_HEIGHT;
    // TODO(eriq)
    let width = 1200;

    let tree = d3.layout.tree()
        .size([height, width])
    ;

    let dataNodes = parseNodes(tree);
    let dataLinks = tree.links(dataNodes);

    let svg = d3.select(".tree-area").append("svg")
        .append("g")
        .attr("transform", "translate(50, 50)")
    ;

    let graphicalNodes = svg.selectAll("g.node")
        .data(dataNodes, function(node) { return node.id; })
    ;

    let displayNodes = graphicalNodes.enter()
        .append("g")
        .attr("class", "node")
        .attr("transform", function(node) { return "translate(" + node.x + "," + node.y + ")"; })
    ;

    METRICS.forEach(function(metric) {
        displayNodes.attr(`data-${metric}`, function(node) { return node[metric]; });
    });

    displayNodes.append("circle")
        .attr("r", NODE_DIAMETER / 2)
        .style("fill", "#fff")
    ;

    displayNodes.append("text")
        .attr("y", function(node) { return node.children ? -NODE_DIAMETER : NODE_DIAMETER; })
        .attr("dy", ".35em")
        .attr("text-anchor", "middle")
        .text(function(node) { return node.name; })
        .style("fill-opacity", 1)
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
    let dataNodes = tree.nodes(window.searchspace.data);

    window.searchspace.ranges = {};
    METRICS.forEach(function(metric) {
        window.searchspace.ranges[metric] = [null, null];
    });

    let id = 0;
    dataNodes.forEach(function(node) {
        node.y = node.depth * LEVEL_HEIGHT;
        node.x *= 1.25;

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

    return dataNodes;
}

function heatmap(metric) {
    if (!(metric in window.searchspace.ranges)) {
        return;
    }

    let [min, max] = window.searchspace.ranges[metric];

    document.querySelectorAll('.node').forEach(function(node) {
        let value = node.dataset[metric];
        let color = getColor(value, min, max);

        node.querySelector('circle').style.fill = color;
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
