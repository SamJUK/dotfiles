-- ============================================================
-- GitHub Copilot: inline ghost text, like VSCode
-- <Tab> accepts (wired in completion.lua), <M-]>/<M-[> cycle,
-- <C-]> dismisses
-- ============================================================
-- FIRST RUN: after installation run  :Copilot auth
--            and follow the browser login prompt
-- ============================================================

return {
  {
    "zbirenbaum/copilot.lua",
    cmd  = "Copilot",
    event = "InsertEnter",
    config = function()
      require("copilot").setup({
        suggestion = { auto_trigger = true },
        panel      = { enabled = false },

        -- Copilot won't activate in these filetypes
        filetypes = {
          markdown   = true,   -- enable in markdown (useful for docs)
          gitcommit  = false,
          help       = false,
          ["."]      = false,  -- disabled by default for unlisted types
        },
      })
    end,
  },
}
