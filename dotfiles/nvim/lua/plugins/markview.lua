return {
  "OXY2DEV/markview.nvim",
  -- Upstream is explicit: do not lazy load, the plugin lazy-loads itself.
  lazy = false,
  keys = {
    { "<leader>um", "<cmd>Markview toggle<cr>", desc = "Toggle Markdown Render" },
    { "<leader>uM", "<cmd>Markview splitToggle<cr>", desc = "Toggle Markdown Splitview" },
  },
  opts = {
    preview = {
      icon_provider = "mini", -- LazyVim already installs mini.icons
    },
  },
  config = function(_, opts)
    require("markview").setup(opts)
    -- Tables are the one thing markview only partially handles under wrap, so
    -- turn wrapping off in markdown buffers and scroll horizontally instead.
    vim.api.nvim_create_autocmd("FileType", {
      pattern = { "markdown", "quarto" },
      callback = function()
        vim.opt_local.wrap = false
        vim.opt_local.expandtab = true
      end,
    })
  end,
}
