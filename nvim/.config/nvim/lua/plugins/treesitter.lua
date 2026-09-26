-- ============================================================
-- Treesitter: AST-based syntax highlighting
-- NOTE: nvim-treesitter v1.x broke the old configs API.
-- Highlight is now native to nvim; this plugin provides parsers + queries.
-- ============================================================

return {
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    event = { "BufReadPost", "BufNewFile", "VeryLazy" },
    dependencies = {
      "nvim-treesitter/nvim-treesitter-textobjects",
    },
    config = function()
      -- v1.x: setup() only accepts install_dir (parsers go in stdpath("data")/site)
      require("nvim-treesitter").setup()

      local parsers = {
        "php", "javascript", "typescript", "tsx",
        "css", "scss", "html", "go", "gomod",
        "yaml", "xml", "json", "lua",
        "markdown", "markdown_inline", "bash",
        "dockerfile", "sql", "regex", "vim", "vimdoc",
      }

      -- Install any missing parsers in the background (non-blocking)
      vim.schedule(function()
        require("nvim-treesitter").install(parsers)
      end)

      -- Enable treesitter highlighting per buffer.
      -- On first open of an unknown filetype, auto-install its parser.
      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("ts_highlight", { clear = true }),
        callback = function(ev)
          -- Skip very large files (> 200 KB)
          local ok_stat, stats = pcall(vim.uv.fs_stat, vim.api.nvim_buf_get_name(ev.buf))
          if ok_stat and stats and stats.size > 200 * 1024 then return end

          local lang = vim.treesitter.language.get_lang(vim.bo[ev.buf].filetype)
          if not lang then return end

          local ok = pcall(vim.treesitter.start, ev.buf, lang)
          if not ok then
            -- Parser missing → install silently, will highlight on next open
            vim.schedule(function()
              require("nvim-treesitter").install({ lang })
            end)
          end
        end,
      })

      -- Incremental selection (Ctrl+Space to expand, Backspace to shrink)
      vim.keymap.set("n", "<C-space>", function()
        vim.cmd("normal! vib")
      end, { desc = "Start selection (treesitter)" })

      -- ── nvim-treesitter-textobjects (v1.x uses its own setup) ──
      require("nvim-treesitter-textobjects").setup({
        select = {
          enable = true,
          lookahead = true,
          keymaps = {
            ["af"] = "@function.outer",   -- select whole function
            ["if"] = "@function.inner",   -- select function body
            ["ac"] = "@class.outer",      -- select whole class
            ["ic"] = "@class.inner",      -- select class body
            ["aa"] = "@parameter.outer",  -- select whole argument
            ["ia"] = "@parameter.inner",  -- select argument value
            ["ab"] = "@block.outer",
            ["ib"] = "@block.inner",
          },
        },
        -- Jump between functions/classes with ]m / [m
        move = {
          enable = true,
          set_jumps = true,
          goto_next_start     = { ["]m"] = "@function.outer", ["]c"] = "@class.outer" },
          goto_next_end       = { ["]M"] = "@function.outer", ["]C"] = "@class.outer" },
          goto_previous_start = { ["[m"] = "@function.outer", ["[c"] = "@class.outer" },
          goto_previous_end   = { ["[M"] = "@function.outer", ["[C"] = "@class.outer" },
        },
        -- Swap function arguments with <leader>a / <leader>A
        swap = {
          enable = true,
          swap_next     = { ["<leader>a"] = "@parameter.inner" },
          swap_previous = { ["<leader>A"] = "@parameter.inner" },
        },
      })
    end,
  },
}
