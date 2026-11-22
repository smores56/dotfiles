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
-- Enough of the conversation to name the work without paying for all of it.
local CONTEXT_MSGS = 12
local CONTEXT_CHARS = 2400

local first_prompt, latest_prompt, latest_reply = {}, {}, {}
local slugs, sluggers, busy, dirty = {}, {}, {}, {}

-- A prompt that only nudges the agent along names nothing, and neither does a
-- slug squeezed out of one. A session resumed after a stall opens with these.
local CONTINUATIONS = {
  ["continue"] = true,
  ["go on"] = true,
  ["keep going"] = true,
  ["carry on"] = true,
  ["keep at it"] = true,
  ["try again"] = true,
  ["one more"] = true,
  ["resume"] = true,
  ["proceed"] = true,
  ["retry"] = true,
  ["next"] = true,
  ["yes"] = true,
  ["ok"] = true,
  ["do it"] = true,
  ["more"] = true,
}

local function squeeze(text)
  return (text or ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

local function normalize(text)
  return squeeze((text or ""):lower():gsub("%p+", " "))
end

local function is_continuation(text)
  local norm = normalize(text)
  if CONTINUATIONS[norm] then return true end
  -- One or two bare words are an answer or a nudge, not a subject.
  local words = 0
  for _ in norm:gmatch("%a+") do
    words = words + 1
    if words > 2 then return false end
  end
  return #norm <= 24
end

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

-- Clean-bare checkouts sit in <repo>/<branch>, where the branch says nothing
-- and the repo name says what the work is.
local BRANCH_DIRS = { main = true, master = true, dev = true, develop = true, trunk = true }

local function dir_slug(dir)
  if not dir or dir == "" then return "" end
  local base = maki.fs.basename(dir)
  if BRANCH_DIRS[base] then base = maki.fs.basename(maki.fs.dirname(dir)) end
  return slugify(base)
end

-- The project directory always says something, so it is the title of last
-- resort for a session nothing has named yet.
local function project_slug(sid)
  local s = maki.session.read({ session = sid })
  return dir_slug(s and s.cwd)
end

local function apply_title()
  local s = maki.session.read()
  if not s then return end
  local slug = slugs[s.id]
  if not slug then
    -- A session this process did not see start (resumed, or after /reload)
    -- still carries maki's auto title, which is its first prompt.
    local title = s.title ~= "New session" and s.title or nil
    if title and not is_continuation(title) then slug = slugify(title) end
    if not slug or slug == "" then slug = project_slug(s.id) end
  end
  if slug == "" then slug = "maki" end
  maki.ui.set_window_title(SUSHI .. ": " .. slug)
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

local NAMELESS = { session = true, chat = true, conversation = true, task = true }

-- True for a slug that could have come from "continue" alone.
local function names_nothing(slug)
  for w in slug:gmatch("%a+") do
    if not (CONTINUATIONS[w] or NAMELESS[w]) then return false end
  end
  return true
end

-- What a session is about lives in its transcript, not in the newest message,
-- so read the recent turns instead of the prompt that triggered this run. Tool
-- traffic is noise for a title, and reply_text drops it.
local function transcript(sid)
  local msgs = maki.session.messages({ session = sid, last = CONTEXT_MSGS })
  if not msgs then return nil end
  local lines, total = {}, 0
  for _, m in ipairs(msgs) do
    -- A plain turn leaves `kind` null, so name the two report kinds to skip.
    local kind = m.kind
    if kind ~= "observation" and kind ~= "context_update" and m.display_text ~= "" then
      local text = squeeze(reply_text(m))
      if text ~= "" then
        -- The user's own words name the work; the assistant's prose is
        -- supporting detail, so it gets the shorter cut.
        local cap = m.role == "user" and 400 or 200
        local line = (m.role == "user" and "User: " or "Assistant: ") .. text:sub(1, cap)
        lines[#lines + 1] = line
        total = total + #line
        if total >= CONTEXT_CHARS then break end
      end
    end
  end
  return #lines > 0 and table.concat(lines, "\n") or nil
end

local function generate(sid)
  if busy[sid] then
    dirty[sid] = true
    return
  end
  busy[sid] = true
  maki.async.spawn(function()
    local body = transcript(sid)
    if not body then
      -- No transcript to read yet, so use what the autocmds saw.
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
      body = #parts > 0 and table.concat(parts, "\n\n") or nil
    end
    if not body then
      busy[sid] = false
      return
    end
    local sess = sluggers[sid]
    if not sess then
      local weak = maki.model.tier("weak")
      sess = maki.agent.session({
        session = sid,
        scope = "session",
        name = "sushi-title",
        thinking = "off",
        model_spec = weak and weak.spec or WEAK_MODEL,
        system = "You title coding sessions. Reply with only a URL slug: 2 to 4 "
          .. "lowercase words joined by hyphens, at most " .. MAX_SLUG
          .. " characters, naming the project, files, or task the session "
          .. "works on. Take that subject from the transcript, even when the "
          .. "newest message only says \"continue\". Reuse the current slug "
          .. "when it already fits. No quotes, punctuation, or explanation.",
      })
      if not sess then
        busy[sid] = false
        return
      end
      sluggers[sid] = sess
    end
    local request = {}
    local s = maki.session.read({ session = sid })
    if s and s.cwd then request[#request + 1] = "Working directory: " .. s.cwd end
    if slugs[sid] then request[#request + 1] = "Current slug: " .. slugs[sid] end
    request[#request + 1] = "Transcript:\n" .. body
    request[#request + 1] = "Slug:"
    local r, err = sess:prompt(table.concat(request, "\n\n"))
    busy[sid] = false
    if err then
      sluggers[sid] = nil
    elseif r then
      local slug = slugify(r.text)
      -- Keep the previous slug rather than let a nameless one through.
      if slug ~= "" and not names_nothing(slug) then
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

maki.api.create_autocmd("SessionFocusChanged", { callback = apply_title })

maki.api.create_autocmd("TurnStart", { callback = function(ev)
  local sid, text = ev.data.session_id, ev.data.text
  if not sid or not text then return end
  latest_prompt[sid] = text
  if first_prompt[sid] then return end
  first_prompt[sid] = text
  -- A bare nudge must not become the tab title: apply_title falls back to the
  -- project directory until the slugger has read the transcript.
  if not is_continuation(text) then
    slugs[sid] = slugify(text)
    apply_title()
  end
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
