-- ============================================================
-- Core Vim Options
-- ============================================================

local opt = vim.opt

-- Leader keys — MUST be set before lazy.nvim loads plugins
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- ── Line Numbers ─────────────────────────────────────────────
opt.number = true           -- absolute line number on current line
opt.relativenumber = true   -- relative numbers for fast j/k jumps

-- ── Tabs & Indentation ───────────────────────────────────────
opt.tabstop = 2             -- a tab = 2 spaces (overridden per-filetype)
opt.shiftwidth = 2
opt.expandtab = true        -- convert tabs to spaces
opt.autoindent = true
opt.smartindent = true

-- ── Wrapping ─────────────────────────────────────────────────
opt.wrap = false            -- no line wrapping (horizontal scroll instead)
opt.linebreak = true        -- if wrap is enabled, break at word boundaries

-- ── Search ───────────────────────────────────────────────────
opt.ignorecase = true       -- case-insensitive search…
opt.smartcase = true        -- …unless you type uppercase
opt.hlsearch = false        -- don't keep highlighting after search
opt.incsearch = true        -- show matches as you type

-- ── Appearance ───────────────────────────────────────────────
opt.termguicolors = true    -- 24-bit colour
opt.signcolumn = "yes"      -- always show sign column (prevents layout shift)
opt.cursorline = true       -- highlight current line
opt.scrolloff = 8           -- keep 8 lines visible above/below cursor
opt.sidescrolloff = 8
opt.colorcolumn = "120"     -- ruler at 120 chars
opt.cmdheight = 1
opt.showmode = false        -- lualine shows the mode, this is redundant
opt.pumheight = 10          -- max items in completion popup
opt.conceallevel = 0        -- show `` in markdown files

-- ── Splits ───────────────────────────────────────────────────
opt.splitright = true       -- vertical splits open to the right
opt.splitbelow = true       -- horizontal splits open below

-- ── Files & Undo ─────────────────────────────────────────────
opt.swapfile = false
opt.backup = false
opt.undofile = true         -- persistent undo across sessions
opt.undodir = os.getenv("HOME") .. "/.vim/undodir"

-- ── Clipboard ────────────────────────────────────────────────
opt.clipboard = "unnamedplus"  -- use system clipboard by default

-- ── Mouse ────────────────────────────────────────────────────
opt.mouse = "a"

-- ── Performance ──────────────────────────────────────────────
opt.updatetime = 250        -- faster CursorHold events (LSP hover, gitsigns)
opt.timeoutlen = 300        -- time to wait for a mapped sequence

-- ── Completion ───────────────────────────────────────────────
opt.completeopt = { "menu", "menuone", "noselect" }
opt.shortmess:append("c")  -- don't show "match x of y" in completion

-- ── Folding (treesitter-powered) ─────────────────────────────
opt.foldmethod = "expr"
opt.foldexpr = "nvim_treesitter#foldexpr()"
opt.foldlevel = 99          -- open all folds by default

-- ── Encoding ─────────────────────────────────────────────────
opt.encoding = "utf-8"
opt.fileencoding = "utf-8"

-- ── Misc ─────────────────────────────────────────────────────
opt.formatoptions:remove({ "c", "r", "o" })  -- don't auto-insert comment leader on newline
opt.iskeyword:append("-")   -- treat hyphenated-words as one word
opt.fillchars = { eob = " " }  -- hide ~ on empty lines at end of buffer
