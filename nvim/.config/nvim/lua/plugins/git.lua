-- ============================================================
-- Git: gitsigns (inline diff/blame) + lazygit TUI
-- ============================================================
-- REQUIRED: brew install lazygit
-- ============================================================

return {

  -- ── Gitsigns: inline git decorations ──────────────────────
  -- Shows +/~/- in the sign column, inline blame, hunk preview
  {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPost", "BufNewFile" },
    config = function()
      require("gitsigns").setup({
        signs = {
          add          = { text = "▎" },
          change       = { text = "▎" },
          delete       = { text = "" },
          topdelete    = { text = "" },
          changedelete = { text = "▎" },
          untracked    = { text = "▎" },
        },
        signcolumn       = true,
        numhl            = false,
        linehl           = false,
        word_diff        = false,
        watch_gitdir     = { follow_files = true },
        current_line_blame = false,  -- toggle with <leader>gb
        current_line_blame_opts = {
          virt_text         = true,
          virt_text_pos     = "eol",  -- end of line blame text
          delay             = 1000,
          ignore_whitespace = false,
        },
        current_line_blame_formatter = "<author>, <author_time:%Y-%m-%d> - <summary>",
        preview_config = { border = "rounded" },

        on_attach = function(bufnr)
          local gs  = package.loaded.gitsigns
          local map = function(mode, keys, func, desc)
            vim.keymap.set(mode, keys, func, { buffer = bufnr, desc = "Git: " .. desc })
          end

          -- Navigation between hunks
          map("n", "]h", function()
            if vim.wo.diff then return "]c" end
            vim.schedule(function() gs.next_hunk() end)
            return "<Ignore>"
          end, "Next hunk")

          map("n", "[h", function()
            if vim.wo.diff then return "[c" end
            vim.schedule(function() gs.prev_hunk() end)
            return "<Ignore>"
          end, "Previous hunk")

          -- Hunk actions
          map({ "n", "v" }, "<leader>gs", ":Gitsigns stage_hunk<CR>",     "Stage hunk")
          map({ "n", "v" }, "<leader>gr", ":Gitsigns reset_hunk<CR>",     "Reset hunk")
          map("n",          "<leader>gS", gs.stage_buffer,                "Stage buffer")
          map("n",          "<leader>gR", gs.reset_buffer,                "Reset buffer")
          map("n",          "<leader>gu", gs.undo_stage_hunk,             "Undo stage hunk")
          map("n",          "<leader>gp", gs.preview_hunk,                "Preview hunk")
          map("n",          "<leader>gd", gs.diffthis,                    "Diff this file")
          map("n",          "<leader>gD", function() gs.diffthis("~") end,"Diff against HEAD~")

          -- Blame
          map("n",          "<leader>gb", gs.toggle_current_line_blame,   "Toggle line blame")
          map("n",          "<leader>gB", function()
            gs.blame_line({ full = true })
          end, "Full blame popup")

          -- Text objects: select a hunk with 'ih' / 'ah'
          map({ "o", "x" }, "ih", ":<C-U>Gitsigns select_hunk<CR>",      "Select hunk")
          map({ "o", "x" }, "ah", ":<C-U>Gitsigns select_hunk<CR>",      "Select hunk")
        end,
      })
    end,
  },

  -- ── Lazygit inside NVIM ────────────────────────────────────
  -- Full git TUI without leaving the editor
  {
    "kdheepak/lazygit.nvim",
    cmd  = { "LazyGit", "LazyGitConfig", "LazyGitCurrentFile" },
    dependencies = { "nvim-lua/plenary.nvim" },
    keys = {
      { "<leader>gg", "<cmd>LazyGit<cr>",            desc = "LazyGit" },
      { "<leader>gf", "<cmd>LazyGitCurrentFile<cr>", desc = "LazyGit (current file)" },
      { "<leader>gc", "<cmd>LazyGitConfig<cr>",      desc = "LazyGit config" },
    },
    config = function()
      -- Let lazygit inherit the terminal's colour scheme
      vim.g.lazygit_floating_window_winblend = 0
      vim.g.lazygit_floating_window_scaling_factor = 0.9
    end,
  },
}
