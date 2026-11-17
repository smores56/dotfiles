-- Maki talks directly to Neuralwatt (models); TinyFish search arrives over
-- MCP from mcp.toml. Keys come from ~/.config/secrets.env.

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
  plugins = {
    -- The bundled websearch only speaks Exa/You.com/Kagi/SearXNG; TinyFish
    -- arrives as MCP tools instead (mcp.toml). Memory keeps its bundled
    -- default, so leaving it out enables it.
    websearch = { enabled = false },
  },
})

-- TinyFish's MCP server ships wallet, monitor, and browser-automation tools.
-- A deny rule cannot say "everything but search", and always_yolo bypasses a
-- per-server default, so stop the rest here. plugin.toml carries the grants
-- maki requires for a layer on tools that declare no permission.
maki.api.set_slot("tool.*.input", function(prev, input, ctx)
  if ctx.tool:sub(1, 10) == "tinyfish__" and ctx.tool ~= "tinyfish__search" then
    return nil, "Only the TinyFish `search` tool is available; the rest of the server is denied."
  end
  return prev(input, ctx)
end)
