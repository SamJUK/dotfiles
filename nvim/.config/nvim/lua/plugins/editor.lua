-- ============================================================
-- Editor Enhancements
-- autopairs, surround, comments, indent guides, colour preview,
-- todo-comments, illuminate, harpoon, toggleterm
-- ============================================================

return {

  -- ── Auto-pairs: close brackets/quotes automatically ───────
  {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    config = function()
      local autopairs = require("nvim-autopairs")
      autopairs.setup({
        check_ts = true,  -- use treesitter for smarter pairing
        ts_config = {
          lua  = { "string" },  -- don't pair inside strings
          php  = { "template_string" },
          javascript = { "template_string", "string" },
        },
        disable_filetype = { "TelescopePrompt" },
      })
      -- Connect autopairs to nvim-cmp: add `(` after confirming a function
      local cmp_autopairs = require("nvim-autopairs.completion.cmp")
      local cmp = require("cmp")
      cmp.event:on("confirm_done", cmp_autopairs.on_confirm_done())
    end,
  },

  -- ── Surround: add/change/delete surrounding chars ─────────
  -- Examples: cs"'  →  change " to '
  --           ysiw(  →  wrap word in ()
  --           ds"    →  delete surrounding "
  {
    "kylechui/nvim-surround",
    event   = "VeryLazy",
    version = "*",
    config  = function()
      require("nvim-surround").setup()
    end,
  },

  -- ── Comments: gcc to toggle, gc in visual mode ────────────
  {
    "numToStr/Comment.nvim",
    event = "VeryLazy",
    config = function()
      require("Comment").setup({
        -- PHP-aware block comments
        pre_hook = require("ts_context_commentstring.integrations.comment_nvim").create_pre_hook(),
      })
    end,
    dependencies = { "JoosepAlviste/nvim-ts-context-commentstring" },
  },

  -- ── ts-context-commentstring: correct comment type per context ─
  -- e.g. // in JS, # in PHP, <!-- --> in HTML inside .php files
  {
    "JoosepAlviste/nvim-ts-context-commentstring",
    lazy = true,
    config = function()
      require("ts_context_commentstring").setup({ enable_autocmd = false })
    end,
  },

  -- ── Indent guides ─────────────────────────────────────────
  {
    "lukas-reineke/indent-blankline.nvim",
    event = { "BufReadPost", "BufNewFile" },
    main  = "ibl",
    config = function()
      require("ibl").setup({
        indent = {
          char      = "│",
          tab_char  = "│",
        },
        scope = {
          enabled   = true,   -- highlight the current scope's indent line
          show_start = true,
          show_end   = false,
        },
        exclude = {
          filetypes = {
            "help", "dashboard", "neo-tree", "Trouble", "lazy", "mason",
            "notify", "toggleterm",
          },
        },
      })
    end,
  },

  -- ── Colour preview: see #fff / rgb() as actual colours ────
  {
    "brenoprata10/nvim-highlight-colors",
    event = { "BufReadPost", "BufNewFile" },
    config = function()
      require("nvim-highlight-colors").setup({
        render = "background",  -- "background" | "foreground" | "virtual"
        enable_named_colors = true,  -- red, blue, etc.
        enable_tailwind     = true,  -- Tailwind CSS classes (if you use them)
      })
    end,
  },

  -- ── TODO/FIXME/NOTE highlights ────────────────────────────
  {
    "folke/todo-comments.nvim",
    event        = { "BufReadPost", "BufNewFile" },
    dependencies = { "nvim-lua/plenary.nvim" },
    keys = {
      { "<leader>ft",  "<cmd>TodoTelescope<cr>",           desc = "Find TODOs" },
      { "<leader>xt",  "<cmd>Trouble todo toggle<cr>",     desc = "TODOs (Trouble)" },
      { "]t",          function() require("todo-comments").jump_next() end, desc = "Next TODO" },
      { "[t",          function() require("todo-comments").jump_prev() end, desc = "Prev TODO" },
    },
    config = function()
      require("todo-comments").setup({
        signs     = true,
        highlight = { multiline = false },
      })
    end,
  },

  -- ── Illuminate: highlight all uses of word under cursor ───
  {
    "RRethy/vim-illuminate",
    event = { "BufReadPost", "BufNewFile" },
    config = function()
      require("illuminate").configure({
        providers = { "lsp", "treesitter", "regex" },
        delay     = 200,
        filetypes_denylist = { "neo-tree", "dashboard", "Trouble", "lazy" },
        under_cursor = true,
      })
    end,
  },

  -- ── Harpoon v2: bookmark & jump to key files instantly ────
  -- Ideal when you're working across 3-5 files constantly
  -- <leader>ha to add, <leader>hh to open menu, <leader>1-5 to jump
  {
    "ThePrimeagen/harpoon",
    branch       = "harpoon2",
    dependencies = { "nvim-lua/plenary.nvim" },
    event        = "VeryLazy",
    config = function()
      local harpoon = require("harpoon")
      harpoon:setup({
        settings = {
          save_on_toggle = true,
          sync_on_ui_close = true,
        },
      })

      local map = vim.keymap.set
      map("n", "<leader>ha", function() harpoon:list():add() end,
          { desc = "Harpoon: add file" })
      map("n", "<leader>hh", function() harpoon.ui:toggle_quick_menu(harpoon:list()) end,
          { desc = "Harpoon: open menu" })
      map("n", "<leader>hn", function() harpoon:list():next() end,
          { desc = "Harpoon: next file" })
      map("n", "<leader>hp", function() harpoon:list():prev() end,
          { desc = "Harpoon: prev file" })

      -- Jump to pinned files with <leader>1 through <leader>5
      for i = 1, 5 do
        map("n", "<leader>" .. i, function() harpoon:list():select(i) end,
            { desc = "Harpoon: jump to file " .. i })
      end
    end,
  },

  -- ── Toggleterm: floating/split terminal ───────────────────
  {
    "akinsho/toggleterm.nvim",
    version = "*",
    keys = {
      { "<C-\\>", desc = "Toggle terminal" },
      { "<leader>tf", "<cmd>ToggleTerm direction=float<cr>",      desc = "Terminal float" },
      { "<leader>th", "<cmd>ToggleTerm direction=horizontal<cr>", desc = "Terminal horizontal" },
      { "<leader>tv", "<cmd>ToggleTerm direction=vertical<cr>",   desc = "Terminal vertical" },
    },
    config = function()
      require("toggleterm").setup({
        size = function(term)
          if term.direction == "horizontal" then return 15
          elseif term.direction == "vertical" then return vim.o.columns * 0.4
          end
        end,
        open_mapping    = [[<C-\>]],
        hide_numbers    = true,
        shade_terminals = true,
        shading_factor  = 2,
        start_in_insert = true,
        insert_mappings = true,
        persist_size    = true,
        direction       = "float",
        close_on_exit   = true,
        shell           = vim.o.shell,
        float_opts = {
          border   = "curved",
          winblend = 3,
        },
        -- <Esc> or <C-\> exits terminal mode back to normal mode
        on_open = function(term)
          vim.keymap.set("t", "<Esc>", "<C-\\><C-n>",
            { buffer = term.bufnr, desc = "Exit terminal mode" })
          vim.keymap.set("t", "<C-\\>", "<C-\\><C-n>:ToggleTerm<CR>",
            { buffer = term.bufnr, desc = "Toggle terminal" })
        end,
      })
    end,
  },

  -- ── Mini.nvim: small utility plugins from echasnovski ─────
  -- Using mini.ai for better text objects (very useful!)
  {
    "echasnovski/mini.ai",
    event   = "VeryLazy",
    version = "*",
    config  = function()
      require("mini.ai").setup({ n_lines = 500 })
    end,
  },

}
