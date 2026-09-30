-- ============================================================
-- Completion: blink.cmp
-- Sources: LSP, snippets (friendly-snippets via vim.snippet),
-- buffer words, file paths, cmdline
-- ============================================================

return {
  {
    "saghen/blink.cmp",
    version = "1.*",  -- release tags ship the prebuilt fuzzy matcher
    event = { "InsertEnter", "CmdlineEnter" },
    dependencies = { "rafamadriz/friendly-snippets" },
    init = function()
      -- copilot.lua only hides its ghost text for the native popup menu
      vim.api.nvim_create_autocmd("User", {
        pattern = "BlinkCmpMenuOpen",
        callback = function() vim.b.copilot_suggestion_hidden = true end,
      })
      vim.api.nvim_create_autocmd("User", {
        pattern = "BlinkCmpMenuClose",
        callback = function() vim.b.copilot_suggestion_hidden = false end,
      })
    end,
    opts = {
      -- ── Keymaps ─────────────────────────────────────────
      keymap = {
        preset = "none",
        ["<C-k>"]     = { "select_prev", "fallback" },
        ["<C-j>"]     = { "select_next", "fallback" },
        ["<C-b>"]     = { "scroll_documentation_up", "fallback" },
        ["<C-f>"]     = { "scroll_documentation_down", "fallback" },
        ["<C-Space>"] = { "show", "show_documentation", "hide_documentation" },
        ["<C-e>"]     = { "hide", "fallback" },
        ["<CR>"]      = { "accept", "fallback" },  -- only when an item is selected

        -- Tab: move through completion, accept Copilot ghost text, or jump snippet placeholders
        ["<Tab>"] = {
          "select_next",
          function()
            local copilot = require("copilot.suggestion")
            if copilot.is_visible() then
              copilot.accept()
              return true
            end
          end,
          "snippet_forward",
          "fallback",
        },
        ["<S-Tab>"] = { "select_prev", "snippet_backward", "fallback" },
      },

      completion = {
        list = { selection = { preselect = false } },  -- don't auto-select the first item
        menu = {
          border = "rounded",
          -- icon, label, then source name (LSP / Snippets / Buffer / Path)
          draw = { columns = { { "kind_icon" }, { "label", "label_description", gap = 1 }, { "source_name" } } },
        },
        documentation = { auto_show = true, auto_show_delay_ms = 200, window = { border = "rounded" } },
      },

      -- Function signature popup while typing arguments
      signature = { enabled = true, window = { border = "rounded" } },

      sources = {
        default = { "lsp", "path", "snippets", "buffer" },
      },

      cmdline = {
        completion = { menu = { auto_show = true } },
      },
    },
  },
}
