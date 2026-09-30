-- ============================================================
-- Diagnostics: Formatting, Linting, Trouble panel
--
-- conform.nvim  → format on save (goimports/gofumpt, terraform fmt, shfmt, prettier)
-- nvim-lint     → async linting (phpcs, phpstan, eslint, hadolint)
-- trouble.nvim  → VSCode-style Problems panel
-- ============================================================
-- External tools are installed by Mason (see lsp.lua), except:
--   composer global require friendsofphp/php-cs-fixer squizlabs/php_codesniffer phpstan/phpstan
--   brew install terraform shellcheck tflint
-- ============================================================

return {

  -- ── conform.nvim: Format on Save ──────────────────────────
  {
    "stevearc/conform.nvim",
    event = { "BufWritePre" },
    cmd   = { "ConformInfo" },
    keys  = {
      {
        "<leader>lf",
        function() require("conform").format({ async = true, lsp_format = "fallback" }) end,
        desc = "Format file",
        mode = { "n", "v" },
      },
    },
    config = function()
      require("conform").setup({
        formatters_by_ft = {
          php        = { "php_cs_fixer" },  -- uses the project's .php-cs-fixer(.dist).php
          javascript = { "prettier" },
          typescript = { "prettier" },
          javascriptreact = { "prettier" },
          typescriptreact = { "prettier" },
          css        = { "prettier" },
          scss       = { "prettier" },
          html       = { "prettier" },
          json       = { "prettier" },
          yaml       = { "prettier" },
          markdown   = { "prettier" },
          go         = { "goimports", "gofumpt" },
          terraform  = { "terraform_fmt" },
          ["terraform-vars"] = { "terraform_fmt" },
          lua        = { "stylua" },      -- Lua: for editing nvim config
          sh         = { "shfmt" },
          bash       = { "shfmt" },
          ["*"]      = { "trim_whitespace" },  -- trim trailing whitespace on all files
        },

        -- Format when you save (with a 3-second timeout), except PHP: Magento's stock
        -- .php-cs-fixer.dist.php doesn't exclude third-party code in app/code, so a save
        -- would reformat whole vendor modules. Format PHP on demand with <leader>lf.
        format_on_save = function(bufnr)
          if vim.bo[bufnr].filetype == "php" then return end
          return { timeout_ms = 3000, lsp_format = "fallback" }
        end,

        -- Don't error if a formatter isn't installed
        notify_on_error = false,

        formatters = {
          -- A global php-cs-fixer refuses PHP newer than it supports without this
          php_cs_fixer = { env = { PHP_CS_FIXER_IGNORE_ENV = "1" } },
          -- Only where the project configures prettier, so it doesn't rewrite
          -- composer.json, Ansible YAML etc. in repos that don't use it
          prettier = { require_cwd = true },
        },
      })
    end,
  },

  -- ── nvim-lint: Async Linting ───────────────────────────────
  {
    "mfussenegger/nvim-lint",
    event = { "BufReadPost", "BufNewFile", "BufWritePost" },
    config = function()
      local lint = require("lint")

      lint.linters_by_ft = {
        javascript = { "eslint" },
        typescript = { "eslint" },
        dockerfile = { "hadolint" },
      }

      -- PHP linters only run where the project configures them: phpcs's default
      -- standard floods Magento code with warnings, and phpstan needs its neon file
      local function php_linters(bufnr)
        local linters = {}
        if vim.fs.root(bufnr, { "phpcs.xml", "phpcs.xml.dist", ".phpcs.xml", ".phpcs.xml.dist" }) then
          table.insert(linters, "phpcs")
        end
        if vim.fs.root(bufnr, { "phpstan.neon", "phpstan.neon.dist", "phpstan.dist.neon" }) then
          table.insert(linters, "phpstan")
        end
        return linters
      end

      vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost" }, {
        group = vim.api.nvim_create_augroup("lint", { clear = true }),
        callback = function(ev)
          local names = vim.bo[ev.buf].filetype == "php" and php_linters(ev.buf) or nil
          -- ignore_errors: a linter that isn't installed (e.g. no eslint) stays quiet
          lint.try_lint(names, { ignore_errors = true })
        end,
      })
    end,
  },

  -- ── Trouble.nvim: Project Diagnostics Panel ───────────────
  -- Like VSCode's "Problems" tab (Ctrl+Shift+M)
  {
    "folke/trouble.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    cmd  = "Trouble",
    keys = {
      { "<leader>xx", "<cmd>Trouble diagnostics toggle<cr>",
        desc = "Toggle diagnostics panel" },
      { "<leader>xd", "<cmd>Trouble diagnostics toggle filter.buf=0<cr>",
        desc = "Document diagnostics" },
      { "<leader>xw", "<cmd>Trouble diagnostics toggle<cr>",
        desc = "Workspace diagnostics" },
      { "<leader>xq", "<cmd>Trouble qflist toggle<cr>",
        desc = "Quickfix list" },
      { "<leader>xl", "<cmd>Trouble loclist toggle<cr>",
        desc = "Location list" },
      { "gR",         "<cmd>Trouble lsp toggle<cr>",
        desc = "LSP references (Trouble)" },
    },
    config = function()
      require("trouble").setup({
        modes = {
          diagnostics = {
            auto_close = false,
            auto_open  = false,
          },
        },
        icons = {
          indent = {
            top        = "│ ",
            middle     = "├╴",
            last       = "└╴",
            fold_open  = " ",
            fold_closed = " ",
            ws         = "  ",
          },
          folder_closed = " ",
          folder_open   = " ",
          kinds = {
            Array     = " ", Boolean = " ", Class = " ", Constant = " ",
            Constructor = " ", Enum = " ", EnumMember = " ", Event = " ",
            Field = " ", File = " ", Function = "󰊕 ", Interface = " ",
            Key = " ", Method = "󰆧 ", Module = " ", Namespace = "󰦮 ",
            Null = " ", Number = " ", Object = " ", Operator = " ",
            Package = " ", Property = " ", String = " ", Struct = " ",
            TypeParameter = " ", Variable = " ",
          },
        },
      })
    end,
  },
}
