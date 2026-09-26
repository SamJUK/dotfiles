-- ============================================================
-- Completion: nvim-cmp + LuaSnip
-- Sources: LSP, snippets, buffer words, file paths, cmdline
-- ============================================================

return {
  {
    "hrsh7th/nvim-cmp",
    event = { "InsertEnter", "CmdlineEnter" },
    dependencies = {
      -- Completion sources
      "hrsh7th/cmp-nvim-lsp",               -- LSP completions
      "hrsh7th/cmp-nvim-lsp-signature-help", -- function signature popup while typing args
      "hrsh7th/cmp-buffer",                  -- words from open buffers
      "hrsh7th/cmp-path",                    -- file system paths
      "hrsh7th/cmp-cmdline",                 -- : command line completions
      -- Snippets
      "L3MON4D3/LuaSnip",                   -- snippet engine
      "saadparwaiz1/cmp_luasnip",            -- LuaSnip → cmp bridge
      "rafamadriz/friendly-snippets",        -- large snippet library (PHP, JS, Go, HTML…)
      -- Copilot source (configured in copilot.lua, registered here)
      "zbirenbaum/copilot-cmp",
    },
    config = function()
      local cmp     = require("cmp")
      local luasnip = require("luasnip")

      -- Load friendly-snippets (VSCode-style snippet files)
      require("luasnip.loaders.from_vscode").lazy_load()

      -- ── Completion menu icons ──────────────────────────────
      local kind_icons = {
        Text          = "󰉿", Method        = "󰆧", Function      = "󰊕",
        Constructor   = "", Field         = "󰜢", Variable      = "󰀫",
        Class         = "󰠱", Interface     = "", Module        = "",
        Property      = "󰜢", Unit          = "󰑭", Value         = "󰎠",
        Enum          = "", Keyword       = "󰌋", Snippet       = "",
        Color         = "󰏘", File          = "󰈙", Reference     = "󰈇",
        Folder        = "󰉋", EnumMember    = "", Constant      = "󰏿",
        Struct        = "󰙅", Event         = "", Operator      = "󰆕",
        TypeParameter = "", Copilot       = "",
      }

      cmp.setup({
        snippet = {
          expand = function(args)
            luasnip.lsp_expand(args.body)
          end,
        },

        window = {
          completion    = cmp.config.window.bordered(),
          documentation = cmp.config.window.bordered(),
        },

        -- ── Keymaps ─────────────────────────────────────────
        mapping = cmp.mapping.preset.insert({
          ["<C-k>"]     = cmp.mapping.select_prev_item(),      -- prev item
          ["<C-j>"]     = cmp.mapping.select_next_item(),      -- next item
          ["<C-b>"]     = cmp.mapping.scroll_docs(-4),         -- scroll docs up
          ["<C-f>"]     = cmp.mapping.scroll_docs(4),          -- scroll docs down
          ["<C-Space>"] = cmp.mapping.complete(),              -- trigger completion manually
          ["<C-e>"]     = cmp.mapping.abort(),                 -- close completion
          ["<CR>"]      = cmp.mapping.confirm({ select = false }), -- confirm only if selected

          -- Tab: navigate snippet placeholders OR move through completion
          ["<Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_next_item()
            elseif luasnip.expand_or_locally_jumpable() then
              luasnip.expand_or_jump()
            else
              fallback()  -- Copilot.lua will intercept Tab for ghost text
            end
          end, { "i", "s" }),

          ["<S-Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_prev_item()
            elseif luasnip.locally_jumpable(-1) then
              luasnip.jump(-1)
            else
              fallback()
            end
          end, { "i", "s" }),
        }),

        -- ── Completion sources (priority order) ───────────────
        sources = cmp.config.sources({
          { name = "copilot",                   priority = 100, group_index = 1 },
          { name = "nvim_lsp",                  priority = 90,  group_index = 1 },
          { name = "nvim_lsp_signature_help",   priority = 80,  group_index = 1 },
          { name = "luasnip",                   priority = 70,  group_index = 1 },
        }, {
          { name = "buffer",  keyword_length = 3 },
          { name = "path" },
        }),

        -- ── Item formatting (shows icon + source name) ─────────
        formatting = {
          format = function(entry, vim_item)
            vim_item.kind = string.format("%s %s", kind_icons[vim_item.kind] or "", vim_item.kind)
            vim_item.menu = ({
              copilot               = "[Copilot]",
              nvim_lsp              = "[LSP]",
              nvim_lsp_signature_help = "[Sig]",
              luasnip               = "[Snippet]",
              buffer                = "[Buffer]",
              path                  = "[Path]",
            })[entry.source.name]
            -- Truncate long completions
            vim_item.abbr = string.sub(vim_item.abbr, 1, 50)
            return vim_item
          end,
        },

        -- Don't auto-select the first item
        preselect = cmp.PreselectMode.None,

        -- Experimental ghost-text (shows completion inline — like VS Code)
        experimental = {
          ghost_text = false,  -- disabled; Copilot handles ghost text
        },
      })

      -- ── Cmdline completions ('/'-search and ':'-commands) ───
      cmp.setup.cmdline({ "/", "?" }, {
        mapping = cmp.mapping.preset.cmdline(),
        sources = { { name = "buffer" } },
      })

      cmp.setup.cmdline(":", {
        mapping = cmp.mapping.preset.cmdline(),
        sources = cmp.config.sources(
          { { name = "path" } },
          { { name = "cmdline" } }
        ),
      })
    end,
  },

  -- ── LuaSnip standalone (already a dependency above) ───────
  {
    "L3MON4D3/LuaSnip",
    lazy  = true,
    build = "make install_jsregexp",  -- enable regex in snippets
  },
}
