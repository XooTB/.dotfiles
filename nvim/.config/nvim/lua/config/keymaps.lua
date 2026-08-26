-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

vim.keymap.set("n", "<C-Left>", "<cmd>vertical resize -5<CR>", {desc = "Decrease window width"})
vim.keymap.set("n", "<C-Right>", "<cmd>vertical resize +5<CR>", {desc = "Increase window width"})
