-- Custom providers carry no curated tiers, so tier("weak") resolves to nil.
local WEAK_MODEL = "neuralwatt/qwen-3.8-27b"

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
      WEAK_MODEL,
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
local MAX_SLUG = 32
-- A tool-heavy turn spends messages without saying anything, so read deep and
-- keep only the newest text that fits the budget.
local CONTEXT_MSGS = 60
local CONTEXT_CHARS = 2400

local first_prompt, latest_prompt = {}, {}
local slugs, sluggers, busy, dirty = {}, {}, {}, {}

-- A prompt that only nudges the agent along names nothing, and neither does a
-- slug built from the same words. A session resumed after a stall starts with
-- one.
local NUDGE_WORDS = {
  ["continue"] = true, ["go"] = true, ["on"] = true, ["keep"] = true,
  ["going"] = true, ["carry"] = true, ["at"] = true, ["it"] = true,
  ["try"] = true, ["again"] = true, ["retry"] = true, ["one"] = true,
  ["more"] = true, ["resume"] = true, ["proceed"] = true, ["next"] = true,
  ["yes"] = true, ["ok"] = true, ["do"] = true, ["please"] = true,
}
-- Words that fill a name rather than name anything.
local VAGUE = { session = true, chat = true, conversation = true, task = true }

local function squeeze(text)
  return (text or ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

local function every_word_in(text, allowed)
  local seen = false
  for w in (text or ""):gmatch("%a+") do
    if not allowed[w] then return false end
    seen = true
  end
  return seen
end

local function is_nudge(text)
  local norm = squeeze((text or ""):lower():gsub("%p+", " "))
  return norm == "" or (#norm <= 24 and every_word_in(norm, NUDGE_WORDS))
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

local function apply_title()
  local s = maki.session.read()
  if not s then return end
  local slug = slugs[s.id]
  if not slug then
    -- A session this process did not see start (resumed, or after /reload)
    -- still carries maki's auto title, which is its first prompt. When that
    -- says nothing, the project directory is the hint at hand.
    local title = type(s.title) == "string" and s.title or ""
    if title ~= "New session" and not is_nudge(title) then slug = slugify(title) end
    if not slug or slug == "" then slug = dir_slug(s.cwd) end
  end
  if slug == "" then slug = "maki" end
  maki.ui.set_window_title(SUSHI .. ": " .. slug)
end

local function reply_text(msg)
  local out = {}
  for _, block in ipairs(msg and msg.content or {}) do
    if block.type == "text" and type(block.text) == "string" then
      out[#out + 1] = block.text
    end
  end
  return table.concat(out, "\n")
end

-- True for a slug that says only what the person already typed.
local function names_nothing(slug)
  for w in (slug or ""):gmatch("%a+") do
    if not (NUDGE_WORDS[w] or VAGUE[w]) then return false end
  end
  return true
end

-- Cut to a byte budget without leaving half a UTF-8 character behind.
local function clip(text, max)
  if #text <= max then return text end
  return (maki.text.to_utf8(text:sub(1, max)):gsub("\239\191\189+$", ""))
end

-- What a session is about lives in its transcript, not in the newest message,
-- so read the recent turns. Tool traffic is noise for a title, and reply_text
-- drops it.
local function transcript(sid)
  local msgs = maki.session.messages({ session = sid, last = CONTEXT_MSGS })
  if not msgs then return nil end
  local lines, total = {}, 0
  -- Newest first: the work being done now is what must survive the budget.
  for i = #msgs, 1, -1 do
    local m = msgs[i]
    -- A plain turn leaves `kind` null, so name the two report kinds to skip.
    local kind = m.kind
    if kind ~= "observation" and kind ~= "context_update" and m.display_text ~= "" then
      -- The user's own words name the work; the assistant's prose is
      -- supporting detail, so it gets the shorter cut.
      local text = squeeze(clip(reply_text(m), m.role == "user" and 400 or 200))
      if text ~= "" then
        table.insert(lines, 1, (m.role == "user" and "User: " or "Assistant: ") .. text)
        total = total + #text
        if total >= CONTEXT_CHARS then break end
      end
    end
  end
  return #lines > 0 and table.concat(lines, "\n") or nil
end

local function slugger(sid)
  local sess = sluggers[sid]
  if sess then return sess end
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
  sluggers[sid] = sess
  return sess
end

local function naming_request(sid)
  local body = transcript(sid)
  if not body then
    -- No transcript to read, so use what the autocmds saw.
    local parts = {}
    if first_prompt[sid] then
      parts[#parts + 1] = "Session started with: " .. first_prompt[sid]
    end
    if latest_prompt[sid] and latest_prompt[sid] ~= first_prompt[sid] then
      parts[#parts + 1] = "Latest request: " .. latest_prompt[sid]
    end
    body = #parts > 0 and table.concat(parts, "\n\n") or nil
  end
  if not body then return nil end
  local out = {}
  local s = maki.session.read({ session = sid })
  if s and s.cwd then out[#out + 1] = "Working directory: " .. s.cwd end
  if slugs[sid] then out[#out + 1] = "Current slug: " .. slugs[sid] end
  out[#out + 1] = "Transcript:\n" .. body
  out[#out + 1] = "Slug:"
  return table.concat(out, "\n\n")
end

local function retitle(sid)
  local sess = slugger(sid)
  local text = sess and naming_request(sid)
  if not text then return end
  local r, err = sess:prompt(text)
  if err then
    sluggers[sid] = nil
    return
  end
  if not sluggers[sid] then return end -- the session ended under the prompt
  local slug = r and slugify(r.text) or ""
  -- Keep the previous slug rather than let a nameless one through.
  if slug ~= "" and not names_nothing(slug) then
    slugs[sid] = slug
    apply_title()
  end
end

local function generate(sid)
  if busy[sid] then
    dirty[sid] = true
    return
  end
  busy[sid] = true
  maki.async.spawn(function()
    -- One tail, so a raise anywhere in naming cannot wedge the session.
    pcall(retitle, sid)
    busy[sid] = false
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
  if not is_nudge(text) then
    slugs[sid] = slugify(text)
    apply_title()
  end
  generate(sid)
end })

local function forget(sid)
  local sess = sluggers[sid]
  if sess then sess:close() end
  first_prompt[sid], latest_prompt[sid] = nil, nil
  slugs[sid], sluggers[sid], busy[sid], dirty[sid] = nil, nil, nil, nil
end

maki.api.create_autocmd("TurnEnd", { callback = function(ev)
  local sid = ev.data.session_id
  if sid and ev.data.reason ~= "dropped" then generate(sid) end
end })

maki.api.create_autocmd({ "SessionEnd", "SessionReset" }, { callback = function(ev)
  local sid = ev.data.session_id
  if sid then forget(sid) end
  apply_title()
end })
