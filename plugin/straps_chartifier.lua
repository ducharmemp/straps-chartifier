if vim.g.loaded_straps_chartifier then
  return
end
vim.g.loaded_straps_chartifier = true

local function register()
  require("straps_chartifier").register()
end

register()
local group = vim.api.nvim_create_augroup("straps_chartifier", { clear = true })
vim.api.nvim_create_autocmd("VimEnter", { group = group, once = true, callback = register })
