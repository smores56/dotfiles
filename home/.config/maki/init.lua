maki.setup({
  always_yolo = true,
  always_thinking = "max",
  ui = {
    theme = "system",
  },
  -- allowed_models also bounds CLI/API model changes and delegation.
  provider = {
    default_model = "neuralwatt/deepseek-v4.1-flash",
    allowed_models = {
      "neuralwatt/deepseek-v4.1-flash",
      "neuralwatt/qwen-3.8-27b",
      "neuralwatt/kimi-k3.1-pro",
    },
  },
  plugins = {
    -- The bundled websearch cannot speak TinyFish, which mcp.toml provides.
    websearch = { enabled = false },
  },
})

-- Plan mode is never wanted here, and Tab's default toggles it. Accept a
-- completion or ghost text as usual, then swallow the key instead of falling
-- back to the host's plan/build switch.
maki.keymap.set({ "n", "i" }, "<Tab>", function()
  if maki.ui.action("completion.accept") then return end
  if maki.ui.action("ghost.accept") then return end
end)

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
