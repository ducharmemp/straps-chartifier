-- Run: busted tests/prompt_spec.lua

dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/helpers.lua")

local registry = require("straps.registry")
local chartifier = require("straps_chartifier")
local prompt = require("straps_chartifier.prompt")

local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")
local f = assert(io.open(tmp .. "/AGENTS.md", "w"))
f:write("project-marker-text\n")
f:close()
local saved_home, saved_cwd = vim.env.HOME, vim.fn.getcwd()
vim.env.HOME = tmp
vim.fn.chdir(tmp)

teardown(function()
  vim.env.HOME = saved_home
  vim.fn.chdir(saved_cwd)
end)

local function section_order(text)
  local out = {}
  for header in text:gmatch("\n# ([^\n]+)") do out[#out + 1] = header end
  return out
end

describe("register before straps setup", function()
  it("defines the tool and skill but defers the prompt layer", function()
    local ok, why = chartifier.register()
    assert.is_false(ok)
    assert.equals("prompt layer not registered: straps setup() has not run", why)
    assert.is_not_nil(registry.get("tool.show_chart"))
    assert.is_not_nil(registry.get("skill.charting"))
    assert.is_nil(registry.get("fn.system_prompt_layer.chartifier"))
    assert.equals("not registered: straps setup() has not run", chartifier.status().prompt_layer)
  end)
end)

describe("register after straps setup", function()
  setup(function()
    local straps = require("straps").setup({})
    straps.config.session_dir = vim.fn.tempname()
  end)

  it("appends # Charts as the last section, after # Project instructions", function()
    assert.is_true(chartifier.register())
    assert.equals("registered", chartifier.status().prompt_layer)
    local text = registry.call("fn.system_prompt")
    local order = section_order(text)
    assert.equals("Charts", order[#order])
    local project_at, charts_at
    for i, h in ipairs(order) do
      if h == "Project instructions" then project_at = i end
      if h == "Charts" then charts_at = i end
    end
    assert.is_not_nil(project_at)
    assert.is_true(project_at < charts_at)
    assert.is_not_nil(text:find("project-marker-text", 1, true))
    assert.is_not_nil(text:find(prompt.LAYER, 1, true))
  end)

  it("lists skill.charting under # Skills", function()
    local text = registry.call("fn.system_prompt")
    local skills = text:match("\n# Skills\n(.-)\n# ")
    assert.is_not_nil(skills)
    assert.is_not_nil(skills:find("- skill.charting: " .. registry.get("skill.charting").doc, 1, true))
    assert.equals(prompt.SKILL, registry.call("skill.charting"))
  end)

  it("drops the section when config.prompt_layer is false", function()
    chartifier.config.prompt_layer = false
    local text = registry.call("fn.system_prompt")
    assert.is_nil(text:find("\n# Charts", 1, true))
    assert.equals("Project instructions", section_order(text)[#section_order(text)])
    chartifier.config.prompt_layer = true
    text = registry.call("fn.system_prompt")
    assert.is_not_nil(text:find("\n# Charts", 1, true))
  end)

  it("keeps the section under 25 lines and names every kind", function()
    local n = select(2, prompt.LAYER:gsub("\n", "\n")) + 1
    assert.is_true(n <= 25, "layer is " .. n .. " lines")
    for _, kind in ipairs(require("straps_chartifier.render").KINDS) do
      assert.is_not_nil(prompt.LAYER:find(kind, 1, true), kind)
      assert.is_not_nil(prompt.SKILL:find("- " .. kind .. ":", 1, true), kind)
    end
  end)
end)
