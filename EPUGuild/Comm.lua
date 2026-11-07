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

local function de(s, i, depth)
  depth = depth or 0
  if depth > 24 then error("too deeply nested") end
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
      k, i = de(s, i, depth + 1)
      v, i = de(s, i, depth + 1)
      if type(k) ~= "string" and type(k) ~= "number" then error("invalid key") end
      t[k] = v
    end
    return t, i + 1
  end
  error("bad data at " .. i)
end

function ns.Deserialize(s)
  if type(s) ~= "string" or #s > 262144 then error("payload too large") end
  local v, pos = de(s, 1)
  if pos ~= #s + 1 then error("trailing data") end
  return v
end

---------------------------------------------------------------------------
-- Sending. Messages over 250 bytes are split into numbered parts.
-- Both prefix and shared connection limits can reject traffic. Keep initial
-- bursts small, pace packets, and retain refused packets for a longer retry.
---------------------------------------------------------------------------
local MAX_SINGLE = 250
local CHUNK = 230
-- Other addons share the character's connection. Avoid the large login burst
-- even when our own prefix still has tokens available.
local BURST, REFILL, SPACING = 2, 1.1, 0.55

local queue, sending, msgCounter = {}, false, 0
local tokens, lastRefill = BURST, 0
local pauseUntil, lastThrottle, lastAttempt, recovering = 0, nil, nil, false
local backoff = 0
local net = { attempts=0, refused=0, warnings=0, sent=0 }

local function Pause()
  local now=GetTime()
  if lastThrottle and now-lastThrottle<2 then return end -- same refusal, two event paths
  backoff=(lastThrottle and now-lastThrottle<60) and math.min(60,math.max(5,backoff*2)) or 5
  lastThrottle=now
  pauseUntil=math.max(pauseUntil,now+backoff)
  tokens,lastRefill,recovering=0,now,true
end
function ns.NetworkStatus()
  return {queued=#queue,attempts=net.attempts,sent=net.sent,refused=net.refused,warnings=net.warnings,
    pause=math.max(0,math.ceil(pauseUntil-GetTime()))}
end
function ns.PrintNetworkStatus()
  local s=ns.NetworkStatus()
  ns.Print("Network: "..s.queued.." queued, "..s.sent.." accepted, "..s.refused.." refused, "..s.warnings
    .." recent-send throttle warning(s), "..s.pause.."s cooldown. Counts are for EPU this session; a shared warning cannot identify its source.")
end
ns.On("CHAT_MSG_SYSTEM",function(msg)
  if ERR_CHAT_THROTTLED and msg==ERR_CHAT_THROTTLED and lastAttempt and GetTime()-lastAttempt<=2 then
    net.warnings=net.warnings+1
    Pause()
  end
end)

local THROTTLED = {}
if Enum and Enum.SendAddonMessageResult then
  local R = Enum.SendAddonMessageResult
  for _, k in ipairs({ "AddonMessageThrottle", "ChannelThrottle", "GeneralError" }) do
    if R[k] ~= nil then THROTTLED[R[k]] = true end
  end
end

local function Refused(result)
  if result == false then return true end                 -- older clients: false = not sent
  return type(result) == "number" and THROTTLED[result] == true
end

local function pump()
  local m = queue[1]
  if not m then sending = false return end
  local now = GetTime()
  if now<pauseUntil then C_Timer.After(pauseUntil-now+0.05,pump); return end
  if recovering then tokens,lastRefill,recovering=1,now,false end
  tokens = math.min(BURST, tokens + (now - lastRefill) / REFILL)
  lastRefill = now
  if tokens < 1 then
    C_Timer.After(REFILL * (1 - tokens) + 0.05, pump)
    return
  end
  lastAttempt=now
  net.attempts=net.attempts+1
  local chat=m[4]=="CHAT"
  local ok,result
  if chat then ok,result=pcall(SendChatMessage,m[1],"GUILD")
  else ok,result=pcall(C_ChatInfo.SendAddonMessage,ns.PREFIX,m[1],m[2],m[3]) end
  if ok and ((chat and result==false) or (not chat and Refused(result))) then
    net.refused=net.refused+1
    Pause()                                              -- retain the packet and cool down
    C_Timer.After(math.max(REFILL,pauseUntil-now)+0.05, pump)
    return
  end
  table.remove(queue, 1)
  if ok then net.sent=net.sent+1 end
  tokens = tokens - 1
  C_Timer.After(SPACING, pump)
end

function ns.Send(kind, data, channel, target)
  channel = channel or "GUILD"
  if channel == "GUILD" and not IsInGuild() then return end
  local body = kind .. ns.Serialize(data)
  if #body > 262144 or #queue > 12000 then return false end
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

-- User-requested needs posts and optional milestone announcements share the
-- same budget instead of sending several visible guild-chat lines at once.
function ns.SendGuildChat(text)
  if not IsInGuild() or type(text)~="string" or #text>255 or #queue>=12000 then return false end
  queue[#queue+1]={text,"GUILD",nil,"CHAT"}
  if not sending then sending=true; pump() end
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
local partial = {}
local TTL = 1800
local function Expire()
  local now = GetTime()
  for key,p in pairs(partial) do if now - p.at > TTL then partial[key] = nil end end
  if ns.ExpireSync then ns.ExpireSync() end
  C_Timer.After(30, Expire)
end
C_Timer.After(30, Expire)
function ns.PartialCount() local n=0; for _ in pairs(partial) do n=n+1 end; return n end

function ns.HandleAddonMessage(prefix, msg, channel, sender)
  if prefix ~= ns.PREFIX or type(msg) ~= "string" or #msg > 255 then return end
  if channel ~= "GUILD" and channel ~= "WHISPER" and channel ~= "OFFICER" then return end
  sender = ns.Short(sender)
  if not sender or sender == ns.me then return end
  -- The server already authenticates membership on GUILD/OFFICER. A new member
  -- may speak before our roster refresh; only whispers require a roster match.
  if channel == "WHISPER" and ns.roster and next(ns.roster) and not ns.roster[sender] then return end

  local body
  local t = msg:sub(1, 1)
  if t == "S" then
    body = msg:sub(2)
  elseif t == "P" then
    local id, i, n, part = msg:match("^P(%d+):(%d+):(%d+):(.*)$")
    if not id then return end
    i, n = tonumber(i), tonumber(n)
    if n < 1 or n > 1140 or i < 1 or i > n then return end
    local key = channel .. ":" .. sender .. ":" .. id
    local p = partial[key]
    if p and (p.n ~= n or GetTime() - p.at > TTL) then partial[key]=nil; return end
    if not p then
      local total, own = 0, 0
      for _,v in pairs(partial) do total=total+1; if v.sender==sender then own=own+1 end end
      if total>=32 or own>=4 then return end
      p = { n = n, parts = {}, got = 0, bytes = 0, at=GetTime(), sender=sender }
      partial[key] = p
    end
    if not p.parts[i] then
      p.parts[i] = part
      p.got = p.got + 1
      p.bytes = p.bytes + #part
      if p.bytes > 262144 then partial[key]=nil; return end
    end
    if ns.sync and channel=="GUILD" and ns.IsTrusted(sender) then ns.sync.lastPart=GetTime() end
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
  if handler then
    local ok,err = pcall(handler, sender, data, channel)
    if not ok then ns.lastMessageError = tostring(err) end
  end
end

ns.On("CHAT_MSG_ADDON", ns.HandleAddonMessage)

ns.On("PLAYER_LOGIN", function()
  C_ChatInfo.RegisterAddonMessagePrefix(ns.PREFIX)
end)
