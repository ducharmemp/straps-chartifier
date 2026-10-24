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
    entries.register_tool(define)
    tool_registered = true
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
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  M.register()
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
  local parts = { ("show_chart: opened a %s chart"):format(spec.kind) }
  if spec.title then parts[#parts + 1] = (" — %s"):format(spec.title) end
  parts[#parts + 1] = (" (%d %s, %d series, %d lines)"):format(count, noun, #spec.series, #rendered.lines)
  return table.concat(parts)
end

function M.show_chart(input, ctx)
  local render = require("straps_chartifier.render")
  local spec, err = render.normalize(input, M.config)
  if not spec then
    return "show_chart: " .. err
  end
  local registry = require("straps.registry")
  local ok, rendered, render_err = pcall(registry.call, "fn.chartifier_render", spec)
  if not ok then
    return "show_chart: " .. tostring(rendered)
  end
  if type(rendered) ~= "table" then
    return "show_chart: " .. tostring(render_err or rendered)
  end
  local ok_open, open_err = pcall(require("straps_chartifier.view").open, rendered, {
    title = spec.title,
    split = spec.split or M.config.split,
    highlight = M.config.highlight,
  })
  if not ok_open then
    return "show_chart: " .. tostring(open_err)
  end
  if spec.kind == "histogram" then
    spec.labels = render.histogram_bins(spec.series[1].values, spec.bins, spec.unit)
  end
  return confirmation(spec, rendered)
end

function M.status()
  local layer_state
  if layer_registered then
    layer_state = "registered"
  elseif M.config.prompt_layer == false then
    layer_state = "disabled by config.prompt_layer"
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
