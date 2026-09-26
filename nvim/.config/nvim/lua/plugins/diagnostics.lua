-- ============================================================
-- Diagnostics: Formatting, Linting, Trouble panel
--
-- conform.nvim  → format on save (phpcbf, prettier, gofmt)
-- nvim-lint     → async linting (phpcs, phpstan, eslint)
-- trouble.nvim  → VSCode-style Problems panel
-- ============================================================
-- REQUIRED external tools (install once):
--   composer global require squizlabs/php_codesniffer phpstan/phpstan
--   npm install -g prettier eslint
--   brew install stylua
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
        function() require("conform").format({ async = true, lsp_fallback = true }) end,
        desc = "Format file",
        mode = { "n", "v" },
      },
    },
    config = function()
      require("conform").setup({
        formatters_by_ft = {
          php        = { "phpcbf" },      -- PHP: PHP Code Beautifier
          javascript = { "prettier" },
          typescript = { "prettier" },
          jsx        = { "prettier" },
          tsx        = { "prettier" },
          css        = { "prettier" },
          scss       = { "prettier" },
          html       = { "prettier" },
          json       = { "prettier" },
          yaml       = { "prettier" },
          markdown   = { "prettier" },
          go         = { "gofmt" },       -- Go: standard formatter
          lua        = { "stylua" },      -- Lua: for editing nvim config
          sh         = { "shfmt" },
          ["*"]      = { "trim_whitespace" },  -- trim trailing whitespace on all files
        },

        -- Format when you save (with a 3-second timeout)
        format_on_save = {
          timeout_ms   = 3000,
          lsp_fallback = true,  -- fall back to LSP formatting if no formatter configured
        },

        -- Don't error if a formatter isn't installed
        notify_on_error = false,

        -- Custom formatter configs
        formatters = {
          phpcbf = {
            command = function()
              -- Check for project-local phpcbf first, then global
              if vim.fn.executable("./vendor/bin/phpcbf") == 1 then
                return "./vendor/bin/phpcbf"
              end
              return vim.fn.expand("~/.composer/vendor/bin/phpcbf")
            end,
            args = { "--standard=PSR12", "$FILENAME" },
            stdin = false,
          },
          prettier = {
            require_cwd = false,
            -- Use project .prettierrc if present, otherwise sensible defaults
          },
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
        php        = { "phpcs", "phpstan" },
        javascript = { "eslint" },
        typescript = { "eslint" },
      }

      -- ── phpcs config ──────────────────────────────────────
      local phpcs = lint.linters.phpcs
      phpcs.cmd = function()
        if vim.fn.executable("./vendor/bin/phpcs") == 1 then
          return "./vendor/bin/phpcs"
        end
        return vim.fn.expand("~/.composer/vendor/bin/phpcs")
      end
      phpcs.args = {
        "--report=json",
        "--standard=PSR12",     -- change to your standard (PSR2, WordPress, etc.)
        "--runtime-set", "ignore_warnings_on_exit", "1",
        "-",  -- read from stdin
      }

      -- ── phpstan config ────────────────────────────────────
      local phpstan = lint.linters.phpstan
      phpstan.cmd = function()
        if vim.fn.executable("./vendor/bin/phpstan") == 1 then
          return "./vendor/bin/phpstan"
        end
        return vim.fn.expand("~/.composer/vendor/bin/phpstan")
      end
      -- phpstan requires a phpstan.neon config in the project root
      -- it won't run if no config file is found (graceful failure)

      -- ── eslint config ─────────────────────────────────────
      -- Looks for .eslintrc.* in the project (won't error without it)

      -- Run linting after save and on buffer enter
      vim.api.nvim_create_autocmd({ "BufWritePost", "BufReadPost", "InsertLeave" }, {
        callback = function()
          -- Only lint if the linter is available for this filetype
          local linters = lint.linters_by_ft[vim.bo.filetype]
          if linters then
            lint.try_lint()
          end
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
