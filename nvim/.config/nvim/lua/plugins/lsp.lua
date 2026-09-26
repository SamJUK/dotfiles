-- ============================================================
-- LSP: Language Server Protocol
-- Mason   → installs language servers automatically
-- lspconfig → configures each server
-- ============================================================

return {

  -- ── Mason: LSP server / linter / formatter installer ──────
  {
    "williamboman/mason.nvim",
    cmd  = "Mason",
    keys = { { "<leader>lm", "<cmd>Mason<cr>", desc = "Mason (LSP manager)" } },
    build = ":MasonUpdate",
    config = function()
      require("mason").setup({
        ui = {
          border = "rounded",
          icons = {
            package_installed   = "✓",
            package_pending     = "➜",
            package_uninstalled = "✗",
          },
        },
      })
    end,
  },

  -- ── Mason ↔ lspconfig bridge ───────────────────────────────
  {
    "williamboman/mason-lspconfig.nvim",
    dependencies = { "williamboman/mason.nvim" },
    config = function()
      require("mason-lspconfig").setup({
        -- These servers are auto-installed on first launch
        ensure_installed = {
          "intelephense",             -- PHP
          "ts_ls",                    -- JavaScript / TypeScript
          "cssls",                    -- CSS
          "html",                     -- HTML
          "gopls",                    -- Go
          "yamlls",                   -- YAML
          "lemminx",                  -- XML
          "lua_ls",                   -- Lua (for editing nvim config)
          "jsonls",                   -- JSON
        },
        automatic_installation = true,
      })
    end,
  },

  -- ── Core LSP config ───────────────────────────────────────
  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPost", "BufNewFile" },
    dependencies = {
      "williamboman/mason.nvim",
      "williamboman/mason-lspconfig.nvim",
      "hrsh7th/cmp-nvim-lsp",  -- enhanced LSP capabilities for completion
    },
    config = function()
      -- ── Diagnostic appearance ─────────────────────────────
      vim.diagnostic.config({
        virtual_text = {
          prefix = "●",  -- icon before inline diagnostic message
          spacing = 4,
        },
        signs = {
          text = {
            [vim.diagnostic.severity.ERROR] = " ",
            [vim.diagnostic.severity.WARN]  = " ",
            [vim.diagnostic.severity.INFO]  = " ",
            [vim.diagnostic.severity.HINT]  = "󰠠 ",
          },
        },
        underline    = true,
        update_in_insert = false,  -- only show diagnostics in normal mode
        severity_sort = true,
        float = {
          border = "rounded",
          source = "always",
        },
      })

      -- ── Hover / signature help window style ───────────────
      vim.lsp.handlers["textDocument/hover"] =
        vim.lsp.with(vim.lsp.handlers.hover, { border = "rounded" })
      vim.lsp.handlers["textDocument/signatureHelp"] =
        vim.lsp.with(vim.lsp.handlers.signature_help, { border = "rounded" })

      -- ── Keymaps applied whenever an LSP attaches ──────────
      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("lsp_keymaps", { clear = true }),
        callback = function(event)
          local buf = event.buf
          local map = function(keys, func, desc)
            vim.keymap.set("n", keys, func, { buffer = buf, desc = "LSP: " .. desc })
          end
          local map_i = function(keys, func, desc)
            vim.keymap.set("i", keys, func, { buffer = buf, desc = "LSP: " .. desc })
          end

          -- Navigation
          map("gd", function() require("telescope.builtin").lsp_definitions() end,     "Go to definition")
          map("gD", vim.lsp.buf.declaration,                                            "Go to declaration")
          map("gr", function() require("telescope.builtin").lsp_references() end,      "Go to references")
          map("gi", function() require("telescope.builtin").lsp_implementations() end, "Go to implementation")
          map("gt", function() require("telescope.builtin").lsp_type_definitions() end,"Go to type definition")

          -- Documentation
          map("K",           vim.lsp.buf.hover,           "Hover documentation")
          map_i("<C-s>",     vim.lsp.buf.signature_help,  "Signature help (parameter hints)")

          -- Actions
          map("<leader>rn",  vim.lsp.buf.rename,          "Rename symbol")
          map("<leader>ca",  vim.lsp.buf.code_action,     "Code action")
          map("<leader>lf",  function() vim.lsp.buf.format({ async = true }) end, "Format file")

          -- Diagnostics
          map("<leader>ld",  vim.diagnostic.open_float,   "Show line diagnostics")
          map("[d",          vim.diagnostic.goto_prev,    "Previous diagnostic")
          map("]d",          vim.diagnostic.goto_next,    "Next diagnostic")

          -- Workspace
          map("<leader>lwa", vim.lsp.buf.add_workspace_folder,    "Add workspace folder")
          map("<leader>lwr", vim.lsp.buf.remove_workspace_folder, "Remove workspace folder")
          map("<leader>lwl", function()
            print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
          end, "List workspace folders")

          -- Toggle inlay hints (nvim 0.10+: shows types inline in Go/TS)
          local client = vim.lsp.get_client_by_id(event.data.client_id)
          if client and client.supports_method("textDocument/inlayHint") then
            map("<leader>li", function()
              vim.lsp.inlay_hint.enable(
                not vim.lsp.inlay_hint.is_enabled({ bufnr = buf }),
                { bufnr = buf }
              )
            end, "Toggle inlay hints")
          end
        end,
      })

      -- ── Capabilities (enhanced by nvim-cmp) ───────────────
      local capabilities = require("cmp_nvim_lsp").default_capabilities()

      -- ── Server configurations ─────────────────────────────
      local lspconfig = require("lspconfig")

      -- PHP — Intelephense (free tier: completions, hover, go-to-def, signatures)
      -- For premium features, set vim.g.intelephense_licence_key in ~/.config/nvim/lua/local.lua
      lspconfig.intelephense.setup({
        capabilities = capabilities,
        settings = {
          intelephense = {
            environment = { phpVersion = "8.4" },
            files = { maxSize = 1000000 },
            stubs = {
              "apache", "bcmath", "bz2", "calendar", "Core", "ctype", "curl", "date",
              "dom", "enchant", "exif", "fileinfo", "filter", "ftp", "gd", "gettext",
              "gmp", "hash", "iconv", "imap", "intl", "json", "libxml", "mbstring",
              "mcrypt", "meta", "mysqli", "openssl", "pcntl", "pcre", "PDO",
              "pdo_mysql", "pdo_pgsql", "pdo_sqlite", "pgsql", "Phar", "posix",
              "readline", "Reflection", "session", "SimpleXML", "soap", "sockets",
              "sodium", "SPL", "sqlite3", "standard", "superglobals", "tokenizer",
              "xml", "xmlreader", "xmlwriter", "xsl", "zip", "zlib",
            },
            format = { enable = false },  -- use phpcbf (conform.nvim) for formatting
          },
        },
      })

      -- JavaScript / TypeScript
      lspconfig.ts_ls.setup({
        capabilities = capabilities,
        settings = {
          typescript = {
            inlayHints = {
              includeInlayParameterNameHints = "all",
              includeInlayFunctionParameterTypeHints = true,
              includeInlayVariableTypeHints = true,
              includeInlayPropertyDeclarationTypeHints = true,
              includeInlayFunctionLikeReturnTypeHints = true,
            },
          },
          javascript = {
            inlayHints = {
              includeInlayParameterNameHints = "all",
              includeInlayFunctionParameterTypeHints = true,
            },
          },
        },
      })

      -- CSS
      lspconfig.cssls.setup({
        capabilities = capabilities,
        settings = {
          css  = { validate = true, lint = { unknownAtRules = "ignore" } },
          scss = { validate = true, lint = { unknownAtRules = "ignore" } },
          less = { validate = true },
        },
      })

      -- HTML
      lspconfig.html.setup({ capabilities = capabilities })

      -- Go
      lspconfig.gopls.setup({
        capabilities = capabilities,
        settings = {
          gopls = {
            analyses  = { unusedparams = true },
            staticcheck = true,
            gofumpt   = true,
            hints = {
              parameterNames       = true,
              assignVariableTypes  = true,
              compositeLiteralFields = true,
              compositeLiteralTypes  = true,
              constantValues       = true,
              functionTypeParameters = true,
              rangeVariableTypes   = true,
            },
          },
        },
      })

      -- YAML
      lspconfig.yamlls.setup({
        capabilities = capabilities,
        settings = {
          yaml = {
            keyOrdering = false,
            validate     = true,
            schemaStore  = { enable = true, url = "https://www.schemastore.org/api/json/catalog.json" },
          },
        },
      })

      -- XML
      lspconfig.lemminx.setup({ capabilities = capabilities })

      -- JSON
      lspconfig.jsonls.setup({
        capabilities = capabilities,
        settings = {
          json = {
            schemas = require("schemastore").json.schemas(),  -- loaded if SchemaStore plugin present
            validate = { enable = true },
          },
        },
        on_new_config = function(new_config)
          -- Gracefully skip SchemaStore if not installed
          local ok, _ = pcall(require, "schemastore")
          if not ok then
            new_config.settings.json.schemas = {}
          end
        end,
      })

      -- Lua (for editing this NVIM config)
      lspconfig.lua_ls.setup({
        capabilities = capabilities,
        settings = {
          Lua = {
            runtime = { version = "LuaJIT" },
            diagnostics = { globals = { "vim" } },  -- recognise vim global
            workspace = {
              library = vim.api.nvim_get_runtime_file("", true),
              checkThirdParty = false,
            },
            telemetry = { enable = false },
            hint = { enable = true },
          },
        },
      })
    end,
  },

  -- ── SchemaStore: JSON/YAML schema catalogue (optional) ────
  {
    "b0o/SchemaStore.nvim",
    lazy = true,
  },
}
