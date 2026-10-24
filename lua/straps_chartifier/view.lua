local M = {}

M.NAMESPACE = "straps_chartifier"
M.FILETYPE = "strapschart"

local SERIES_COLORS = {
  { fg = "#5fafff" }, { fg = "#ffaf5f" }, { fg = "#5fd75f" }, { fg = "#ff5f87" },
  { fg = "#af87ff" }, { fg = "#5fd7d7" }, { fg = "#d7af00" }, { fg = "#ff875f" },
}

function M.define_highlights()
  for i, color in ipairs(SERIES_COLORS) do
    vim.api.nvim_set_hl(0, "StrapsChartSeries" .. i, vim.tbl_extend("force", { default = true }, color))
  end
  vim.api.nvim_set_hl(0, "StrapsChartAxis", { default = true, link = "Comment" })
  vim.api.nvim_set_hl(0, "StrapsChartPositive", { default = true, link = "DiffAdd" })
  vim.api.nvim_set_hl(0, "StrapsChartNegative", { default = true, link = "DiffDelete" })
  vim.api.nvim_set_hl(0, "StrapsChartTitle", { default = true, link = "Title" })
end

local function new_split_win(cmd)
  local cur = vim.api.nvim_get_current_win()
  vim.cmd(cmd)
  local w = vim.api.nvim_get_current_win()
  pcall(vim.api.nvim_set_current_win, cur)
  return w
end

local function scratch_buf(lines, name)
  local b = vim.api.nvim_create_buf(false, true)
  vim.bo[b].buftype = "nofile"
  vim.bo[b].bufhidden = "wipe"
  vim.bo[b].swapfile = false
  vim.api.nvim_buf_set_lines(b, 0, -1, false, lines)
  vim.bo[b].modifiable = false
  vim.bo[b].filetype = M.FILETYPE
  pcall(vim.api.nvim_buf_set_name, b, name)
  return b
end

function M.open(rendered, opts)
  opts = opts or {}
  M.define_highlights()
  local name = "straps://chart/" .. (opts.title or ("chart-" .. os.time()))
  local b = scratch_buf(rendered.lines, name)
  if opts.highlight ~= false then
    local ns = vim.api.nvim_create_namespace(M.NAMESPACE)
    for _, sp in ipairs(rendered.spans) do
      vim.api.nvim_buf_set_extmark(b, ns, sp.row, sp.col_start, { end_col = sp.col_end, hl_group = sp.group })
    end
  end
  local cmd = opts.split == "horizontal" and "botright split" or "botright vsplit"
  local win = new_split_win(cmd)
  vim.api.nvim_win_set_buf(win, b)
  vim.wo[win].wrap = false
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].list = false
  if opts.title then pcall(function() vim.wo[win].winbar = opts.title end) end
  return b, win
end

return M
