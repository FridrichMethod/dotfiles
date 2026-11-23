-- Settings on top of the lang.python extra.

-- Interpreters of this host's conda and micromamba environments: every prefix
-- registered in ~/.conda/environments.txt (named and -p environments, such as
-- a project's .conda), plus each root and its envs/* (the active root from
-- CONDA_EXE or MAMBA_ROOT_PREFIX, then the usual per-user roots). Read once when
-- the plugin loads; no directory tree is walked.
local function conda_pythons()
  local prefixes = {}
  local ok, lines = pcall(vim.fn.readfile, vim.fs.normalize("~/.conda/environments.txt"))
  if ok then
    vim.list_extend(prefixes, lines)
  end
  local roots = { "~/micromamba", "~/miniforge3", "~/miniconda3", "~/.conda" }
  if vim.env.MAMBA_ROOT_PREFIX then
    table.insert(roots, 1, vim.env.MAMBA_ROOT_PREFIX)
  end
  if vim.env.CONDA_EXE then
    table.insert(roots, 1, vim.fs.dirname(vim.fs.dirname(vim.env.CONDA_EXE)))
  end
  for _, root in ipairs(roots) do
    root = vim.fs.normalize(root)
    prefixes[#prefixes + 1] = root
    vim.list_extend(prefixes, vim.fn.glob(root .. "/envs/*", false, true))
  end
  local pythons, seen = {}, {}
  for _, prefix in ipairs(prefixes) do
    local python = vim.fs.normalize(prefix) .. "/bin/python"
    if not seen[python] and vim.fn.executable(python) == 1 then
      seen[python] = true
      pythons[#pythons + 1] = vim.fn.shellescape(python)
    end
  end
  return pythons
end

-- Project searches stop four levels below the root (<root>/sub/.venv/bin/python);
-- upstream follows symlinks through every data and checkpoint directory.
local function project_search(var)
  local excludes = "-E /proc -E .git/ -E site-packages/ -E node_modules/"
  return ("$FD '/bin/python$' '%s' --full-path --color never -HI -a -L --max-depth 4 %s"):format(var, excludes)
end

return {
  {
    "linux-cultist/venv-selector.nvim",
    -- Only adjust the plugin when the lang.python extra provides it.
    optional = true,
    opts = function(_, opts)
      opts.search = opts.search or {}
      local pythons = conda_pythons()
      if #pythons > 0 then
        opts.search.conda_envs = {
          command = "printf '%s\\n' " .. table.concat(pythons, " "),
          type = "anaconda",
        }
      end
      -- conda_envs covers these.
      opts.search.anaconda_envs = false
      opts.search.miniconda_envs = false
      opts.search.cwd = { command = project_search("$CWD") }
      opts.search.workspace = { command = project_search("$WORKSPACE_PATH") }
      opts.search.file = false
    end,
  },

  -- One Python type server: mason-lspconfig enables every installed server that
  -- is not disabled, and lang.python disables only pyright, basedpyright, ruff
  -- and ruff_lsp, so a leftover ty or pyrefly install would attach as well.
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      local lsp = vim.g.lazyvim_python_lsp or "pyright"
      for _, server in ipairs({ "ty", "pyrefly", "zuban", "pylsp", "jedi_language_server", "pylyzer", "pyre" }) do
        opts.servers[server] = opts.servers[server] or {}
        opts.servers[server].enabled = server == lsp
      end
    end,
  },

  -- Send lines, selections and "# %%" cells to a REPL in another tmux pane,
  -- such as IPython inside a Slurm allocation. The first send from a buffer
  -- asks for the pane (the previous pane is the default), so code never lands
  -- in an unconfirmed pane such as a coding agent's prompt.
  {
    "jpalardy/vim-slime",
    ft = { "python", "julia", "sh", "zsh" },
    init = function()
      vim.g.slime_target = "tmux"
      vim.g.slime_no_mappings = 1
      vim.g.slime_bracketed_paste = 1
      vim.g.slime_cell_delimiter = "^# %%"
      vim.g.slime_default_config = {
        socket_name = vim.env.TMUX and vim.split(vim.env.TMUX, ",")[1] or "default",
        target_pane = "{last}",
      }
    end,
    keys = {
      { "<localleader>c", "<Plug>SlimeSendCell", ft = { "python", "julia", "sh", "zsh" }, desc = "Send Cell to REPL" },
      { "<localleader>l", "<Plug>SlimeLineSend", ft = { "python", "julia", "sh", "zsh" }, desc = "Send Line to REPL" },
      {
        "<localleader>p",
        "<Plug>SlimeParagraphSend",
        ft = { "python", "julia", "sh", "zsh" },
        desc = "Send Paragraph to REPL",
      },
      {
        "<localleader>r",
        "<Plug>SlimeRegionSend",
        mode = "x",
        ft = { "python", "julia", "sh", "zsh" },
        desc = "Send Selection to REPL",
      },
      { "<localleader>v", "<Plug>SlimeConfig", ft = { "python", "julia", "sh", "zsh" }, desc = "Choose REPL Pane" },
    },
  },
}
