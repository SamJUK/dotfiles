-- ============================================================
-- LSP: Language Server Protocol
-- Mason   → installs language servers automatically
-- lspconfig → configures each server
-- ============================================================

return {

  -- ── Mason: LSP server / linter / formatter installer ──────
  {
    "williamboman/mason.nvim",
    lazy = false,  -- puts Mason's bin/ on PATH before linters and formatters run
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

      -- Formatters and linters (LSP servers are installed by mason-lspconfig below)
      local registry = require("mason-registry")
      registry.refresh(function()
        for _, name in ipairs({ "goimports", "gofumpt", "shfmt", "hadolint", "prettier", "ansible-lint" }) do
          local pkg = registry.get_package(name)
          if not pkg:is_installed() then pkg:install() end
        end
      end)
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
          "terraformls",              -- Terraform (tflint comes from brew)
          "ansiblels",                -- Ansible
          "bashls",                   -- Bash (uses shellcheck from brew)
          "dockerls",                 -- Dockerfile
          "docker_compose_language_service", -- docker-compose.yml
        },
        -- Servers are enabled in nvim-lspconfig below, after vim.lsp.config has run
        automatic_enable = false,
      })
    end,
  },

  -- ── Core LSP config ───────────────────────────────────────
  {
    "neovim/nvim-lspconfig",
    -- Not BufReadPost: vim.lsp.enable() fires FileType when loaded mid-read,
    -- which makes filetype detection skip that buffer (no ft, no highlighting)
    event = "VeryLazy",
    dependencies = {
      "williamboman/mason.nvim",
      "williamboman/mason-lspconfig.nvim",
      "saghen/blink.cmp",  -- completion capabilities, needed before any server starts
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
        -- Built-in [d / ]d open the float after jumping
        jump = {
          on_jump = function(_, bufnr)
            vim.diagnostic.open_float({ bufnr = bufnr, scope = "cursor", focus = false })
          end,
        },
      })

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
          map("K",       function() vim.lsp.buf.hover({ border = "rounded" }) end,          "Hover documentation")
          map_i("<C-s>", function() vim.lsp.buf.signature_help({ border = "rounded" }) end, "Signature help (parameter hints)")

          -- Actions
          map("<leader>rn",  vim.lsp.buf.rename,          "Rename symbol")
          map("<leader>ca",  vim.lsp.buf.code_action,     "Code action")
          -- <leader>lf (format) is conform.nvim's, which falls back to LSP itself

          -- Diagnostics
          map("<leader>ld",  vim.diagnostic.open_float,   "Show line diagnostics")

          -- Workspace
          map("<leader>lwa", vim.lsp.buf.add_workspace_folder,    "Add workspace folder")
          map("<leader>lwr", vim.lsp.buf.remove_workspace_folder, "Remove workspace folder")
          map("<leader>lwl", function()
            print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
          end, "List workspace folders")

          -- Toggle inlay hints (nvim 0.10+: shows types inline in Go/TS)
          local client = vim.lsp.get_client_by_id(event.data.client_id)
          if client and client:supports_method("textDocument/inlayHint") then
            map("<leader>li", function()
              vim.lsp.inlay_hint.enable(
                not vim.lsp.inlay_hint.is_enabled({ bufnr = buf }),
                { bufnr = buf }
              )
            end, "Toggle inlay hints")
          end
        end,
      })

      -- ── Capabilities (enhanced by blink.cmp) ──────────────
      vim.lsp.config("*", { capabilities = require("blink.cmp").get_lsp_capabilities() })

      -- ── Server configurations ─────────────────────────────
      -- Merged over the defaults nvim-lspconfig ships in its lsp/ directory

      -- PHP — Intelephense (free tier: completions, hover, go-to-def, signatures)
      -- For premium features, set vim.g.intelephense_licence_key in ~/.config/nvim/lua/local.lua
      vim.lsp.config("intelephense", {
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
            format = { enable = false },  -- php-cs-fixer via conform.nvim (<leader>lf)
          },
        },
      })

      -- JavaScript / TypeScript
      vim.lsp.config("ts_ls", {
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
      vim.lsp.config("cssls", {
        settings = {
          css  = { validate = true, lint = { unknownAtRules = "ignore" } },
          scss = { validate = true, lint = { unknownAtRules = "ignore" } },
          less = { validate = true },
        },
      })

      -- Go
      vim.lsp.config("gopls", {
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
      vim.lsp.config("yamlls", {
        settings = {
          yaml = {
            keyOrdering = false,
            validate     = true,
            schemaStore  = { enable = true, url = "https://www.schemastore.org/api/json/catalog.json" },
          },
        },
      })

      -- XML: Magento's urn:magento:... schema references can't be resolved without
      -- a catalog, so only schema-validate when the schema is actually found
      vim.lsp.config("lemminx", {
        settings = {
          xml = { validation = { schema = { enabled = "onValidSchema" } } },
        },
      })

      -- JSON
      vim.lsp.config("jsonls", {
        settings = {
          json = {
            schemas = require("schemastore").json.schemas(),
            validate = { enable = true },
          },
        },
      })

      -- Lua (for editing this NVIM config)
      vim.lsp.config("lua_ls", {
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

      -- Ansible: ansible-core and ansible-lint come from Mason's ansible-lint venv
      -- (macOS has no `python`, which is the server's default interpreter)
      local ansible_venv = vim.fn.stdpath("data") .. "/mason/packages/ansible-lint/venv/bin/"
      vim.lsp.config("ansiblels", {
        settings = {
          ansible = {
            ansible = { path = ansible_venv .. "ansible" },
            python  = { interpreterPath = ansible_venv .. "python" },
          },
        },
      })

      vim.lsp.enable({
        "intelephense", "ts_ls", "cssls", "html", "gopls",
        "yamlls", "lemminx", "jsonls", "lua_ls",
        "terraformls", "tflint", "ansiblels", "bashls",
        "dockerls", "docker_compose_language_service",
      })
    end,
  },

  -- ── SchemaStore: JSON/YAML schema catalogue (optional) ────
  {
    "b0o/SchemaStore.nvim",
    lazy = true,
  },
}
