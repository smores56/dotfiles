-- WezTerm, shared by every desktop. Colors and font only; zsh does the rest.
local wezterm = require("wezterm")
local config = wezterm.config_builder()

config.color_scheme = "rose-pine-moon"
config.font = wezterm.font("Google Sans Code")
config.font_size = 13.0
config.hide_tab_bar_if_only_one_tab = true
config.window_close_confirmation = "NeverPrompt"

-- A login zsh: macOS has /bin/zsh; Linux gets the mise zsh at ~/.local/bin/zsh.
if wezterm.target_triple:find("darwin") then
  config.default_prog = { "/bin/zsh", "-l" }
else
  config.default_prog = { wezterm.home_dir .. "/.local/bin/zsh", "-l" }
end

return config
