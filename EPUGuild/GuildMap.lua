-- Guild positions are live and session-only. Never sync or save them.
local ADDON, ns = ...
local locations, markers, pool = {}, {}, {}
local TTL, INTERVAL, HEARTBEAT = 120, 30, 60
local last, lastSent, guild, panel
local ref = "EPUGuildLocations"
ns.guildLocations = locations

-- One reset requested for the guild's rollout. Thereafter preserve individual
-- choices, including explicit opt-outs, across reloads and future updates.
function ns.ApplyGuildMapDefaults()
  local s=ns.db and ns.db.settings; if not s then return false end
  local reset=(tonumber(s.guildMapSetup) or 0)<1
  for _,key in ipairs({'shareLocation','guildWorldMap','guildMinimap','guildClassIcons'}) do
    if reset or s[key]==nil then s[key]=true end
  end
  if reset then s.guildMapSetup=1 end
  return reset
end
local circle='Interface\\CharacterFrame\\TempPortraitAlphaMask'

local function Setting(key) return ns.db and ns.db.settings[key] end
local function Number(n,lo,hi)
  if issecretvalue and issecretvalue(n) then return false end
  return type(n)=="number" and n==n and n>=lo and n<=hi
end
local function MapInfo(id)
  if not Number(id,1,1000000) or id%1~=0 or not C_Map or not C_Map.GetMapInfo then return end
  local ok,info=pcall(C_Map.GetMapInfo,id)
  if ok then return info end
end
local function Pins()
  return LibStub and LibStub("HereBeDragons-Pins-2.0",true)
end

---------------------------------------------------------------------------
-- Layers. Forever runs several copies ("layers") of each zone. The client
-- has no API for it, but every NPC's GUID carries the copy's zone UID
-- (Creature-0-server-instance-zoneUID-npc-spawn). We read it from NPCs you
-- target, mouse over or see nameplates for, and share it alongside the
-- location (same opt-in). IDs only compare within one zone, and a reading
-- goes stale after a few minutes.
---------------------------------------------------------------------------
local FRESH=300
local layer
local function ZoneOf(map)
  -- Caves and city sub-maps share their zone's layer: climb to the zone.
  for _=1,6 do
    local info=MapInfo(map)
    if not info then return end
    if not info.mapType or info.mapType<=3 or not info.parentMapID or info.parentMapID==0 then return map end
    map=info.parentMapID
  end
  return map
end
local function ParseLayer(guid)
  if type(guid)~="string" or (issecretvalue and issecretvalue(guid)) then return end
  local kind,_,_,_,zoneUID=strsplit("-",guid)
  if kind~="Creature" and kind~="Vehicle" then return end
  zoneUID=tonumber(zoneUID)
  if Number(zoneUID,1,4294967295) and zoneUID%1==0 then return zoneUID end
end
local function SeeUnit(unit)
  if (IsInInstance and IsInInstance()) or not C_Map or not C_Map.GetBestMapForUnit then return end
  local ok,guid=pcall(UnitGUID,unit)
  local id=ok and ParseLayer(guid)
  if not id then return end
  local okm,map=pcall(C_Map.GetBestMapForUnit,"player")
  local zone=okm and ZoneOf(map)
  if not zone then return end
  local changed=not layer or layer.id~=id or layer.zone~=zone
  layer={zone=zone,id=id,at=GetTime()}
  -- Tell guildmates within ~10 s instead of waiting for the next heartbeat.
  if changed and lastSent then lastSent=math.min(lastSent,GetTime()-INTERVAL+10) end
end
ns.SeeLayerUnit=SeeUnit
-- Your current layer, if you've seen an NPC in this zone recently.
function ns.MyLayer()
  if not layer or GetTime()-layer.at>FRESH or (IsInInstance and IsInInstance()) then return end
  local ok,map=pcall(C_Map.GetBestMapForUnit,"player")
  if not ok or ZoneOf(map)~=layer.zone then return end
  return layer
end
-- "same", "other", or nil when unknown (not sharing, other zone, stale).
function ns.LayerOf(name)
  local me,p=ns.MyLayer(),locations[name]
  if not me or not p or not p.l or not p.lat or GetTime()-p.lat>FRESH then return end
  if ZoneOf(p.map)~=me.zone then return end
  return p.l==me.id and "same" or "other"
end
ns.On("PLAYER_TARGET_CHANGED",function() SeeUnit("target") end)
ns.On("UPDATE_MOUSEOVER_UNIT",function() SeeUnit("mouseover") end)
ns.On("NAME_PLATE_UNIT_ADDED",function(unit) SeeUnit(unit) end)
ns.On("ZONE_CHANGED_NEW_AREA",function() layer=nil end)
local function Remove(name)
  local pair=markers[name]
  if not pair then return end
  local pins=Pins()
  if pins then
    pins:RemoveWorldMapIcon(ref,pair.world)
    pins:RemoveMinimapIcon(ref,pair.mini)
  end
  pair.world:Hide(); pair.mini:Hide()
  pair.key=nil
  markers[name]=nil
  pool[#pool+1]=pair
end
local function Clear()
  for name in pairs(markers) do Remove(name) end
  wipe(locations)
end
local function Tooltip(self)
  local name=self.member
  local p=locations[name]
  if not p then return end
  local r=ns.roster[name] or {}
  local info=MapInfo(p.map)
  GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
  GameTooltip:SetText(name)
  GameTooltip:AddLine("Level "..tostring(r.level or "?").." "..(r.class or ""),1,1,1)
  GameTooltip:AddLine((info and info.name or "Unknown zone")..string.format(" (%.1f, %.1f)",p.x*100,p.y*100),1,1,1)
  GameTooltip:AddLine("Updated "..math.floor(GetTime()-p.at).."s ago",0.7,0.7,0.7)
  local where=ns.LayerOf(name)
  if where then GameTooltip:AddLine(where=="same" and "Same layer as you" or "On another layer",where=="same" and 0.3 or 1,where=="same" and 0.87 or 0.7,where=="same" and 0.5 or 0.28) end
  GameTooltip:AddLine("Click to whisper",1,0.82,0)
  GameTooltip:AddLine("Players may be in another layer or phase.",0.7,0.7,0.7)
  GameTooltip:Show()
end
local function Icon(size)
  local f=CreateFrame("Button",nil,UIParent)
  f:SetSize(size,size)
  f.rim=f:CreateTexture(nil,'BACKGROUND')
  f.rim:SetAllPoints(); f.rim:SetTexture(circle); f.rim:SetVertexColor(0.05,0.05,0.05,1)
  f.dot=f:CreateTexture(nil,"ARTWORK")
  f.dot:SetPoint('CENTER'); f.dot:SetSize(size-2,size-2)
  f:SetScript("OnEnter",Tooltip)
  f:SetScript("OnLeave",function() GameTooltip:Hide() end)
  f:SetScript("OnClick",function(self)
    if ChatFrame_SendTell then ChatFrame_SendTell(self.member) end
  end)
  f:Hide()
  return f
end
function ns.RefreshGuildMap()
  local pins=Pins()
  for name,p in pairs(locations) do
    local r=ns.roster[name]
    if GetTime()-p.at>=TTL or not r or not r.online or not IsInGuild() then
      locations[name]=nil; Remove(name)
    elseif not pins or (Setting("guildWorldMap")==false and Setting("guildMinimap")==false) then
      Remove(name)
    else
      local pair=markers[name]
      if not pair then
        pair=table.remove(pool) or {world=Icon(20),mini=Icon(18)}
        markers[name]=pair
        pair.world.member=name; pair.mini.member=name
      end
      -- Re-register only on movement/settings change, not each expiry tick.
      local key=p.map..":"..p.x..":"..p.y..":"..tostring(Setting("guildWorldMap"))..":"..tostring(Setting("guildMinimap"))..':'..tostring(Setting('guildClassIcons'))..':'..tostring(r.classFile)
      if pair.key~=key then
        pins:RemoveWorldMapIcon(ref,pair.world); pins:RemoveMinimapIcon(ref,pair.mini)
        local color=RAID_CLASS_COLORS and RAID_CLASS_COLORS[r.classFile]
        local texture,coords=ns.ClassIcon(r.classFile)
        for _,f in ipairs({pair.world,pair.mini}) do
          if Setting('guildClassIcons')~=false and texture then
            f.dot:SetTexture(texture); f.dot:SetTexCoord(unpack(coords)); f.dot:SetVertexColor(1,1,1,1)
          else
            f.dot:SetTexture(circle); f.dot:SetTexCoord(0,1,0,1)
            f.dot:SetVertexColor(color and color.r or 0.3,color and color.g or 1,color and color.b or 0.4,1)
          end
        end
        if Setting("guildWorldMap")~=false then pins:AddWorldMapIconMap(ref,pair.world,p.map,p.x,p.y,HBD_PINS_WORLDMAP_SHOW_WORLD or 3) end
        if Setting("guildMinimap")~=false then pins:AddMinimapIconMap(ref,pair.mini,p.map,p.x,p.y,true,false) end
        pair.key=key
      end
    end
  end
end
local function ResetGuild()
  local key=ns.GuildKey()
  if key~=guild then
    guild=key; last=nil; lastSent=nil
    ns.CancelEphemeral("L"); Clear()
  end
end
ns.comm.L=function(sender,data,channel)
  ResetGuild()
  if not guild or channel~="GUILD" or sender==ns.me or not ns.roster[sender] or not ns.roster[sender].online or type(data)~="table" then return end
  if data.off==true then locations[sender]=nil; Remove(sender); return end
  if not MapInfo(data.map) or not Number(data.x,0,1) or not Number(data.y,0,1) then return end
  local prev=locations[sender]
  if prev and GetTime()-prev.at<5 and prev.l==data.l then return end
  local l=Number(data.l,1,4294967295) and data.l%1==0 and data.l or nil
  locations[sender]={map=data.map,x=data.x,y=data.y,at=GetTime(),l=l,lat=l and GetTime() or nil}
  ns.RefreshGuildMap()
end
local function Position()
  if IsInInstance and IsInInstance() then return end
  if not C_Map or not C_Map.GetBestMapForUnit or not C_Map.GetPlayerMapPosition then return end
  local id=C_Map.GetBestMapForUnit("player")
  if not MapInfo(id) then return end
  local pos=C_Map.GetPlayerMapPosition(id,"player")
  if not pos then return end
  local x,y=pos:GetXY()
  if not Number(x,0,1) or not Number(y,0,1) or (x==0 and y==0) then return end
  return {map=id,x=math.floor(x*10000+0.5)/10000,y=math.floor(y*10000+0.5)/10000}
end
local function Withdraw()
  ns.CancelEphemeral("L")
  local key=guild
  ns.SendEphemeral("L",{off=true},TTL,function() return IsInGuild() and ns.GuildKey()==key end)
  last=nil
end
function ns.SetLocationSharing(on)
  ns.db.settings.shareLocation=on==true
  ResetGuild()
  if not on then Withdraw() else lastSent=nil end
  ns.Print("Guild location sharing "..(on and "on. Your outdoor location is visible to guildmates using EPU." or "off."))
  if ns.RefreshGuildMapSettings then ns.RefreshGuildMapSettings() end
end
function ns.UpdateGuildLocation()
  ResetGuild()
  ns.RefreshGuildMap()
  if not guild or not Setting("shareLocation") then return end
  local now=GetTime()
  if lastSent and now-lastSent<INTERVAL then return end
  -- Coordinates can be unavailable/restricted. Never attempt to work around it.
  local ok,p=pcall(Position)
  if not ok or not p then
    if last then Withdraw(); lastSent=now end
    return
  end
  local mine=ns.MyLayer()
  if mine and ZoneOf(p.map)==mine.zone then p.l=mine.id end
  if last and last.map==p.map and last.l==p.l and math.abs(last.x-p.x)<0.001 and math.abs(last.y-p.y)<0.001 and now-(lastSent or 0)<HEARTBEAT then return end
  local net=ns.NetworkStatus()
  if net.queued>0 or net.pause>0 then return end
  local key=guild
  if ns.SendEphemeral("L",p,15,function()
    return Setting("shareLocation")==true and IsInGuild() and ns.GuildKey()==key and not (IsInInstance and IsInInstance())
  end) then last=p; lastSent=now end
end
function ns.RefreshGuildMapSettings()
  if not panel then return end
  panel.share:SetChecked(Setting("shareLocation")==true)
  panel.world:SetChecked(Setting("guildWorldMap")~=false)
  panel.mini:SetChecked(Setting("guildMinimap")~=false)
  panel.icons:SetChecked(Setting('guildClassIcons')~=false)
  local n=0
  for _ in pairs(locations) do n=n+1 end
  local mine=ns.MyLayer()
  panel.status:SetText(n.." guildmate(s) sharing recently. "..(Pins() and "" or "Map library unavailable. ").."Markers expire after two minutes. "
    ..(mine and "Your layer was detected "..math.floor(GetTime()-mine.at).."s ago; the Roster shows who shares it." or "Target or mouse over any NPC to detect your layer."))
end
function ns.ShowGuildMapSettings()
  if not panel then
    panel=ns.InterfaceWindow("EPUGuildMapSettings",UIParent,"Guild map",380,344)
    panel:SetMovable(true); panel:EnableMouse(true); panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart",panel.StartMoving); panel:SetScript("OnDragStop",panel.StopMovingOrSizing)
    local function Check(key,label,y,callback)
      local b=ns.InterfaceButton(panel,label,348,28)
      b:SetPoint("TOPLEFT",16,y)
      b.text:ClearAllPoints(); b.text:SetPoint("LEFT",10,0)
      function b:SetChecked(on)
        self.checked=on==true
        self:SetOn(self.checked)
        self:SetLabel(label.."  ·  "..(self.checked and "On" or "Off"))
      end
      function b:GetChecked() return self.checked end
      b:SetScript("OnClick",function(self) callback(not self:GetChecked()); ns.RefreshGuildMap(); ns.RefreshGuildMapSettings() end)
      panel[key]=b
    end
    Check("share","Share my outdoor location",-38,ns.SetLocationSharing)
    Check("world","Show guildmates on the world map",-76,function(on) ns.db.settings.guildWorldMap=on end)
    Check("mini","Show nearby guildmates on the minimap",-114,function(on) ns.db.settings.guildMinimap=on end)
    Check('icons','Use class icons (off = round dots)',-152,function(on) ns.db.settings.guildClassIcons=on end)
    panel.status=ns.InterfaceFont(panel,12)
    panel.status:SetPoint("TOPLEFT",20,-198); panel.status:SetWidth(340); panel.status:SetJustifyH("LEFT")
    panel.status:SetWordWrap(true)
    panel.buttonSettings=ns.InterfaceButton(panel,"Move minimap button",180,24)
    panel.buttonSettings:SetPoint("BOTTOMLEFT",20,52)
    panel.buttonSettings:SetScript("OnClick",function() ns.ShowMinimapButtonSettings() end)
    local hint=ns.InterfaceFont(panel,11,{.64,.69,.76})
    hint:SetPoint("BOTTOMLEFT",20,18); hint:SetWidth(340)
    hint:SetWordWrap(true)
    hint:SetText("Both players need EPU 0.11+ (0.22.3+ for layers). No location history is saved. Click a marker to whisper.")
  end
  ns.RefreshGuildMapSettings(); panel:Show()
end
ns.On("GUILD_ROSTER_UPDATE",function() ResetGuild(); ns.RefreshGuildMap() end)
ns.On("PLAYER_GUILD_UPDATE",function() ResetGuild(); ns.RefreshGuildMap() end)
ns.On("PLAYER_ENTERING_WORLD",function()
  ResetGuild()
  if IsInInstance and IsInInstance() and last then Withdraw() end
end)
ns.On("PLAYER_LOGOUT",function() ns.CancelEphemeral("L"); Clear() end)
ns.On("PLAYER_LOGIN",function()
  ResetGuild()
  if ns.guildMapReset then
    ns.Print('Guild map enabled: your outdoor location is shared with guildmates. Use /epu map to change sharing, displays and icons.')
    ns.guildMapReset=nil
  end
  local function Tick()
    ns.UpdateGuildLocation(); ns.RefreshGuildMapSettings()
    C_Timer.After(5,Tick)
  end
  C_Timer.After(10+math.random()*20,Tick)
end)

---------------------------------------------------------------------------
-- Live status for the Guildmates list: "looking for a partner" and the size
-- of your group. Ephemeral like locations: nothing is saved, and it is only
-- sent while there is something to say (or once to clear it).
---------------------------------------------------------------------------
local status, lookingSince = {}, nil
local STATUS_TTL, STATUS_BEAT = 200, 90
local lastStatus, lastStatusAt
local function GroupSize()
  local n = GetNumGroupMembers and GetNumGroupMembers() or 0
  return n > 1 and n or 1
end
local function SendStatus(force)
  if not IsInGuild or not IsInGuild() then return end
  local looking = lookingSince ~= nil
  local g = GroupSize()
  local sig = (looking and "L" or "-") .. g
  local now = GetTime()
  local idle = not looking and g <= 1
  if not force and sig == lastStatus and (idle or now - (lastStatusAt or 0) < STATUS_BEAT) then return end
  if idle and (lastStatus == nil or lastStatus == "-1") and not force then lastStatus = sig; return end
  lastStatus, lastStatusAt = sig, now
  ns.SendEphemeral("P", { lf = looking or nil, g = g }, 20)
end
ns.comm.P = function(sender, data, channel)
  if channel ~= "GUILD" or type(data) ~= "table" or sender == ns.me or not ns.roster[sender] then return end
  local g = tonumber(data.g)
  status[sender] = { lf = data.lf == true, g = (g and g >= 1 and g <= 40 and g % 1 == 0) and g or nil, at = GetTime() }
  ns.Changed()
end
function ns.GuildmateStatus(name)
  if name == ns.me then return { lf = lookingSince ~= nil, g = GroupSize() } end
  local s = status[name]
  if not s or GetTime() - s.at > STATUS_TTL then return nil end
  return s
end
function ns.LookingForPartner() return lookingSince ~= nil end
function ns.SetLookingForPartner(on)
  lookingSince = on and GetTime() or nil
  SendStatus(true)
  ns.Print(on and "Guildmates now see you're looking for a partner (until you untick it or log off)." or "No longer looking for a partner.")
end
ns.On("GROUP_ROSTER_UPDATE", function() if ns.Debounce then ns.Debounce("guildStatus", 2, SendStatus) else SendStatus() end end)
ns.On("PLAYER_LOGIN", function()
  if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(30, function() pcall(SendStatus) end) end
end)

-- Right-click a guildmate: whisper, invite, waypoint, layer.
function ns.GuildmateMenu(anchor, name)
  local items = {}
  local short = name:match("^(%S+)") or name
  local r = ns.roster[name] or {}
  if name ~= ns.me then
    items[#items + 1] = { label = "Whisper " .. short, value = "whisper" }
    if r.online then items[#items + 1] = { label = "Invite to group", value = "invite" } end
    local p = locations[name]
    if p and GetTime() - p.at < TTL then items[#items + 1] = { label = "Set a waypoint to them", value = "waypoint" } end
    if ns.LayerOf and ns.LayerOf(name) == "other" then items[#items + 1] = { label = "Ask to join their layer", value = "layer" } end
  end
  items[#items + 1] = { label = "Details", value = "details" }
  ns.OpenMenu(anchor, items, nil, function(v)
    if v == "whisper" then if ChatFrame_SendTell then ChatFrame_SendTell(name) end
    elseif v == "invite" then
      if C_PartyInfo and C_PartyInfo.InviteUnit then C_PartyInfo.InviteUnit(name) elseif InviteUnit then InviteUnit(name) end
    elseif v == "waypoint" then ns.WaypointTo(name)
    elseif v == "layer" then
      if ChatFrame_OpenChat then ChatFrame_OpenChat("/w " .. name .. " Could you invite me to a group so I can join your layer in "
        .. (r.zone or "this zone") .. "? I'll accept the world refresh and leave the group after.") end
    else ns.UI:OpenDetails("member", name) end
  end)
end
function ns.WaypointTo(name)
  local p = locations[name]
  if not p then return ns.Print(name .. " isn't sharing a location right now.") end
  if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
    local ok = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(p.map, p.x, p.y))
    if ok then
      if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true) end
      return ns.Print("Waypoint set to " .. name .. "'s last shared position.")
    end
  end
  if TomTom and TomTom.AddWaypoint then
    TomTom:AddWaypoint(p.map, p.x, p.y, { title = name })
    return ns.Print("TomTom waypoint set to " .. name .. ".")
  end
  ns.Print("This client can't place map waypoints. " .. name .. " is at " .. math.floor(p.x * 1000) / 10 .. ", " .. math.floor(p.y * 1000) / 10 .. ".")
end

-- Guildmate tooltips: who's looking for a partner.
local function TooltipStatus(tt)
  if not tt or not tt.GetUnit then return end
  local ok, _, unit = pcall(tt.GetUnit, tt)
  if not ok or not unit or not UnitIsPlayer or not UnitIsPlayer(unit) then return end
  local okn, n = pcall(UnitName, unit)
  if not okn or type(n) ~= "string" or (issecretvalue and issecretvalue(n)) then return end
  local s = ns.roster[n] and ns.GuildmateStatus(n)
  if s and s.lf then tt:AddLine("Looking for a partner (EPU)", 0.95, 0.76, 0.31) end
  if ns.roster[n] and ns.SharedQuestIDs then
    local shared = ns.SharedQuestIDs(n)
    if #shared > 0 then tt:AddLine("On " .. #shared .. (#shared == 1 and " of your quests" or " of your quests") .. " (EPU)", 0.29, 0.87, 0.50) end
  end
end
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt) pcall(TooltipStatus, tt) end)
elseif GameTooltip and GameTooltip.HookScript then
  pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetUnit", function(tt) pcall(TooltipStatus, tt) end)
end


---------------------------------------------------------------------------
-- Chat history: whispers (and optionally guild and officer chat) saved on
-- this PC only, so they survive /reload and logging out. Never shared.
---------------------------------------------------------------------------
local CHAT_KEEP = 200            -- lines kept per channel
local CHAT_MAX_AGE = 7 * 86400   -- and nothing older than a week
local REPLAY_WINDOW = 3600       -- after a reload, show the last hour
local REPLAY_LINES = 15
local CHANNELS = {
  whisper = { label = "Whispers", group = "WHISPER", info = "WHISPER" },
  guild = { label = "Guild chat", group = "GUILD", info = "GUILD" },
  officer = { label = "Officer chat", group = "OFFICER", info = "OFFICER" },
}
local CHANNEL_ORDER = { "whisper", "guild", "officer" }

local function ChatDB()
  local c = ns.cdb
  if not c then return nil end
  c.chatlog = c.chatlog or {}
  c.chatkeep = c.chatkeep or { whisper = true, guild = false, officer = false, replay = true }
  for _, k in ipairs(CHANNEL_ORDER) do c.chatlog[k] = c.chatlog[k] or {} end
  return c
end
local function CanOfficerChat()
  if C_GuildInfo and C_GuildInfo.CanSpeakInOfficerChat then
    local ok, v = pcall(C_GuildInfo.CanSpeakInOfficerChat)
    if ok and v ~= nil then return v and true or false end
  end
  return ns.IsTrusted and ns.IsTrusted(ns.me) or false
end
ns.CanOfficerChat = CanOfficerChat
function ns.ChatKeep(channel)
  local c = ChatDB()
  if not c then return false end
  if channel == "officer" and not CanOfficerChat() then return false end
  return c.chatkeep[channel] == true
end
function ns.SetChatKeep(channel, on)
  local c = ChatDB()
  if c then c.chatkeep[channel] = on and true or false end
end
local function Plain(v)
  if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
  if type(v) ~= "string" then return nil end
  return v
end
function ns.LogChat(channel, who, msg, out)
  if not ns.ChatKeep(channel) then return end
  who = Plain(who)
  if not who or who == "" then return end
  local text = Plain(msg) or "(the game hid this message)"
  local log = ChatDB().chatlog[channel]
  log[#log + 1] = { t = time(), who = who, msg = text, out = out or nil }
  local cutoff = time() - CHAT_MAX_AGE
  local drop = 0
  while drop < #log and (#log - drop > CHAT_KEEP or (log[drop + 1].t or 0) < cutoff) do drop = drop + 1 end
  if drop > 0 then
    for i = 1, #log - drop do log[i] = log[i + drop] end
    for i = #log, #log - drop + 1, -1 do log[i] = nil end
  end
  if ns.MessengerChanged then ns.MessengerChanged(channel, who, not out) end
  local UI = ns.UI
  if UI and UI:IsShown() then
    if UI.view == "chat" then ns.Changed() end
    local d = UI.details
    if d and d:IsShown() and d.kind == "chatwith" and (d.key == channel or d.key == "w:" .. who) then
      ns.Debounce("chatThread", 0.2, function() if d.kind == "chatwith" then UI:FillDetails() end end)
    end
  end
end
function ns.ChatLog(channel)
  local c = ChatDB()
  return c and c.chatlog[channel] or {}
end
ns.On("CHAT_MSG_WHISPER", function(msg, sender) ns.LogChat("whisper", sender, msg, false) end)
ns.On("CHAT_MSG_WHISPER_INFORM", function(msg, target) ns.LogChat("whisper", target, msg, true) end)
ns.On("CHAT_MSG_GUILD", function(msg, sender) ns.LogChat("guild", sender, msg, false) end)
ns.On("CHAT_MSG_OFFICER", function(msg, sender) ns.LogChat("officer", sender, msg, false) end)

local function Hex(info)
  local t = ChatTypeInfo and ChatTypeInfo[info]
  if not t then return "|cffffffff" end
  return string.format("|cff%02x%02x%02x", (t.r or 1) * 255, (t.g or 1) * 255, (t.b or 1) * 255)
end
local function PlayerLink(who)
  return "|Hplayer:" .. who .. "|h[" .. (ns.Short and ns.Short(who) or who) .. "]|h"
end
local function FormatLine(channel, e)
  local stamp = date("%H:%M", e.t)
  local color = Hex(CHANNELS[channel].info)
  local body
  if channel == "whisper" then
    body = e.out and ("To " .. PlayerLink(e.who) .. ": " .. e.msg) or (PlayerLink(e.who) .. " whispers: " .. e.msg)
  else
    body = "[" .. (channel == "guild" and "Guild" or "Officer") .. "] " .. PlayerLink(e.who) .. ": " .. e.msg
  end
  return color .. "[" .. stamp .. "] " .. body .. "|r"
end
ns.FormatChatLine = FormatLine
local function FramesFor(group)
  local out = {}
  for i = 1, (NUM_CHAT_WINDOWS or 1) do
    local f = _G["ChatFrame" .. i]
    if f and f.AddMessage and ChatFrame_ContainsMessageGroup and ChatFrame_ContainsMessageGroup(f, group) then out[#out + 1] = f end
  end
  if #out == 0 and DEFAULT_CHAT_FRAME then out[1] = DEFAULT_CHAT_FRAME end
  return out
end
-- After a reload (or a fresh login) put the last hour back into the chat
-- windows that show that kind of chat, greyed so it reads as history.
function ns.ReplayChat()
  local c = ChatDB()
  if not c or c.chatkeep.replay == false then return 0 end
  local since, shown = time() - REPLAY_WINDOW, 0
  for _, channel in ipairs(CHANNEL_ORDER) do
    if ns.ChatKeep(channel) then
      local log, lines = c.chatlog[channel], {}
      for i = #log, 1, -1 do
        local e = log[i]
        if (e.t or 0) < since or #lines >= REPLAY_LINES then break end
        table.insert(lines, 1, e)
      end
      if #lines > 0 then
        for _, f in ipairs(FramesFor(CHANNELS[channel].group)) do
          f:AddMessage("|cff888888EPU: " .. CHANNELS[channel].label:lower() .. " from before the reload (/epu chat for more)|r")
          for _, e in ipairs(lines) do f:AddMessage(FormatLine(channel, e)) end
        end
        shown = shown + #lines
      end
    end
  end
  return shown
end
ns.On("PLAYER_ENTERING_WORLD", function(initial, reloading)
  if not (initial or reloading) or ns.chatReplayed then return end
  ns.chatReplayed = true
  if C_Timer and C_Timer.After then C_Timer.After(2, ns.ReplayChat) else ns.ReplayChat() end
end)

function ns.ShowChatHistory(channel)
  local UI = ns.UI
  UI:Show()
  UI:CloseDetails()
  if channel == "guild" or channel == "officer" then UI:SetView("chat"); return UI:OpenDetails("chatwith", channel) end
  local v = ns.ChatView
  if v and v.onSelect then v.onSelect() else UI:SetView("chat") end
end
ns.CHAT_CHANNELS, ns.CHAT_ORDER = CHANNELS, CHANNEL_ORDER
ns.ChatDB = ChatDB
function ns.ChatUnread()
  local c = ChatDB()
  if not c then return 0 end
  local seen, n = c.chatSeenAt or 0, 0
  local log = c.chatlog.whisper
  for i = #log, 1, -1 do
    local e = log[i]
    if (e.t or 0) <= seen then break end
    if not e.out then n = n + 1 end
  end
  return n
end
function ns.MarkChatSeen()
  local c = ChatDB()
  if c then c.chatSeenAt = time() end
end
-- One row per person you whispered with, newest conversation first.
function ns.ChatConversations()
  local log, seen, out = ns.ChatLog("whisper"), {}, {}
  local since = (ChatDB() or {}).chatSeenAt or 0
  for i = #log, 1, -1 do
    local e = log[i]
    local c = seen[e.who]
    if not c then
      c = { who = e.who, last = e, n = 0, unread = 0 }
      seen[e.who] = c; out[#out + 1] = c
    end
    c.n = c.n + 1
    if not e.out and (e.t or 0) > since then c.unread = c.unread + 1 end
  end
  return out
end
local function Ago(t)
  local d = time() - (t or 0)
  if d < 60 then return "just now" end
  if d < 3600 then return math.floor(d / 60) .. "m ago" end
  if d < 86400 then return math.floor(d / 3600) .. "h ago" end
  return math.floor(d / 86400) .. "d ago"
end
ns.ChatAgo = Ago
-- One conversation in the side panel: the thread, newest at the bottom, and a
-- reply box. key is "w:<name>" for whispers, or "guild" / "officer".
local function Send(key, text)
  if type(text) ~= "string" or text:gsub("%s", "") == "" or not SendChatMessage then return false end
  text = text:sub(1, 255)
  if key == "guild" then SendChatMessage(text, "GUILD")
  elseif key == "officer" then SendChatMessage(text, "OFFICER")
  else SendChatMessage(text, "WHISPER", nil, key:sub(3)) end
  return true
end
local function ThreadKey(key)
  if key ~= "guild" and key ~= "officer" and key:sub(1, 2) ~= "w:" then key = "w:" .. key end
  return key
end
-- Lines of a conversation, newest first.
local function ThreadLines(key, max)
  local channel = key:sub(1, 2) == "w:" and "whisper" or key
  local who = channel == "whisper" and key:sub(3) or nil
  local log, lines = ns.ChatLog(channel), {}
  for i = #log, 1, -1 do
    if not who or log[i].who == who then lines[#lines + 1] = log[i] end
    if #lines >= (max or 60) then break end
  end
  return lines, channel, who
end
local function LineText(channel, e)
  local speaker = e.out and "|cff9fb4c8You|r" or ("|cffffffff" .. (ns.Short and ns.Short(e.who) or e.who) .. "|r")
  local color = channel == "whisper" and (e.out and "|cffd9b3ff" or "|cffff80ff") or (channel == "guild" and "|cff40ff40" or "|cff40c040")
  return "|cff888888" .. date("%H:%M", e.t) .. "|r  " .. speaker .. "\n" .. color .. e.msg .. "|r"
end
ns.ChatThreadKey, ns.ChatThreadLines, ns.ChatLineText, ns.ChatSend = ThreadKey, ThreadLines, LineText, Send
local function FillChatWith(det, key)
  local UI = ns.UI
  key = ThreadKey(key)
  if key == "officer" and not CanOfficerChat() then UI:CloseDetails(); return true end
  local lines, channel, who = ThreadLines(key, 60)
  local short = who and (ns.Short and ns.Short(who) or who)
  local member = who and ns.roster[short]
  det:Reset(channel == "whisper" and ((member and ns.ClassIcon(member.classFile)) or "Interface\\Icons\\INV_Letter_15")
      or (channel == "guild" and "Interface\\Icons\\INV_Shirt_GuildTabard_01" or "Interface\\Icons\\INV_Misc_Key_03"),
    nil, who and short or CHANNELS[channel].label, who and (member and ((member.online and "Online" or "Offline") .. (member.zone and member.online and (" · " .. member.zone) or "")
      .. " · level " .. (member.level or "?")) or "Whispers") or "Saved on this PC")
  -- reply first, newest messages right under it
  local box = det:Field(who and "Reply" or "Say", "", math.max(160, det.panelWidth - 110))
  local function Go()
    if Send(key, box:GetText()) then
      box:SetText("")
      C_Timer.After(0.3, function() if UI.details.kind == "chatwith" and UI.details.key == key then UI:FillDetails() end end)
    end
  end
  box.onEnter = Go
  local buttons = { { "Send", Go, accent = true, tip = "Or press Enter" } }
  if who then
    buttons[#buttons + 1] = { "Invite", function() local invite = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit; if invite then invite(who) end end }
    if member and ns.GuildmateMenu then buttons[#buttons + 1] = { "More", function(self) ns.GuildmateMenu(self, short) end } end
  end
  buttons[#buttons + 1] = { "Pop out", function() ns.OpenMessenger(key) end, tip = "Open this conversation in a small window you can move and minimize" }
  det:Buttons(buttons)
  det:Gap(4)
  if #lines == 0 then det:Text(who and ("No saved whispers with " .. short .. " yet.") or "Nothing saved yet.", nil) end
  local lastDay
  for _, e in ipairs(lines) do
    local day = date("%A %d %B", e.t)
    if day ~= lastDay then det:Text("|cfff2c14e" .. day .. "|r"); lastDay = day end
    det:Text(LineText(channel, e))
  end
  if channel == "whisper" then ns.MarkChatSeen() end
  return true
end

---------------------------------------------------------------------------
-- Pop-out messenger: a small window of its own that you can move, resize and
-- minimize to a title bar. Newest messages on top, reply box at the top.
---------------------------------------------------------------------------
local Mgr, Bub
local function MState()
  local c = ChatDB()
  if not c then return {} end
  c.messenger = c.messenger or {}
  return c.messenger
end
local function ConversationItems()
  local items = {}
  for _, ch in ipairs({ "guild", "officer" }) do
    if ns.ChatKeep(ch) then items[#items + 1] = { label = CHANNELS[ch].label, value = ch } end
  end
  for _, c in ipairs(ns.ChatConversations()) do
    items[#items + 1] = { label = (ns.Short and ns.Short(c.who) or c.who) .. (c.unread > 0 and (" (" .. c.unread .. " new)") or ""), value = "w:" .. c.who }
  end
  return items
end
local function BuildMessenger()
  local K = ns.UIKit
  if Mgr or not K then return Mgr end
  local C = K.C
  local f = CreateFrame("Frame", "EPUGuildMessenger", UIParent)
  Mgr = f
  f:SetSize(340, 400)
  f:SetFrameStrata("MEDIUM")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:SetResizable(true)
  if f.SetResizeBounds then f:SetResizeBounds(260, 200, 700, 900) elseif f.SetMinResize then f:SetMinResize(260, 200) end
  f:EnableMouse(true)
  local bg = K.Tex(f, "BACKGROUND", C.bg or C.panel)
  bg:SetAllPoints()
  for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
    local t = K.Tex(f, "BORDER", C.line)
    t:SetPoint(side[1]); t:SetPoint(side[2])
    if side[3] then t:SetHeight(1) else t:SetWidth(1) end
  end
  -- title bar: drag to move, click the name to switch conversations
  local bar = CreateFrame("Frame", nil, f)
  bar:SetPoint("TOPLEFT"); bar:SetPoint("TOPRIGHT"); bar:SetHeight(28)
  bar:EnableMouse(true)
  bar:RegisterForDrag("LeftButton")
  bar:SetScript("OnDragStart", function() f:StartMoving() end)
  bar:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
    local p, _, rp, x, y = f:GetPoint()
    MState().point = { p, rp, x, y }
  end)
  local barBg = K.Tex(bar, "BACKGROUND", C.panel2 or C.panel)
  barBg:SetAllPoints()
  f.pick = K.Btn(bar, "", 200, 20)
  f.pick:SetPoint("LEFT", 4, 0)
  if K.AddDropdownArrow then K.AddDropdownArrow(f.pick) end
  f.pick.tip = "Switch conversation"
  f.pick:SetScript("OnClick", function(self)
    K.OpenMenu(self, ConversationItems(), MState().key, function(v)
      if v then MState().key = v; f:Update() end
    end)
  end)
  f.close = K.Btn(bar, "x", 22, 20)
  f.close:SetPoint("RIGHT", -4, 0)
  f.close.tip = "Close (reopen from Chat > Pop out or /epu messenger)"
  f.close:SetScript("OnClick", function() ns.CloseMessenger() end)
  f.min = K.Btn(bar, "-", 22, 20)
  f.min:SetPoint("RIGHT", f.close, "LEFT", -3, 0)
  f.min.tip = "Minimize to a small bubble"
  f.min:SetScript("OnClick", function() ns.MinimizeMessenger(not MState().min) end)
  f.full = K.Btn(bar, "Open", 44, 20)
  f.full:SetPoint("RIGHT", f.min, "LEFT", -3, 0)
  f.full.tip = "Open the Chat page"
  f.full:SetScript("OnClick", function() ns.ShowChatHistory() end)
  -- body
  f.body = CreateFrame("Frame", nil, f)
  f.body:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, 0)
  f.body:SetPoint("BOTTOMRIGHT")
  f.box = K.Box(f.body, 200, "Type a message, Enter to send")
  f.box:SetPoint("TOPLEFT", 8, -8)
  f.box:SetPoint("TOPRIGHT", -62, -8)
  f.send = K.Btn(f.body, "Send", 50, 22, "accent")
  f.send:SetPoint("TOPRIGHT", -8, -8)
  local function Go()
    local key = MState().key
    if key and Send(key, f.box:GetText()) then f.box:SetText("") end
    f.box:SetFocus()
  end
  f.box.onEnter = Go
  f.send:SetScript("OnClick", Go)
  f.scroll = CreateFrame("ScrollFrame", nil, f.body)
  f.scroll:SetPoint("TOPLEFT", 8, -38)
  f.scroll:SetPoint("BOTTOMRIGHT", -8, 14)
  f.child = CreateFrame("Frame", nil, f.scroll)
  f.child:SetSize(300, 10)
  f.scroll:SetScrollChild(f.child)
  f.text = K.Font(f.child, 12, C.text)
  f.text:SetPoint("TOPLEFT")
  f.text:SetJustifyH("LEFT"); f.text:SetJustifyV("TOP")
  f.text:SetWordWrap(true)
  f.scroll:EnableMouseWheel(true)
  f.scroll:SetScript("OnMouseWheel", function(self, delta)
    local max = math.max(0, f.child:GetHeight() - self:GetHeight())
    self:SetVerticalScroll(math.min(max, math.max(0, self:GetVerticalScroll() - delta * 40)))
  end)
  f.grip = CreateFrame("Button", nil, f.body)
  f.grip:SetSize(14, 14)
  f.grip:SetPoint("BOTTOMRIGHT", -1, 1)
  f.grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  f.grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  f.grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
  f.grip:SetScript("OnMouseUp", function()
    f:StopMovingOrSizing()
    local st = MState(); st.w, st.h = math.floor(f:GetWidth()), math.floor(f:GetHeight())
    f:Update()
  end)
  f:SetScript("OnSizeChanged", function() if f.body:IsShown() then f:Layout() end end)
  function f:Layout()
    local w = math.max(200, (self:GetWidth() or 340) - 30)
    self.child:SetWidth(w)
    self.text:SetWidth(w)
    self.pick:SetWidth(math.max(100, (self:GetWidth() or 340) - 4 - 22 - 3 - 22 - 3 - 44 - 10))
    self.child:SetHeight(math.max(10, math.ceil(self.text:GetStringHeight() or 10)))
  end
  function f:Update()
    local st = MState()
    if not st.key then
      local first = ns.ChatConversations()[1]
      st.key = first and ("w:" .. first.who) or (ns.ChatKeep("guild") and "guild" or nil)
    end
    local unread = ns.ChatUnread()
    local key = st.key
    local label
    if not key then label = "Chat"
    elseif key:sub(1, 2) == "w:" then label = ns.Short and ns.Short(key:sub(3)) or key:sub(3)
    else label = CHANNELS[key].label end
    self.pick:SetLabel(label)
    local bub = ns.ChatBubble()
    if st.min then
      if self:IsShown() then bub:Place() end
      self:Hide()
      bub:Show(); bub:Update()
      return
    end
    bub:Hide()
    self:Show()
    self.body:Show()
    self:SetHeight(st.h or 400)
    local out, lastDay = {}, nil
    if key then
      local lines, channel = ThreadLines(key, 100)
      for _, e in ipairs(lines) do
        local day = date("%A %d %B", e.t)
        if day ~= lastDay then out[#out + 1] = "|cfff2c14e" .. day .. "|r"; lastDay = day end
        out[#out + 1] = LineText(channel, e)
      end
      if channel == "whisper" then ns.MarkChatSeen() end
    end
    self.text:SetText(#out > 0 and table.concat(out, "\n\n") or "|cff888888No messages yet. Pick a conversation above, or type to start.|r")
    self.box:SetShown(key ~= nil); self.send:SetShown(key ~= nil)
    self:Layout()
  end
  return f
end
-- Minimized, the messenger becomes a round bubble like the Events bubble:
-- drag it anywhere, click to open, and a badge counts new whispers.
function ns.ChatBubble()
  if Bub then return Bub end
  local b = CreateFrame("Button", "EPUGuildChatBubble", UIParent)
  Bub = b
  b:SetSize(38, 38)
  b:SetFrameStrata("MEDIUM")
  b:SetClampedToScreen(true)
  b:SetMovable(true)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  local function Round(tex)
    if not b.CreateMaskTexture then return end
    local mask = b:CreateMaskTexture()
    if mask then
      mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
      mask:SetAllPoints(tex)
      tex:AddMaskTexture(mask)
    end
  end
  local ring = b:CreateTexture(nil, "BACKGROUND")
  ring:SetAllPoints()
  ring:SetColorTexture(0.82, 0.63, 0.26, 0.95)
  Round(ring)
  b.ring = ring
  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetPoint("TOPLEFT", 3, -3); icon:SetPoint("BOTTOMRIGHT", -3, 3)
  icon:SetTexture("Interface\\Icons\\INV_Letter_15")
  Round(icon)
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  local badge = CreateFrame("Frame", nil, b)
  badge:SetPoint("TOPRIGHT", b, "TOPRIGHT", 5, 3)
  badge:SetSize(18, 16)
  local fill = badge:CreateTexture(nil, "BACKGROUND")
  fill:SetAllPoints()
  fill:SetColorTexture(0.29, 0.87, 0.50, 1)
  badge.text = ns.InterfaceFont and ns.InterfaceFont(badge, 11, { 0.05, 0.07, 0.09 }) or badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  badge.text:SetPoint("CENTER")
  b.badge = badge
  b:SetScript("OnDragStart", function(self) self.dragging = true; self:StartMoving() end)
  b:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local x, y = self:GetCenter()
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    if x and y and w and h and w > 0 and h > 0 then MState().bubble = { x / w, y / h } end
    C_Timer.After(0, function() self.dragging = nil end)
  end)
  b:SetScript("OnClick", function(self, button)
    if self.dragging then return end
    if button == "RightButton" then ns.ShowChatHistory() else ns.MinimizeMessenger(false) end
  end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Chat")
    local n = ns.ChatUnread()
    GameTooltip:AddLine(n == 0 and "No new whispers" or (n == 1 and "1 new whisper" or (n .. " new whispers")), 1, 1, 1)
    local last = ns.ChatLog("whisper")
    last = last[#last]
    if last and not last.out then GameTooltip:AddLine((ns.Short and ns.Short(last.who) or last.who) .. ": " .. last.msg:sub(1, 80), 1, 0.5, 1, true) end
    GameTooltip:AddLine("Click to open. Right-click for the Chat page. Drag to move.", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  function b:Place()
    self:ClearAllPoints()
    local p = MState().bubble
    if type(p) == "table" and type(p[1]) == "number" and type(p[2]) == "number" then
      self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p[1] * UIParent:GetWidth(), p[2] * UIParent:GetHeight())
    elseif Mgr and Mgr:GetRight() then
      self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", Mgr:GetRight() - 20, Mgr:GetTop() - 20)
    else
      self:SetPoint("CENTER", UIParent, "CENTER", 320, -40)
    end
  end
  function b:Update()
    local n = ns.ChatUnread()
    self.badge:SetShown(n > 0)
    self.badge.text:SetText(n > 99 and "99+" or tostring(n))
    self.badge:SetWidth(math.max(18, (self.badge.text:GetStringWidth() or 8) + 8))
  end
  b:Hide()
  return b
end

function ns.OpenMessenger(key, minimized)
  local f = BuildMessenger()
  if not f then return end
  local st = MState()
  if key then st.key = ThreadKey(key) end
  st.open, st.min = true, minimized and true or false
  f:ClearAllPoints()
  if st.point then f:SetPoint(st.point[1], UIParent, st.point[2], st.point[3], st.point[4]) else f:SetPoint("RIGHT", UIParent, "RIGHT", -80, 40) end
  f:SetSize(st.w or 340, st.h or 400)
  f:Show()
  f:Update()
end
function ns.CloseMessenger()
  MState().open = false
  if Mgr then Mgr:Hide() end
  if Bub then Bub:Hide() end
end
function ns.MinimizeMessenger(on)
  local st = MState()
  st.min = on and true or false
  if Mgr then Mgr:Update() end
end
function ns.ToggleMessenger()
  if (Mgr and Mgr:IsShown()) or (Bub and Bub:IsShown()) then ns.CloseMessenger() else ns.OpenMessenger() end
end
function ns.MessengerChanged(channel, who, incoming)
  if Bub and Bub:IsShown() then
    Bub:Update()
    if incoming and channel == "whisper" then
      MState().key = "w:" .. who   -- open on the newest whisper
      if UIFrameFlash then pcall(UIFrameFlash, Bub.ring, 0.3, 0.3, 2.4, true, 0, 0) end
    end
    return
  end
  if not (Mgr and Mgr:IsShown()) then return end
  local st = MState()
  -- a new whisper while nothing is open there: follow it
  if incoming and channel == "whisper" and not st.key then st.key = "w:" .. who end
  ns.Debounce("messenger", 0.2, function() if Mgr:IsShown() then Mgr:Update() end end)
end
ns.On("PLAYER_LOGIN", function()
  C_Timer.After(3, function() local st = MState(); if st.open then ns.OpenMessenger(nil, st.min) end end)
end)
local function FillChatNew(det)
  det:Reset("Interface\\Icons\\INV_Letter_15", nil, "New message", "Whisper a guildmate")
  local online = {}
  for name, r in pairs(ns.roster) do if r.online and name ~= ns.me then online[#online + 1] = name end end
  table.sort(online)
  local box = det:Field("To", "", 160)
  local function Start(name)
    name = ns.Member and ns.Member(name) or name
    if not name or name == "" then return ns.Print("Type a character name.") end
    ns.UI:OpenDetails("chatwith", "w:" .. name)
  end
  box.onEnter = function() Start(box:GetText()) end
  det:Buttons({ { "Start", function() Start(box:GetText()) end, accent = true } })
  if #online > 0 then
    det:Section("Online guildmates")
    local row = {}
    for i, name in ipairs(online) do
      if i > 30 then break end
      row[#row + 1] = { ns.Short and ns.Short(name) or name, function() Start(name) end }
      if #row == 3 then det:Buttons(row); row = {} end
    end
    if #row > 0 then det:Buttons(row) end
  end
  return true
end
local function FillChatSettings(det)
  local c = ChatDB()
  local UI = ns.UI
  det:Reset("Interface\\Icons\\INV_Misc_Gear_01", nil, "Chat settings", "Saved on this PC only and never shared with the guild")
  for _, k in ipairs(CHANNEL_ORDER) do
    if k ~= "officer" or CanOfficerChat() then
      local keep = ns.ChatKeep(k)
      det:Buttons({ { (keep and "[x] " or "[ ] ") .. "Keep " .. CHANNELS[k].label:lower(), function()
          ns.SetChatKeep(k, not keep); UI:FillDetails(); UI:Refresh() end },
        #c.chatlog[k] > 0 and { "Clear", function() wipe(c.chatlog[k]); UI:FillDetails(); UI:Refresh() end,
          tip = "Delete saved " .. CHANNELS[k].label:lower() .. " from this PC" } or nil })
    end
  end
  det:Buttons({ { (c.chatkeep.replay ~= false and "[x] " or "[ ] ") .. "Show the last hour after a reload", function()
    c.chatkeep.replay = c.chatkeep.replay == false; UI:FillDetails() end } })
  det:Text("Whispers are kept by default. Battle.net whispers aren't kept, and messages the game hides in combat are saved as a placeholder.", nil)
  return true
end
local fillBefore = ns.FillCommunityDetails
ns.FillCommunityDetails = function(kind, key, det)
  if kind == "chatwith" then return FillChatWith(det, key) end
  if kind == "chatnew" then return FillChatNew(det) end
  if kind == "chatsettings" then return FillChatSettings(det) end
  if kind == "chathistory" then ns.ShowChatHistory(key); return true end
  return fillBefore(kind, key, det)
end
