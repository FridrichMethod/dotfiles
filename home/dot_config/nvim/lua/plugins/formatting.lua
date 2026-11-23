return {
  {
    "stevearc/conform.nvim",
    opts = {
      formatters = {
        -- Without an .editorconfig, conform passes shfmt -i <shiftwidth> and no
        -- -ci. Use the -i 4 -ci style of the pre-commit shfmt hook there, and
        -- pass no printer flags when an .editorconfig applies, because shfmt
        -- then reads it.
        shfmt = {
          args = function(_, ctx)
            local args = { "-filename", "$FILENAME" }
            if not vim.fs.find(".editorconfig", { path = ctx.dirname, upward = true })[1] then
              vim.list_extend(args, { "-i", "4", "-ci" })
            end
            return args
          end,
        },
      },
    },
  },
}
