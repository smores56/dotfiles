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

-- Zellij names single-pane tabs after the pane's OSC title, so keep it short:
-- the sushi marks a maki tab, and the slug is a weak model's read of what the
-- session is about, made at the first prompt and again whenever the agent stops.
local SUSHI = "🍣"
-- Custom providers carry no curated tiers, so tier("weak") resolves to nil.
local WEAK_MODEL = "neuralwatt/qwen-3.8-27b"
local MAX_SLUG = 32

local first_prompt, latest_prompt, latest_reply = {}, {}, {}
local slugs, sluggers, busy, dirty = {}, {}, {}, {}

local function slugify(text)
  -- The model is told to answer with just a slug, but drop a "Slug:" label or
  -- backticks and ignore anything past the first line in case it decorates it.
  local line = ((text or ""):lower():gsub("`", ""):match("[^\r\n]+") or "")
  line = line:gsub("^%s*slug:%s*", ""):gsub("^%s+", "")
  local words = {}
  for w in line:gmatch("%w+") do
    words[#words + 1] = w
    if #words == 4 then break end
  end
  local slug = table.concat(words, "-")
  if #slug > MAX_SLUG then
    slug = slug:sub(1, MAX_SLUG):gsub("%-%w*$", "")
  end
  return slug
end

local function apply_title()
  local s = maki.session.read()
  if not s then return end
  local slug = slugs[s.id]
  if not slug then
    -- A session this process did not see start (resumed, or after /reload)
    -- still carries maki's auto title, which is its first prompt.
    slug = s.title ~= "New session" and slugify(s.title) or "maki"
  end
  if slug == "" then slug = "maki" end
  maki.ui.set_window_title(SUSHI .. ": " .. slug)
end

local function generate(sid)
  if busy[sid] then
    dirty[sid] = true
    return
  end
  local parts = {}
  if first_prompt[sid] then
    parts[#parts + 1] = "Session started with: " .. first_prompt[sid]
  end
  if latest_prompt[sid] and latest_prompt[sid] ~= first_prompt[sid] then
    parts[#parts + 1] = "Latest request: " .. latest_prompt[sid]
  end
  if latest_reply[sid] then
    parts[#parts + 1] = "Latest answer: " .. latest_reply[sid]
  end
  if #parts == 0 then return end
  busy[sid] = true
  maki.async.spawn(function()
    local sess = sluggers[sid]
    if not sess then
      local weak = maki.model.tier("weak")
      sess = maki.agent.session({
        session = sid,
        scope = "session",
        name = "sushi-title",
        thinking = "off",
        model_spec = weak and weak.spec or WEAK_MODEL,
        system = "You name coding sessions. Reply with only a URL slug: 2 to 4 "
          .. "lowercase words joined by hyphens, at most " .. MAX_SLUG
          .. " characters. No quotes, punctuation, or explanation.",
      })
      if not sess then
        busy[sid] = false
        return
      end
      sluggers[sid] = sess
    end
    local r, err = sess:prompt(table.concat(parts, "\n\n") .. "\n\nSlug:")
    busy[sid] = false
    if err then
      sluggers[sid] = nil
    elseif r then
      local slug = slugify(r.text)
      if slug ~= "" then
        slugs[sid] = slug
        apply_title()
      end
    end
    if dirty[sid] then
      dirty[sid] = false
      generate(sid)
    end
  end)
end

local function reply_text(msg)
  local out = {}
  for _, block in ipairs(msg and msg.content or {}) do
    if block.type == "text" and block.text then
      out[#out + 1] = block.text
    end
  end
  return table.concat(out, "\n")
end

maki.api.create_autocmd("SessionFocusChanged", { callback = apply_title })

maki.api.create_autocmd("TurnStart", { callback = function(ev)
  local sid, text = ev.data.session_id, ev.data.text
  if not sid or not text then return end
  latest_prompt[sid] = text
  if first_prompt[sid] then return end
  first_prompt[sid] = text
  slugs[sid] = slugify(text)
  apply_title()
  generate(sid)
end })

maki.api.create_autocmd("TurnComplete", { callback = function(ev)
  if ev.data.id then return end -- a subagent's reply, not the chat's
  local sid = ev.data.session_id
  if not sid then return end
  local text = reply_text(ev.data.message)
  if text ~= "" then latest_reply[sid] = text:sub(1, 800) end
end })

maki.api.create_autocmd("TurnEnd", { callback = function(ev)
  local sid = ev.data.session_id
  if sid and ev.data.reason ~= "dropped" then generate(sid) end
end })

maki.api.create_autocmd({ "SessionEnd", "SessionReset" }, { callback = function(ev)
  local sid = ev.data.session_id
  if sid then
    local sess = sluggers[sid]
    if sess then sess:close() end
    first_prompt[sid], latest_prompt[sid], latest_reply[sid] = nil, nil, nil
    slugs[sid], sluggers[sid], busy[sid], dirty[sid] = nil, nil, nil, nil
  end
  apply_title()
end })
