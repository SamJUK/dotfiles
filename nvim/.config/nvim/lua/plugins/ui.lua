-- ============================================================
-- UI: Theme, Statusline, Bufferline, File Tree, Dashboard,
--     Which-key, Aerial (code outline), Icons
-- ============================================================

return {

  -- ── Icons (required by many plugins) ──────────────────────
  { "nvim-tree/nvim-web-devicons", lazy = true },

  -- ── Theme: Catppuccin Mocha (closest to VSCode Dark+) ─────
  {
    "catppuccin/nvim",
    name = "catppuccin",
    priority = 1000,  -- load before everything else
    config = function()
      require("catppuccin").setup({
        flavour = "mocha",  -- latte | frappe | macchiato | mocha
        background = { light = "latte", dark = "mocha" },
        transparent_background = false,
        integrations = {
          bufferline = true,
          cmp = true,
          gitsigns = true,
          neotree = true,
          telescope = { enabled = true },
          treesitter = true,
          which_key = true,
          aerial = true,
          lsp_trouble = true,
          indent_blankline = { enabled = true },
          mini = { enabled = true },
          dashboard = true,
          illuminate = { enabled = true },
        },
      })
      vim.cmd.colorscheme("catppuccin")
    end,
  },

  -- ── Statusline ────────────────────────────────────────────
  {
    "nvim-lualine/lualine.nvim",
    event = "VeryLazy",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      require("lualine").setup({
        options = {
          theme = "catppuccin",
          component_separators = { left = "", right = "" },
          section_separators = { left = "", right = "" },
          globalstatus = true,  -- single statusline across all splits
        },
        sections = {
          lualine_a = { "mode" },
          lualine_b = { "branch", "diff", "diagnostics" },
          lualine_c = {
            { "filename", path = 1 },  -- show relative path
          },
          lualine_x = { "encoding", "fileformat", "filetype" },
          lualine_y = { "progress" },
          lualine_z = { "location" },
        },
      })
    end,
  },

  -- ── Bufferline (VSCode-style tabs) ────────────────────────
  {
    "akinsho/bufferline.nvim",
    event = "VeryLazy",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    keys = {
      { "<S-l>",      "<cmd>BufferLineCycleNext<cr>",      desc = "Next buffer" },
      { "<S-h>",      "<cmd>BufferLineCyclePrev<cr>",      desc = "Previous buffer" },
      { "<leader>bp", "<cmd>BufferLineTogglePin<cr>",      desc = "Pin buffer" },
      { "<leader>bo", "<cmd>BufferLineCloseOthers<cr>",    desc = "Close other buffers" },
    },
    config = function()
      require("bufferline").setup({
        options = {
          mode = "buffers",
          diagnostics = "nvim_lsp",  -- show LSP error count on tab
          diagnostics_indicator = function(count, level)
            local icons = { error = " ", warning = " " }
            return (icons[level] or "") .. count
          end,
          offsets = {
            {
              filetype = "neo-tree",
              text = "File Explorer",
              highlight = "Directory",
              separator = true,
            },
          },
          show_buffer_close_icons = true,
          show_close_icon = false,
          separator_style = "slant",
          always_show_bufferline = false,
        },
      })
    end,
  },

  -- ── File Tree: Neo-tree ───────────────────────────────────
  {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-tree/nvim-web-devicons",
      "MunifTanjim/nui.nvim",
    },
    cmd = "Neotree",
    keys = {
      { "<leader>e", "<cmd>Neotree toggle<cr>",            desc = "Toggle file tree" },
      { "<leader>E", "<cmd>Neotree reveal<cr>",            desc = "Reveal file in tree" },
      { "<leader>ge", "<cmd>Neotree git_status<cr>",       desc = "Git status tree" },
    },
    config = function()
      require("neo-tree").setup({
        close_if_last_window = true,
        popup_border_style = "rounded",
        enable_git_status = true,
        enable_diagnostics = true,
        window = {
          width = 35,
          mappings = {
            ["<space>"] = "none",  -- free up space for leader
            ["l"] = "open",
            ["h"] = "close_node",
            ["v"] = "open_vsplit",
            ["s"] = "open_split",
            ["t"] = "open_tabnew",
            ["a"] = "add",
            ["d"] = "delete",
            ["r"] = "rename",
            ["c"] = "copy",
            ["m"] = "move",
            ["q"] = "close_window",
            ["R"] = "refresh",
            ["?"] = "show_help",
          },
        },
        filesystem = {
          filtered_items = {
            hide_dotfiles = false,   -- show dotfiles (.env, .git etc.)
            hide_gitignored = true,
            hide_by_name = { ".DS_Store", "thumbs.db" },
            always_show = { "vendor" },
            always_show_by_pattern = {
              "vendor/.*",
            },
          },
          follow_current_file = {
            enabled = true,          -- auto-expand tree to current file
          },
          use_libuv_file_watcher = true,
        },
        buffers = {
          follow_current_file = { enabled = true },
        },
        default_component_configs = {
          git_status = {
            symbols = {
              added     = "✚",
              modified  = "",
              deleted   = "✖",
              renamed   = "➜",
              untracked = "★",
              ignored   = "◌",
              unstaged  = "✗",
              staged    = "✓",
              conflict  = "",
            },
          },
        },
      })
    end,
  },

  -- ── Dashboard (start screen with recent files) ────────────
  {
    "nvimdev/dashboard-nvim",
    event = "VimEnter",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      require("dashboard").setup({
        theme = "doom",
        config = {
          header = {
            "",
            "  ███╗   ██╗███████╗ ██████╗ ██╗   ██╗██╗███╗   ███╗  ",
            "  ████╗  ██║██╔════╝██╔═══██╗██║   ██║██║████╗ ████║  ",
            "  ██╔██╗ ██║█████╗  ██║   ██║██║   ██║██║██╔████╔██║  ",
            "  ██║╚██╗██║██╔══╝  ██║   ██║╚██╗ ██╔╝██║██║╚██╔╝██║  ",
            "  ██║ ╚████║███████╗╚██████╔╝ ╚████╔╝ ██║██║ ╚═╝ ██║  ",
            "  ╚═╝  ╚═══╝╚══════╝ ╚═════╝   ╚═══╝  ╚═╝╚═╝     ╚═╝  ",
            "",
          },
          center = {
            { icon = "  ", key = "f", desc = "Find File",     action = "Telescope find_files" },
            { icon = "  ", key = "g", desc = "Live Grep",     action = "Telescope live_grep" },
            { icon = "  ", key = "r", desc = "Recent Files",  action = "Telescope oldfiles" },
            { icon = "  ", key = "e", desc = "File Tree",     action = "Neotree toggle" },
            { icon = "  ", key = "l", desc = "Lazy Plugins",  action = "Lazy" },
            { icon = "  ", key = "q", desc = "Quit",          action = "qa" },
          },
          footer = function()
            local stats = require("lazy").stats()
            return { "⚡ " .. stats.loaded .. "/" .. stats.count .. " plugins loaded" }
          end,
        },
      })
    end,
  },

  -- ── Which-key (keybinding popup — eliminates forgetting shortcuts) ─
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    config = function()
      local wk = require("which-key")
      wk.setup({
        preset = "modern",
        delay = 400,
        win = { border = "rounded" },
      })
      -- Register key group labels
      wk.add({
        { "<leader>b",  group = "Buffer" },
        { "<leader>c",  group = "Code" },
        { "<leader>f",  group = "Find (Telescope)" },
        { "<leader>g",  group = "Git" },
        { "<leader>h",  group = "Harpoon" },
        { "<leader>l",  group = "LSP" },
        { "<leader>s",  group = "Split" },
        { "<leader>t",  group = "Terminal" },
        { "<leader>x",  group = "Diagnostics (Trouble)" },
      })
    end,
  },

  -- ── Aerial: code outline (like VSCode OUTLINE panel) ──────
  {
    "stevearc/aerial.nvim",
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
      "nvim-tree/nvim-web-devicons",
    },
    keys = {
      { "<leader>cs", "<cmd>AerialToggle!<cr>", desc = "Toggle code outline" },
    },
    config = function()
      require("aerial").setup({
        layout = {
          max_width = { 40, 0.2 },
          min_width = 25,
          default_direction = "right",
        },
        attach_mode = "global",
        backends = { "treesitter", "lsp" },
        show_guides = true,
        filter_kind = {
          "Class", "Constructor", "Enum", "Function",
          "Interface", "Module", "Method", "Struct",
        },
      })
    end,
  },

}
