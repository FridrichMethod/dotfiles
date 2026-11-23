-- Trims for the lang.markdown extra.
return {
  -- The browser preview needs a desktop browser on the same host, which SSH
  -- sessions lack; disabling it also skips its build-time download.
  { "iamcco/markdown-preview.nvim", enabled = false },
  -- Lint Markdown only in projects that configure markdownlint; its defaults
  -- (80-column MD013 and more) flag most hand-wrapped prose. markdownlint-cli2
  -- lints stdin with the configuration of its working directory only, so a
  -- child shell runs it from the directory holding the config found here;
  -- nvim-lint's own cwd option would :cd Neovim itself.
  {
    "mfussenegger/nvim-lint",
    optional = true,
    opts = {
      linters = {
        ["markdownlint-cli2"] = {
          condition = function(ctx)
            local config = vim.fs.find({
              ".markdownlint-cli2.jsonc",
              ".markdownlint-cli2.yaml",
              ".markdownlint-cli2.cjs",
              ".markdownlint-cli2.mjs",
              ".markdownlint.jsonc",
              ".markdownlint.json",
              ".markdownlint.yaml",
              ".markdownlint.yml",
              ".markdownlint.cjs",
              ".markdownlint.mjs",
            }, { path = ctx.dirname, upward = true })[1]
            if not config then
              return false
            end
            local linter = require("lint").linters["markdownlint-cli2"]
            linter.cmd = "sh"
            linter.args = { "-c", 'cd "$1" && exec markdownlint-cli2 -', "markdownlint-cli2", vim.fs.dirname(config) }
            return true
          end,
        },
      },
    },
  },
}
