package.path = './lua/?.lua;./lua/?/init.lua;' .. package.path
local plugin = require('straps_chartifier')

describe('setup and health', function()
  it('rejects invalid options before changing config', function()
    local before = vim.deepcopy(plugin.config)
    for _, opts in ipairs({ false, { typo = true }, { height = 0 }, { max_width = 19 }, { split = 'tab' }, { highlight = 1 } }) do
      assert.is_false(pcall(plugin.setup, opts))
      assert.same(before, plugin.config)
    end
  end)
  it('reports missing core and registered tools without registration', function()
    local saved, health = package.loaded['straps.registry'], vim.health
    local reports = {}
    vim.health = setmetatable({}, { __index = function(_, key) return function(msg) reports[#reports + 1] = key .. ':' .. msg end end })
    package.loaded['straps.registry'] = nil
    local loader = package.preload['straps.registry']
    package.preload['straps.registry'] = function() error('missing') end
    require('straps_chartifier.health').check()
    assert.is_truthy(table.concat(reports):find('error:Straps is missing', 1, true))
    reports = {}
    package.loaded['straps.registry'] = { get = function() return {} end }
    require('straps_chartifier.health').check()
    assert.is_truthy(table.concat(reports):find('ok:show_chart registered', 1, true))
    package.loaded['straps.registry'], package.preload['straps.registry'], vim.health = saved, loader, health
  end)
end)
