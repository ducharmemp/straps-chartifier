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
    assert.equals("agent_tool", registry.call("fn.capability", "show_chart_missing", INPUT))
  end)
end)

describe("tool.show_chart", function()
  after_each(close_charts)

  it("opens a chart split and reports kind, title, counts and lines", function()
    local before = #chart_wins()
    local result = registry.call("tool.show_chart", INPUT)
    assert.equals("opened a bar chart — Hits (2 labels, 1 series, 3 lines)", result)
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
    assert.equals("opened a histogram chart (3 bins, 1 series, 3 lines)", result)
  end)

  it("reports scatter points across series", function()
    local result = registry.call("tool.show_chart", { kind = "scatter", height = 2,
      series = { { x = { 1, 2 }, values = { 1, 2 } }, { x = { 3 }, values = { 3 } } } })
    assert.equals("opened a scatter chart (3 points, 2 series, 5 lines)", result)
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
    assert.equals("opened a bar chart — Hits (2 labels, 1 series, 1 lines)", result)
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

describe("chart window", function()
  after_each(close_charts)

  it("defaults width to the chart window's text width when it is narrower than max_width", function()
    local result = registry.call("tool.show_chart", { kind = "bar", labels = { "a", "b" },
      series = { { values = { 3, 1 } } } })
    assert.is_nil(result:find("clamped", 1, true))
    local w = chart_wins()[1]
    local info = vim.fn.getwininfo(w)[1]
    local textw = info.width - info.textoff
    assert.is_true(textw < chartifier.config.max_width)
    local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(w), 0, -1, false)
    assert.equals(textw, vim.fn.strdisplaywidth(lines[1]))
  end)

  it("appends clamp notes to the result", function()
    local result = registry.call("tool.show_chart", vim.tbl_extend("force", INPUT, { width = 500, height = 0 }))
    assert.matches("; width clamped to 100; height clamped to 1$", result)
    result = registry.call("tool.show_chart", vim.tbl_extend("force", INPUT, { width = 30, height = 4 }))
    assert.is_nil(result:find("clamped", 1, true))
  end)

  it("reuses the window already showing a chart", function()
    registry.call("tool.show_chart", INPUT)
    local first = chart_wins()[1]
    local first_buf = vim.api.nvim_win_get_buf(first)
    local wins = #vim.api.nvim_list_wins()
    registry.call("tool.show_chart", vim.tbl_extend("force", INPUT, { title = "Second" }))
    assert.same({ first }, chart_wins())
    assert.equals(wins, #vim.api.nvim_list_wins())
    assert.equals("Second", vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(first), 0, 1, false)[1])
    assert.is_false(vim.api.nvim_buf_is_valid(first_buf))
  end)

  it("escapes % in the winbar title", function()
    registry.call("tool.show_chart", vim.tbl_extend("force", INPUT, { title = "50% done" }))
    assert.equals("50%% done", vim.wo[chart_wins()[1]].winbar)
  end)

  it("reports a buffer name collision instead of opening an unnamed chart", function()
    local blocker = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(blocker, "straps://chart/Taken")
    local result = registry.call("tool.show_chart", vim.tbl_extend("force", INPUT, { title = "Taken" }))
    assert.matches("^show_chart: cannot name the chart buffer straps://chart/Taken", result)
    assert.equals(0, #chart_wins())
    vim.api.nvim_buf_delete(blocker, { force = true })
  end)
end)

describe("status and setup", function()
  it("reports the layer disabled when prompt_layer is false even after registration", function()
    assert.equals("registered", chartifier.status().prompt_layer)
    chartifier.config.prompt_layer = false
    assert.equals("disabled by config.prompt_layer", chartifier.status().prompt_layer)
    chartifier.config.prompt_layer = true
  end)

  it("puts the configured defaults into the width and height descriptions", function()
    local props = registry.get("tool.show_chart").input_schema.properties
    assert.matches("at most 100%)", props.width.description)
    assert.matches("%(default 8%)", props.height.description)
    chartifier.setup({ max_width = 90, height = 12 })
    props = registry.get("tool.show_chart").input_schema.properties
    assert.matches("20 to 90 ", props.width.description)
    assert.matches("%(default 12%)", props.height.description)
    chartifier.setup({ max_width = 100, height = 8 })
  end)

  it("names exactly the kinds whose output depends on height in the height description", function()
    local render = require("straps_chartifier.render")
    local schema = registry.get("tool.show_chart").input_schema.properties
    local function lines_for(kind, height)
      local input = { kind = kind, labels = { "a", "b" }, series = { { values = { 1, 2 } } }, height = height }
      if kind == "histogram" then input.labels = nil end
      if kind == "scatter" then input.labels, input.series = nil, { { x = { 1, 2 }, values = { 1, 2 } } } end
      return #render.render(assert(render.normalize(input, chartifier.config))).lines
    end
    local uses, described = {}, {}
    for _, kind in ipairs(schema.kind.enum) do
      if lines_for(kind, 2) ~= lines_for(kind, 5) then uses[#uses + 1] = kind end
      if schema.height.description:find("[ ,]" .. kind .. "[ ,]") then described[#described + 1] = kind end
    end
    assert.same({ "column", "stacked_column", "line", "scatter" }, uses)
    assert.same(uses, described)
    local readme = table.concat(vim.fn.readfile(H.root .. "/README.md"), "\n")
    local row = readme:match("\n| `height` |[^\n]*")
    for _, kind in ipairs(schema.kind.enum) do
      assert.equals(vim.tbl_contains(uses, kind), row:find("`" .. kind .. "`", 1, true) ~= nil, kind)
    end
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
