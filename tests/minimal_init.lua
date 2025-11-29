-- Minimal init for running tests
vim.opt.rtp:append(".")
vim.opt.rtp:append(vim.fn.stdpath("data") .. "/lazy/plenary.nvim")

vim.cmd([[runtime plugin/plenary.vim]])

vim.o.swapfile = false
vim.bo.swapfile = false
