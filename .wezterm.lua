-- Windows 쪽 파일: C:\Users\<user>\.wezterm.lua
-- 새 머신에서는 이 파일을 그 경로로 복사(또는 심볼릭 링크)해야 적용됨.
-- Alt+1/2/3 -> Ctrl+a(tmux prefix) + 1/2/3 -> bin/dev가 만드는 code/git/term 창 전환
local wezterm = require 'wezterm'
local config = {}
config.default_prog = { 'wsl.exe', '~' }
config.font = wezterm.font 'JetBrains Mono'
config.color_scheme = 'Dracula'
config.keys = {
  { key = '1', mods = 'ALT', action = wezterm.action.SendString '\x011' },
  { key = '2', mods = 'ALT', action = wezterm.action.SendString '\x012' },
  { key = '3', mods = 'ALT', action = wezterm.action.SendString '\x013' },
  { key = 'c', mods = 'CTRL', action = wezterm.action.CopyTo 'Clipboard' },
  { key = 'v', mods = 'CTRL', action = wezterm.action.PasteFrom 'Clipboard' },
}
return config
