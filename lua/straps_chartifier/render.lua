local M = {}

M.KINDS = { "bar", "stacked", "diverging", "column", "stacked_column", "line", "scatter", "sparkline", "histogram" }

local KIND_SET = {}
for _, k in ipairs(M.KINDS) do KIND_SET[k] = true end

local LOWER = { "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" }
local LEFT = { "▏", "▎", "▍", "▌", "▋", "▊", "▉" }
local HALF_RIGHT = "▐"
local FULL = "█"
local BRAILLE_BITS = { { 0x01, 0x02, 0x04, 0x40 }, { 0x08, 0x10, 0x20, 0x80 } }
local SERIES_GROUPS = 8

local function utf8_char(cp)
  return string.char(0xE0 + math.floor(cp / 0x1000), 0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
end

local function dwidth(s)
  return vim.fn.strdisplaywidth(s)
end

local function pad_right(s, w)
  return s .. string.rep(" ", math.max(0, w - dwidth(s)))
end

local function pad_left(s, w)
  return string.rep(" ", math.max(0, w - dwidth(s))) .. s
end

local function round(x)
  return math.floor(x + 0.5)
end

function M.series_group(i)
  return "StrapsChartSeries" .. ((i - 1) % SERIES_GROUPS + 1)
end

function M.format_number(n)
  if n ~= n then return "nan" end
  if n == math.huge then return "inf" end
  if n == -math.huge then return "-inf" end
  if n == math.floor(n) and math.abs(n) < 1e15 then return string.format("%d", n) end
  local s = string.format("%.2f", n):gsub("0+$", ""):gsub("%.$", "")
  return s
end

function M.with_unit(n, unit)
  local s = M.format_number(n)
  if type(unit) ~= "string" or unit == "" then return s end
  if unit:match("^%a") then return s .. " " .. unit end
  return s .. unit
end

local function clamp_int(v, lo, hi, default)
  if type(v) ~= "number" or v ~= v then return default end
  return math.max(lo, math.min(hi, math.floor(v)))
end

local function extremes(series)
  local lo, hi = math.huge, -math.huge
  for _, s in ipairs(series) do
    for _, v in ipairs(s.values) do
      if v < lo then lo = v end
      if v > hi then hi = v end
    end
  end
  return lo, hi
end

local function row_totals(series, n)
  local totals = {}
  for i = 1, n do
    local sum = 0
    for _, ser in ipairs(series) do sum = sum + ser.values[i] end
    totals[i] = sum
  end
  return totals
end

local function sorted_order(values, dir)
  local order = {}
  for i = 1, #values do order[i] = i end
  table.sort(order, function(a, b)
    if values[a] == values[b] then return a < b end
    if dir == "asc" then return values[a] < values[b] end
    return values[a] > values[b]
  end)
  return order
end

local function apply_order(spec, order)
  local labels = {}
  for i, idx in ipairs(order) do labels[i] = spec.labels[idx] end
  spec.labels = labels
  for _, s in ipairs(spec.series) do
    local values = {}
    for i, idx in ipairs(order) do values[i] = s.values[idx] end
    s.values = values
  end
end

function M.normalize(input, config)
  config = config or {}
  local max_bars = config.max_bars or 60
  if type(input) ~= "table" then return nil, "input must be an object" end
  if type(input.kind) ~= "string" or not KIND_SET[input.kind] then
    return nil, ("kind must be one of %s (got %s)"):format(table.concat(M.KINDS, ", "), tostring(input.kind))
  end
  if type(input.series) ~= "table" or #input.series == 0 then
    return nil, "series must be a non-empty array of { name, values }"
  end
  local series = {}
  for i, s in ipairs(input.series) do
    if type(s) ~= "table" or type(s.values) ~= "table" then
      return nil, ("series[%d] must be an object with a values array"):format(i)
    end
    local values = {}
    for j = 1, #s.values do
      local v = s.values[j]
      if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
        return nil, ("series[%d].values[%d] is %s, expected a finite number"):format(i, j, vim.inspect(v))
      end
      values[j] = v
    end
    series[i] = { name = type(s.name) == "string" and s.name ~= "" and s.name or ("series " .. i), values = values }
  end
  local spec = {
    kind = input.kind,
    series = series,
    title = type(input.title) == "string" and input.title ~= "" and input.title or nil,
    unit = type(input.unit) == "string" and input.unit ~= "" and input.unit or nil,
    width = clamp_int(input.width, 20, config.max_width or 100, config.max_width or 100),
    height = clamp_int(input.height, 1, 40, config.height or 8),
    split = (input.split == "vertical" or input.split == "horizontal") and input.split or nil,
  }
  if input.split ~= nil and spec.split == nil then
    return nil, "split must be \"vertical\" or \"horizontal\""
  end
  if spec.kind == "histogram" then
    if #series > 1 then return nil, "histogram takes exactly one series of raw samples" end
    if #series[1].values == 0 then return nil, "histogram needs at least one sample" end
    spec.bins = clamp_int(input.bins, 1, max_bars, 10)
    return spec
  end
  if spec.kind == "scatter" then
    for i, s in ipairs(input.series) do
      if type(s.x) ~= "table" or #s.x ~= #series[i].values then
        return nil, ("series[%d] needs an x array as long as values (scatter plots x against values)"):format(i)
      end
      local xs = {}
      for j = 1, #s.x do
        local v = s.x[j]
        if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
          return nil, ("series[%d].x[%d] is %s, expected a finite number"):format(i, j, vim.inspect(v))
        end
        xs[j] = v
      end
      if #xs == 0 then return nil, ("series[%d] has no points"):format(i) end
      series[i].x = xs
    end
    spec.x_unit = type(input.x_unit) == "string" and input.x_unit ~= "" and input.x_unit or nil
    return spec
  end
  if type(input.labels) ~= "table" or #input.labels == 0 then
    return nil, "labels must be a non-empty array of strings, one per data point"
  end
  if #input.labels > max_bars then
    return nil, ("%d labels exceed max_bars=%d; aggregate the data or raise max_bars")
      :format(#input.labels, max_bars)
  end
  local labels = {}
  for i = 1, #input.labels do
    local l = input.labels[i]
    if type(l) ~= "string" then return nil, ("labels[%d] is %s, expected a string"):format(i, type(l)) end
    labels[i] = l
  end
  spec.labels = labels
  for i, s in ipairs(series) do
    if #s.values ~= #labels then
      return nil, ("series[%d] has %d values but there are %d labels"):format(i, #s.values, #labels)
    end
  end
  if spec.kind == "bar" or spec.kind == "stacked" or spec.kind == "column" or spec.kind == "stacked_column" then
    local lo = extremes(series)
    if lo < 0 then
      return nil, ("%s charts take values >= 0 (found %s); use diverging, line or sparkline for negative data")
        :format(spec.kind, M.format_number(lo))
    end
  end
  if spec.kind == "diverging" and #series > 1 then
    return nil, "diverging takes exactly one series; pass the delta per label"
  end
  if input.sort ~= nil and input.sort ~= "none" then
    if input.sort ~= "asc" and input.sort ~= "desc" then
      return nil, "sort must be \"none\", \"asc\" or \"desc\""
    end
    local stacked = spec.kind == "stacked" or spec.kind == "stacked_column"
    local key = stacked and row_totals(series, #labels) or series[1].values
    apply_order(spec, sorted_order(key, input.sort))
  end
  return spec
end

local function new_output()
  return { lines = {}, spans = {} }
end

local function add_line(out, line, spans)
  out.lines[#out.lines + 1] = line
  local row = #out.lines - 1
  for _, sp in ipairs(spans or {}) do
    out.spans[#out.spans + 1] = { row = row, col_start = sp[1], col_end = sp[2], group = sp[3] }
  end
end

local function add_legend(out, series)
  if #series < 2 then return end
  local parts, spans, col = {}, {}, 0
  for i, s in ipairs(series) do
    local piece = "■ " .. s.name
    if i > 1 then
      parts[#parts + 1] = "  "
      col = col + 2
    end
    spans[#spans + 1] = { col, col + #"■", M.series_group(i) }
    parts[#parts + 1] = piece
    col = col + #piece
  end
  add_line(out, table.concat(parts), spans)
end

local function add_title(out, spec)
  if spec.title then
    add_line(out, spec.title, { { 0, #spec.title, "StrapsChartTitle" } })
  end
end

local function hbar(value, max, barw)
  if max <= 0 or value <= 0 then return "", 0 end
  local eighths = round(value / max * barw * 8)
  if eighths == 0 then eighths = 1 end
  local full, rem = math.floor(eighths / 8), eighths % 8
  local bar = FULL:rep(full) .. (rem > 0 and LEFT[rem] or "")
  return bar, full + (rem > 0 and 1 or 0)
end

local function render_bar(out, spec)
  local series, labels, unit = spec.series, spec.labels, spec.unit
  local _, max = extremes(series)
  local rows = {}
  if #series == 1 then
    for i, label in ipairs(labels) do
      rows[#rows + 1] = { label = label, value = series[1].values[i], series = 1 }
    end
  else
    for i, label in ipairs(labels) do
      rows[#rows + 1] = { label = label }
      for s, ser in ipairs(series) do
        rows[#rows + 1] = { label = "  " .. ser.name, value = ser.values[i], series = s }
      end
    end
  end
  local labelw, valuew = 0, 0
  for _, r in ipairs(rows) do
    labelw = math.max(labelw, dwidth(r.label))
    if r.value then
      r.text = M.with_unit(r.value, unit)
      valuew = math.max(valuew, dwidth(r.text))
    end
  end
  local barw = math.max(1, spec.width - labelw - 3 - valuew)
  for _, r in ipairs(rows) do
    if not r.value then
      add_line(out, r.label)
    else
      local bar, cells = hbar(r.value, max, barw)
      local prefix = pad_right(r.label, labelw) .. " │"
      local line = prefix .. bar .. string.rep(" ", barw - cells) .. " " .. r.text
      local spans = {}
      if #bar > 0 then spans[1] = { #prefix, #prefix + #bar, M.series_group(r.series) } end
      add_line(out, line, spans)
    end
  end
  add_legend(out, series)
  return out
end

local function render_stacked(out, spec)
  local series, labels, unit = spec.series, spec.labels, spec.unit
  local totals = row_totals(series, #labels)
  local max, labelw, valuew = 0, 0, 0
  local texts = {}
  for i, label in ipairs(labels) do
    max = math.max(max, totals[i])
    labelw = math.max(labelw, dwidth(label))
    texts[i] = M.with_unit(totals[i], unit)
    valuew = math.max(valuew, dwidth(texts[i]))
  end
  local barw = math.max(1, spec.width - labelw - 3 - valuew)
  for i, label in ipairs(labels) do
    local prefix = pad_right(label, labelw) .. " │"
    local parts, spans, col, cells, cum = { prefix }, {}, #prefix, 0, 0
    local total_eighths = max > 0 and round(totals[i] / max * barw * 8) or 0
    local last = 0
    for s = #series, 1, -1 do
      if series[s].values[i] > 0 then
        last = s
        break
      end
    end
    for s, ser in ipairs(series) do
      local v = ser.values[i]
      if v > 0 then
        cum = cum + v
        local edge = s == last and math.floor(total_eighths / 8) or round(cum / max * barw)
        local full = math.max(0, edge - cells)
        local segment, seg_cells = FULL:rep(full), full
        if s == last then
          local rem = total_eighths % 8
          if rem == 0 and total_eighths == 0 then rem = 1 end
          if rem > 0 then
            segment, seg_cells = segment .. LEFT[rem], seg_cells + 1
          end
        end
        if seg_cells > 0 then
          spans[#spans + 1] = { col, col + #segment, M.series_group(s) }
          parts[#parts + 1] = segment
          col = col + #segment
          cells = cells + seg_cells
        end
      end
    end
    parts[#parts + 1] = string.rep(" ", math.max(0, barw - cells)) .. " " .. texts[i]
    add_line(out, table.concat(parts), spans)
  end
  add_legend(out, series)
  return out
end

local function render_diverging(out, spec)
  local values, labels, unit = spec.series[1].values, spec.labels, spec.unit
  local lo, hi = extremes(spec.series)
  local neg, pos = math.max(0, -lo), math.max(0, hi)
  local labelw, valuew = 0, 0
  local texts = {}
  for i, label in ipairs(labels) do
    labelw = math.max(labelw, dwidth(label))
    local v = values[i]
    texts[i] = (v > 0 and "+" or "") .. M.with_unit(v, unit)
    valuew = math.max(valuew, dwidth(texts[i]))
  end
  local barw = math.max(2, spec.width - labelw - 3 - valuew)
  local span_total = neg + pos
  local leftw = span_total > 0 and round(neg / span_total * barw) or 0
  if neg > 0 and leftw == 0 then leftw = 1 end
  if pos > 0 and leftw == barw then leftw = barw - 1 end
  local rightw = barw - leftw
  for i, label in ipairs(labels) do
    local v = values[i]
    local prefix = pad_right(label, labelw) .. " "
    local left, right, spans = "", "", {}
    local lcells, rcells = 0, 0
    if v < 0 and leftw > 0 then
      local eighths = round(-v / neg * leftw * 8)
      if eighths == 0 then eighths = 1 end
      local full, rem = math.floor(eighths / 8), eighths % 8
      left = (rem > 0 and HALF_RIGHT or "") .. FULL:rep(full)
      lcells = full + (rem > 0 and 1 or 0)
    elseif v > 0 and rightw > 0 then
      local eighths = round(v / pos * rightw * 8)
      if eighths == 0 then eighths = 1 end
      local full, rem = math.floor(eighths / 8), eighths % 8
      right = FULL:rep(full) .. (rem > 0 and LEFT[rem] or "")
      rcells = full + (rem > 0 and 1 or 0)
    end
    local lpad = string.rep(" ", leftw - lcells)
    local line_left = prefix .. lpad
    if #left > 0 then spans[#spans + 1] = { #line_left, #line_left + #left, "StrapsChartNegative" } end
    local axis_at = #line_left + #left
    local line = line_left .. left .. "│" .. right .. string.rep(" ", rightw - rcells) .. " " .. texts[i]
    spans[#spans + 1] = { axis_at, axis_at + #"│", "StrapsChartAxis" }
    if #right > 0 then spans[#spans + 1] = { axis_at + #"│", axis_at + #"│" + #right, "StrapsChartPositive" } end
    add_line(out, line, spans)
  end
  return out
end

local function column_cell(eighths, k)
  if eighths >= (k + 1) * 8 then return FULL end
  if eighths > k * 8 then return LOWER[eighths - k * 8] end
  return nil
end

local function label_row(out, gutter, positions, width_cells, labels)
  local segments, cursor = {}, 0
  for i, label in ipairs(labels) do
    local x, lw = positions[i], dwidth(label)
    if x + lw > width_cells then x = width_cells - lw end
    if x >= cursor then
      segments[#segments + 1] = string.rep(" ", x - cursor) .. label
      cursor = x + lw
    end
  end
  if #segments > 0 then
    add_line(out, string.rep(" ", gutter + 1) .. table.concat(segments))
  end
end

local function stacked_cell(bounds, k)
  local top = bounds[#bounds].hi
  if top <= k * 8 then return nil, nil end
  local cell = top >= (k + 1) * 8 and FULL or LOWER[top - k * 8]
  local mid = (k * 8 + math.min(top, (k + 1) * 8)) / 2
  for s = 1, #bounds do
    local b = bounds[s]
    if b.hi > b.lo and mid <= b.hi then return cell, s end
  end
  return cell, #bounds
end

local function render_column(out, spec)
  local series, labels, unit, height = spec.series, spec.labels, spec.unit, spec.height
  local stacked = spec.kind == "stacked_column"
  local nseries, nlabels = #series, #labels
  local max
  local totals
  if stacked then
    totals = row_totals(series, nlabels)
    max = 0
    for _, t in ipairs(totals) do max = math.max(max, t) end
  else
    local _
    _, max = extremes(series)
  end
  local top = M.with_unit(max, unit)
  local gutter = math.max(dwidth(top), 1)
  local avail = spec.width - gutter - 1
  local maxlabel = 0
  for _, l in ipairs(labels) do maxlabel = math.max(maxlabel, dwidth(l)) end
  local per_label = stacked and 1 or nseries
  local cw = per_label == 1 and math.max(2, math.min(7, maxlabel)) or 1
  while (per_label * cw + 1) * nlabels > avail and cw > 1 do cw = cw - 1 end
  local gw = per_label * cw + 1
  if gw * nlabels > avail then
    return nil, ("%d labels x %d series do not fit in width %d; raise width or reduce the data")
      :format(nlabels, nseries, spec.width)
  end
  local eighths, bounds = {}, {}
  if stacked then
    for i = 1, nlabels do
      bounds[i] = {}
      local cum = 0
      local total_e = max > 0 and round(totals[i] / max * height * 8) or 0
      if totals[i] > 0 and total_e == 0 then total_e = 1 end
      local last = 0
      for s = nseries, 1, -1 do
        if series[s].values[i] > 0 then
          last = s
          break
        end
      end
      local prev = 0
      for s, ser in ipairs(series) do
        local v = ser.values[i]
        local hi_e = prev
        if v > 0 then
          cum = cum + v
          hi_e = s == last and total_e or round(cum / max * height * 8)
        end
        bounds[i][s] = { lo = prev, hi = hi_e }
        prev = hi_e
      end
    end
  else
    for s, ser in ipairs(series) do
      eighths[s] = {}
      for i, v in ipairs(ser.values) do
        local e = max > 0 and round(v / max * height * 8) or 0
        if v > 0 and e == 0 then e = 1 end
        eighths[s][i] = e
      end
    end
  end
  for k = height - 1, 0, -1 do
    local gutter_text = k == height - 1 and top or (k == 0 and "0" or "")
    local prefix = pad_left(gutter_text, gutter) .. "│"
    local parts, spans, col = { prefix }, {}, #prefix
    for i = 1, nlabels do
      if stacked then
        local cell, owner = stacked_cell(bounds[i], k)
        local text = (cell or " "):rep(cw)
        if cell then spans[#spans + 1] = { col, col + #text, M.series_group(owner) } end
        parts[#parts + 1] = text
        col = col + #text
      else
        for s = 1, nseries do
          local cell = column_cell(eighths[s][i], k)
          local text = (cell or " "):rep(cw)
          if cell then spans[#spans + 1] = { col, col + #text, M.series_group(s) } end
          parts[#parts + 1] = text
          col = col + #text
        end
      end
      parts[#parts + 1] = " "
      col = col + 1
    end
    add_line(out, table.concat(parts), spans)
  end
  local axis = string.rep(" ", gutter) .. "└" .. string.rep("─", gw * nlabels)
  add_line(out, axis, { { gutter, #axis, "StrapsChartAxis" } })
  local fits = true
  for _, l in ipairs(labels) do
    if dwidth(l) > gw - 1 then fits = false end
  end
  local positions = {}
  for i = 1, nlabels do positions[i] = (i - 1) * gw end
  if fits then
    label_row(out, gutter, positions, gw * nlabels, labels)
  else
    local numbers = {}
    for i = 1, nlabels do numbers[i] = tostring(i) end
    label_row(out, gutter, positions, gw * nlabels, numbers)
    local numw = #tostring(nlabels)
    for i, l in ipairs(labels) do
      add_line(out, pad_left(tostring(i), numw) .. "  " .. l)
    end
  end
  add_legend(out, series)
  return out
end

local function plot_line(grid, x0, y0, x1, y1, owner)
  local dx, dy = math.abs(x1 - x0), -math.abs(y1 - y0)
  local sx, sy = x0 < x1 and 1 or -1, y0 < y1 and 1 or -1
  local err = dx + dy
  while true do
    grid[y0][x0] = owner
    if x0 == x1 and y0 == y1 then break end
    local e2 = 2 * err
    if e2 >= dy then
      err = err + dy
      x0 = x0 + sx
    end
    if e2 <= dx then
      err = err + dx
      y0 = y0 + sy
    end
  end
end

local function y_range(lo, hi)
  if lo == hi then return lo - 1, hi + 1 end
  return lo, hi
end

local function braille_grid(W, height)
  local grid = {}
  for y = 0, height * 4 - 1 do grid[y] = {} end
  return grid
end

local function emit_braille(out, grid, W, height, gutter, top, bottom)
  for r = 0, height - 1 do
    local gutter_text = r == 0 and top or (r == height - 1 and bottom or "")
    local prefix = pad_left(gutter_text, gutter) .. "│"
    local parts, spans, col = { prefix }, {}, #prefix
    local open
    for c = 0, W - 1 do
      local bits, owner = 0, nil
      for dx = 0, 1 do
        for dy = 0, 3 do
          local s = grid[r * 4 + dy][c * 2 + dx]
          if s then
            bits = bits + BRAILLE_BITS[dx + 1][dy + 1]
            owner = s
          end
        end
      end
      local text = bits > 0 and utf8_char(0x2800 + bits) or " "
      if owner then
        if open and open.owner == owner then
          open.col_end = col + #text
        else
          open = { col, col + #text, owner = owner, col_end = col + #text }
          spans[#spans + 1] = open
        end
      else
        open = nil
      end
      parts[#parts + 1] = text
      col = col + #text
    end
    for _, sp in ipairs(spans) do
      sp[2] = sp.col_end
      sp[3] = M.series_group(sp.owner)
    end
    add_line(out, table.concat(parts), spans)
  end
  local axis = string.rep(" ", gutter) .. "└" .. string.rep("─", W)
  add_line(out, axis, { { gutter, #axis, "StrapsChartAxis" } })
end

local function render_line(out, spec)
  local series, labels, unit, height = spec.series, spec.labels, spec.unit, spec.height
  local n = #labels
  local lo, hi = y_range(extremes(series))
  local top, bottom = M.with_unit(hi, unit), M.with_unit(lo, unit)
  local gutter = math.max(dwidth(top), dwidth(bottom))
  local W = math.max(2, spec.width - gutter - 1)
  local dots_w, dots_h = W * 2, height * 4
  local grid = braille_grid(W, height)
  local cells = {}
  for s, ser in ipairs(series) do
    local px, py
    for i, v in ipairs(ser.values) do
      local x = n == 1 and 0 or round((i - 1) / (n - 1) * (dots_w - 1))
      local y = round((hi - v) / (hi - lo) * (dots_h - 1))
      if px then
        plot_line(grid, px, py, x, y, s)
      else
        grid[y][x] = s
      end
      px, py = x, y
      if s == 1 then cells[i] = math.floor(x / 2) end
    end
  end
  emit_braille(out, grid, W, height, gutter, top, bottom)
  label_row(out, gutter, cells, W, labels)
  add_legend(out, series)
  return out
end

local function x_extremes(series)
  local lo, hi = math.huge, -math.huge
  for _, s in ipairs(series) do
    for _, v in ipairs(s.x) do
      if v < lo then lo = v end
      if v > hi then hi = v end
    end
  end
  return lo, hi
end

local function render_scatter(out, spec)
  local series, unit, height = spec.series, spec.unit, spec.height
  local lo, hi = y_range(extremes(series))
  local xlo, xhi = y_range(x_extremes(series))
  local top, bottom = M.with_unit(hi, unit), M.with_unit(lo, unit)
  local gutter = math.max(dwidth(top), dwidth(bottom))
  local W = math.max(2, spec.width - gutter - 1)
  local dots_w, dots_h = W * 2, height * 4
  local grid = braille_grid(W, height)
  for s, ser in ipairs(series) do
    for i, v in ipairs(ser.values) do
      local x = math.min(dots_w - 2, round((ser.x[i] - xlo) / (xhi - xlo) * (dots_w - 1)))
      local y = math.min(dots_h - 2, round((hi - v) / (hi - lo) * (dots_h - 1)))
      for dx = 0, 1 do
        for dy = 0, 1 do grid[y + dy][x + dx] = s end
      end
    end
  end
  emit_braille(out, grid, W, height, gutter, top, bottom)
  local left, right = M.with_unit(xlo, spec.x_unit), M.with_unit(xhi, spec.x_unit)
  local gap = W - dwidth(left) - dwidth(right)
  if gap >= 1 then
    add_line(out, string.rep(" ", gutter + 1) .. left .. string.rep(" ", gap) .. right)
  else
    add_line(out, string.rep(" ", gutter + 1) .. left .. ".." .. right)
  end
  add_legend(out, series)
  return out
end

local function render_sparkline(out, spec)
  local series, unit = spec.series, spec.unit
  local namew = 0
  for _, s in ipairs(series) do namew = math.max(namew, dwidth(s.name)) end
  for i, s in ipairs(series) do
    local lo, hi = extremes({ s })
    local chars = {}
    for j, v in ipairs(s.values) do
      local level = lo == hi and 4 or round((v - lo) / (hi - lo) * 7) + 1
      chars[j] = LOWER[level]
    end
    local spark = table.concat(chars)
    local prefix = pad_right(s.name, namew) .. " "
    local line = prefix .. spark .. " " .. M.with_unit(lo, unit) .. ".." .. M.with_unit(hi, unit)
    add_line(out, line, { { #prefix, #prefix + #spark, M.series_group(i) } })
  end
  return out
end

function M.histogram_bins(values, bins, unit)
  local lo, hi = extremes({ { values = values } })
  if lo == hi then
    return { M.with_unit(lo, unit) }, { #values }
  end
  local counts, labels = {}, {}
  local binw = (hi - lo) / bins
  for b = 1, bins do
    counts[b] = 0
    labels[b] = M.with_unit(lo + (b - 1) * binw, unit) .. ".." .. M.with_unit(lo + b * binw, unit)
  end
  for _, v in ipairs(values) do
    local b = math.min(bins, math.floor((v - lo) / binw) + 1)
    counts[b] = counts[b] + 1
  end
  return labels, counts
end

local function render_histogram(out, spec)
  local labels, counts = M.histogram_bins(spec.series[1].values, spec.bins, spec.unit)
  return render_bar(out, {
    labels = labels,
    series = { { name = "count", values = counts } },
    width = spec.width,
  })
end

local RENDERERS = {
  bar = render_bar,
  stacked = render_stacked,
  diverging = render_diverging,
  column = render_column,
  stacked_column = render_column,
  line = render_line,
  scatter = render_scatter,
  sparkline = render_sparkline,
  histogram = render_histogram,
}

function M.render(spec)
  local out = new_output()
  add_title(out, spec)
  return RENDERERS[spec.kind](out, spec)
end

return M
