-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- Snacks animations, smooth scrolling above all, redraw many frames, which lags
-- over SSH. <leader>ua turns them back on for the session.
vim.g.snacks_animate = vim.env.SSH_CONNECTION == nil

-- Python type server for the lang.python extra, which reads this when its
-- module loads. ty and ruff are native binaries; pyright needs Node, which the
-- Marlowe login nodes deny.
vim.g.lazyvim_python_lsp = "ty"

-- American spelling (British forms are marked SpellLocal), no CJK false
-- positives, and the parts of camelCase words checked separately.
vim.opt.spelllang = { "en_us", "cjk" }
vim.opt.spelloptions:append("camel")

-- chezmoi source names (dot_, private_, executable_, ...) hide the target name
-- from filetype detection. Inside a chezmoi source tree, detect the filetype of
-- the target path instead. modify_ templates and *.tmpl keep their own rules.
local chezmoi_attrs = { "encrypted_", "private_", "readonly_", "empty_", "executable_", "create_", "exact_" }

local function chezmoi_target(path)
  local parts = {}
  for part in vim.gsplit(path, "/", { plain = true }) do
    local stripped = true
    while stripped do
      stripped = false
      for _, attr in ipairs(chezmoi_attrs) do
        if vim.startswith(part, attr) then
          part, stripped = part:sub(#attr + 1), true
        end
      end
    end
    parts[#parts + 1] = (part:gsub("^dot_", "."))
  end
  return table.concat(parts, "/")
end

vim.filetype.add({
  extension = {
    -- Protein Data Bank coordinates, which Neovim would map to Prolog.
    pdb = "pdb",
  },
  filename = {
    [".gitconfig_local"] = "gitconfig",
    [".gitignore_global"] = "gitignore",
  },
  pattern = {
    [".*/[^/]*dot_.*"] = {
      function(path, bufnr)
        if vim.startswith(vim.fs.basename(path), "modify_") or path:find("%.tmpl$") then
          return
        end
        if not vim.fs.root(path, { ".chezmoiroot", ".chezmoiignore", ".chezmoiversion" }) then
          return
        end
        local target = chezmoi_target(path)
        if target ~= path then
          -- A filename-only match passes bufnr -1, which must not reach the
          -- inner match: function patterns there would run without a pcall.
          return vim.filetype.match({ filename = target, buf = bufnr ~= -1 and bufnr or nil })
        end
      end,
      { priority = 10 },
    },
    -- chezmoi modify templates keep their target's extension but hold Go
    -- template code; jsonls or taplo formatting would break the template.
    ["modify_.+"] = function(_, bufnr)
      local ok, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, 0, 1, false)
      if ok and lines[1] and lines[1]:find("chezmoi:modify-template", 1, true) then
        return "gotmpl"
      end
    end,
    [".*/tmux/.+%.conf"] = "tmux",
    -- Codex exec-policy rules are Starlark.
    [".*/%.codex/rules/.+%.rules"] = "bzl",
  },
})
