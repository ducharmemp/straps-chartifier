local here = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(here, ":p:h:h")
local straps_root = vim.env.STRAPS_ROOT
if not straps_root or straps_root == "" then
  for _, candidate in ipairs({ root .. "/.ref/straps", root .. "/../straps" }) do
    if vim.fn.isdirectory(candidate .. "/lua/straps") == 1 then
      straps_root = vim.fn.fnamemodify(candidate, ":p"):gsub("/$", "")
      break
    end
  end
end
assert(straps_root and vim.fn.isdirectory(straps_root .. "/lua/straps") == 1,
  "no straps checkout at " .. tostring(straps_root) .. " (set STRAPS_ROOT)")

vim.opt.rtp:prepend(straps_root)
vim.opt.rtp:prepend(root)
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;"
  .. straps_root .. "/lua/?.lua;" .. straps_root .. "/lua/?/init.lua;" .. package.path

return { root = root, straps_root = straps_root }
