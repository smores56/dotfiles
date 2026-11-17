-- WezTerm on macOS. Colors and font only; zsh does the rest.
local wezterm = require("wezterm")
local config = wezterm.config_builder()

config.color_scheme = "rose-pine-moon"
-- The real Bold face, not a synthesized one.
config.font = wezterm.font("Google Sans Code", { weight = "Regular" })
config.font_rules = {
  { intensity = "Bold", italic = false, font = wezterm.font("Google Sans Code", { weight = "Bold" }) },
  { intensity = "Bold", italic = true, font = wezterm.font("Google Sans Code", { weight = "Bold", italic = true }) },
}
config.font_size = 14.0
-- WezTerm rasterizes with FreeType even on macOS; full hinting snaps stems to
-- the pixel grid and looks thin and grainy next to CoreText. Light, unhinted
-- loading on the GPU renderer is close to native macOS text.
config.front_end = "WebGpu"
config.freetype_load_target = "Light"
config.freetype_load_flags = "NO_HINTING"

config.window_background_opacity = 0.95
config.window_decorations = "RESIZE"
config.audible_bell = "Disabled"
config.visual_bell = {
  fade_in_duration_ms = 75,
  fade_out_duration_ms = 75,
}
-- Both Option keys are Alt for the shell and editors.
config.send_composed_key_when_left_alt_is_pressed = false
config.send_composed_key_when_right_alt_is_pressed = false
config.hide_tab_bar_if_only_one_tab = true
config.window_close_confirmation = "NeverPrompt"

config.default_prog = { "/bin/zsh", "-l" }

return config
