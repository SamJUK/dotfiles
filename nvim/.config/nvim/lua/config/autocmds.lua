-- ============================================================
-- Autocommands
-- ============================================================

local augroup = vim.api.nvim_create_augroup
local autocmd = vim.api.nvim_create_autocmd

-- ── Flash yanked text ─────────────────────────────────────────
autocmd("TextYankPost", {
  group = augroup("highlight_yank", { clear = true }),
  callback = function()
    vim.hl.on_yank({ higroup = "IncSearch", timeout = 150 })
  end,
})

-- Trailing whitespace is trimmed on save by conform.nvim (diagnostics.lua)

-- ── Equalise splits when Neovim window is resized ────────────
autocmd("VimResized", {
  group = augroup("resize_splits", { clear = true }),
  callback = function()
    vim.cmd("tabdo wincmd =")
  end,
})

-- ── Return to last cursor position when reopening a file ─────
autocmd("BufReadPost", {
  group = augroup("last_position", { clear = true }),
  callback = function()
    local mark = vim.api.nvim_buf_get_mark(0, '"')
    local lcount = vim.api.nvim_buf_line_count(0)
    if mark[1] > 0 and mark[1] <= lcount then
      pcall(vim.api.nvim_win_set_cursor, 0, mark)
    end
  end,
})

-- ── Auto-create parent directories when saving a new file ────
autocmd("BufWritePre", {
  group = augroup("auto_create_dirs", { clear = true }),
  callback = function(event)
    if event.match:match("^%w%w+://") then return end
    local file = vim.uv.fs_realpath(event.match) or event.match
    vim.fn.mkdir(vim.fn.fnamemodify(file, ":p:h"), "p")
  end,
})

-- ── 4-space default: PHP (PSR-12), Magento XML, and shell ────
-- Only a default for new files: guess-indent.nvim then matches each
-- existing file's own indentation, and .editorconfig beats both
autocmd("FileType", {
  group = augroup("four_space_indent", { clear = true }),
  pattern = { "php", "xml", "sh", "bash" },
  callback = function()
    vim.opt_local.tabstop = 4
    vim.opt_local.shiftwidth = 4
  end,
})

-- ── Treat hyphenated-words as one word where names are kebab-case
-- (not globally: in PHP `ciw` on $this->foo would eat the `-`) ──
autocmd("FileType", {
  group = augroup("kebab_case_words", { clear = true }),
  pattern = { "css", "scss", "less", "html" },
  callback = function()
    vim.opt_local.iskeyword:append("-")
  end,
})

-- ── Go: use tabs (gofmt standard) ────────────────────────────
autocmd("FileType", {
  group = augroup("go_settings", { clear = true }),
  pattern = "go",
  callback = function()
    vim.opt_local.expandtab = false
    vim.opt_local.tabstop = 4
    vim.opt_local.shiftwidth = 4
  end,
})

-- ── Close certain filetypes with just 'q' ────────────────────
autocmd("FileType", {
  group = augroup("close_with_q", { clear = true }),
  pattern = { "help", "lspinfo", "man", "qf", "checkhealth", "notify", "query" },
  callback = function(event)
    vim.bo[event.buf].buflisted = false
    vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = event.buf, silent = true })
  end,
})

-- ── Don't auto-insert comment leader on new lines ────────────
autocmd("FileType", {
  group = augroup("no_auto_comment", { clear = true }),
  pattern = "*",
  callback = function()
    vim.opt_local.formatoptions:remove({ "c", "r", "o" })
  end,
})

-- ── Spell check for markdown and git commit messages ─────────
autocmd("FileType", {
  group = augroup("spell_check", { clear = true }),
  pattern = { "markdown", "gitcommit" },
  callback = function()
    vim.opt_local.spell = true
    vim.opt_local.spelllang = "en_gb"
  end,
})
