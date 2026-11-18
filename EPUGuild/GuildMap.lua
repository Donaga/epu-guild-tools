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
  party = { label = "Party chat", group = "PARTY", info = "PARTY", short = "Party", send = "PARTY", color = "|cffaaaaff",
    icon = "Interface\\Icons\\INV_Misc_GroupNeedMore" },
  raid = { label = "Raid chat", group = "RAID", info = "RAID", short = "Raid", send = "RAID", color = "|cffff7f00",
    icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01" },
}
CHANNELS.guild.short, CHANNELS.guild.send, CHANNELS.guild.color = "Guild", "GUILD", "|cff40ff40"
CHANNELS.guild.icon = "Interface\\Icons\\INV_Shirt_GuildTabard_01"
CHANNELS.officer.short, CHANNELS.officer.send, CHANNELS.officer.color = "Officer", "OFFICER", "|cff40c040"
CHANNELS.officer.icon = "Interface\\Icons\\INV_Misc_Key_03"
local CHANNEL_ORDER = { "whisper", "guild", "officer", "party", "raid" }
-- the group chats, shown pinned above whispers
local GROUP_CHANNELS = { "guild", "officer", "party", "raid" }
ns.CHAT_GROUP_CHANNELS = GROUP_CHANNELS

-- Chat is shared by all characters on this account (and still only on this
-- PC): whispers, party and raid in one place, guild and officer chat per guild.
local MigrateChat
local function ChatDB()
  local db = ns.db
  if not db then return nil end
  db.chat = db.chat or {}
  local c = db.chat
  c.chatlog = c.chatlog or {}
  c.guilds = c.guilds or {}
  c.chatkeep = c.chatkeep or { whisper = true, guild = false, officer = false, replay = true }
  -- party and raid chat are kept unless turned off
  if c.chatkeep.party == nil then c.chatkeep.party = true end
  if c.chatkeep.raid == nil then c.chatkeep.raid = true end
  for _, k in ipairs({ "whisper", "party", "raid" }) do c.chatlog[k] = c.chatlog[k] or {} end
  -- Guild chat is kept by default since 0.28 (the game keeps it on its server
  -- anyway); only a choice someone made themselves is left alone.
  if not c.guildKeepDefault then
    c.guildKeepDefault = true
    if not c.guildKeepChosen then c.chatkeep.guild = true end
  end
  if ns.cdb and ns.cdb.chatlog and MigrateChat then MigrateChat(c, ns.cdb) end
  return c
end
local function LogTable(c, channel)
  if channel == "guild" or channel == "officer" then
    local gk = (ns.GuildKey and ns.GuildKey()) or "none"
    c.guilds[gk] = c.guilds[gk] or {}
    c.guilds[gk][channel] = c.guilds[gk][channel] or {}
    return c.guilds[gk][channel]
  end
  c.chatlog[channel] = c.chatlog[channel] or {}
  return c.chatlog[channel]
end
-- One-time move of a character's chat from before 0.28 into the shared store.
MigrateChat = function(c, cdb)
  if not (ns.GuildKey and ns.GuildKey()) and (next(cdb.chatlog.guild or {}) or next(cdb.chatlog.officer or {})) then return end
  for ch, lines in pairs(cdb.chatlog) do
    if type(lines) == "table" and CHANNELS[ch] then
      local dest = LogTable(c, ch)
      for _, e in ipairs(lines) do
        if type(e) == "table" and e.t then
          e.me = e.me or (ch == "whisper" and ns.me or nil)
          dest[#dest + 1] = e
        end
      end
      table.sort(dest, function(a, b) return (a.t or 0) < (b.t or 0) end)
      while #dest > CHAT_KEEP do table.remove(dest, 1) end
    end
  end
  for k, v in pairs(cdb.chatkeep or {}) do if v == true then c.chatkeep[k] = true end end
  if cdb.chatkeep and cdb.chatkeep.replay == false then c.chatkeep.replay = false end
  c.chatOpts = c.chatOpts or cdb.chatOpts
  c.chatColors = c.chatColors or cdb.chatColors
  c.messenger = c.messenger or cdb.messenger
  c.chatSeen = c.chatSeen or {}
  for k, t in pairs(cdb.chatSeen or {}) do if (c.chatSeen[k] or 0) < t then c.chatSeen[k] = t end end
  c.chatSeenAt = math.max(c.chatSeenAt or 0, cdb.chatSeenAt or 0)
  cdb.chatlog, cdb.chatkeep, cdb.chatOpts, cdb.chatColors, cdb.messenger, cdb.chatSeen, cdb.chatSeenAt = nil
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
  if c then
    c.chatkeep[channel] = on and true or false
    if channel == "guild" then c.guildKeepChosen = true end
    if on and (channel == "guild" or channel == "officer") and ns.PullGuildHistory then ns.PullGuildHistory() end
  end
end
local function Plain(v)
  if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
  if type(v) ~= "string" then return nil end
  return v
end
function ns.LogChat(channel, who, msg, out, sys)
  if not ns.ChatKeep(channel) then return end
  who = Plain(who)
  if not who or who == "" then return end
  local text = Plain(msg) or "(the game hid this message)"
  local log = LogTable(ChatDB(), channel)
  -- sys: "on" / "off" for a guildmate coming online or going offline; these
  -- never count as unread
  log[#log + 1] = { t = time(), who = who, msg = text, out = (out or sys) and true or nil, sys = sys,
    me = channel == "whisper" and ns.me or nil }
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
  return c and LogTable(c, channel) or {}
end
ns.On("CHAT_MSG_WHISPER", function(msg, sender) ns.LogChat("whisper", sender, msg, false); if ns.ChatIncoming then ns.ChatIncoming("whisper", sender, msg) end end)
ns.On("CHAT_MSG_WHISPER_INFORM", function(msg, target) ns.LogChat("whisper", target, msg, true) end)
local function Mine(sender)
  sender = Plain(sender)
  return sender ~= nil and ns.Short and ns.Short(sender) == ns.me
end
local function Group(channel)
  return function(msg, sender)
    local mine = Mine(sender)
    ns.LogChat(channel, sender, msg, mine)
    if not mine and ns.ChatIncoming then ns.ChatIncoming(channel, sender, msg) end
  end
end
ns.On("CHAT_MSG_GUILD", Group("guild"))
ns.On("CHAT_MSG_OFFICER", Group("officer"))
for _, ev in ipairs({ "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER" }) do ns.On(ev, Group("party")) end
-- Guild chat history from the game's server. The Guild & Communities window
-- keeps guild (and officer) chat from before you logged in; EPU reads the same
-- history so its Guild chat has it too. Lines it already has are skipped.
local function Readable(v)
  if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
  return v
end
-- Live chat gives names with the realm ("Name-Realm"), the server history
-- without, so compare short names.
local function SameLine(x, e)
  if x.id and e.id then return x.id == e.id end
  local a = ns.Short and ns.Short(x.who or "") or x.who
  local b = ns.Short and ns.Short(e.who or "") or e.who
  return a == b and x.msg == e.msg and (x.sys or false) == (e.sys or false) and math.abs((x.t or 0) - (e.t or 0)) <= 180
end
-- Remove repeats of the same line from the same person a moment apart.
local function DedupeLog(log)
  local out, removed = {}, 0
  for _, e in ipairs(log) do
    local dup = false
    for i = #out, math.max(1, #out - 60), -1 do
      if SameLine(out[i], e) then dup = true; break end
      if (e.t or 0) - (out[i].t or 0) > 180 then break end
    end
    if dup then removed = removed + 1 else out[#out + 1] = e end
  end
  if removed > 0 then
    for i = 1, #out do log[i] = out[i] end
    for i = #log, #out + 1, -1 do log[i] = nil end
  end
  return removed
end
ns.ChatDedupe = DedupeLog
-- Every guild message has its own server time stamp (to the microsecond),
-- kept as e.id. A line EPU saw live gets the id of the matching server
-- message, so the same line is never added twice and a real repeat ("nn",
-- "nn") stays as two lines.
local function MergeHistory(channel, entries)
  if #entries == 0 or not ns.ChatKeep(channel) then return 0 end
  local log = LogTable(ChatDB(), channel)
  local added = 0
  local ids = {}
  for _, x in ipairs(log) do if x.id then ids[x.id] = x end end
  for _, e in ipairs(entries) do
    local dup = e.id and ids[e.id] ~= nil
    if not dup then
      -- the closest live line without an id that says the same thing
      local best, bestGap
      for i = #log, math.max(1, #log - 400), -1 do
        local x = log[i]
        if not x.id and SameLine(x, e) then
          local gap = math.abs((x.t or 0) - e.t)
          if not best or gap < bestGap then best, bestGap = x, gap end
        end
      end
      if best then
        best.id = e.id; best.t = e.t   -- the server's time is the exact one
        if e.id then ids[e.id] = best end
        dup = true
      end
    end
    if not dup and time() - e.t < CHAT_MAX_AGE then
      log[#log + 1] = e; added = added + 1
      if e.id then ids[e.id] = e end
    end
  end
  if added > 0 then
    table.sort(log, function(a, b) return (a.t or 0) < (b.t or 0) end)
    while #log > CHAT_KEEP do table.remove(log, 1) end
    -- history from before now isn't "new": don't let it flood the unread counts
    local c = ChatDB()
    c.chatSeen = c.chatSeen or {}
    local newest = 0
    for _, e in ipairs(entries) do newest = math.max(newest, e.t) end
    if (c.chatSeen[channel] or 0) == 0 then c.chatSeen[channel] = newest end
  end
  return added
end
function ns.PullGuildHistory()
  local c = ChatDB()
  if c and not c.dedupedV1 then
    c.dedupedV1 = true
    for _, g in pairs(c.guilds or {}) do
      for _, log in pairs(g) do if type(log) == "table" then DedupeLog(log) end end
    end
  end
  if not (C_Club and C_Club.GetGuildClubId and C_Club.GetStreams and C_Club.GetMessageRanges and C_Club.GetMessagesInRange) then return 0 end
  local ok, clubId = pcall(C_Club.GetGuildClubId)
  if not ok or not clubId then return 0 end
  local okS, streams = pcall(C_Club.GetStreams, clubId)
  if not okS or type(streams) ~= "table" then return 0 end
  local total = 0
  for _, st in ipairs(streams) do
    local kind = Enum and Enum.ClubStreamType and ((st.streamType == Enum.ClubStreamType.Guild and "guild") or (st.streamType == Enum.ClubStreamType.Officer and "officer")) or nil
    if not kind and type(st.name) == "string" then kind = (st.name == (GUILD or "Guild") and "guild") or (st.name == (OFFICER or "Officer") and "officer") or nil end
    if kind and (kind ~= "officer" or CanOfficerChat()) and ns.ChatKeep(kind) then
      local entries = {}
      local okR, ranges = pcall(C_Club.GetMessageRanges, clubId, st.streamId)
      for _, r in ipairs(okR and type(ranges) == "table" and ranges or {}) do
        local okM, msgs = pcall(C_Club.GetMessagesInRange, clubId, st.streamId, r.oldestMessageId, r.newestMessageId)
        for _, m in ipairs(okM and type(msgs) == "table" and msgs or {}) do
          local author = m.author and Readable(m.author.name)
          local content = Readable(m.content)
          local epoch = m.messageId and Readable(m.messageId.epoch)
          if type(author) == "string" and type(content) == "string" and content ~= "" and type(epoch) == "number" and not m.destroyed then
            local short = ns.Short and ns.Short(author) or author
            entries[#entries + 1] = { t = math.floor(epoch / 1000000), id = epoch, who = short, msg = content, out = short == ns.me or nil }
          end
        end
      end
      total = total + MergeHistory(kind, entries)
      -- ask the server for a bit more history the first time
      if C_Club.RequestMoreMessagesBefore and not ns.chatHistoryAsked then
        pcall(C_Club.RequestMoreMessagesBefore, clubId, st.streamId, nil, 50)
      end
    end
  end
  ns.chatHistoryAsked = true
  if total > 0 then
    if ns.MessengerChanged then ns.MessengerChanged("guild", nil, false) end
    if ns.UI and ns.UI:IsShown() and ns.UI.view == "chat" then ns.Changed() end
  end
  return total
end
ns.On("CLUB_MESSAGE_ADDED", function(clubId, streamId, messageId)
  if not (C_Club and C_Club.GetGuildClubId and C_Club.GetMessageInfo) then return end
  local ok, gid = pcall(C_Club.GetGuildClubId)
  if not ok or gid ~= clubId then return end
  ns.Debounce("guildHistory", 1, ns.PullGuildHistory)
end)
ns.On("CLUB_MESSAGE_HISTORY_RECEIVED", function() ns.Debounce("guildHistory", 1, ns.PullGuildHistory) end)
ns.On("PLAYER_LOGIN", function() if C_Timer then C_Timer.After(8, ns.PullGuildHistory) end end)
ns.On("PLAYER_GUILD_UPDATE", function() ns.Debounce("guildHistory", 5, ns.PullGuildHistory) end)

-- Guildmates coming online and going offline, shown in Guild chat. The game
-- announces both as system messages; only guild members are kept.
local function SystemPattern(fmt)
  if type(fmt) ~= "string" then return nil end
  fmt = fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.-)"):gsub("%%%%d", "%%d+")
  return "^" .. fmt .. "$"
end
ns.On("CHAT_MSG_SYSTEM", function(msg)
  msg = Plain(msg)
  if not msg or not ns.ChatKeep("guild") or (ns.ChatOptions and ns.ChatOptions().presence == false) then return end
  local on = SystemPattern(ERR_FRIEND_ONLINE_SS or "|Hplayer:%s|h[%s]|h has come online.")
  local off = SystemPattern(ERR_FRIEND_OFFLINE_S or "%s has gone offline.")
  local name, state = on and msg:match(on), "on"
  if not name and off then name = msg:match(off); state = "off" end
  if not name then return end
  local short = ns.Short and ns.Short(name) or name
  if not ns.roster[short] or short == ns.me then return end
  ns.LogChat("guild", short, state == "on" and "came online" or "went offline", true, state)
end)
for _, ev in ipairs({ "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING" }) do ns.On(ev, Group("raid")) end

local function Hex(info)
  local t = ChatTypeInfo and ChatTypeInfo[info]
  if not t then return "|cffffffff" end
  return string.format("|cff%02x%02x%02x", (t.r or 1) * 255, (t.g or 1) * 255, (t.b or 1) * 255)
end
-- Colors follow the game's own chat colors (Chat settings in the game), unless
-- you pick your own for a chat in EPU's Chat settings. Sent whispers use the
-- game's "whisper sent" color.
local FALLBACK = { whisper = { 1, 0.5, 1 }, whisperOut = { 1, 0.5, 1 }, guild = { 0.25, 1, 0.25 },
  officer = { 0.25, 0.75, 0.25 }, party = { 0.67, 0.67, 1 }, raid = { 1, 0.5, 0 } }
local function ColorKey(channel, out) return (channel == "whisper" and out) and "whisperOut" or channel end
function ns.ChatColorRGB(channel, out, who)
  local key = ColorKey(channel, out)
  local colors = (ChatDB() or {}).chatColors
  -- a color picked for one person wins for their whispers to you
  local person = colors and channel == "whisper" and not out and who and colors["w:" .. who]
  if type(person) == "table" and type(person[1]) == "number" then return person[1], person[2], person[3], true end
  local c = colors and colors[key]
  if type(c) == "table" and type(c[1]) == "number" then return c[1], c[2], c[3], true end
  local info = key == "whisperOut" and "WHISPER_INFORM" or CHANNELS[channel].info
  local t = ChatTypeInfo and ChatTypeInfo[info]
  if t and t.r then return t.r, t.g, t.b, false end
  local f = FALLBACK[key] or { 1, 1, 1 }
  return f[1], f[2], f[3], false
end
local function ChatColor(channel, out, who)
  local r, g, b = ns.ChatColorRGB(channel, out, who)
  return string.format("|cff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end
ns.ChatColor = ChatColor
local function PlayerLink(who)
  return "|Hplayer:" .. who .. "|h[" .. (ns.Short and ns.Short(who) or who) .. "]|h"
end
local function FormatLine(channel, e)
  local stamp = date("%H:%M", e.t)
  local color = ChatColor(channel, e.out, e.who)
  local body
  if channel == "whisper" then
    body = e.out and ("To " .. PlayerLink(e.who) .. ": " .. e.msg) or (PlayerLink(e.who) .. " whispers: " .. e.msg)
  else
    body = "[" .. (CHANNELS[channel].short or channel) .. "] " .. PlayerLink(e.who) .. (e.sys and " " or ": ") .. e.msg
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
      local log, lines = LogTable(c, channel), {}
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
-- Unread is kept per conversation: "w:<name>", "guild" or "officer".
local function SeenAt(key)
  local c = ChatDB()
  if not c then return 0 end
  c.chatSeen = c.chatSeen or {}
  return c.chatSeen[key] or c.chatSeenAt or 0
end
function ns.ChatUnreadFor(key)
  local c = ChatDB()
  if not c then return 0 end
  local channel = key:sub(1, 2) == "w:" and "whisper" or key
  if channel ~= "whisper" and not ns.ChatKeep(channel) then return 0 end
  local who = channel == "whisper" and key:sub(3) or nil
  local seen, n = SeenAt(key), 0
  local log = LogTable(c, channel)
  for i = #log, 1, -1 do
    local e = log[i]
    if (e.t or 0) <= seen then break end
    if not e.out and (not who or e.who == who) then n = n + 1 end
  end
  return n
end
-- all unread whispers, across people
function ns.ChatUnread()
  local n = 0
  for _, conv in ipairs(ns.ChatConversations()) do n = n + conv.unread end
  return n
end
-- unread guild (and, for officers who keep it, officer) messages
function ns.ChatUnreadGuild()
  return ns.ChatUnreadFor("guild") + (CanOfficerChat() and ns.ChatUnreadFor("officer") or 0)
end
function ns.MarkChatSeen(key)
  local c = ChatDB()
  if not c or not key then return end
  c.chatSeen = c.chatSeen or {}
  c.chatSeen[key] = time()
end
-- One row per person you whispered with, newest conversation first.
function ns.ChatConversations()
  local log, seen, out = ns.ChatLog("whisper"), {}, {}
  for i = #log, 1, -1 do
    local e = log[i]
    local c = seen[e.who]
    if not c then
      c = { who = e.who, last = e, n = 0, unread = 0, since = SeenAt("w:" .. e.who) }
      seen[e.who] = c; out[#out + 1] = c
    end
    c.n = c.n + 1
    if not e.out and (e.t or 0) > c.since then c.unread = c.unread + 1 end
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
  if CHANNELS[key] and CHANNELS[key].send then SendChatMessage(text, CHANNELS[key].send)
  else SendChatMessage(text, "WHISPER", nil, key:sub(3)) end
  return true
end
local function ThreadKey(key)
  if not (CHANNELS[key] and key ~= "whisper") and key:sub(1, 2) ~= "w:" then key = "w:" .. key end
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
  local color = ChatColor(channel, e.out)
  return "|cff888888" .. date("%H:%M", e.t) .. "|r  " .. speaker .. "\n" .. color .. e.msg .. "|r"
end
-- Group a thread (newest first) for display: a gold day header, then the
-- speaker's name and time once, with their messages under it, the way chat
-- apps group consecutive messages.
-- Chat options, saved per character.
local function Opt()
  local c = ChatDB()
  if not c then return {} end
  c.chatOpts = c.chatOpts or {}
  local o = c.chatOpts
  if o.windows == nil then o.windows = "tabs" end      -- "tabs" or "separate"
  if o.pop == nil then o.pop = false end                -- open a window when a whisper arrives
  if o.combat == nil then o.combat = true end           -- tuck chat windows away in combat
  if o.fade == nil then o.fade = false end              -- fade when the mouse is elsewhere
  if o.mentions == nil then o.mentions = true end       -- alert when your name comes up
  o.words = o.words or {}
  o.sounds = o.sounds or {}
  if o.sounds.mention == nil then o.sounds.mention = 3081 end
  if o.typing == nil then o.typing = true end
  if o.lineTimes == nil then o.lineTimes = true end     -- time on every message
  return o
end
ns.ChatOptions = Opt
-- Reading font for chat: which font, size and outline (Chat settings > Text).
ns.CHAT_FONTS = {
  { label = "EPU (Inter)", value = "epu" },
  { label = "Game (Friz Quadrata)", value = "friz", path = "Fonts\\FRIZQT__.TTF" },
  { label = "Chat (Arial Narrow)", value = "arial", path = "Fonts\\ARIALN.TTF" },
  { label = "Skurri", value = "skurri", path = "Fonts\\skurri.ttf" },
  { label = "Morpheus", value = "morpheus", path = "Fonts\\MORPHEUS.TTF" },
}
function ns.ChatFont()
  local o = Opt()
  local path
  for _, f in ipairs(ns.CHAT_FONTS) do if f.value == (o.font or "epu") then path = f.path end end
  if not path then path = ns.UIKit and ns.UIKit.FONT or STANDARD_TEXT_FONT end
  local size = math.max(9, math.min(22, tonumber(o.size) or 12))
  return path, size, o.outline and "OUTLINE" or ""
end
local function ApplyFont(fs, base)
  local path, size, flags = ns.ChatFont()
  size = size + (base or 0)
  if fs:SetFont(path, size, flags) == false then fs:SetFont(ns.UIKit and ns.UIKit.FallbackFont or STANDARD_TEXT_FONT, size, flags) end
end
ns.ApplyChatFont = ApplyFont
-- Strip colors, links and icons for copying.
local function PlainText(msg)
  msg = tostring(msg or "")
  msg = msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  msg = msg:gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""):gsub("||", "|")
  return msg
end
ns.ChatPlainText = PlainText
-- Web addresses become clickable links (click to copy).
local function Linkify(msg, color)
  local function L(url) return "|cff66b8ff|Hepuurl:" .. url .. "|h" .. url .. "|h|r" .. (color or "") end
  msg = msg:gsub("(https?://[%w%-%._~:/%?#@!%$&%*%+,;=%%]+)", L)
  msg = msg:gsub("(%f[%w]www%.[%w%-%.]+%.[%a][%w%-%._~:/%?#@!%$&%*%+,;=%%]*)", function(url)
    return L(url)
  end)
  return msg
end
ns.ChatLinkify = Linkify
-- "Alt (Main)" when EPU knows the main.
local function Display(who)
  local short = ns.Short and ns.Short(who) or who
  local main = ns.MainOf and ns.MainOf(short)
  if main and main ~= short then return short .. " |cff888888(" .. main .. ")|r", short end
  return short, short
end
ns.ChatDisplayName = Display
-- Typing indicators from guildmates who use EPU.
local typingAt = {}
function ns.ChatTyping(who)
  local short = ns.Short and ns.Short(who) or who
  local at = typingAt[short]
  return at ~= nil and GetTime() - at < 6
end
local function ThreadBlocks(channel, lines, plains)
  local blocks, lastDay, cur = {}, nil, nil
  for _, e in ipairs(lines) do
    local day = date("%A %d %B", e.t)
    if day ~= lastDay then blocks[#blocks + 1] = { day = "|cfff2c14e" .. day .. "|r" }; lastDay = day; cur = nil end
    local speaker = e.out and "You" or (ns.Short and ns.Short(e.who) or e.who)
    if e.sys then
      local who = Display(e.who)
      blocks[#blocks + 1] = { line = "|cff888888" .. date("%H:%M", e.t) .. "  |r" .. (e.sys == "on" and "|TInterface\\COMMON\\Indicator-Green:12:12|t " or "|TInterface\\COMMON\\Indicator-Gray:12:12|t ")
        .. "|cffaaaaaa" .. who .. (e.sys == "on" and " came online" or " went offline") .. "|r" }
      cur = nil
      speaker = nil
    end
    if not speaker then
    elseif not cur or cur.speaker ~= speaker or cur.me ~= e.me or math.abs((cur.t or 0) - (e.t or 0)) > 600 then
      cur = { speaker = speaker, who = e.who, t = e.t, out = e.out, me = e.me, msgs = {}, plain = {} }
      blocks[#blocks + 1] = cur
    end
    if speaker then
      local color = ChatColor(channel, e.out, e.who)
      local stamp = Opt().lineTimes and ("|cff777777" .. date("%H:%M", e.t) .. "|r  ") or ""
      table.insert(cur.msgs, 1, stamp .. color .. Linkify(e.msg, color) .. "|r")
      table.insert(cur.plain, 1, "[" .. date("%H:%M", e.t) .. "] " .. (e.out and (ns.me or "You") or speaker) .. ": " .. PlainText(e.msg))
    end
  end
  local out = {}
  for _, b in ipairs(blocks) do
    if b.day then out[#out + 1] = b.day
    elseif b.line then out[#out + 1] = b.line
    else
      local n = 1
      if plains then plains[#plains + 1] = table.concat(b.plain, "\n"); n = #plains end
      local name = b.out and "|cff9fb4c8You|r" or ("|cffffffff|Hplayer:" .. b.who .. "|h" .. Display(b.who) .. "|h|r")
      local stamp = plains and ("|cff888888|Hepublock:" .. n .. "|h" .. date("%H:%M", b.t) .. "|h|r") or ("|cff888888" .. date("%H:%M", b.t) .. "|r")
      -- messages inside a block are oldest first, like normal chat; blocks are newest first
      local on = (b.me and b.me ~= ns.me) and ("  |cff888888on " .. b.me .. "|r") or ""
      out[#out + 1] = name .. "  " .. stamp .. on .. "\n" .. table.concat(b.msgs, "\n")
    end
  end
  return out
end
ns.ChatThreadKey, ns.ChatThreadLines, ns.ChatLineText, ns.ChatSend, ns.ChatThreadBlocks = ThreadKey, ThreadLines, LineText, Send, ThreadBlocks

-- A whole conversation as text: plain, Discord (Markdown) or BBCode, oldest first.
function ns.ChatConversationText(key, fmt)
  local lines, channel = ThreadLines(key, 300)
  local out = {}
  for i = #lines, 1, -1 do
    local e = lines[i]
    local who = (e.out and not e.sys) and (ns.me or "You") or (ns.Short and ns.Short(e.who) or e.who)
    local msg = PlainText(e.msg)
    local stamp = date("%Y-%m-%d %H:%M", e.t)
    if e.sys then
      out[#out + 1] = (fmt == "discord" and ("_" .. who .. " " .. msg .. "_ `" .. date("%H:%M", e.t) .. "`")) or ("[" .. stamp .. "] " .. who .. " " .. msg)
    elseif fmt == "discord" then
      out[#out + 1] = "**" .. who .. "** `" .. date("%H:%M", e.t) .. "` " .. msg
    elseif fmt == "bbcode" then
      msg = msg:gsub("(https?://%S+)", "[url]%1[/url]")
      out[#out + 1] = "[color=#888888]" .. stamp .. "[/color] [b]" .. who .. "[/b]: " .. msg
    else
      out[#out + 1] = "[" .. stamp .. "] " .. who .. ": " .. msg
    end
  end
  local title = channel == "whisper" and ("Whispers with " .. (ns.Short and ns.Short(key:sub(3)) or key:sub(3))) or CHANNELS[channel].label
  if fmt == "discord" then table.insert(out, 1, "__" .. title .. "__") elseif fmt == "bbcode" then table.insert(out, 1, "[b]" .. title .. "[/b]") end
  return table.concat(out, "\n")
end
-- Copy window: text selected, ready for Ctrl+C.
local Copy
function ns.ShowCopy(text, title, key)
  local K = ns.UIKit
  if not K then return end
  if not Copy then
    local C = K.C
    Copy = CreateFrame("Frame", "EPUGuildCopy", UIParent)
    Copy:SetSize(460, 280)
    Copy:SetPoint("CENTER")
    Copy:SetFrameStrata("DIALOG")
    Copy:SetToplevel(true)
    Copy:EnableMouse(true)
    Copy:SetMovable(true)
    Copy:RegisterForDrag("LeftButton")
    Copy:SetScript("OnDragStart", Copy.StartMoving)
    Copy:SetScript("OnDragStop", Copy.StopMovingOrSizing)
    local bg = K.Tex(Copy, "BACKGROUND", C.bg or C.panel); bg:SetAllPoints()
    local edge = K.Tex(Copy, "BORDER", C.gold); edge:SetPoint("TOPLEFT"); edge:SetPoint("TOPRIGHT"); edge:SetHeight(2)
    Copy.title = K.Font(Copy, 13, C.gold)
    Copy.title:SetPoint("TOPLEFT", 12, -10)
    Copy.hint = K.Font(Copy, 11, C.muted)
    Copy.hint:SetPoint("TOPLEFT", Copy.title, "BOTTOMLEFT", 0, -3)
    Copy.hint:SetText("Press Ctrl+C to copy, then Esc to close.")
    Copy.close = K.Btn(Copy, "x", 22, 20)
    Copy.close:SetPoint("TOPRIGHT", -8, -8)
    Copy.close:SetScript("OnClick", function() Copy:Hide() end)
    Copy.scroll = CreateFrame("ScrollFrame", nil, Copy)
    Copy.scroll:SetPoint("TOPLEFT", 12, -48)
    Copy.scroll:SetPoint("BOTTOMRIGHT", -12, 40)
    Copy.edit = CreateFrame("EditBox", nil, Copy.scroll)
    Copy.edit:SetMultiLine(true)
    Copy.edit:SetAutoFocus(true)
    Copy.edit:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
    Copy.edit:SetWidth(430)
    Copy.edit:SetScript("OnEscapePressed", function() Copy:Hide() end)
    Copy.scroll:SetScrollChild(Copy.edit)
    Copy.scroll:EnableMouseWheel(true)
    Copy.scroll:SetScript("OnMouseWheel", function(self, d)
      self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange() or 0, self:GetVerticalScroll() - d * 40)))
    end)
    Copy.formats = {}
    for i, f in ipairs({ { "plain", "Plain text" }, { "discord", "Discord" }, { "bbcode", "BBCode" } }) do
      local b = K.Btn(Copy, f[2], 90, 22)
      b:SetPoint("BOTTOMLEFT", 12 + (i - 1) * 96, 10)
      b:SetScript("OnClick", function()
        if Copy.key then ns.ShowCopy(ns.ChatConversationText(Copy.key, f[1]), Copy.title:GetText(), Copy.key); Copy.fmt = f[1] end
      end)
      b.fmt = f[1]
      Copy.formats[i] = b
    end
  end
  Copy.key = key
  Copy.title:SetText(title or "Copy")
  for _, b in ipairs(Copy.formats) do b:SetShown(key ~= nil); b:SetOn((Copy.fmt or "plain") == b.fmt) end
  Copy.edit:SetText(text or "")
  Copy:Show()
  Copy.edit:SetFocus()
  Copy.edit:HighlightText()
end
-- Clicks on links inside EPU's chat: web addresses and time stamps copy,
-- names open the conversation, items show their tooltip as usual.
function ns.ChatLinkClick(owner, link, text, button, openName)
  if type(link) ~= "string" then return end
  local kind, rest = link:match("^(%w+):(.*)$")
  if kind == "epuurl" then return ns.ShowCopy(rest, "Link") end
  if kind == "epublock" then
    local t = owner and owner.blockPlain and owner.blockPlain[tonumber(rest)]
    if t then return ns.ShowCopy(t, "Messages") end
    return
  end
  if kind == "player" and openName then
    local name = rest:match("^([^:]+)")
    if name then return openName(name) end
  end
  if SetItemRef then pcall(SetItemRef, link, text, button) end
end
local function FillChatWith(det, key)
  local UI = ns.UI
  key = ThreadKey(key)
  if (key == "guild" or key == "officer") and not det.epuHistoryPulled then
    det.epuHistoryPulled = true
    ns.PullGuildHistory()
  end
  if key == "officer" and not CanOfficerChat() then UI:CloseDetails(); return true end
  local lines, channel, who = ThreadLines(key, 60)
  local short = who and (ns.Short and ns.Short(who) or who)
  local member = who and ns.roster[short]
  det:Reset(channel == "whisper" and ((member and ns.ClassIcon(member.classFile)) or "Interface\\Icons\\INV_Letter_15")
      or CHANNELS[channel].icon,
    nil, who and Display(who) or CHANNELS[channel].label, who and ((ns.ChatTyping(who) and "|cff4ade80typing...|r · " or "") .. (member and ((member.online and "Online" or "Offline") .. (member.zone and member.online and (" · " .. member.zone) or "")
      .. " · level " .. (member.level or "?")) or "Whispers")) or "Saved on this PC")
  -- links in the thread: web addresses copy, names open their conversation
  local body = det.body
  if body and body.SetHyperlinksEnabled and not body.epuLinks then
    body.epuLinks = true
    body:SetHyperlinksEnabled(true)
    body:SetScript("OnHyperlinkClick", function(self, link, text, button)
      ns.ChatLinkClick(self, link, text, button, function(name) UI:OpenDetails("chatwith", "w:" .. name) end)
    end)
  end
  if body then body.blockPlain = {} end
  det.textFont = { ns.ChatFont() }
  -- reply first, newest messages right under it
  local box = det:Field(who and "Reply" or "Say", "", math.max(160, det.panelWidth - 110))
  local function Go()
    if Send(key, box:GetText()) then
      box:SetText("")
      C_Timer.After(0.3, function() if UI.details.kind == "chatwith" and UI.details.key == key then UI:FillDetails() end end)
    end
  end
  box.onEnter = Go
  box.onChange = function(self) ns.ChatTypingPing(key, self:GetText()) end
  local buttons = { { "Send", Go, accent = true, tip = "Or press Enter" } }
  if who then
    buttons[#buttons + 1] = { "Invite", function() local invite = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit; if invite then invite(who) end end }
    if member and ns.GuildmateMenu then buttons[#buttons + 1] = { "More", function(self) ns.GuildmateMenu(self, short) end } end
  end
  buttons[#buttons + 1] = { "Pop out", function() ns.OpenMessenger(key) end, tip = "Open this conversation in a small window you can move and minimize" }
  if who then
    buttons[#buttons + 1] = { ChatColor("whisper", false, who) .. "Color|r", function() ns.PickChatColor("whisper", false, who) end,
      tip = "Give " .. short .. "'s whispers their own color" .. (ns.HasPersonColor(who) and " (right now their own; pick again or use Chat settings to reset)" or "") }
  end
  buttons[#buttons + 1] = { "Copy", function() ns.ShowCopy(ns.ChatConversationText(key, "plain"), who and ("Whispers with " .. short) or CHANNELS[channel].label, key) end,
    tip = "Copy the conversation as plain text, Discord or BBCode. Click a time to copy just those messages." }
  det:Buttons(buttons)
  det:Gap(4)
  if #lines == 0 then det:Text(who and ("No saved whispers with " .. short .. " yet.") or "Nothing saved yet.", nil) end
  for _, block in ipairs(ThreadBlocks(channel, lines, body and body.blockPlain)) do det:Text(block) end
  ns.MarkChatSeen(key)
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
  for _, ch in ipairs(GROUP_CHANNELS) do
    if ns.ChatKeep(ch) and (ch ~= "officer" or CanOfficerChat()) then
      local n = ns.ChatUnreadFor(ch)
      items[#items + 1] = { label = CHANNELS[ch].label .. (n > 0 and (" (" .. n .. " new)") or ""), value = ch }
    end
  end
  for _, c in ipairs(ns.ChatConversations()) do
    items[#items + 1] = { label = (ns.Short and ns.Short(c.who) or c.who) .. (c.unread > 0 and (" (" .. c.unread .. " new)") or ""), value = "w:" .. c.who }
  end
  return items
end
-- Windows: "main" is the tabbed messenger; "w:<name>" are per-person windows
-- (Chat settings > Windows: one per person).
local Windows = {}
local function WState(id)
  local m = MState()
  if id == "main" then return m end
  m.people = m.people or {}
  m.people[id] = m.people[id] or {}
  return m.people[id]
end
local function SavePoint(f)
  local p, _, rp, x, y = f:GetPoint()
  if p then WState(f.id).point = { p, rp, x, y } end
end
local function BuildWindow(id)
  local K = ns.UIKit
  if Windows[id] or not K then return Windows[id] end
  local C = K.C
  local single = id ~= "main"
  local f = CreateFrame("Frame", (not single) and "EPUGuildMessenger" or nil, UIParent)
  Windows[id] = f
  if not single then Mgr = f end
  f.id, f.single = id, single
  f:SetSize(340, 400)
  f:SetFrameStrata("MEDIUM")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:SetResizable(true)
  if f.SetResizeBounds then f:SetResizeBounds(240, 160, 900, 1000) elseif f.SetMinResize then f:SetMinResize(240, 160) end
  f:EnableMouse(true)
  -- drag from anywhere that isn't a button or the text box
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePoint(self) end)
  local function Draggable(w)
    w:RegisterForDrag("LeftButton")
    w:SetScript("OnDragStart", function() f:StartMoving() end)
    w:SetScript("OnDragStop", function() f:StopMovingOrSizing(); SavePoint(f) end)
  end
  local bg = K.Tex(f, "BACKGROUND", C.bg or C.panel)
  bg:SetAllPoints()
  for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
    local t = K.Tex(f, "BORDER", C.line)
    t:SetPoint(side[1]); t:SetPoint(side[2])
    if side[3] then t:SetHeight(1) else t:SetWidth(1) end
  end
  local bar = CreateFrame("Frame", nil, f)
  bar:SetPoint("TOPLEFT"); bar:SetPoint("TOPRIGHT"); bar:SetHeight(28)
  bar:EnableMouse(true)
  Draggable(bar)
  f.bar = bar
  local barBg = K.Tex(bar, "BACKGROUND", C.panel2 or C.panel)
  barBg:SetAllPoints()
  f.pick = K.Btn(bar, "", 200, 20)
  f.pick:SetPoint("LEFT", 6, 0)
  Draggable(f.pick)
  if not single and K.AddDropdownArrow then K.AddDropdownArrow(f.pick) end
  f.pick.tip = single and "Drag to move. Click for whisper, invite and more." or "Switch conversation (drag to move)"
  f.pick:SetScript("OnClick", function(self)
    if single then
      local short = ns.Short and ns.Short(id:sub(3)) or id:sub(3)
      if ns.GuildmateMenu and ns.roster[short] then ns.GuildmateMenu(self, short) end
      return
    end
    K.OpenMenu(self, ConversationItems(), MState().key, function(v)
      if v then MState().key = v; f:Update() end
    end)
  end)
  f.close = K.Btn(bar, "x", 22, 20)
  f.close:SetPoint("RIGHT", -4, 0)
  f.close.tip = "Close"
  f.close:SetScript("OnClick", function() ns.CloseMessenger(id) end)
  f.min = K.Btn(bar, "-", 22, 20)
  f.min:SetPoint("RIGHT", f.close, "LEFT", -3, 0)
  f.min.tip = single and "Minimize to the chat bubble" or "Minimize to a small bubble"
  f.min:SetScript("OnClick", function() ns.MinimizeMessenger(true, id) end)
  f.copy = K.Btn(bar, "Copy", 44, 20)
  f.copy:SetPoint("RIGHT", f.min, "LEFT", -3, 0)
  f.copy.tip = "Copy this conversation (plain text, Discord or BBCode)"
  f.copy:SetScript("OnClick", function()
    local key = f:Key()
    if key then ns.ShowCopy(ns.ChatConversationText(key, "plain"), f.pick.text:GetText(), key) end
  end)
  f.full = K.Btn(bar, "Open", 44, 20)
  f.full:SetPoint("RIGHT", f.copy, "LEFT", -3, 0)
  f.full.tip = "Open the Chat page"
  f.full:SetScript("OnClick", function() ns.ShowChatHistory() end)
  f.body = CreateFrame("Frame", nil, f)
  f.body:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, 0)
  f.body:SetPoint("BOTTOMRIGHT")
  f.body:EnableMouse(true)
  Draggable(f.body)
  f.tabs = {}
  local top = single and -8 or -34
  f.box = K.Box(f.body, 200, "Type a message, Enter to send")
  f.box:SetPoint("TOPLEFT", 10, top)
  f.box:SetPoint("TOPRIGHT", -64, top)
  f.send = K.Btn(f.body, "Send", 50, 22, "accent")
  f.send:SetPoint("TOPRIGHT", -10, top)
  local function Go()
    local key = f:Key()
    if key and Send(key, f.box:GetText()) then
      f.box:SetText("")
      ns.ChatTypingPing(key, "")
    end
    f.box:SetFocus()
  end
  f.box.onEnter = Go
  f.box.onChange = function(self) local key = f:Key(); if key then ns.ChatTypingPing(key, self:GetText()) end end
  f.send:SetScript("OnClick", Go)
  f.scroll = CreateFrame("ScrollFrame", nil, f.body)
  f.scroll:SetPoint("TOPLEFT", 12, top - 32)
  f.scroll:SetPoint("BOTTOMRIGHT", -12, 16)
  f.child = CreateFrame("Frame", nil, f.scroll)
  f.child:SetSize(300, 10)
  f.scroll:SetScrollChild(f.child)
  f.text = K.Font(f.child, 12, C.text)
  f.text:SetPoint("TOPLEFT", 2, 0)
  if f.text.SetSpacing then f.text:SetSpacing(2) end
  f.text:SetJustifyH("LEFT"); f.text:SetJustifyV("TOP")
  f.text:SetWordWrap(true)
  if f.child.SetHyperlinksEnabled then
    f.child:SetHyperlinksEnabled(true)
    f.child:SetScript("OnHyperlinkClick", function(self, link, text, button)
      ns.ChatLinkClick(self, link, text, button, function(name)
        if single then return ns.OpenMessenger("w:" .. name) end
        MState().key = "w:" .. name; f:Update()
      end)
    end)
  end
  f.scroll:EnableMouseWheel(true)
  f.scroll:SetScript("OnMouseWheel", function(self, delta)
    local max = math.max(0, f.child:GetHeight() - self:GetHeight())
    self:SetVerticalScroll(math.min(max, math.max(0, self:GetVerticalScroll() - delta * 40)))
  end)
  f.grip = CreateFrame("Button", nil, f.body)
  f.grip:SetSize(16, 16)
  f.grip:SetPoint("BOTTOMRIGHT", -1, 1)
  f.grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  f.grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  f.grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
  f.grip:SetScript("OnMouseUp", function()
    f:StopMovingOrSizing()
    local st = WState(id); st.w, st.h = math.floor(f:GetWidth()), math.floor(f:GetHeight())
    f:Update()
  end)
  f:SetScript("OnSizeChanged", function() if f.body:IsShown() then f:Layout() end end)
  -- fade when the mouse is elsewhere (Chat settings)
  local fadeT = 0
  f:SetScript("OnUpdate", function(self, el)
    fadeT = fadeT + (el or 0)
    if fadeT < 0.2 then return end
    fadeT = 0
    local o = Opt()
    local over = not o.fade or (MouseIsOver and MouseIsOver(self)) or self.box:HasFocus()
    self:SetAlpha(over and 1 or 0.35)
  end)
  function f:Key()
    if single then return id end
    return MState().key
  end
  function f:Layout()
    local w = math.max(200, (self:GetWidth() or 340) - 30)
    self.child:SetWidth(w)
    self.text:SetWidth(w - 6)
    self.pick:SetWidth(math.max(90, (self:GetWidth() or 340) - 4 - 22 - 3 - 22 - 3 - 44 - 3 - 44 - 12))
    self.child:SetHeight(math.max(10, math.ceil(self.text:GetStringHeight() or 10)))
  end
  function f:Update()
    local st = WState(id)
    if not single and not MState().key then
      local first = ns.ChatConversations()[1]
      MState().key = first and ("w:" .. first.who) or (ns.ChatKeep("guild") and "guild" or nil)
    end
    local key = self:Key()
    local label
    if not key then label = "Chat"
    elseif key:sub(1, 2) == "w:" then
      label = Display(key:sub(3))
      if ns.ChatTyping(key:sub(3)) then label = label .. "  |cff4ade80typing...|r" end
    else label = CHANNELS[key].label end
    self.pick:SetLabel(label)
    if st.min then
      self:Hide()
      ns.RefreshChatBubble()
      return
    end
    self:Show()
    self.body:Show()
    self:SetHeight(st.h or (single and 300 or 400))
    local out = {}
    self.child.blockPlain = {}
    if key then
      local lines, channel = ThreadLines(key, 100)
      out = ThreadBlocks(channel, lines, self.child.blockPlain)
      ns.MarkChatSeen(key)
    end
    ApplyFont(self.text)
    if self.box.SetFont then ApplyFont(self.box) end
    self.text:SetText(#out > 0 and table.concat(out, "\n\n") or "|cff888888No messages yet. Type above to start.|r")
    self.box:SetShown(key ~= nil); self.send:SetShown(key ~= nil)
    self:Layout()
    if not single then self:Tabs() end
    ns.RefreshChatBubble()
  end
  function f:Tabs()
    local st = MState()
    if st.key and st.key:sub(1, 2) == "w:" then st.lastWhisper = st.key end
    local list = { { key = "tells", label = "Tells", n = ns.ChatUnread() } }
    for _, ch in ipairs(GROUP_CHANNELS) do
      if ns.ChatKeep(ch) then list[#list + 1] = { key = ch, label = CHANNELS[ch].short, n = ns.ChatUnreadFor(ch) } end
    end
    local width = (self:GetWidth() or 340) - 20
    local w = math.floor((width - (#list - 1) * 3) / #list)
    for i, t in ipairs(list) do
      local b = self.tabs[i]
      if not b then
        b = K.Btn(self.body, "", 60, 20)
        self.tabs[i] = b
      end
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", 10 + (i - 1) * (w + 3), -7)
      b:SetWidth(w)
      b:SetLabel(t.label .. (t.n > 0 and (" |cff4ade80" .. t.n .. "|r") or ""))
      local on = (t.key == "tells" and st.key and st.key:sub(1, 2) == "w:") or st.key == t.key
      b:SetOn(on and true or false)
      b.tip = t.key == "tells" and "Your whispers. Pick a person from the name at the top." or (CHANNELS[t.key].label .. ": read and reply here")
      b:SetScript("OnClick", function()
        if t.key == "tells" then
          local first = ns.ChatConversations()[1]
          st.key = st.lastWhisper or (first and ("w:" .. first.who)) or st.key
        else
          st.key = t.key
        end
        self:Update()
      end)
      b:Show()
    end
    for i = #list + 1, #self.tabs do self.tabs[i]:Hide() end
  end
  return f
end
local function BuildMessenger() return BuildWindow("main") end
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
  -- guild chat counter, bottom-right, in guild green-blue
  local gbadge = CreateFrame("Frame", nil, b)
  gbadge:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 5, -3)
  gbadge:SetSize(18, 16)
  local gfill = gbadge:CreateTexture(nil, "BACKGROUND")
  gfill:SetAllPoints()
  gfill:SetColorTexture(0.25, 0.55, 0.95, 1)
  gbadge.text = ns.InterfaceFont and ns.InterfaceFont(gbadge, 11, { 1, 1, 1 }) or gbadge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  gbadge.text:SetPoint("CENTER")
  b.gbadge = gbadge
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
    if button == "RightButton" then ns.ShowChatHistory() else ns.RestoreChatWindows() end
  end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Chat")
    local n, gn = ns.ChatUnread(), ns.ChatUnreadGuild()
    GameTooltip:AddLine(n == 0 and "No new whispers" or (n == 1 and "1 new whisper" or (n .. " new whispers")), 0.29, 0.87, 0.50)
    if ns.ChatKeep("guild") or ns.ChatKeep("officer") then
      GameTooltip:AddLine(gn == 0 and "No new guild messages" or (gn == 1 and "1 new guild message" or (gn .. " new guild messages")), 0.4, 0.65, 1)
    end
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
    for badge, n in pairs({ [self.badge] = ns.ChatUnread(), [self.gbadge] = ns.ChatUnreadGuild() }) do
      badge:SetShown(n > 0)
      badge.text:SetText(n > 99 and "99+" or tostring(n))
      badge:SetWidth(math.max(18, (badge.text:GetStringWidth() or 8) + 8))
    end
  end
  b:Hide()
  return b
end

-- Open a conversation in a window. With "one window per person" on, a whisper
-- gets its own window; group chats use the tabbed window.
function ns.OpenMessenger(key, minimized)
  key = key and ThreadKey(key) or nil
  local id = "main"
  if key and key:sub(1, 2) == "w:" and Opt().windows == "separate" then id = key end
  local f = BuildWindow(id)
  if not f then return end
  local st = WState(id)
  if id == "main" and key then st.key = key end
  st.open, st.min = true, minimized and true or false
  f:ClearAllPoints()
  if st.point then f:SetPoint(st.point[1], UIParent, st.point[2], st.point[3], st.point[4])
  elseif id ~= "main" then
    local n = 0
    for _, w in pairs(Windows) do if w ~= f and w:IsShown() then n = n + 1 end end
    f:SetPoint("RIGHT", UIParent, "RIGHT", -80 - n * 24, 40 - n * 24)
  else f:SetPoint("RIGHT", UIParent, "RIGHT", -80, 40) end
  f:SetSize(st.w or 340, st.h or (id == "main" and 400 or 300))
  f:Show()
  f:Update()
  return f
end
function ns.CloseMessenger(id)
  if id then
    WState(id).open = false
    if Windows[id] then Windows[id]:Hide() end
  else
    for wid, w in pairs(Windows) do WState(wid).open = false; w:Hide() end
  end
  ns.RefreshChatBubble()
end
-- on: minimize; id: one window (default every open one)
function ns.MinimizeMessenger(on, id)
  for wid, w in pairs(Windows) do
    if (not id or wid == id) and WState(wid).open then
      WState(wid).min = on and true or false
      w:Update()
    end
  end
  ns.RefreshChatBubble()
end
function ns.RestoreChatWindows()
  local any = false
  for wid, w in pairs(Windows) do
    local st = WState(wid)
    if st.open and st.min then st.min = false; w:Update(); any = true end
  end
  if not any then ns.OpenMessenger() end
  ns.RefreshChatBubble()
end
local function AnyOpen(minimized)
  for wid, w in pairs(Windows) do
    local st = WState(wid)
    if st.open and (minimized == nil or (st.min and true or false) == minimized) then return true end
  end
  return false
end
function ns.RefreshChatBubble()
  local b = ns.ChatBubble()
  if not b then return end
  if AnyOpen(true) then
    if not b:IsShown() then b:Place() end
    b:Show(); b:Update()
  else
    b:Hide()
  end
end
function ns.ToggleMessenger()
  if AnyOpen() then ns.CloseMessenger() else ns.OpenMessenger() end
end
function ns.MessengerChanged(channel, who, incoming)
  local o = Opt()
  -- a new whisper: follow it, or pop a window if that's switched on
  if incoming and channel == "whisper" then
    local key = "w:" .. who
    if o.windows == "separate" then
      local w = Windows[key]
      if (w and WState(key).open) or o.pop then
        if not (InCombatLockdown and InCombatLockdown() and o.combat) then ns.OpenMessenger(key, WState(key).min) end
      end
    else
      if not MState().key or (Bub and Bub:IsShown()) then MState().key = key end
      if o.pop and not AnyOpen() and not (InCombatLockdown and InCombatLockdown() and o.combat) then ns.OpenMessenger(key) end
    end
    if Bub and Bub:IsShown() and UIFrameFlash then pcall(UIFrameFlash, Bub.ring, 0.3, 0.3, 2.4, true, 0, 0) end
  end
  ns.Debounce("messenger", 0.2, function()
    for wid, w in pairs(Windows) do if w:IsShown() then w:Update() end end
    ns.RefreshChatBubble()
  end)
end
-- Combat: tuck every chat window into the bubble, bring them back after.
ns.On("PLAYER_REGEN_DISABLED", function()
  if not Opt().combat then return end
  for wid, w in pairs(Windows) do
    local st = WState(wid)
    if st.open and not st.min then st.min, st.combatMin = true, true; w:Hide() end
  end
  ns.RefreshChatBubble()
end)
ns.On("PLAYER_REGEN_ENABLED", function()
  for wid, w in pairs(Windows) do
    local st = WState(wid)
    if st.combatMin then st.combatMin = nil; st.min = false; w:Update() end
  end
  ns.RefreshChatBubble()
end)
ns.On("PLAYER_LOGIN", function()
  C_Timer.After(3, function()
    local st = MState()
    if st.open then ns.OpenMessenger(nil, st.min) end
    for wid, p in pairs(st.people or {}) do
      if p.open and Opt().windows == "separate" then ns.OpenMessenger(wid, p.min) end
    end
  end)
end)

---------------------------------------------------------------------------
-- Typing indicator between EPU users (whispers only).
---------------------------------------------------------------------------
local typingSent = {}
function ns.ChatTypingPing(key, text)
  if not Opt().typing or type(key) ~= "string" or key:sub(1, 2) ~= "w:" then return end
  local target = key:sub(3)
  local short = ns.Short and ns.Short(target) or target
  local r = ns.roster[short]
  if not r or not r.online or not ns.Send then return end
  local typing = type(text) == "string" and text ~= ""
  local last = typingSent[short]
  if typing then
    if not last or GetTime() - last > 4 then
      typingSent[short] = GetTime()
      ns.Send("T", { on = true }, "WHISPER", short)
    end
  elseif last then
    typingSent[short] = nil
    ns.Send("T", { on = false }, "WHISPER", short)
  end
end
ns.comm.T = function(sender, data, channel)
  if channel ~= "WHISPER" or type(data) ~= "table" then return end
  local short = ns.Short and ns.Short(sender) or sender
  typingAt[short] = data.on and GetTime() or nil
  local function Refresh()
    local key = "w:" .. sender
    for _, w in pairs(Windows) do if w:IsShown() and w:Key() and (w:Key() == key or w:Key() == "w:" .. short) then w:Update() end end
    local d = ns.UI and ns.UI.details
    if d and d:IsShown() and d.kind == "chatwith" and (d.key == key or d.key == "w:" .. short) then ns.UI:FillDetails() end
  end
  Refresh()
  if data.on and C_Timer then C_Timer.After(6.2, Refresh) end
end

---------------------------------------------------------------------------
-- Sounds per chat, and alerts when someone mentions you.
---------------------------------------------------------------------------
ns.CHAT_SOUNDS = {
  { label = "Off", value = false },
  { label = "Whisper bell", value = 3081 },
  { label = "Ping", value = 3175 },
  { label = "Ready check", value = 8960 },
  { label = "Raid warning", value = 8959 },
  { label = "Invite", value = 880 },
}
local soundAt = {}
local function PlayChatSound(id, slot)
  if not id or not PlaySound then return end
  if soundAt[slot] and GetTime() - soundAt[slot] < 2 then return end
  soundAt[slot] = GetTime()
  pcall(PlaySound, id, "Master")
end
local function MentionWords()
  local o, words = Opt(), {}
  for _, n in ipairs(ns.MyChars and ns.MyChars() or { ns.me }) do
    local first = (ns.Short and ns.Short(n) or n):match("^(%S+)")
    if first and #first >= 3 then words[#words + 1] = first:lower() end
  end
  for w in pairs(o.words) do words[#words + 1] = w end
  return words
end
function ns.ChatMentions(msg)
  msg = Plain(msg)
  if not msg then return false end
  local low = msg:lower()
  for _, w in ipairs(MentionWords()) do
    local pat = "%f[%w]" .. w:gsub("(%W)", "%%%1") .. "%f[%W]"
    if low:find(pat) then return true end
  end
  return false
end
function ns.ChatIncoming(channel, sender, msg)
  local o = Opt()
  PlayChatSound(o.sounds[channel], channel)
  if channel ~= "whisper" and o.mentions and ns.ChatMentions(msg) then
    PlayChatSound(o.sounds.mention, "mention")
    local who = ns.Short and ns.Short(Plain(sender) or "?") or sender
    if ns.Notify then
      ns.Notify("Mentioned in " .. CHANNELS[channel].label:lower(), who .. ": " .. PlainText(Plain(msg) or ""),
        "Interface\\Icons\\INV_Letter_15", { category = "mentions", kind = "chatwith", key = channel, revision = tostring(time()) })
    end
  end
end

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
  local o = Opt()
  local UI = ns.UI
  local K = ns.UIKit
  local function Again() UI:FillDetails(); UI:Refresh() end
  local function Check(on, text) return (on and "[x] " or "[ ] ") .. text end
  det:Reset("Interface\\Icons\\INV_Misc_Gear_01", nil, "Chat settings", "Saved on this PC only and never shared with the guild")
  det:Section("Windows")
  det:Buttons({ { "Tabs in one window", function() o.windows = "tabs"; Again() end, on = o.windows == "tabs",
      tip = "Whispers share one window with tabs for each chat" },
    { "One window per person", function() o.windows = "separate"; Again() end, on = o.windows == "separate",
      tip = "Each person you whisper gets a window of their own; guild, party and raid stay in the tabbed window" } })
  det:Buttons({ { Check(o.pop, "Open a window when a whisper arrives"), function() o.pop = not o.pop; Again() end } })
  det:Buttons({ { Check(o.combat, "Tuck windows into the bubble during combat"), function() o.combat = not o.combat; Again() end,
      tip = "They come back when combat ends" } })
  det:Buttons({ { Check(o.fade, "Fade windows when the mouse is elsewhere"), function() o.fade = not o.fade; Again() end } })
  det:Buttons({ { Check(o.typing, "Show and send \"typing...\" (EPU users)"), function() o.typing = not o.typing; Again() end } })
  det:Buttons({ { Check(o.lineTimes, "Show the time on every message"), function() o.lineTimes = not o.lineTimes; ns.ChatColorsChanged(); Again() end,
      tip = "Otherwise the time shows once for each group of messages" } })
  det:Buttons({ { Check(o.presence ~= false, "Show guildmates coming online and going offline in Guild chat"), function()
    o.presence = o.presence == false; Again() end } })
  det:Section("Text")
  local fontLabel = "EPU (Inter)"
  for _, f in ipairs(ns.CHAT_FONTS) do if f.value == (o.font or "epu") then fontLabel = f.label end end
  local _, size = ns.ChatFont()
  det:Buttons({ { "Font: " .. fontLabel, function(self)
      K.OpenMenu(self, ns.CHAT_FONTS, o.font or "epu", function(v) o.font = v or "epu"; ns.ChatColorsChanged(); Again() end)
    end, tip = "The font for messages in EPU's chat" },
    { "A-", function() o.size = math.max(9, size - 1); ns.ChatColorsChanged(); Again() end, tip = "Smaller text" },
    { "Size " .. size, function() o.size = 12; ns.ChatColorsChanged(); Again() end, tip = "Click to go back to 12" },
    { "A+", function() o.size = math.min(22, size + 1); ns.ChatColorsChanged(); Again() end, tip = "Bigger text" },
    { Check(o.outline, "Outline"), function() o.outline = not o.outline; ns.ChatColorsChanged(); Again() end,
      tip = "A thin dark edge around letters; easier to read on busy backgrounds" } })
  det.textFont = { ns.ChatFont() }
  det:Text("|cffffffffSample Name|r  |cff88888822:30|r\n" .. ChatColor("guild", false) .. "This is how messages will look.|r")
  det.textFont = nil
  det:Section("Chats to keep, colors and sounds")
  for _, k in ipairs(CHANNEL_ORDER) do
    if k ~= "officer" or CanOfficerChat() then
      local keep = ns.ChatKeep(k)
      local specs = { { Check(keep, CHANNELS[k].short or "Whispers"), function() ns.SetChatKeep(k, not keep); Again() end,
        tip = "Save " .. CHANNELS[k].label:lower() .. " on this PC" } }
      specs[#specs + 1] = { ChatColor(k, false) .. "Color|r", function() ns.PickChatColor(k, false) end,
        tip = "Pick a color for " .. CHANNELS[k].label:lower() .. " in EPU. Right now: " .. (select(4, ns.ChatColorRGB(k, false)) and "your own color" or "the game's chat color") }
      if k == "whisper" then
        specs[#specs + 1] = { ChatColor(k, true) .. "Sent|r", function() ns.PickChatColor(k, true) end, tip = "Color for whispers you send" }
      end
      local soundLabel = "Sound: Off"
      for _, snd in ipairs(ns.CHAT_SOUNDS) do if snd.value == (o.sounds[k] or false) then soundLabel = "Sound: " .. snd.label end end
      specs[#specs + 1] = { soundLabel, function(self)
        K.OpenMenu(self, ns.CHAT_SOUNDS, o.sounds[k] or false, function(v)
          o.sounds[k] = v or nil
          if v and PlaySound then pcall(PlaySound, v, "Master") end
          Again()
        end)
      end, tip = "Play a sound when a message arrives in " .. CHANNELS[k].label:lower() }
      if #ns.ChatLog(k) > 0 then
        specs[#specs + 1] = { "Clear", function() wipe(ns.ChatLog(k)); Again() end,
          tip = "Delete saved " .. CHANNELS[k].label:lower() .. " from this PC" }
      end
      det:Buttons(specs)
    end
  end
  det:Buttons({ { Check(c.chatkeep.replay ~= false, "Show the last hour after a reload"), function()
    c.chatkeep.replay = c.chatkeep.replay == false; Again() end } })
  -- people with their own color
  local people = {}
  for k2 in pairs(c.chatColors or {}) do if k2:sub(1, 2) == "w:" then people[#people + 1] = k2:sub(3) end end
  table.sort(people)
  if #people > 0 then
    det:Text("People with their own color:", nil)
    local row = {}
    for _, who in ipairs(people) do
      row[#row + 1] = { ChatColor("whisper", false, who) .. (ns.Short and ns.Short(who) or who) .. "|r  x", function() ns.ClearPersonColor(who) end,
        tip = "Back to the normal whisper color" }
      if #row == 3 then det:Buttons(row); row = {} end
    end
    if #row > 0 then det:Buttons(row) end
  end
  if c.chatColors and next(c.chatColors) then
    det:Buttons({ { "Use the game's chat colors", function() c.chatColors = nil; ns.ChatColorsChanged() end,
      tip = "Forget every color picked here, including people's, and follow the game's chat colors again" } })
  end
  det:Section("Mentions")
  local soundLabel = "Sound: Off"
  for _, snd in ipairs(ns.CHAT_SOUNDS) do if snd.value == (o.sounds.mention or false) then soundLabel = "Sound: " .. snd.label end end
  det:Buttons({ { Check(o.mentions, "Alert me when my name comes up"), function() o.mentions = not o.mentions; Again() end,
      tip = "In guild, officer, party or raid chat. Uses your characters' first names and the words below." },
    { soundLabel, function(self)
      K.OpenMenu(self, ns.CHAT_SOUNDS, o.sounds.mention or false, function(v)
        o.sounds.mention = v or false
        if v and PlaySound then pcall(PlaySound, v, "Master") end
        Again()
      end)
    end } })
  local words = {}
  for w in pairs(o.words) do words[#words + 1] = w end
  table.sort(words)
  if #words > 0 then
    local row = {}
    for _, w in ipairs(words) do
      row[#row + 1] = { w .. "  x", function() o.words[w] = nil; Again() end, tip = "Stop alerting on this word" }
      if #row == 4 then det:Buttons(row); row = {} end
    end
    if #row > 0 then det:Buttons(row) end
  end
  local box = det:Field("Also alert on", "", 140)
  local function AddWord()
    local w = (box:GetText() or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if #w >= 2 and #w <= 30 then o.words[w] = true end
    Again()
  end
  box.onEnter = AddWord
  det:Buttons({ { "Add word", AddWord } })
  det:Text("Colors follow the game's chat colors unless you pick your own. Battle.net whispers aren't kept, and messages the game hides in combat are saved as a placeholder.", nil)
  return true
end
function ns.ClearPersonColor(who)
  local c = ChatDB()
  if c and c.chatColors then c.chatColors["w:" .. who] = nil end
  ns.ChatColorsChanged()
end
function ns.HasPersonColor(who)
  local c = ChatDB()
  return c ~= nil and c.chatColors ~= nil and c.chatColors["w:" .. who] ~= nil
end
function ns.ChatColorsChanged()
  local UI = ns.UI
  if UI and UI:IsShown() then
    if UI.details:IsShown() and (UI.details.kind == "chatsettings" or UI.details.kind == "chatwith") then UI:FillDetails() end
    UI:Refresh()
  end
  if Mgr and Mgr:IsShown() then Mgr:Update() end
end
-- who: pick a color for one person's whispers instead of a whole chat
function ns.PickChatColor(channel, out, who)
  if not ColorPickerFrame then return ns.Print("This game client has no color picker.") end
  local key = who and ("w:" .. who) or ColorKey(channel, out)
  local r, g, b = ns.ChatColorRGB(channel, out, who)
  local function Save(nr, ng, nb)
    local c = ChatDB()
    c.chatColors = c.chatColors or {}
    c.chatColors[key] = { nr, ng, nb }
    ns.ChatColorsChanged()
  end
  local function Current()
    local nr, ng, nb = ColorPickerFrame:GetColorRGB()
    Save(nr, ng, nb)
  end
  local function Cancel(prev)
    if type(prev) == "table" and prev.r then Save(prev.r, prev.g, prev.b) else Save(r, g, b) end
  end
  if ColorPickerFrame.SetupColorPickerAndShow then
    ColorPickerFrame:SetupColorPickerAndShow({ r = r, g = g, b = b, hasOpacity = false,
      swatchFunc = Current, cancelFunc = function() Save(r, g, b) end })
  else
    ColorPickerFrame.hasOpacity = false
    ColorPickerFrame.previousValues = { r = r, g = g, b = b }
    ColorPickerFrame.func, ColorPickerFrame.cancelFunc = Current, Cancel
    ColorPickerFrame:SetColorRGB(r, g, b)
    ColorPickerFrame:Hide(); ColorPickerFrame:Show()
  end
end
local fillBefore = ns.FillCommunityDetails
ns.FillCommunityDetails = function(kind, key, det)
  if kind == "chatwith" then return FillChatWith(det, key) end
  if kind == "chatnew" then return FillChatNew(det) end
  if kind == "chatsettings" then return FillChatSettings(det) end
  if kind == "chathistory" then ns.ShowChatHistory(key); return true end
  return fillBefore(kind, key, det)
end
