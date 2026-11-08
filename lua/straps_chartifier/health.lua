local M = {}

function M.check()
  vim.health.start("straps_chartifier")
  local ok, registry = pcall(require, "straps.registry")
  if not ok then
    vim.health.error("Straps is missing from runtimepath")
    return
  end
  local status = require("straps_chartifier").status()
  if registry.get("tool.show_chart") then vim.health.ok("show_chart registered")
  else vim.health.warn("show_chart is not registered; run setup() after Straps setup()") end
  vim.health.info("prompt layer: " .. status.prompt_layer)
end

return M
