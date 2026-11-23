-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

local aug = vim.api.nvim_create_augroup("RestoreCursorOnExit", { clear = true })
vim.api.nvim_create_autocmd("VimLeavePre", {
  group = aug,
  command = "set guicursor=a:ver25",
  desc = "Restore terminal cursor to a steady vertical bar",
})

-- Reload the current file when Claude Code, Codex or git changed it on disk
-- while Neovim kept focus. LazyVim checks only on FocusGained, TermClose and
-- TermLeave. Checking one buffer keeps this to a single stat on NFS or Lustre.
vim.api.nvim_create_autocmd({ "BufEnter", "CursorHold" }, {
  group = vim.api.nvim_create_augroup("user_checktime", { clear = true }),
  desc = "Reload the current file if it changed outside Neovim",
  callback = function(ev)
    if vim.bo[ev.buf].buftype == "" and vim.fn.getcmdwintype() == "" then
      vim.cmd("checktime " .. ev.buf)
    end
  end,
})

-- Over SSH LazyVim leaves 'clipboard' empty, so plain yanks stay inside Neovim.
-- Copy yanks (not deletes, not named registers) to "+", which tmux or OSC 52
-- forwards to the local terminal's clipboard. vim-slime builds every REPL send
-- from an unnamed yank, so yanks made inside its functions are skipped.
-- has("clipboard") keeps a session without a clipboard provider from printing
-- "No provider" on every yank.
if vim.env.SSH_CONNECTION then
  vim.api.nvim_create_autocmd("TextYankPost", {
    group = vim.api.nvim_create_augroup("user_ssh_yank", { clear = true }),
    desc = "Copy yanks to the local clipboard over SSH",
    callback = function()
      local event = vim.v.event
      if
        event.operator == "y"
        and event.regname == ""
        and not vim.fn.expand("<stack>"):find("slime#", 1, true)
        and vim.fn.has("clipboard") == 1
      then
        vim.fn.setreg("+", event.regcontents, event.regtype)
      end
    end,
  })
end

-- LaTeX gets the wrap and spell LazyVim gives markdown, typst and plaintex.
vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("user_tex_wrap_spell", { clear = true }),
  pattern = { "tex" },
  desc = "Wrap and spell-check LaTeX",
  callback = function()
    vim.opt_local.wrap = true
    vim.opt_local.spell = true
  end,
})

-- Shell scripts follow the shfmt -i 4 -ci style of lua/plugins/formatting.lua;
-- an .editorconfig still wins, because Neovim applies it after FileType.
vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("user_shell_indent", { clear = true }),
  pattern = { "sh", "bash", "zsh" },
  desc = "Indent shell scripts by 4",
  callback = function()
    vim.opt_local.shiftwidth = 4
    vim.opt_local.tabstop = 4
  end,
})

-- Saving leaves these files as written: their LSP servers and markdownlint-cli2
-- would otherwise rewrite them on every save. <leader>cf formats on demand, and
-- <leader>uF turns format-on-save back on for the current buffer.
vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("user_autoformat_scope", { clear = true }),
  pattern = { "json", "jsonc", "json5", "markdown", "markdown.mdx", "toml", "yaml" },
  desc = "Disable format-on-save for data and prose files",
  callback = function(ev)
    if vim.b[ev.buf].autoformat == nil then
      vim.b[ev.buf].autoformat = false
    end
  end,
})
