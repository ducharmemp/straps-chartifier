-- Run: busted tests/tool_spec.lua

local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")

local straps = require("straps").setup({})
straps.config.session_dir = vim.fn.tempname()
local registry = require("straps.registry")

vim.g.loaded_straps = nil
vim.cmd("source " .. vim.fn.fnameescape(H.straps_root .. "/plugin/straps.lua"))
vim.g.loaded_straps_chartifier = nil
vim.cmd("source " .. vim.fn.fnameescape(H.root .. "/plugin/straps_chartifier.lua"))
local chartifier = require("straps_chartifier")

local INPUT = {
  kind = "bar", title = "Hits", unit = "ms", labels = { "a", "b" },
  series = { { name = "x", values = { 3, 1 } } },
}

local function chart_wins()
  local out = {}
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    local b = vim.api.nvim_win_get_buf(w)
    if vim.bo[b].filetype == "strapschart" then out[#out + 1] = w end
  end
  return out
end

local function close_charts()
  for _, w in ipairs(chart_wins()) do vim.api.nvim_win_close(w, true) end
end

describe("registration from the plugin file", function()
  it("defines the tool, the renderer fn, the skill and the prompt layer", function()
    assert.is_not_nil(registry.get("tool.show_chart"))
    assert.is_not_nil(registry.get("fn.chartifier_render"))
    assert.is_not_nil(registry.get("skill.charting"))
    assert.is_not_nil(registry.get("fn.system_prompt_layer.chartifier"))
    assert.equals("registered", chartifier.status().prompt_layer)
    assert.is_true(chartifier.status().tool)
  end)

  it("is guarded against a second source", function()
    assert.is_true(vim.g.loaded_straps_chartifier)
    local v = registry.get("tool.show_chart").version
    vim.cmd("source " .. vim.fn.fnameescape(H.root .. "/plugin/straps_chartifier.lua"))
    assert.equals(v, registry.get("tool.show_chart").version)
  end)
end)

describe("permissions", function()
  it("classifies show_chart as read so hook.confirm auto-allows it", function()
    assert.equals("read", registry.call("fn.capability", "show_chart", INPUT))
    assert.is_true(registry.call("fn.readonly_policy", "show_chart", INPUT))
    assert.is_true(registry.call("hook.confirm", "show_chart", INPUT, {}))
    assert.equals("other", registry.call("fn.capability", "show_chart_missing", INPUT))
  end)
end)

describe("tool.show_chart", function()
  after_each(close_charts)

  it("opens a chart split and reports kind, title, counts and lines", function()
    local before = #chart_wins()
    local result = registry.call("tool.show_chart", INPUT)
    assert.equals("show_chart: opened a bar chart — Hits (2 labels, 1 series, 3 lines)", result)
    assert.equals(before + 1, #chart_wins())
    local b = vim.api.nvim_win_get_buf(chart_wins()[1])
    local lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
    assert.equals("Hits", lines[1])
    assert.matches("^a │" .. ("█"):rep(10) .. ".* 3 ms$", lines[2])
    assert.equals("Hits", vim.wo[chart_wins()[1]].winbar)
  end)

  it("reports histogram bins and omits the title segment when there is none", function()
    local result = registry.call("tool.show_chart",
      { kind = "histogram", bins = 3, series = { { values = { 1, 2, 3 } } } })
    assert.equals("show_chart: opened a histogram chart (3 bins, 1 series, 3 lines)", result)
  end)

  it("reports scatter points across series", function()
    local result = registry.call("tool.show_chart", { kind = "scatter", height = 2,
      series = { { x = { 1, 2 }, values = { 1, 2 } }, { x = { 3 }, values = { 3 } } } })
    assert.equals("show_chart: opened a scatter chart (3 points, 2 series, 5 lines)", result)
  end)

  it("returns an error string for bad input and opens nothing", function()
    local before = #chart_wins()
    assert.equals("show_chart: kind must be one of bar, stacked, diverging, column, stacked_column, line, scatter,"
      .. " sparkline, histogram (got pie)",
      registry.call("tool.show_chart", { kind = "pie", labels = { "a" }, series = { { values = { 1 } } } }))
    assert.equals("show_chart: series[1] has 1 values but there are 2 labels",
      registry.call("tool.show_chart", { kind = "bar", labels = { "a", "b" }, series = { { values = { 1 } } } }))
    assert.equals("show_chart: input must be an object", registry.call("tool.show_chart", nil))
    assert.equals(before, #chart_wins())
  end)

  it("returns the renderer's refusal as an error string", function()
    local labels, values = {}, {}
    for i = 1, 30 do
      labels[i] = "label" .. i
      values[i] = i
    end
    local result = registry.call("tool.show_chart",
      { kind = "column", width = 20, labels = labels, series = { { values = values } } })
    assert.equals("show_chart: 30 labels x 1 series do not fit in width 20; raise width or reduce the data", result)
    assert.equals(0, #chart_wins())
  end)

  it("honors config.split, config.highlight and the split override", function()
    chartifier.config.split = "horizontal"
    chartifier.config.highlight = false
    registry.call("tool.show_chart", INPUT)
    local w = chart_wins()[1]
    local layout = vim.fn.winlayout()
    assert.equals(w, layout[2][#layout[2]][2])
    local ns = vim.api.nvim_create_namespace("straps_chartifier")
    assert.equals(0, #vim.api.nvim_buf_get_extmarks(vim.api.nvim_win_get_buf(w), ns, 0, -1, {}))
    close_charts()
    chartifier.config.highlight = true
    registry.call("tool.show_chart", vim.tbl_extend("force", INPUT, { split = "vertical" }))
    w = chart_wins()[1]
    assert.equals("row", vim.fn.winlayout()[1])
    assert.equals(3, #vim.api.nvim_buf_get_extmarks(vim.api.nvim_win_get_buf(w), ns, 0, -1, {}))
    chartifier.config.split = "vertical"
  end)

  it("draws through fn.chartifier_render so a redefinition changes the output", function()
    registry.define({
      name = "fn.chartifier_render",
      kind = "fn",
      source = [[return function(spec) return { lines = { "custom " .. spec.kind }, spans = {} } end]],
    }, { scope = "global" })
    local result = registry.call("tool.show_chart", INPUT)
    assert.equals("show_chart: opened a bar chart — Hits (2 labels, 1 series, 1 lines)", result)
    local b = vim.api.nvim_win_get_buf(chart_wins()[1])
    assert.same({ "custom bar" }, vim.api.nvim_buf_get_lines(b, 0, -1, false))
    registry.define({
      name = "fn.chartifier_render",
      kind = "fn",
      source = [[return function(spec) error("renderer broke") end]],
    }, { scope = "global" })
    close_charts()
    assert.matches("^show_chart: .*renderer broke", registry.call("tool.show_chart", INPUT))
    assert.equals(0, #chart_wins())
    registry.define({
      name = "fn.chartifier_render",
      kind = "fn",
      source = [[return function(spec) return require("straps_chartifier.render").render(spec) end]],
    }, { scope = "global" })
  end)
end)

describe("tool schema", function()
  it("reaches the API tool list with the nested series schema intact", function()
    local tools = registry.call("fn.build_tools")
    local found
    for _, t in ipairs(tools) do
      if t.name == "show_chart" then found = t end
    end
    assert.is_not_nil(found)
    assert.same({ "kind", "series" }, found.input_schema.required)
    assert.equals("object", found.input_schema.properties.series.items.type)
    assert.same({ "values" }, found.input_schema.properties.series.items.required)
  end)
end)
