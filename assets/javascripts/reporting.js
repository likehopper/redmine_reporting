/*
 * File: redmine_reporting/assets/javascripts/reporting.js
 *
 * Redmine Reporting - project reporting plugin
 * SPDX-License-Identifier: GPL-2.0-or-later
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */
// Redmine Reporting dashboard: draws the charts from the #report-data payload and opens
// the matching native Redmine list for a clicked bar, point or period label.
(() => {
"use strict";

const report = JSON.parse(document.getElementById("report-data").textContent);
// Strings in the user's Redmine language, with Rails-style %{name} placeholders.
const i18n = JSON.parse(document.getElementById("report-i18n").textContent);
const t = (key, values = {}) => (i18n[key] ?? key).replace(/%\{(\w+)\}/g, (_, name) => values[name] ?? "");
// Same palette and color maps as ReportingTMA-Django, plus Redmine's default tracker names.
const PALETTE = ["#4472C4", "#E74C3C", "#F7941D", "#2ECC71", "#9B59B6", "#1ABC9C", "#F39C12", "#D35400", "#2980B9", "#7F8C8D"];
const TRACKER_COLORS = {
  "Bug": "#4472C4", "Anomalie": "#4472C4", "Change": "#E74C3C", "Evolution": "#E74C3C", "Feature request": "#E74C3C",
  "Support": "#F7941D", "Support request": "#F7941D", "Task": "#2ECC71", "Tâche": "#2ECC71"
};
const PRIORITY_COLORS = {
  "Immediate": "#4472C4", "Immédiate": "#4472C4", "Urgent": "#4472C4", "Urgente": "#4472C4",
  "High": "#E74C3C", "Haute": "#E74C3C", "Normal": "#F7941D", "Normale": "#F7941D", "Low": "#2ECC71", "Basse": "#2ECC71"
};
const colorFor = (name, map) => {
  if (map[name]) return map[name];
  let hash = 0;
  for (const character of String(name)) hash = character.charCodeAt(0) + ((hash << 5) - hash);
  return PALETTE[Math.abs(hash) % PALETTE.length];
};
const legend = (position = "bottom") => ({ position, labels: { boxWidth: 12, font: { size: 11 } } });
const axes = (options = {}) => ({
  x: { grid: { display: false }, ...options.x },
  y: { grid: { color: "rgba(0,0,0,.05)" }, ...options.y }
});
const sum = values => values.reduce((total, value) => total + value, 0);
const round2 = value => Math.round(value * 100) / 100;
// Numbers in the page language ("83,1" in French), with the precision the server uses.
const numberFormat = digits => new Intl.NumberFormat(document.documentElement.lang || undefined, { maximumFractionDigits: digits });
const formatDays = numberFormat(1).format;
const formatHours = numberFormat(2).format;

const detailsUrl = document.querySelector(".reporting-sections").dataset.reportDetailsUrl;
const detailWindow = (title, filters) => {
  const params = new URLSearchParams(report.queryParams);
  Object.entries({ title, from: report.dateFrom, to: report.dateTo, ...filters }).forEach(([key, value]) => params.set(key, value));
  window.open(`${detailsUrl}?${params}`, "_blank", "noopener,noreferrer");
};
// Calendar boundaries come from PeriodGrid, including partial periods and time zones.
const periodRange = (ranges, index) => ranges[index];
// A click on an element wins; otherwise the nearest point or bar of the clicked period is used,
// so a period can be opened from anywhere in its column, not only on a 4px point.
// Charts over periods also accept a click on the period label below the x axis.
const clickable = (resolve, resolvePeriod) => ({
  onClick: (event, _elements, chart) => {
    let elements = chart.getElementsAtEventForMode(event, "nearest", { intersect: true }, false);
    if (!elements.length) elements = chart.getElementsAtEventForMode(event, "nearest", { intersect: false, axis: "xy" }, false);
    const request = elements.length && resolve(elements[0], chart);
    if (request) detailWindow(request.title, request.filters);
  },
  // "on" options are not scriptable in Chart.js, so the function is kept as is.
  ...(resolvePeriod ? { onPeriodClick: resolvePeriod } : {})
});
// Chart.js only calls onClick inside the plot area; labels below the x axis are handled here.
Chart.register({
  id: "periodLabelClick",
  afterEvent(chart, { event, inChartArea }) {
    const resolvePeriod = chart.options.onPeriodClick;
    const area = chart.chartArea;
    const xAxis = chart.scales.x;
    if (event.type !== "click" || inChartArea || !resolvePeriod || !xAxis) return;
    if (event.y <= area.bottom || event.y > xAxis.bottom || event.x < area.left || event.x > area.right) return;
    const request = resolvePeriod(Math.round(xAxis.getValueForPixel(event.x)));
    if (request) detailWindow(request.title, request.filters);
  }
});
window.matchMedia("(min-width: 700px)").addEventListener("change", () => {
  Object.values(Chart.instances).forEach(chart => {
    positionLegend(chart.config.options, chart.canvas.id, chart.width);
    chart.update("none");
  });
});
// Issues created or closed during a period, whatever the dataset.
const flowPeriod = (index) => {
  const range = periodRange(flow.periodRanges, index);
  return { title: t("created_or_closed", { period: flow.periodLabels[index] }), filters: { records: "issues", flow_from: range.from, flow_to: range.to } };
};
const backlogPeriod = (labels, starts) => (index) => ({
  title: t("backlog_at", { period: labels[index] }), filters: { records: "issues", backlog_at: periodRange(starts, index).to }
});
// Tabs and charts hidden by project modules or permissions have no canvas and are skipped.
const positionLegend = (options, id, width) => {
  if (!/^(consumption-|status-|time-activity)/.test(id)) return;
  const side = window.innerWidth >= 700 && width >= 480;
  options.plugins.legend.position = side ? "right" : "bottom";
  options.plugins.legend.maxWidth = side ? 180 : width;
};
const draw = (id, config) => {
  const canvas = document.getElementById(id);
  if (!canvas) return;
  const options = { responsive: true, maintainAspectRatio: false, ...config.options };
  positionLegend(options, id, canvas.parentElement.clientWidth);
  options.onResize = (chart, size) => positionLegend(chart.config.options, id, size.width);
  return new Chart(canvas, { ...config, options });
};
const drawDonut = (id, labels, values, resolve) => {
  const canvas = document.getElementById(id);
  if (!canvas) return;
  if (!values.length) {
    canvas.closest(".reporting-chart").innerHTML = `<p class="reporting-empty">${t("no_issue")}</p>`;
    return;
  }
  draw(id, {
    type: "doughnut",
    data: { labels, datasets: [{ data: values, backgroundColor: labels.map((_, index) => PALETTE[index % PALETTE.length]), borderWidth: 2 }] },
    options: { plugins: { legend: legend("right") }, ...clickable(resolve) }
  });
};
const lineSeries = (label, data, color, fill) => ({ label, data, borderColor: color, backgroundColor: fill, fill: true, tension: 0.3, pointRadius: 4 });

const flow = report.issueFlow;
if (flow) {
// Each group has two signed datasets on the same stack; equal counts never cancel.
const mirroredFlowChart = (id, groups, colorMap, dimension) => draw(id, {
  type: "bar",
  data: {
    labels: flow.periodLabels,
    datasets: groups.flatMap(group => [
      { label: group.label, data: group.opened, flowEvent: "created", backgroundColor: colorFor(group.label, colorMap), stack: "flow" },
      { label: group.label, data: group.closed, flowEvent: "closed", backgroundColor: colorFor(group.label, colorMap), stack: "flow" }
    ])
  },
  options: {
    plugins: {
      legend: {
        ...legend(),
        labels: { ...legend().labels, filter: item => item.datasetIndex % 2 === 0 },
        // A legend item toggles both the positive and negative bars for its group.
        onClick: (_event, item, chartLegend) => {
          const chart = chartLegend.chart;
          const visible = !chart.isDatasetVisible(item.datasetIndex);
          chart.setDatasetVisibility(item.datasetIndex, visible);
          chart.setDatasetVisibility(item.datasetIndex + 1, visible);
          chart.update();
        }
      },
      tooltip: { callbacks: { label: context => {
        const eventLabel = t(context.dataset.flowEvent === "closed" ? "closures" : "created");
        const count = context.parsed.y;
        return t("value", { label: `${context.dataset.label} — ${eventLabel}`, value: `${count > 0 ? "+" : ""}${count}` });
      } } }
    },
    scales: axes({ x: { stacked: true }, y: { stacked: true, ticks: { precision: 0 } } }),
    ...clickable((element, chart) => {
      const dataset = chart.data.datasets[element.datasetIndex];
      const range = periodRange(flow.periodRanges, element.index);
      const isClosed = dataset.flowEvent === "closed";
      return {
        title: `${dataset.label} — ${t(isClosed ? "closures" : "created")} — ${flow.periodLabels[element.index]}`,
        filters: { records: "issues", [dimension]: dataset.label,
          ...(isClosed ? { closed_from: range.from, closed_to: range.to } : { created_from: range.from, created_to: range.to }) }
      };
    }, flowPeriod)
  }
});
mirroredFlowChart("flow-tracker", flow.trackerFlow, TRACKER_COLORS, "tracker");
mirroredFlowChart("flow-priority", flow.priorityFlow, PRIORITY_COLORS, "priority");
draw("flow-monthly", {
  type: "line",
  data: { labels: flow.periodLabels, datasets: [lineSeries(t("opened"), flow.opened, "#E74C3C", "rgba(231,76,60,.08)"), lineSeries(t("closed"), flow.closed, "#27AE60", "rgba(39,174,96,.08)")] },
  options: {
    plugins: { legend: legend() },
    scales: axes({ y: { beginAtZero: true, ticks: { precision: 0 } } }),
    ...clickable((element) => {
      const range = periodRange(flow.periodRanges, element.index);
      const isClosed = element.datasetIndex === 1;
      return {
        title: `${t(isClosed ? "closed" : "opened")} — ${flow.periodLabels[element.index]}`,
        filters: { records: "issues", ...(isClosed ? { closed_from: range.from, closed_to: range.to } : { created_from: range.from, created_to: range.to }) }
      };
    }, flowPeriod)
  }
});
draw("flow-cumulative", {
  type: "line",
  data: { labels: flow.periodLabels, datasets: [lineSeries(t("created_cumulative"), flow.cumulativeCreated, "#E74C3C", "rgba(231,76,60,.08)"), lineSeries(t("closed_cumulative"), flow.cumulativeClosed, "#27AE60", "rgba(39,174,96,.08)")] },
  options: {
    plugins: { legend: legend() },
    scales: axes({ y: { beginAtZero: true, ticks: { precision: 0 } } }),
    ...clickable((element) => {
      const date = periodRange(flow.periodRanges, element.index).to;
      return element.datasetIndex
        ? { title: t("closed_between", { from: report.dateFrom, to: date }), filters: { records: "issues", closed_from: report.dateFrom, closed_to: date } }
        : { title: t("created_between", { from: report.dateFrom, to: date }), filters: { records: "issues", created_from: report.dateFrom, created_to: date } };
    }, (index) => {
      const date = periodRange(flow.periodRanges, index).to;
      return { title: t("created_or_closed_between", { from: report.dateFrom, to: date }),
        filters: { records: "issues", flow_from: report.dateFrom, flow_to: date } };
    })
  }
});
drawDonut("status-open", flow.openStatusLabels, flow.openStatusValues, (element) => ({ title: `${t("opened")} — ${flow.openStatusLabels[element.index]}`, filters: { records: "issues", status: flow.openStatusLabels[element.index], open: "true" } }));
drawDonut("status-closed", flow.closedStatusLabels, flow.closedStatusValues, (element) => ({ title: `${t("closed")} — ${flow.closedStatusLabels[element.index]}`, filters: { records: "issues", status: flow.closedStatusLabels[element.index], closed_from: report.dateFrom, closed_to: report.dateTo } }));

}

const activity = report.activity;
if (activity) {
const users = activity.userLabels.map((label, index) => ({ label, index, hours: activity.userHours[index] }))
  .sort((first, second) => second.hours - first.hours);
draw("time-user", {
  type: "bar",
  data: {
    labels: users.map(user => user.label),
    datasets: activity.activityLabels.map((label, activityIndex) => ({
      label, activityId: activity.activityIds[activityIndex],
      data: users.map(user => activity.userActivityHours[activityIndex][user.index]),
      backgroundColor: PALETTE[activityIndex % PALETTE.length]
    }))
  },
  options: {
    indexAxis: "y",
    plugins: {
      legend: { display: false },
      tooltip: { callbacks: { label: context => t("value", { label: context.dataset.label, value: t("hours_short", { value: formatHours(context.parsed.x) }) }) } }
    },
    scales: { x: { stacked: true, grid: { color: "rgba(0,0,0,.05)" } }, y: { stacked: true, grid: { display: false } } },
    ...clickable((element, chart) => {
      const user = users[element.index];
      const dataset = chart.data.datasets[element.datasetIndex];
      return { title: `${t("time")} — ${user.label} — ${dataset.label}`,
        filters: { records: "time_entries", user_id: activity.userIds[user.index], activity_id: dataset.activityId } };
    })
  }
});
drawDonut("time-activity", activity.activityLabels, activity.activityHours, (element) => ({ title: `${t("activity")} — ${activity.activityLabels[element.index]}`, filters: { records: "time_entries", activity_id: activity.activityIds[element.index] } }));

}

const consumption = report.consumption;
if (consumption) {
const shortDays = value => t("days_short", { value: formatDays(value) });
// Canvas legend entries expose their interpretation without replacing the toggle behavior.
const legendHelp = {
  onHover: (event, item, chartLegend) => {
    const chart = chartLegend.chart;
    const container = chart.canvas.parentElement;
    let tooltip = container.querySelector(".reporting-legend-tooltip");
    if (!tooltip) {
      tooltip = document.createElement("div");
      tooltip.className = "reporting-legend-tooltip";
      tooltip.setAttribute("role", "tooltip");
      container.appendChild(tooltip);
    }
    tooltip.textContent = t(chart.data.datasets[item.datasetIndex].help);
    tooltip.style.left = `${Math.max(0, Math.min(event.x + 12, container.clientWidth - 260))}px`;
    tooltip.hidden = false;
    tooltip.style.top = `${Math.max(0, Math.min(event.y + 16, container.clientHeight - tooltip.offsetHeight - 4))}px`;
  },
  onLeave: (_event, _item, chartLegend) => {
    const tooltip = chartLegend.chart.canvas.parentElement.querySelector(".reporting-legend-tooltip");
    if (tooltip) tooltip.hidden = true;
  }
};
const consumptionChart = (id, data, monthEntries = (index) => ({
  title: `${t("spent")} — ${data.labels[index]}`, filters: { records: "time_entries", ...periodRange(data.periodRanges, index) }
})) => draw(id, {
  type: "bar",
  data: {
    labels: data.labels,
    datasets: [
      { type: "bar", label: t("refills"), help: "refills_help", data: data.refills, backgroundColor: "rgba(68,114,196,.65)", order: 3 },
      { type: "bar", label: t("spent"), help: "spent_help", data: data.spent, backgroundColor: "rgba(247,148,29,.45)", order: 3 },
      { type: "line", label: t("credit"), help: "credit_help", data: data.credit, borderColor: "#27AE60", borderWidth: 2.5, pointRadius: 3, tension: 0.3, fill: false, order: 1 },
      { type: "line", label: t("balance_at_month_start"), help: "balance_help", data: data.creditBefore, borderColor: "#82E0AA", borderWidth: 1.5, borderDash: [4, 4], pointRadius: 2, tension: 0.3, fill: false, order: 1 },
      { type: "line", label: t("horizon"), help: "horizon_help", data: data.horizon, borderColor: "#2ECC71", borderWidth: 1.5, borderDash: [8, 4], pointRadius: 2, tension: 0.3, fill: false, order: 1 },
      // Tooltip only: not drawn and hidden from the legend.
      { type: "line", label: t("cumulative_spent"), data: data.cumulativeSpent, borderColor: "#D5D8DC", backgroundColor: "#D5D8DC", borderWidth: 0, pointRadius: 0, pointHoverRadius: 0, fill: false, order: 4, tooltipOnly: true }
    ]
  },
  options: {
    interaction: { mode: "index", intersect: false },
    plugins: {
      legend: { ...legend("top"), ...legendHelp, labels: { ...legend().labels, filter: (item, chartData) => !chartData.datasets[item.datasetIndex]?.tooltipOnly } },
      tooltip: { callbacks: { label: context => t("value", { label: context.dataset.label, value: t("days", { value: formatDays(context.parsed.y) }) }) } }
    },
    scales: axes({ y: { ticks: { callback: value => shortDays(value) } } }),
    ...clickable(({ index }) => monthEntries(index), monthEntries)
  }
});
consumptionChart("consumption-period", consumption.period);
consumptionChart("consumption-contract", consumption.contract);

}

const backlog = report.backlog;
if (backlog) {
const stackedBacklog = (id, items, colorMap, dimension) => draw(id, {
  type: "bar",
  data: { labels: backlog.periodLabels, datasets: items.map(item => ({ label: item.label, data: item.data, backgroundColor: colorFor(item.label, colorMap), stack: "backlog" })) },
  options: {
    plugins: { legend: legend() },
    scales: axes({ x: { stacked: true }, y: { stacked: true, ticks: { precision: 0 } } }),
    ...clickable((element, chart) => {
      const label = chart.data.datasets[element.datasetIndex].label;
      return { title: t("backlog_group", { group: label, period: backlog.periodLabels[element.index] }), filters: { records: "issues", backlog_at: periodRange(backlog.periodRanges, element.index).to, [dimension]: label } };
    }, backlogPeriod(backlog.periodLabels, backlog.periodRanges))
  }
});
stackedBacklog("backlog-tracker", backlog.trackerSeries, TRACKER_COLORS, "tracker");
stackedBacklog("backlog-priority", backlog.prioritySeries, PRIORITY_COLORS, "priority");
const remainingPeriod = (index, tracker) => ({
  title: `${t("remaining")}${tracker ? ` ${tracker}` : ""} — ${backlog.periodLabels[index]}`,
  filters: { records: "issues", backlog_at: periodRange(backlog.periodRanges, index).to, times: "true", ...(tracker ? { tracker } : {}) }
});
if (backlog.remainingSeries) draw("estimated-remaining", {
  type: "bar",
  data: {
    labels: backlog.periodLabels,
    datasets: [
      { type: "line", label: t("total"), data: backlog.remainingTotal, borderColor: "#5B6770", backgroundColor: "#5B6770", borderWidth: 2.5, pointRadius: 3, tension: 0.3, fill: false, order: 1 },
      ...backlog.remainingSeries.map(item => ({ label: item.label, data: item.data, backgroundColor: colorFor(item.label, TRACKER_COLORS), stack: "remaining", order: 2 }))
    ]
  },
  options: {
    plugins: { legend: legend(), tooltip: { callbacks: { label: context => t("remaining_hours", { label: context.dataset.label, value: formatHours(context.parsed.y) }) } } },
    scales: axes({ x: { stacked: true }, y: { stacked: true, ticks: { callback: value => t("hours_short", { value }) } } }),
    ...clickable((element, chart) => remainingPeriod(element.index, element.datasetIndex ? chart.data.datasets[element.datasetIndex].label : null), remainingPeriod)
  }
});

}

const performance = report.performance;
if (performance) {
const velocityPeriod = (index) => {
  const range = periodRange(performance.periodRanges, index);
  return { title: `${t("closed_issues")} — ${performance.periodLabels[index]}`, filters: { records: "issues", closed: "true", closed_from: range.from, closed_to: range.to } };
};
draw("velocity", {
  type: "bar",
  data: { labels: performance.periodLabels, datasets: [{ label: t("closed_issues"), data: performance.velocity, backgroundColor: "rgba(39,174,96,.75)", borderRadius: 3 }] },
  options: {
    plugins: { legend: { display: false } },
    scales: axes({ y: { ticks: { precision: 0 } } }),
    ...clickable(({ index }) => velocityPeriod(index), velocityPeriod)
  }
});
draw("resolution", {
  type: "bar",
  data: { labels: performance.resolutionLabels, datasets: [{ label: t("average_days"), data: performance.resolutionDays, backgroundColor: performance.resolutionLabels.map(label => colorFor(label, PRIORITY_COLORS)), borderRadius: 3 }] },
  options: {
    indexAxis: "y",
    plugins: { legend: { display: false }, tooltip: { callbacks: { label: context => t("average_days_tooltip", { days: context.parsed.x, count: performance.resolutionCounts[context.dataIndex] }) } } },
    scales: { x: { grid: { color: "rgba(0,0,0,.05)" } }, y: { grid: { display: false } } },
    ...clickable((element) => ({ title: `${t("resolution")} — ${performance.resolutionLabels[element.index]}`, filters: { records: "issues", closed: "true", closed_from: report.dateFrom, closed_to: report.dateTo, priority: performance.resolutionLabels[element.index] } }))
  }
});
draw("aging", {
  type: "bar",
  data: { labels: performance.agingLabels, datasets: [{ label: t("open_issues"), data: performance.agingValues, backgroundColor: ["#27AE60", "#F7941D", "#E67E22", "#E74C3C", "#8E44AD"], borderRadius: 3 }] },
  options: {
    plugins: { legend: { display: false } },
    scales: axes({ y: { ticks: { precision: 0 } } }),
    ...clickable((element) => ({ title: `${t("aging")} — ${performance.agingLabels[element.index]}`, filters: { records: "issues", open: "true", age: performance.agingKeys[element.index], as_of: report.dateTo } }))
  }
});
}
const build = report.build;
if (build && build.versions.length) {
  const rows = build.versions;
  const labels = rows.map(row => row.name || t("build_unversioned"));
  const selection = (index, filters = {}) => ({title: labels[index], filters: {
    records: "issues", version_id: rows[index].id || "none", ...filters
  }});
  draw("build-progress", {
    type: "bar",
    data: {labels, datasets: [
      {label: t("closed_issues"), data: rows.map(row => row.closed), backgroundColor: "#27AE60"},
      {label: t("open_issues"), data: rows.map(row => row.open), backgroundColor: "#4472C4"}
    ]},
    options: {indexAxis: "y", plugins: {legend: legend(), tooltip: {callbacks: {
      afterTitle: contexts => `${rows[contexts[0].dataIndex].progress}%`
    }}}, scales: axes({x: {stacked: true, ticks: {precision: 0}}, y: {stacked: true}}),
    ...clickable(({index, datasetIndex}) => selection(index, datasetIndex ? {open: "true"} : {closed: "true"}))}
  });
  draw("build-deadlines", {
    type: "bar",
    data: {labels, datasets: [{label: t("build_overdue"), data: rows.map(row => row.overdue), backgroundColor: "#E74C3C"}]},
    options: {indexAxis: "y", plugins: {legend: legend(), tooltip: {callbacks: {
      afterTitle: contexts => t("build_due", {date: rows[contexts[0].dataIndex].dueDate || t("build_no_due")})
    }}}, scales: axes({x: {ticks: {precision: 0}}}),
    ...clickable(({index}) => {
      const yesterday = new Date(`${build.today}T12:00:00Z`);
      yesterday.setUTCDate(yesterday.getUTCDate() - 1);
      return selection(index, {open: "true", due_before: yesterday.toISOString().slice(0, 10)});
    })}
  });
  if (rows[0].spent !== undefined) draw("build-charges", {
    type: "bar",
    data: {labels, datasets: ["estimated", "spent", "remaining", "overrun"].map((key, index) => ({
      label: t(`build_${key}`), data: rows.map(row => row[key]), backgroundColor: PALETTE[index]
    }))},
    options: {indexAxis: "y", plugins: {legend: legend(), tooltip: {callbacks: {
      label: context => `${context.dataset.label}: ${formatHours(context.parsed.x)} h`
    }}}, scales: axes({x: {ticks: {callback: value => t("hours_short", {value})}}}),
    ...clickable(({index, datasetIndex}) => selection(index, {times: "true", ...(datasetIndex === 2 ? {open: "true"} : {})}))}
  });
}
const workload = report.workload;
if (workload) {
  ["assignees", "remaining", "contributors"].forEach(key => {
    const rows = workload[key];
    if (!rows || !rows.length) return;
    const hours = key !== "assignees";
    draw(`workload-${key}`, {
      type: "bar",
      data: {labels: rows.map(row => row.name || t("workload_unassigned")), datasets: [{
        label: t(`workload_${key}`), data: rows.map(row => hours ? row.hours : row.count), backgroundColor: "#4472C4"
      }]},
      options: {indexAxis: "y", plugins: {legend: {display: false}, tooltip: {callbacks: {
        label: context => hours ? t("hours_short", {value: formatHours(context.parsed.x)}) : t("workload_count", {count: context.parsed.x, missing: rows[context.dataIndex].unestimated})
      }}}, scales: axes({x: {beginAtZero: true, ticks: hours ? {callback: value => t("hours_short", {value})} : {precision: 0}}}),
      ...clickable(({index}) => ({title: rows[index].name || t("workload_unassigned"), filters:
        key === "contributors" ? {records: "time_entries", user_id: rows[index].id} : {
          records: "issues", open: "true", assignee_id: rows[index].id || "none",
          ...(key === "remaining" ? {times: "true", workload_effort: "true"} : {})
        }
      }))}
    });
  });
}
if (workload && workload.mix) {
  const rows = workload.mix;
  const total = sum(rows.map(row => row.hours));
  if (total > 0) draw("workload-mix", {
    type: "doughnut",
    data: {labels: rows.map(row => t(`work_mix_${row.role}`)), datasets: [{data: rows.map(row => row.hours), backgroundColor: ["#4472C4", "#27AE60", "#F7941D", "#7F8C8D"]}]},
    options: {plugins: {legend: legend(), tooltip: {callbacks: {
      label: context => `${context.label}: ${formatHours(context.parsed)} h (${formatHours(context.parsed * 100 / total)} %)`
    }}}, ...clickable(({index}) => ({title: t(`work_mix_${rows[index].role}`), filters: {records: "time_entries", work_role: rows[index].role}}))}
  });
  else {
    const canvas = document.getElementById("workload-mix");
    if (canvas) canvas.closest(".reporting-chart").textContent = t("work_mix_empty");
  }
}
if (report.burnup) report.burnup.versions.forEach((version, index) => {
  draw(`burnup-${index}`, {
    type: "line",
    data: {labels: report.burnup.labels, datasets: [
      {label: t("burnup_scope"), data: version.scope, borderColor: "#4472C4", backgroundColor: "#4472C4", tension: 0, pointRadius: 4},
      {label: t("burnup_completed"), data: version.completed, borderColor: "#27AE60", backgroundColor: "#27AE60", tension: 0, pointRadius: 4}
    ]},
    options: {plugins: {legend: legend(), tooltip: {callbacks: {afterTitle: contexts => report.burnup.dates[contexts[0].dataIndex]}}},
      scales: axes({y: {beginAtZero: true, ticks: {precision: 0}}}),
      ...clickable(({index: point, datasetIndex}) => ({title: version.name || t("build_unversioned"), filters: {
        records: "issues", version_at: report.burnup.dates[point], historical_version_id: version.id || "none", completed: datasetIndex === 1 ? "true" : "false"
      }}))}
  });
});
})();
