-- Catppuccin Mocha, the theme of kitty, WezTerm, Windows Terminal, tmux and bat.
return {
  {
    "catppuccin/nvim",
    name = "catppuccin",
    opts = {
      -- Fixed, so tmux or SSH background detection never selects latte.
      flavour = "mocha",
      -- Terminal buffers (lazygit, <C-/>) use catppuccin's Mocha terminal colors.
      term_colors = true,
    },
  },
  {
    "LazyVim/LazyVim",
    -- Neovim 0.12 ships its own "catppuccin", a Vim port that ignores these
    -- opts; "catppuccin-nvim" is the plugin's name for itself.
    opts = { colorscheme = "catppuccin-nvim" },
  },
}
