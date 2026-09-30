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
  if (!/^(flow-tracker|flow-priority|backlog-|estimated-remaining|consumption-|status-|time-activity)/.test(id)) return;
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
const statCards = (id, cards) => {
  const container = document.getElementById(id);
  if (!container) return;
  container.innerHTML = cards.map(([value, label, color]) =>
    `<div class="reporting-stat"><div class="value"${color ? ` style="color:${color}"` : ""}>${value}</div><div class="label">${label}</div></div>`
  ).join("");
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
const users = activity.userLabels.map((label, index) => [label, activity.userHours[index]]).sort((a, b) => b[1] - a[1]);
draw("time-user", {
  type: "bar",
  data: { labels: users.map(([label]) => label), datasets: [{ label: t("hours"), data: users.map(([, hours]) => hours), backgroundColor: users.map((_, index) => PALETTE[index % PALETTE.length]) }] },
  options: {
    indexAxis: "y",
    plugins: { legend: { display: false } },
    scales: { x: { grid: { color: "rgba(0,0,0,.05)" } }, y: { grid: { display: false } } },
    ...clickable((element) => ({ title: `${t("time")} — ${users[element.index][0]}`, filters: { records: "time_entries", user: users[element.index][0] } }))
  }
});
drawDonut("time-activity", activity.activityLabels, activity.activityHours, (element) => ({ title: `${t("activity")} — ${activity.activityLabels[element.index]}`, filters: { records: "time_entries", activity: activity.activityLabels[element.index] } }));

}

const consumption = report.consumption;
if (consumption) {
const contract = consumption.contract;
const granted = sum(contract.grants);
const refilled = sum(contract.refills);
const consumed = round2(sum(contract.spent));
const available = granted + refilled;
const progress = available ? Math.round(consumed / available * 100) : 0;
const shortDays = value => t("days_short", { value: formatDays(value) });
statCards("consumption-stats", [
  [shortDays(round2(granted)), t("initial_credit")],
  [shortDays(round2(refilled)), t("refills")],
  [shortDays(consumed), t("consumed"), "#E74C3C"],
  [shortDays(contract.credit.length ? contract.credit[contract.credit.length - 1] : 0), t("remaining_credit"), "#27AE60"],
  [`${progress}%`, t("progress")]
]);
const progressCard = document.querySelector("#consumption-stats .reporting-stat:last-child");
progressCard?.insertAdjacentHTML("beforeend", `<div class="reporting-progress"><div style="width:${Math.min(progress, 100)}%;background:${progress > 90 ? "#E74C3C" : progress > 70 ? "#F7941D" : "#27AE60"}"></div></div>`);
const consumptionChart = (id, data, monthEntries = (index) => ({
  title: `${t("spent")} — ${data.labels[index]}`, filters: { records: "time_entries", ...periodRange(data.periodRanges, index) }
})) => draw(id, {
  type: "bar",
  data: {
    labels: data.labels,
    datasets: [
      { type: "bar", label: t("refills"), data: data.refills, backgroundColor: "rgba(68,114,196,.65)", order: 3 },
      { type: "bar", label: t("spent"), data: data.spent, backgroundColor: "rgba(247,148,29,.45)", order: 3 },
      { type: "line", label: t("credit"), data: data.credit, borderColor: "#27AE60", borderWidth: 2.5, pointRadius: 3, tension: 0.3, fill: false, order: 1 },
      { type: "line", label: t("balance_at_month_start"), data: data.creditBefore, borderColor: "#82E0AA", borderWidth: 1.5, borderDash: [4, 4], pointRadius: 2, tension: 0.3, fill: false, order: 1 },
      { type: "line", label: t("horizon"), data: data.horizon, borderColor: "#2ECC71", borderWidth: 1.5, borderDash: [8, 4], pointRadius: 2, tension: 0.3, fill: false, order: 1 },
      // Tooltip only: not drawn and hidden from the legend.
      { type: "line", label: t("cumulative_spent"), data: data.cumulativeSpent, borderColor: "#D5D8DC", backgroundColor: "#D5D8DC", borderWidth: 0, pointRadius: 0, pointHoverRadius: 0, fill: false, order: 4, tooltipOnly: true }
    ]
  },
  options: {
    interaction: { mode: "index", intersect: false },
    plugins: {
      legend: { ...legend("top"), labels: { ...legend().labels, filter: (item, chartData) => !chartData.datasets[item.datasetIndex]?.tooltipOnly } },
      tooltip: { callbacks: { label: context => t("value", { label: context.dataset.label, value: t("days", { value: formatDays(context.parsed.y) }) }) } }
    },
    scales: axes({ y: { ticks: { callback: value => shortDays(value) } } }),
    ...clickable(({ index }) => monthEntries(index), monthEntries)
  }
});
consumptionChart("consumption-12m", consumption.last12);
consumptionChart("consumption-contract", contract);

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
})();
