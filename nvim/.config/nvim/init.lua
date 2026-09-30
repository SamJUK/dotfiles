-- ============================================================
-- NVIM Configuration — init.lua
-- Plugin manager: lazy.nvim
-- ============================================================

-- Load core options FIRST so <leader> is set before any plugin
require("config.options")
require("config.keymaps")
require("config.autocmds")

-- ── Bootstrap lazy.nvim ─────────────────────────────────────
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- ── Load all plugins from lua/plugins/ ───────────────────────
-- lazy.nvim auto-discovers every file inside lua/plugins/
require("lazy").setup("plugins", {
  change_detection = { notify = false },  -- don't nag about config changes
  checker = { enabled = true, notify = false },  -- silent update checks
  rocks = { enabled = false },  -- no plugin here needs luarocks
  performance = {
    rtp = {
      -- Disable built-in plugins we replace (netrw → neo-tree) or don't need
      disabled_plugins = {
        "gzip", "netrwPlugin", "tarPlugin", "tohtml", "tutor", "zipPlugin",
      },
    },
  },
  ui = {
    border = "rounded",
  },
})
