-- Sherlock and Marlowe only (home/.chezmoiignore): their site rules keep compile
-- work inside Slurm allocations, and Marlowe's login nodes refuse to run node.
-- slurmd sets SLURMD_NODENAME for job steps on a compute node; a salloc shell
-- left on the login node does not have it.
local on_compute_node = vim.env.SLURMD_NODENAME ~= nil

local specs = {
  -- The login env's tools win over mason's prebuilt binaries, which can need a
  -- newer glibc than the cluster has (mason's tree-sitter-cli is built against
  -- glibc 2.39).
  { "mason-org/mason.nvim", opts = { PATH = "append" } },
}

-- Build parsers only on a compute node, and only with a tree-sitter CLI that
-- is not mason's. Otherwise keep the parsers already built and add or rebuild
-- them with :TSInstall or :TSUpdate inside an allocation.
local cli = vim.fn.exepath("tree-sitter")
local have_cli = cli ~= "" and not cli:find("/mason/bin/", 1, true)
if not (on_compute_node and have_cli) then
  specs[#specs + 1] = {
    "nvim-treesitter/nvim-treesitter",
    build = false,
    opts = function(_, opts)
      opts.ensure_installed = {}
    end,
  }
end

-- Login nodes that refuse to run node (Marlowe's AppArmor block-node profile):
-- skip the node-based servers, tools and linters instead of failing at every
-- start. pcall: an exec denial makes vim.system() raise instead of returning,
-- and wait() returns nil for a process that outlives the timeout.
local function node_runs()
  if on_compute_node then
    return true
  end
  if vim.fn.executable("node") ~= 1 then
    return false
  end
  local ok, result = pcall(function()
    return vim.system({ "node", "--version" }, { stdout = false, stderr = false }):wait(3000)
  end)
  return ok and result ~= nil and result.code == 0
end

if not node_runs() then
  local npm_servers = { "bashls", "pyright", "jsonls", "yamlls" }
  local npm_tools = { "markdownlint-cli2", "markdown-toc" }
  local function keep(tool)
    return not vim.tbl_contains(npm_tools, tool)
  end
  specs[#specs + 1] = {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      for _, server in ipairs(npm_servers) do
        opts.servers[server] = opts.servers[server] or {}
        opts.servers[server].enabled = false
      end
    end,
  }
  specs[#specs + 1] = {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      opts.ensure_installed = vim.tbl_filter(keep, opts.ensure_installed or {})
    end,
  }
  specs[#specs + 1] = {
    "mfussenegger/nvim-lint",
    optional = true,
    opts = function(_, opts)
      for ft, linters in pairs(opts.linters_by_ft or {}) do
        opts.linters_by_ft[ft] = vim.tbl_filter(keep, linters)
      end
    end,
  }
end

return specs
