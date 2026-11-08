local M = {}

M.config = {
  max_width = 100,
  height = 8,
  max_bars = 60,
  highlight = true,
  prompt_layer = true,
  split = "vertical",
}

local tool_registered = false
local layer_registered = false

local function straps_ready(registry)
  return registry.get("fn.system_prompt_layer.project") ~= nil
end

function M.register()
  local ok, registry = pcall(require, "straps.registry")
  if not ok then
    return false, "straps is not on the runtimepath"
  end
  local define = registry.define_default or registry.define
  local entries = require("straps_chartifier.entries")
  if not tool_registered then
    entries.register_tool(define, M.config)
    tool_registered = true
  else
    local current = registry.get("tool.show_chart")
    if current and current.source == entries.TOOL_SRC
      and not vim.deep_equal(current.input_schema, entries.tool_schema(M.config)) then
      entries.define_tool(function(spec) return registry.define(spec, { scope = "global" }) end, M.config)
    end
  end
  if not layer_registered then
    if not straps_ready(registry) then
      return false, "prompt layer not registered: straps setup() has not run"
    end
    entries.register_layer(define)
    layer_registered = true
  end
  return true
end

function M.setup(opts)
  assert(opts == nil or type(opts) == "table", "straps_chartifier: setup options must be a table")
  local config = vim.tbl_deep_extend("force", M.config, opts or {})
  for key, value in pairs(opts or {}) do
    assert(M.config[key] ~= nil, "straps_chartifier: unknown option " .. tostring(key))
    assert(type(value) == type(M.config[key]), "straps_chartifier: invalid type for " .. key)
  end
  for key, minimum in pairs({ max_width = 20, height = 1, max_bars = 1 }) do
    local value = config[key]
    assert(value == value and value < math.huge and value % 1 == 0 and value >= minimum,
      "straps_chartifier: " .. key .. " must be an integer >= " .. minimum)
  end
  assert(config.height <= 40, "straps_chartifier: height must be <= 40")
  assert(config.split == "vertical" or config.split == "horizontal", "straps_chartifier: invalid split")
  M.config = config
  local ok, why = M.register()
  if not ok then
    vim.notify("straps_chartifier: " .. why, vim.log.levels.WARN)
  end
  return M
end

local function count_of(spec)
  if spec.kind == "histogram" then
    return #spec.labels, "bins"
  end
  if spec.kind == "scatter" then
    local n = 0
    for _, s in ipairs(spec.series) do n = n + #s.values end
    return n, "points"
  end
  return #spec.labels, "labels"
end

local function confirmation(spec, rendered)
  local count, noun = count_of(spec)
  local parts = { ("opened a %s chart"):format(spec.kind) }
  if spec.title then parts[#parts + 1] = (" — %s"):format(spec.title) end
  parts[#parts + 1] = (" (%d %s, %d series, %d lines)"):format(count, noun, #spec.series, #rendered.lines)
  if spec.notes and #spec.notes > 0 then
    parts[#parts + 1] = "; " .. table.concat(spec.notes, "; ")
  end
  return table.concat(parts)
end

function M.show_chart(input, ctx)
  local render = require("straps_chartifier.render")
  local view = require("straps_chartifier.view")
  local spec, err = render.normalize(input, M.config)
  if not spec then
    return "show_chart: " .. err
  end
  local win, created = view.window({ split = spec.split or M.config.split })
  local function fail(msg)
    if created and vim.api.nvim_win_is_valid(win) then pcall(vim.api.nvim_win_close, win, true) end
    return "show_chart: " .. msg
  end
  if not spec.width_given then
    spec.width = math.max(20, math.min(spec.width, view.text_width(win)))
  end
  local registry = require("straps.registry")
  local ok, rendered, render_err = pcall(registry.call, "fn.chartifier_render", spec)
  if not ok then
    return fail(tostring(rendered))
  end
  if type(rendered) ~= "table" then
    return fail(tostring(render_err or rendered))
  end
  local ok_fill, fill_err = pcall(view.fill, win, rendered, { title = spec.title, highlight = M.config.highlight })
  if not ok_fill then
    return fail(tostring(fill_err))
  end
  if spec.kind == "histogram" then
    spec.labels = render.histogram_bins(spec.series[1].values, spec.bins, spec.unit)
  end
  return confirmation(spec, rendered)
end

function M.status()
  local layer_state
  if M.config.prompt_layer == false then
    layer_state = "disabled by config.prompt_layer"
  elseif layer_registered then
    layer_state = "registered"
  else
    layer_state = "not registered: straps setup() has not run"
  end
  return { tool = tool_registered, prompt_layer = layer_state, config = M.config }
end

M._reset = function()
  tool_registered = false
  layer_registered = false
end

return M
