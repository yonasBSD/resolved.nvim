-- vim: ft=lua
std = "luajit"
globals = { "vim" }
read_globals = { "vim" }
max_line_length = false
codes = true

exclude_files = {
  ".luarocks",
  ".install",
}

ignore = {
  "212", -- unused argument (common in callbacks)
}
