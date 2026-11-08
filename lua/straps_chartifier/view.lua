local M = {}

M.NAMESPACE = "straps_chartifier"
M.FILETYPE = "strapschart"

local SERIES_COLORS = {
  { fg = "#5fafff", ctermfg = 75 }, { fg = "#ffaf5f", ctermfg = 215 },
  { fg = "#5fd75f", ctermfg = 77 }, { fg = "#ff5f87", ctermfg = 204 },
  { fg = "#af87ff", ctermfg = 141 }, { fg = "#5fd7d7", ctermfg = 80 },
  { fg = "#d7af00", ctermfg = 178 }, { fg = "#ff875f", ctermfg = 209 },
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

local function chart_win()
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == M.FILETYPE then
      return w
    end
  end
end

function M.window(opts)
  opts = opts or {}
  local win, created = chart_win(), false
  if not win then
    win = new_split_win(opts.split == "horizontal" and "botright split" or "botright vsplit")
    created = true
  end
  vim.wo[win].wrap = false
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].list = false
  return win, created
end

function M.text_width(win)
  local info = vim.fn.getwininfo(win)[1]
  return info.width - info.textoff
end

local function fill(win, rendered, opts)
  local b = vim.api.nvim_create_buf(false, true)
  local old = vim.api.nvim_win_get_buf(win)
  local old_name = vim.api.nvim_buf_get_name(old)
  local renamed = false
  local old_winbar = vim.wo[win].winbar
  local ok, err = pcall(function()
    vim.bo[b].buftype = "nofile"
    vim.bo[b].bufhidden = "wipe"
    vim.bo[b].swapfile = false
    vim.api.nvim_buf_set_lines(b, 0, -1, false, rendered.lines)
    vim.bo[b].modifiable = false
    vim.bo[b].filetype = M.FILETYPE
    if opts.highlight ~= false then
      local ns = vim.api.nvim_create_namespace(M.NAMESPACE)
      for _, sp in ipairs(rendered.spans) do
        vim.api.nvim_buf_set_extmark(b, ns, sp.row, sp.col_start, { end_col = sp.col_end, hl_group = sp.group })
      end
    end
    local name = "straps://chart/" .. (opts.title or ("chart-" .. os.time()))
    if old_name == name then
      vim.api.nvim_buf_set_name(old, "")
      renamed = true
    end
    local ok_name, name_err = pcall(vim.api.nvim_buf_set_name, b, name)
    if not ok_name then
      error(("cannot name the chart buffer %s: %s"):format(name, tostring(name_err)), 0)
    end
    vim.api.nvim_win_set_buf(win, b)
    vim.wo[win].winbar = opts.title and opts.title:gsub("%%", "%%%%") or ""
  end)
  if not ok then
    if vim.api.nvim_buf_is_valid(b) then pcall(vim.api.nvim_buf_delete, b, { force = true }) end
    if renamed and vim.api.nvim_buf_is_valid(old) then pcall(vim.api.nvim_buf_set_name, old, old_name) end
    if vim.api.nvim_win_is_valid(win) then vim.wo[win].winbar = old_winbar end
    error(err, 0)
  end
  return b
end

function M.fill(win, rendered, opts)
  M.define_highlights()
  return fill(win, rendered, opts or {})
end

function M.open(rendered, opts)
  opts = opts or {}
  local win, created = M.window(opts)
  local ok, b = pcall(M.fill, win, rendered, opts)
  if not ok then
    if created and vim.api.nvim_win_is_valid(win) then pcall(vim.api.nvim_win_close, win, true) end
    error(b, 0)
  end
  return b, win
end

return M
