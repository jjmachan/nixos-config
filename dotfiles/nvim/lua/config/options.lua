-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
local opt = vim.opt

opt.wrap = true -- Ennable line wrap

-- Over ssh/mosh: copy with OSC 52 (herdr → mosh → Ghostty puts it on the Mac
-- clipboard), and make plain `y` do it. LazyVim turns the system clipboard off
-- under ssh. Paste reads nvim's own register: mosh can't relay clipboard reads
-- back, so OSC 52 paste would hang. Paste from the Mac with Cmd+V instead.
if vim.env.SSH_CONNECTION then
  local osc52 = require("vim.ui.clipboard.osc52")
  local function paste()
    return { vim.fn.split(vim.fn.getreg(""), "\n"), vim.fn.getregtype("") }
  end
  vim.g.clipboard = {
    name = "OSC 52",
    copy = { ["+"] = osc52.copy("+"), ["*"] = osc52.copy("*") },
    paste = { ["+"] = paste, ["*"] = paste },
  }
end
opt.clipboard = "unnamedplus"
