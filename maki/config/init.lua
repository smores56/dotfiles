-- Maki configuration, symlinked by install.sh to ~/.config/maki/init.lua.
--
-- Maki talks directly to Neuralwatt (models) and TinyFish (web search) with
-- keys from ~/.config/secrets.env. There is no capability broker, no agent VM,
-- and no memory service. Edit this file in the dotfiles repo, not in $HOME.

maki.setup({
  always_yolo = true,
  always_thinking = "max",
  -- Follow the terminal's ANSI palette so Maki inherits the desktop theme.
  ui = {
    theme = "system",
  },
  -- Only the declared Neuralwatt models. allowed_models wins for selectors,
  -- CLI/API model changes, delegation, and `maki models`.
  provider = {
    default_model = "neuralwatt/deepseek-v4.1-flash",
    allowed_models = {
      "neuralwatt/deepseek-v4.1-flash",
      "neuralwatt/qwen-3.8-27b",
      "neuralwatt/kimi-k3.1-pro",
    },
  },
  -- Search uses the TinyFish Search API over https; no private host allowlist.
  net = {
    allowed_private_hosts = {},
  },
  plugins = {
    bash = { enabled = true },
    -- The bundled websearch only speaks Exa/You.com; websearch_owned.lua below
    -- reclaims the tool name and calls TinyFish instead.
    websearch = { enabled = false },
    memory = { enabled = false },
  },
})

require("websearch_owned")
