-- ============================================================
-- GitHub Copilot
-- Uses copilot.lua (faster Lua port) + copilot-cmp (suggestions
-- appear in the completion menu alongside LSP completions)
-- ============================================================
-- FIRST RUN: after installation run  :Copilot auth
--            and follow the browser login prompt
-- ============================================================

return {
  -- ── Core Copilot plugin ────────────────────────────────────
  {
    "zbirenbaum/copilot.lua",
    cmd  = "Copilot",
    event = "InsertEnter",
    config = function()
      require("copilot").setup({
        -- Disable inline ghost text — copilot-cmp shows suggestions
        -- in the completion menu instead (more predictable UX)
        suggestion = { enabled = false },
        panel      = { enabled = false },

        -- Copilot won't activate in these filetypes
        filetypes = {
          markdown   = true,   -- enable in markdown (useful for docs)
          gitcommit  = false,
          help       = false,
          ["."]      = false,  -- disabled by default for unlisted types
        },

        -- Use the latest stable Copilot server
        copilot_node_command = "node",

        server_opts_overrides = {
          trace = "verbose",
          settings = {
            advanced = {
              listCount         = 10,
              inlineSuggestCount = 3,
            },
          },
        },
      })
    end,
  },

  -- ── Copilot as a cmp source ────────────────────────────────
  {
    "zbirenbaum/copilot-cmp",
    dependencies = { "zbirenbaum/copilot.lua" },
    config = function()
      require("copilot_cmp").setup()
    end,
  },
}
