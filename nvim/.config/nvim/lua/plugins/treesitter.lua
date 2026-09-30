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
        "php", "phpdoc", "javascript", "typescript", "tsx",
        "css", "scss", "html", "graphql", "go", "gomod", "gosum", "gowork",
        "yaml", "xml", "json", "lua", "python", "toml", "ini",
        "markdown", "markdown_inline", "bash", "make",
        "terraform", "hcl", "jinja", "jinja_inline", "nginx", "ssh_config",
        "dockerfile", "sql", "regex", "vim", "vimdoc",
        "diff", "gitcommit", "git_rebase", "gitignore", "git_config",
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
          -- Parser missing → install it if one exists (not for TelescopePrompt, neo-tree…)
          if not ok and require("nvim-treesitter.parsers")[lang] then
            vim.schedule(function()
              require("nvim-treesitter").install({ lang })
            end)
          end
        end,
      })

      -- Incremental selection (Ctrl+Space to expand, Backspace to shrink)
      -- Uses Neovim's built-in treesitter `an` / `in` visual mappings
      vim.keymap.set("n", "<C-space>", "van", { remap = true, desc = "Start selection (treesitter)" })
      vim.keymap.set("x", "<C-space>", "an", { remap = true, desc = "Expand selection" })
      vim.keymap.set("x", "<BS>", "in", { remap = true, desc = "Shrink selection" })

      -- ── nvim-treesitter-textobjects (v1.x uses its own setup) ──
      -- setup() only takes options; keymaps are plain vim.keymap.set calls
      require("nvim-treesitter-textobjects").setup({
        select = { lookahead = true },
        move = { set_jumps = true },
      })

      -- Arguments (aa / ia) and brackets (ab / ib) come from mini.ai
      local select = require("nvim-treesitter-textobjects.select")
      for key, query in pairs({
        af = "@function.outer",   -- select whole function
        ["if"] = "@function.inner",   -- select function body
        ac = "@class.outer",      -- select whole class
        ic = "@class.inner",      -- select class body
      }) do
        vim.keymap.set({ "x", "o" }, key, function()
          select.select_textobject(query, "textobjects")
        end, { desc = "Select " .. query })
      end

      -- Jump between functions with ]m / [m
      -- No ]c / [c class jumps: those are Vim's diff-mode change jumps
      local move = require("nvim-treesitter-textobjects.move")
      for key, fn in pairs({
        ["]m"] = move.goto_next_start,     ["]M"] = move.goto_next_end,
        ["[m"] = move.goto_previous_start, ["[M"] = move.goto_previous_end,
      }) do
        vim.keymap.set({ "n", "x", "o" }, key, function()
          fn("@function.outer", "textobjects")
        end, { desc = "Move to @function.outer" })
      end

      -- Swap function arguments with <leader>a / <leader>A
      local swap = require("nvim-treesitter-textobjects.swap")
      vim.keymap.set("n", "<leader>a", function() swap.swap_next("@parameter.inner") end,
        { desc = "Swap with next argument" })
      vim.keymap.set("n", "<leader>A", function() swap.swap_previous("@parameter.inner") end,
        { desc = "Swap with previous argument" })
    end,
  },
}
