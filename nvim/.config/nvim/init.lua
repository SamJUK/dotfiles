-- ============================================================
-- NVIM Configuration — init.lua
-- Plugin manager: lazy.nvim
-- ============================================================

-- Suppress lspconfig's per-server deprecation (it still works; native migration in roadmap)
-- vim.deprecate is what lspconfig calls on each require('lspconfig').servername access
local _deprecate = vim.deprecate
vim.deprecate = function(name, alt, ver, plugin, ...)
  if plugin == "nvim-lspconfig" then return end
  _deprecate(name, alt, ver, plugin, ...)
end

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
  performance = {
    rtp = {
      -- Disable built-in plugins we replace or don't need
      disabled_plugins = {
        "gzip", "matchit", "matchparen", "netrwPlugin",
        "tarPlugin", "tohtml", "tutor", "zipPlugin",
      },
    },
  },
  ui = {
    border = "rounded",
  },
})
