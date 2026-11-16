-- WezTerm, shared by every desktop. Colors and font only; zsh does the rest.
local wezterm = require("wezterm")
local config = wezterm.config_builder()

config.color_scheme = "rose-pine-moon"
-- Same faces and size as the retired kitty setup: Regular for text, the real
-- Bold face (not synthesized) for bold.
config.font = wezterm.font("Google Sans Code", { weight = "Regular" })
config.font_rules = {
  { intensity = "Bold", italic = false, font = wezterm.font("Google Sans Code", { weight = "Bold" }) },
  { intensity = "Bold", italic = true, font = wezterm.font("Google Sans Code", { weight = "Bold", italic = true }) },
}
config.font_size = 12.0
config.hide_tab_bar_if_only_one_tab = true
config.window_close_confirmation = "NeverPrompt"

-- A login zsh: macOS has /bin/zsh; Linux gets the mise zsh at ~/.local/bin/zsh.
if wezterm.target_triple:find("darwin") then
  config.default_prog = { "/bin/zsh", "-l" }
else
  config.default_prog = { wezterm.home_dir .. "/.local/bin/zsh", "-l" }
end

return config
