local M = {}

local TOOL_DOC = "Show the user numeric data as a chart in a scratch split beside the transcript, with"
  .. " one highlight group per series. Use it whenever a result is numeric and comparative (counts per"
  .. " file, timings before and after, sizes, a distribution, a value over time) instead of listing the"
  .. " numbers in the reply. Read-only: creates a scratch buffer, touches no files. Parameters: kind"
  .. " (required) — 'bar' (ranked categories, horizontal), 'stacked' (one horizontal bar per label, the"
  .. " series laid end to end and the total printed), 'diverging' (one series of deltas, negatives left"
  .. " of a zero axis and positives right), 'column' (categories side by side, several series per"
  .. " category), 'stacked_column' (one column per label, series stacked), 'line' (a value over an"
  .. " ordered axis, braille), 'scatter' (x against values per series, braille; each series carries an x"
  .. " array), 'sparkline' (one compact row per series), 'histogram' (raw samples, binned by the tool);"
  .. " labels (required except for histogram and scatter) — one string per data point; series (required)"
  .. " — array of { name, values, x? }, every values array as long as labels (histogram: one series of"
  .. " raw samples; scatter: x as long as values); title, unit (optional) — unit is appended to every"
  .. " printed y value; x_unit (optional, scatter); sort (optional) — 'asc' or 'desc' by the first"
  .. " series or by the row total for stacked kinds; bins (optional, histogram) — bin count, default 10;"
  .. " width, height (optional) — cells; split (optional) — 'vertical' (default) or 'horizontal'. bar,"
  .. " stacked, column and stacked_column take values >= 0; diverging, line, scatter and sparkline take"
  .. " any number. Returns a one-line confirmation, or 'show_chart: <reason>' when the input is rejected."

local TOOL_SCHEMA = {
  type = "object",
  properties = {
    kind = {
      type = "string",
      enum = { "bar", "stacked", "diverging", "column", "stacked_column", "line", "scatter", "sparkline", "histogram" },
      description = "Chart kind.",
    },
    title = { type = "string", description = "Title shown in the winbar and as the first line." },
    labels = { type = "array", items = { type = "string" },
      description = "One label per data point, in drawing order. Not used by histogram or scatter." },
    series = {
      type = "array",
      items = {
        type = "object",
        properties = {
          name = { type = "string", description = "Series name, printed in the legend." },
          values = { type = "array", items = { type = "number" }, description = "One value per label." },
          x = { type = "array", items = { type = "number" },
            description = "scatter only: one x per value." },
        },
        required = { "values" },
      },
      description = "One or more series. Every values array must be as long as labels.",
    },
    unit = { type = "string", description = "Unit suffix for printed values, e.g. 'ms', 'KB', '%'." },
    x_unit = { type = "string", description = "scatter only: unit suffix for the x axis ends." },
    sort = { type = "string", enum = { "none", "asc", "desc" },
      description = "Sort labels by the first series, or by the row total for stacked kinds;"
        .. " not for histogram or scatter." },
    bins = { type = "integer", description = "Histogram bin count (default 10)." },
    width = { type = "integer", description = "Chart width in cells (default config.max_width)." },
    height = { type = "integer", description = "Plot height in rows for column, line and scatter (default 8)." },
    split = { type = "string", enum = { "vertical", "horizontal" }, description = "Split direction." },
  },
  required = { "kind", "series" },
}

local TOOL_SRC = [[return function(input, ctx)
  return require("straps_chartifier").show_chart(input, ctx)
end]]

local RENDER_SRC = [[return function(spec)
  return require("straps_chartifier.render").render(spec)
end]]

local LAYER_SRC = [[return function(opts)
  local chartifier = require("straps_chartifier")
  if chartifier.config.prompt_layer == false then
    return nil
  end
  return require("straps_chartifier.prompt").LAYER
end]]

function M.register_tool(define)
  define({
    name = "tool.show_chart",
    kind = "tool",
    doc = TOOL_DOC,
    input_schema = TOOL_SCHEMA,
    capability = "read",
    source = TOOL_SRC,
  })
  define({
    name = "fn.chartifier_render",
    kind = "fn",
    doc = "Draw a normalized chart spec."
      .. " (spec) -> { lines = string[], spans = { row, col_start, col_end, group }[] }."
      .. " Rows and byte columns are 0-based, col_end exclusive, as nvim_buf_set_extmark takes them.",
    source = RENDER_SRC,
  })
  define({
    name = "skill.charting",
    kind = "skill",
    doc = "Before calling show_chart: picking the kind, labels, units, and what the reply says beside a chart.",
    source = require("straps_chartifier.prompt").SKILL,
  })
end

function M.register_layer(define)
  define({
    name = "fn.system_prompt_layer.chartifier",
    kind = "fn",
    doc = "Prompt layer: \"# Charts\" section nudging the agent toward show_chart for numeric results.",
    source = LAYER_SRC,
  })
end

return M
