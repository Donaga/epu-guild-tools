-- EPU Guild Tools: serialization and throttled, chunked addon messaging
local ADDON, ns = ...

---------------------------------------------------------------------------
-- Serializer for nested tables of strings, numbers and booleans.
--   number  #<n>;      string  $<escaped>;      true T   false F   nil N
--   table   { key value key value ... }
-- Strings escape ~ ; | and newlines so ';' always ends a value.
---------------------------------------------------------------------------
local function esc(s)
  s = s:gsub("~", "~~"):gsub(";", "~s"):gsub("|", "~p"):gsub("\n", "~n"):gsub("[%z\r]", "")
  return s
end

local UNESC = { ["~"] = "~", s = ";", p = "|", n = "\n" }
local function unesc(s)
  return (s:gsub("~(.)", UNESC))
end

local function ser(v, out)
  local t = type(v)
  if t == "number" then
    out[#out + 1] = "#" .. tostring(v) .. ";"
  elseif t == "string" then
    out[#out + 1] = "$" .. esc(v) .. ";"
  elseif t == "boolean" then
    out[#out + 1] = v and "T" or "F"
  elseif t == "table" then
    out[#out + 1] = "{"
    for k, val in pairs(v) do
      ser(k, out)
      ser(val, out)
    end
    out[#out + 1] = "}"
  else
    out[#out + 1] = "N"
  end
end

function ns.Serialize(v)
  local out = {}
  ser(v, out)
  return table.concat(out)
end

local function de(s, i)
  local c = s:sub(i, i)
  if c == "#" or c == "$" then
    local e = s:find(";", i, true)
    if not e then error("truncated") end
    local raw = s:sub(i + 1, e - 1)
    if c == "#" then return tonumber(raw), e + 1 end
    return unesc(raw), e + 1
  elseif c == "T" then return true, i + 1
  elseif c == "F" then return false, i + 1
  elseif c == "N" then return nil, i + 1
  elseif c == "{" then
    local t = {}
    i = i + 1
    while s:sub(i, i) ~= "}" do
      if i > #s then error("truncated") end
      local k, v
      k, i = de(s, i)
      v, i = de(s, i)
      if k ~= nil then t[k] = v end
    end
    return t, i + 1
  end
  error("bad data at " .. i)
end

function ns.Deserialize(s)
  local v = de(s, 1)
  return v
end

---------------------------------------------------------------------------
-- Sending. Messages over 250 bytes are split into numbered parts.
-- A simple queue keeps us at ~4 messages a second to stay under the
-- server's addon message throttle.
---------------------------------------------------------------------------
local MAX_SINGLE = 250
local CHUNK = 230
local INTERVAL = 0.25

local queue, sending, msgCounter = {}, false, 0

local function pump()
  local m = table.remove(queue, 1)
  if not m then sending = false return end
  C_ChatInfo.SendAddonMessage(ns.PREFIX, m[1], m[2], m[3])
  C_Timer.After(INTERVAL, pump)
end

function ns.Send(kind, data, channel, target)
  channel = channel or "GUILD"
  if channel == "GUILD" and not IsInGuild() then return end
  local body = kind .. ns.Serialize(data)
  if #body + 1 <= MAX_SINGLE then
    queue[#queue + 1] = { "S" .. body, channel, target }
  else
    msgCounter = (msgCounter % 999) + 1
    local n = math.ceil(#body / CHUNK)
    for i = 1, n do
      local part = body:sub((i - 1) * CHUNK + 1, i * CHUNK)
      queue[#queue + 1] = { "P" .. msgCounter .. ":" .. i .. ":" .. n .. ":" .. part, channel, target }
    end
  end
  if not sending then
    sending = true
    pump()
  end
end

function ns.QueueLength() return #queue end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
local partial = {}

function ns.HandleAddonMessage(prefix, msg, channel, sender)
  if prefix ~= ns.PREFIX then return end
  sender = ns.Short(sender)
  if not sender or sender == ns.me then return end

  local body
  local t = msg:sub(1, 1)
  if t == "S" then
    body = msg:sub(2)
  elseif t == "P" then
    local id, i, n, part = msg:match("^P(%d+):(%d+):(%d+):(.*)$")
    if not id then return end
    i, n = tonumber(i), tonumber(n)
    local key = sender .. ":" .. id
    local p = partial[key]
    if not p or i == 1 then
      p = { n = n, parts = {}, got = 0 }
      partial[key] = p
    end
    if not p.parts[i] then
      p.parts[i] = part
      p.got = p.got + 1
    end
    if p.got < p.n then return end
    partial[key] = nil
    body = table.concat(p.parts)
  else
    return
  end

  local kind = body:sub(1, 1)
  local ok, data = pcall(ns.Deserialize, body:sub(2))
  if not ok then return end
  local handler = ns.comm[kind]
  if handler then handler(sender, data, channel) end
end

ns.On("CHAT_MSG_ADDON", ns.HandleAddonMessage)

ns.On("PLAYER_LOGIN", function()
  C_ChatInfo.RegisterAddonMessagePrefix(ns.PREFIX)
end)
