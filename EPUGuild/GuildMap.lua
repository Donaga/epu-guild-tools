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
local classes='Interface\\TargetingFrame\\UI-Classes-Circles'
-- Classic class atlas layout; used when the global table is unavailable.
local classCoords={WARRIOR={0,0.25,0,0.25},MAGE={0.25,0.5,0,0.25},ROGUE={0.5,0.75,0,0.25},DRUID={0.75,1,0,0.25},
  HUNTER={0,0.25,0.25,0.5},SHAMAN={0.25,0.5,0.25,0.5},PRIEST={0.5,0.75,0.25,0.5},WARLOCK={0.75,1,0.25,0.5},PALADIN={0,0.25,0.5,0.75}}

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
        local coords=r.classFile and ((CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[r.classFile]) or classCoords[r.classFile])
        for _,f in ipairs({pair.world,pair.mini}) do
          if Setting('guildClassIcons')~=false and coords then
            f.dot:SetTexture(classes); f.dot:SetTexCoord(unpack(coords)); f.dot:SetVertexColor(1,1,1,1)
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
    panel=CreateFrame("Frame","EPUGuildMapSettings",UIParent,"BasicFrameTemplateWithInset")
    panel:SetSize(380,344); panel:SetPoint("CENTER"); panel:SetFrameStrata("DIALOG")
    panel:SetMovable(true); panel:EnableMouse(true); panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart",panel.StartMoving); panel:SetScript("OnDragStop",panel.StopMovingOrSizing)
    panel.TitleText:SetText("EPU Guild Map")
    tinsert(UISpecialFrames,"EPUGuildMapSettings")
    local function Check(key,label,y,callback)
      local b=CreateFrame("CheckButton",nil,panel,"UICheckButtonTemplate")
      b:SetPoint("TOPLEFT",16,y)
      b.label=b:CreateFontString(nil,"OVERLAY","GameFontHighlight")
      b.label:SetPoint("LEFT",b,"RIGHT",0,0)
      b.label:SetText(label)
      b:SetScript("OnClick",function(self) callback(self:GetChecked()==true); ns.RefreshGuildMap(); ns.RefreshGuildMapSettings() end)
      panel[key]=b
    end
    Check("share","Share my outdoor location",-38,ns.SetLocationSharing)
    Check("world","Show guildmates on the world map",-76,function(on) ns.db.settings.guildWorldMap=on end)
    Check("mini","Show nearby guildmates on the minimap",-114,function(on) ns.db.settings.guildMinimap=on end)
    Check('icons','Use class icons (off = round dots)',-152,function(on) ns.db.settings.guildClassIcons=on end)
    panel.status=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    panel.status:SetPoint("TOPLEFT",20,-198); panel.status:SetWidth(340); panel.status:SetJustifyH("LEFT")
    panel.buttonSettings=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate")
    panel.buttonSettings:SetSize(180,24); panel.buttonSettings:SetPoint("BOTTOMLEFT",20,52)
    panel.buttonSettings:SetText("Move minimap button")
    panel.buttonSettings:SetScript("OnClick",function() ns.ShowMinimapButtonSettings() end)
    local hint=panel:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT",20,18); hint:SetWidth(340)
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
