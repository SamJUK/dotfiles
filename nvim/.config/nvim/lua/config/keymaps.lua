-- ============================================================
-- Global Keymaps (non-plugin)
-- Plugin-specific keymaps live inside each plugin's spec.
-- ============================================================

local map = vim.keymap.set

-- ── Window Navigation (like VSCode Ctrl+pane) ────────────────
map("n", "<C-h>", "<C-w>h", { desc = "Move to left window" })
map("n", "<C-j>", "<C-w>j", { desc = "Move to lower window" })
map("n", "<C-k>", "<C-w>k", { desc = "Move to upper window" })
map("n", "<C-l>", "<C-w>l", { desc = "Move to right window" })

-- ── Window Resizing ──────────────────────────────────────────
map("n", "<C-Up>",    ":resize -2<CR>",          { desc = "Decrease window height", silent = true })
map("n", "<C-Down>",  ":resize +2<CR>",          { desc = "Increase window height", silent = true })
map("n", "<C-Left>",  ":vertical resize -2<CR>", { desc = "Decrease window width",  silent = true })
map("n", "<C-Right>", ":vertical resize +2<CR>", { desc = "Increase window width",  silent = true })

-- ── Buffer Navigation (like VSCode Ctrl+Tab) ─────────────────
map("n", "<S-l>",       ":bnext<CR>",                         { desc = "Next buffer",              silent = true })
map("n", "<S-h>",       ":bprevious<CR>",                     { desc = "Previous buffer",          silent = true })
map("n", "<leader>bd",  ":bdelete<CR>",                       { desc = "Close buffer",             silent = true })
map("n", "<leader>bD",  ":%bdelete|edit#|bdelete#<CR>",       { desc = "Close all other buffers",  silent = true })
map("n", "<leader>.",   "<C-^>",                              { desc = "Switch to alternate file" })

-- ── Splits ───────────────────────────────────────────────────
map("n", "<leader>sv", "<C-w>v",      { desc = "Split vertical" })
map("n", "<leader>sh", "<C-w>s",      { desc = "Split horizontal" })
map("n", "<leader>se", "<C-w>=",      { desc = "Equalise splits" })
map("n", "<leader>sx", ":close<CR>",  { desc = "Close split", silent = true })

-- ── Indenting in visual mode (stay in visual after indent) ───
map("v", "<", "<gv", { desc = "Indent left" })
map("v", ">", ">gv", { desc = "Indent right" })

-- ── Move lines up/down (like VSCode Alt+↑/↓) ─────────────────
map("n", "<A-j>", ":m .+1<CR>==",        { desc = "Move line down",       silent = true })
map("n", "<A-k>", ":m .-2<CR>==",        { desc = "Move line up",         silent = true })
map("v", "<A-j>", ":m '>+1<CR>gv=gv",   { desc = "Move selection down",  silent = true })
map("v", "<A-k>", ":m '<-2<CR>gv=gv",   { desc = "Move selection up",    silent = true })

-- ── Paste without yanking the replaced text ──────────────────
map("v", "p", '"_dP', { desc = "Paste without yanking" })

-- ── Keep search results centred ──────────────────────────────
map("n", "n", "nzzzv", { desc = "Next result (centred)" })
map("n", "N", "Nzzzv", { desc = "Prev result (centred)" })

-- ── Clear search highlight ───────────────────────────────────
map("n", "<Esc>", ":nohlsearch<CR>", { desc = "Clear search highlight", silent = true })

-- ── Save / Quit ──────────────────────────────────────────────
map("n", "<leader>w",  ":w<CR>",   { desc = "Save file",      silent = true })
map("n", "<leader>q",  ":q<CR>",   { desc = "Quit",           silent = true })
map("n", "<leader>Q",  ":qa!<CR>", { desc = "Force quit all", silent = true })

-- ── Select all (like Ctrl+A in VSCode) ───────────────────────
map("n", "<C-a>", "ggVG", { desc = "Select all" })

-- ── Better J (keep cursor in place when joining lines) ───────
map("n", "J", "mzJ`z", { desc = "Join lines (keep cursor)" })

-- ── Add blank line above/below without entering insert mode ──
map("n", "<leader>o", "o<Esc>", { desc = "Add blank line below" })
map("n", "<leader>O", "O<Esc>", { desc = "Add blank line above" })
