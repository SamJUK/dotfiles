-- ============================================================
-- Telescope: Fuzzy Finder (Files, Grep, LSP, Diagnostics…)
-- Powered by ripgrep — far superior to VSCode's search
-- ============================================================

return {
  {
    "nvim-telescope/telescope.nvim",
    version = "*",  -- latest release; 0.1.x breaks with the new nvim-treesitter
    dependencies = {
      "nvim-lua/plenary.nvim",
      -- Native FZF sorter: much faster fuzzy matching
      {
        "nvim-telescope/telescope-fzf-native.nvim",
        build = "make",
        cond = function() return vim.fn.executable("make") == 1 end,
      },
    },
    cmd = "Telescope",
    keys = {
      -- ── Files ──────────────────────────────────────────────
      { "<leader>ff", "<cmd>Telescope find_files<cr>",                        desc = "Find files" },
      { "<leader>fr", "<cmd>Telescope oldfiles<cr>",                          desc = "Recent files" },
      { "<leader>fn", "<cmd>enew<cr>",                                        desc = "New file" },

      -- ── Grep (the main reason to switch from VSCode search) ─
      { "<leader>fg", "<cmd>Telescope live_grep<cr>",                         desc = "Live grep (whole project)" },
      { "<leader>fw", "<cmd>Telescope grep_string<cr>",                       desc = "Grep word under cursor" },
      { "<leader>fc", "<cmd>Telescope current_buffer_fuzzy_find<cr>",         desc = "Grep current file" },

      -- ── Buffers & navigation ───────────────────────────────
      { "<leader>fb", "<cmd>Telescope buffers sort_mru=true<cr>",             desc = "Find open buffers" },
      { "<leader>fk", "<cmd>Telescope keymaps<cr>",                           desc = "Find keymaps" },
      { "<leader>fh", "<cmd>Telescope help_tags<cr>",                         desc = "Find help" },
      { "<leader>fm", "<cmd>Telescope marks<cr>",                             desc = "Find marks" },
      { "<leader>f:", "<cmd>Telescope command_history<cr>",                   desc = "Command history" },

      -- ── LSP-aware search ───────────────────────────────────
      { "<leader>fs", "<cmd>Telescope lsp_document_symbols<cr>",              desc = "Find symbols (file)" },
      { "<leader>fS", "<cmd>Telescope lsp_dynamic_workspace_symbols<cr>",     desc = "Find symbols (project)" },
      { "<leader>fd", "<cmd>Telescope diagnostics<cr>",                       desc = "Find diagnostics" },

      -- ── Git (under <leader>g: nesting them under <leader>fg made live grep wait) ──
      { "<leader>gl", "<cmd>Telescope git_commits<cr>",                       desc = "Git log (commits)" },
      { "<leader>go", "<cmd>Telescope git_branches<cr>",                      desc = "Git branches (checkout)" },
      { "<leader>gm", "<cmd>Telescope git_status<cr>",                        desc = "Git modified files" },
    },
    config = function()
      local telescope = require("telescope")
      local actions   = require("telescope.actions")

      telescope.setup({
        defaults = {
          prompt_prefix   = "  ",
          selection_caret = " ",
          path_display    = { "truncate" },
          sorting_strategy = "ascending",
          layout_config = {
            horizontal = { prompt_position = "top", preview_width = 0.55 },
            vertical   = { mirror = false },
            width      = 0.87,
            height     = 0.80,
          },
          mappings = {
            i = {
              ["<C-k>"] = actions.move_selection_previous,
              ["<C-j>"] = actions.move_selection_next,
              ["<C-q>"] = actions.send_selected_to_qflist + actions.open_qflist,
              ["<Esc>"] = actions.close,
              ["<C-u>"] = false,  -- clear prompt with Ctrl+U
              ["<C-d>"] = false,
            },
          },
          -- Search hidden files too (but not .git/)
          file_ignore_patterns = {
            "%.git/", "node_modules/", "%.lock",
            "%.DS_Store", "__pycache__/",
          },
          vimgrep_arguments = {
            "rg", "--color=never", "--no-heading", "--with-filename",
            "--line-number", "--column", "--smart-case",
            "--hidden",           -- include dotfiles
            "--glob=!.git/*",     -- but not .git
            "--glob=!node_modules/*",
          },
        },
        pickers = {
          find_files = {
            -- Use fd if available (faster), else ripgrep
            find_command = vim.fn.executable("fd") == 1
              and { "fd", "--type", "f", "--hidden", "--follow",
                    "--exclude", ".git", "--exclude", "node_modules" }
              or nil,
            hidden = true,
          },
          live_grep = {
            additional_args = { "--hidden" },
          },
          buffers = {
            show_all_buffers = true,
            mappings = {
              i = { ["<C-d>"] = actions.delete_buffer },
            },
          },
        },
        extensions = {
          fzf = {
            fuzzy                   = true,
            override_generic_sorter = true,
            override_file_sorter    = true,
            case_mode               = "smart_case",
          },
        },
      })

      -- Load the fzf extension for faster sorting
      telescope.load_extension("fzf")
    end,
  },
}
