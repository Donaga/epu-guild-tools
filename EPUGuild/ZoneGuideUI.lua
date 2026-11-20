-- EPU Guild Tools: Zone Visitor's Guide popup window UI.
local _, ns = ...

local win
local state = {
  zoneId = nil,
  tab = "overview",
  continent = "All",
  zoneSearch = "",
  nearLevel = false,
  contentSearch = "",
  myFactionOnly = false,
}

local function Colors() return ns.InterfaceColors end
local function Font(parent, size, color) return ns.InterfaceFont(parent, size, color) end
local function Btn(parent, text, w, h) return ns.InterfaceButton(parent, text, w, h) end

local function MakeTex(parent, layer, c, a)
  local t = parent:CreateTexture(nil, layer or "BACKGROUND")
  t:SetColorTexture(c[1], c[2], c[3], a or 1)
  return t
end

local function MakeEdges(frame, c)
  for _, spec in ipairs({
    { "TOPLEFT", "TOPRIGHT", "height", 1 },
    { "BOTTOMLEFT", "BOTTOMRIGHT", "height", 1 },
    { "TOPLEFT", "BOTTOMLEFT", "width", 1 },
    { "TOPRIGHT", "BOTTOMRIGHT", "width", 1 },
  }) do
    local t = MakeTex(frame, "BORDER", c, 1)
    t:SetPoint(spec[1]); t:SetPoint(spec[2])
    if spec[3] == "height" then t:SetHeight(spec[4]) else t:SetWidth(spec[4]) end
  end
end

local function FactionColor(faction)
  local C = Colors()
  if faction == "Alliance" then return C.blue end
  if faction == "Horde" then return C.red end
  return C.gold
end

local function MatchesSearch(q, ...)
  if not q or q == "" then return true end
  local needle = q:lower()
  for i = 1, select("#", ...) do
    local v = select(i, ...)
    if type(v) == "string" and v:lower():find(needle, 1, true) then return true end
  end
  return false
end

local function FactionAllowed(itemFaction, playerFaction)
  if not state.myFactionOnly or not playerFaction then return true end
  if not itemFaction or itemFaction == "Neutral" or itemFaction == "Contested" then return true end
  return itemFaction == playerFaction
end

-- Simple vertical flow builder for the scrollable content child.
local function NewFlow(child, width)
  local flow = { child = child, width = width, y = -8, widgets = {} }

  local function Track(w)
    flow.widgets[#flow.widgets + 1] = w
    return w
  end

  function flow:Clear()
    for _, w in ipairs(self.widgets) do
      w:Hide()
      w:SetParent(nil)
    end
    self.widgets = {}
    self.y = -8
  end

  function flow:Space(px)
    self.y = self.y - (px or 8)
  end

  function flow:Section(title)
    local C = Colors()
    self:Space(6)
    local h = Track(Font(self.child, 13, C.gold))
    h:SetPoint("TOPLEFT", 10, self.y)
    h:SetWidth(self.width - 24)
    h:SetJustifyH("LEFT")
    h:SetText(title)
    local rule = Track(MakeTex(self.child, "BORDER", C.line, 1))
    rule:SetPoint("TOPLEFT", 10, self.y - 18)
    rule:SetSize(self.width - 24, 1)
    self.y = self.y - 26
  end

  function flow:Paragraph(text, color)
    local C = Colors()
    local fs = Track(Font(self.child, 12, color or C.text))
    fs:SetPoint("TOPLEFT", 12, self.y)
    fs:SetWidth(self.width - 28)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
    fs:SetText(text)
    local h = math.max(16, fs:GetStringHeight() or 16)
    self.y = self.y - h - 6
  end

  function flow:Card(opts)
    local C = Colors()
    local card = Track(CreateFrame("Frame", nil, self.child))
    card:SetPoint("TOPLEFT", 10, self.y)
    card:SetWidth(self.width - 24)
    MakeTex(card, "BACKGROUND", C.panel, 1):SetAllPoints()
    MakeEdges(card, C.line)

    local padX, curY = 10, -8
    local rightOffset = 10

    if opts.coords and opts.coords[1] and opts.coords[2] then
      local cx, cy = opts.coords[1], opts.coords[2]
      local wp = Track(Btn(card, string.format("%.1f, %.1f", cx, cy), 82, 22))
      wp:SetPoint("TOPRIGHT", -8, -7)
      wp.tip = "Click to set a map waypoint here"
      local mapID, label = opts.mapID, opts.waypointLabel or opts.title
      wp:SetScript("OnClick", function() ns.SetZoneWaypoint(mapID, cx, cy, label) end)
      rightOffset = 98
    end

    local title = Track(Font(card, 12, opts.titleColor or C.white))
    title:SetPoint("TOPLEFT", padX, curY)
    title:SetWidth(self.width - 24 - padX - rightOffset)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(true)
    title:SetText(opts.title or "")
    local th = math.max(15, title:GetStringHeight() or 15)
    curY = curY - th - 2

    if opts.sub and opts.sub ~= "" then
      local sub = Track(Font(card, 11, opts.subColor or C.muted))
      sub:SetPoint("TOPLEFT", padX, curY)
      sub:SetWidth(self.width - 24 - padX - rightOffset)
      sub:SetJustifyH("LEFT")
      sub:SetWordWrap(true)
      sub:SetText(opts.sub)
      local sh = math.max(14, sub:GetStringHeight() or 14)
      curY = curY - sh - 2
    end

    if opts.note and opts.note ~= "" then
      local note = Track(Font(card, 11, opts.noteColor or C.text))
      note:SetPoint("TOPLEFT", padX, curY)
      note:SetWidth(self.width - 44)
      note:SetJustifyH("LEFT")
      note:SetWordWrap(true)
      note:SetText(opts.note)
      local nh = math.max(14, note:GetStringHeight() or 14)
      curY = curY - nh - 2
    end

    local totalH = math.max(36, -curY + 6)
    card:SetHeight(totalH)
    self.y = self.y - totalH - 5
  end

  function flow:Finish()
    self.child:SetHeight(math.max(200, -self.y + 16))
  end

  return flow
end

local function RenderZoneList()
  if not win then return end
  local C = Colors()
  local list = ns.GetZoneList(state.continent, state.zoneSearch, state.nearLevel)
  for _, b in ipairs(win.zoneButtons) do b:Hide() end

  local y = -4
  for i, z in ipairs(list) do
    local b = win.zoneButtons[i]
    if not b then
      b = CreateFrame("Button", nil, win.zoneChild)
      b:SetSize(202, 34)
      b.bg = MakeTex(b, "BACKGROUND", C.panel2, 1)
      b.bg:SetAllPoints()
      b.strip = MakeTex(b, "BORDER", C.gold, 1)
      b.strip:SetPoint("TOPLEFT"); b.strip:SetPoint("BOTTOMLEFT"); b.strip:SetWidth(2)
      b.name = Font(b, 12, C.white)
      b.name:SetPoint("TOPLEFT", 8, -4)
      b.name:SetWidth(140); b.name:SetJustifyH("LEFT")
      b.lvl = Font(b, 10, C.muted)
      b.lvl:SetPoint("TOPRIGHT", -6, -5)
      b.sub = Font(b, 10, C.muted)
      b.sub:SetPoint("BOTTOMLEFT", 8, 4)
      b.sub:SetWidth(186); b.sub:SetJustifyH("LEFT")
      b:SetScript("OnEnter", function(self)
        if state.zoneId ~= self.zoneId then self.bg:SetColorTexture(C.hover[1], C.hover[2], C.hover[3], 1) end
      end)
      b:SetScript("OnLeave", function(self)
        local sel = state.zoneId == self.zoneId
        local c = sel and C.selected or C.panel
        self.bg:SetColorTexture(c[1], c[2], c[3], 1)
      end)
      b:SetScript("OnClick", function(self)
        state.zoneId = self.zoneId
        win.contentScroll:SetVerticalScroll(0)
        RenderZoneList()
        ns.RefreshZoneGuideContent()
      end)
      win.zoneButtons[i] = b
    end

    b.zoneId = z.id
    b:SetPoint("TOPLEFT", 4, y)
    local sel = (state.zoneId == z.id)
    local bg = sel and C.selected or C.panel
    b.bg:SetColorTexture(bg[1], bg[2], bg[3], 1)
    b.strip:SetShown(sel)
    b.name:SetText(z.name)
    b.name:SetTextColor((sel and C.gold or C.white)[1], (sel and C.gold or C.white)[2], (sel and C.gold or C.white)[3])
    b.lvl:SetText(z.levelRange and (z.levelRange[1] .. "–" .. z.levelRange[2]) or "")
    local fc = FactionColor(z.faction)
    b.sub:SetText((z.faction or "Neutral") .. " · " .. (z.continent or ""))
    b.sub:SetTextColor(fc[1], fc[2], fc[3])
    b:Show()
    y = y - 36
  end
  win.zoneChild:SetHeight(math.max(200, -y + 8))
end

local function RenderContent()
  if not win then return end
  local C = Colors()
  local zone = ns.GetZoneById(state.zoneId)
  if not zone then
    local list = ns.GetZoneList("All", "", false)
    zone = list[1]
    if zone then state.zoneId = zone.id end
  end
  if not zone then return end

  win.bannerTitle:SetText("Welcome to " .. zone.name)
  win.bannerSub:SetText(zone.tagline or "")
  local lr = zone.levelRange and ("Levels " .. zone.levelRange[1] .. "–" .. zone.levelRange[2]) or "All Levels"
  win.bannerMeta:SetText(lr .. "  ·  " .. (zone.continent or "") .. "  ·  " .. (zone.faction or "Neutral"))
  local fc = FactionColor(zone.faction)
  win.bannerMeta:SetTextColor(fc[1], fc[2], fc[3])

  for _, tb in pairs(win.tabButtons) do
    local active = (tb.key == state.tab)
    tb.bg:SetColorTexture((active and C.selected or C.panel2)[1], (active and C.selected or C.panel2)[2], (active and C.selected or C.panel2)[3], 1)
    tb.text:SetTextColor((active and C.gold or C.text)[1], (active and C.gold or C.text)[2], (active and C.gold or C.text)[3])
    tb.strip:SetShown(active)
  end

  local flow = win.flow
  flow:Clear()

  local q = state.contentSearch
  local pFaction = ns.GetPlayerFaction()
  local pLevel = ns.GetPlayerLevel()
  local live = ns.GetZoneLiveInfo(zone)

  if state.tab == "overview" then
    flow:Section("Visitor's Overview")
    flow:Paragraph(zone.overview or "No overview available yet.")

    if zone.dungeons and #zone.dungeons > 0 then
      flow:Section("Dungeons & Raids")
      for _, d in ipairs(zone.dungeons) do
        local dr = d.levelRange and ("Levels " .. d.levelRange[1] .. "–" .. d.levelRange[2]) or ""
        flow:Card({
          title = d.name,
          sub = dr,
          coords = d.x and { d.x, d.y } or nil,
          mapID = zone.mapID,
          waypointLabel = d.name,
        })
      end
    end

    flow:Section("Flight Paths")
    if zone.flightPaths and #zone.flightPaths > 0 then
      local shown = 0
      for _, fp in ipairs(zone.flightPaths) do
        if FactionAllowed(fp.faction, pFaction) and MatchesSearch(q, fp.name, fp.faction, fp.note) then
          shown = shown + 1
          flow:Card({
            title = fp.name,
            sub = fp.faction or "Neutral",
            subColor = FactionColor(fp.faction),
            note = fp.note,
            coords = fp.x and { fp.x, fp.y } or nil,
            mapID = zone.mapID,
            waypointLabel = fp.name .. " Flight Master",
          })
        end
      end
      if shown == 0 then flow:Paragraph("No flight paths match your current filter.", C.muted) end
    else
      flow:Paragraph("No flight paths in this zone.", C.muted)
    end

    flow:Section("Fishing Summary")
    if zone.fishing and zone.fishing.fish and #zone.fishing.fish > 0 then
      flow:Paragraph("Skill: " .. (zone.fishing.levelNote or tostring(zone.fishing.minSkill or 1)), C.gold)
      flow:Paragraph("Catches: " .. table.concat(zone.fishing.fish, ", "))
    else
      flow:Paragraph(zone.fishing and zone.fishing.levelNote or "No fishing data.", C.muted)
    end

    flow:Section("Guildmates Here Now (" .. #live.guildmates .. ")")
    if #live.guildmates > 0 then
      local names = {}
      for _, m in ipairs(live.guildmates) do
        names[#names + 1] = m.name .. " (Lv " .. m.level .. " " .. m.class .. ")"
      end
      flow:Paragraph(table.concat(names, "  ·  "), C.green)
    else
      flow:Paragraph("No online guildmates currently reported in " .. zone.name .. ".", C.muted)
    end

    if #live.herbs > 0 or #live.ores > 0 then
      flow:Section("Observed Gathering Nodes (EPU Guild Data)")
      if #live.herbs > 0 then
        local list = {}
        for i = 1, math.min(8, #live.herbs) do list[#list + 1] = live.herbs[i].name end
        flow:Paragraph("Herbs: " .. table.concat(list, ", "), C.green)
      end
      if #live.ores > 0 then
        local list = {}
        for i = 1, math.min(8, #live.ores) do list[#list + 1] = live.ores[i].name end
        flow:Paragraph("Ores: " .. table.concat(list, ", "), C.gold)
      end
    end

  elseif state.tab == "vendors" then
    flow:Section("Vendors (including off-the-road merchants)")
    local vShown = 0
    for _, v in ipairs(zone.vendors or {}) do
      if FactionAllowed(v.faction, pFaction) and MatchesSearch(q, v.name, v.type, v.location, v.note) then
        vShown = vShown + 1
        flow:Card({
          title = v.name .. (v.type and ("  ·  " .. v.type) or ""),
          sub = (v.faction or "Neutral") .. (v.location and ("  ·  " .. v.location) or ""),
          subColor = FactionColor(v.faction),
          note = v.note,
          coords = v.x and { v.x, v.y } or nil,
          mapID = zone.mapID,
          waypointLabel = v.name,
        })
      end
    end
    if vShown == 0 then flow:Paragraph("No vendors match your current filter.", C.muted) end

    flow:Section("Recipes & Patterns in " .. zone.name)
    local rShown = 0
    for _, r in ipairs(zone.recipes or {}) do
      if FactionAllowed(r.faction, pFaction) and MatchesSearch(q, r.name, r.profession, r.source, r.sourceName, r.note) then
        rShown = rShown + 1
        local lim = r.limited and " [Limited Supply]" or ""
        flow:Card({
          title = r.name .. lim,
          titleColor = r.limited and C.gold or C.white,
          sub = string.format("%s%s  ·  %s: %s  ·  %s", r.profession or "Profession", r.skill and (" (" .. r.skill .. ")") or "", r.source or "Source", r.sourceName or "?", r.faction or "Neutral"),
          subColor = FactionColor(r.faction),
          note = r.note,
          coords = r.x and { r.x, r.y } or nil,
          mapID = zone.mapID,
          waypointLabel = (r.sourceName or r.name),
        })
      end
    end
    if rShown == 0 then flow:Paragraph("No recipes or patterns match your current filter.", C.muted) end

  elseif state.tab == "trainers" then
    flow:Section("Class & Profession Trainers")
    local tShown = 0
    for _, t in ipairs(zone.trainers or {}) do
      if FactionAllowed(t.faction, pFaction) and MatchesSearch(q, t.name, t.type, t.location, t.note) then
        tShown = tShown + 1
        flow:Card({
          title = t.name .. "  ·  " .. (t.type or "Trainer"),
          sub = (t.faction or "Neutral") .. (t.location and ("  ·  " .. t.location) or ""),
          subColor = FactionColor(t.faction),
          note = t.note,
          coords = t.x and { t.x, t.y } or nil,
          mapID = zone.mapID,
          waypointLabel = t.name .. " (" .. (t.type or "Trainer") .. ")",
        })
      end
    end
    if tShown == 0 then flow:Paragraph("No trainers listed or matching your filter in this zone.", C.muted) end

  elseif state.tab == "fishing" then
    flow:Section("Fishing Level & Catchable Fish")
    local f = zone.fishing
    if f then
      flow:Paragraph("Recommended Skill: " .. (f.levelNote or tostring(f.minSkill or 1)), C.gold)
      if f.fish and #f.fish > 0 then
        for _, fishName in ipairs(f.fish) do
          if MatchesSearch(q, fishName) then
            flow:Card({ title = fishName, sub = "Catchable in " .. zone.name })
          end
        end
      else
        flow:Paragraph("No catchable fish in this zone.", C.muted)
      end
    end

    flow:Section("Herbs & Ores Observed in " .. zone.name)
    if #live.herbs == 0 and #live.ores == 0 then
      flow:Paragraph("No gathering spot observations recorded for this zone yet.", C.muted)
    else
      for _, h in ipairs(live.herbs) do
        if MatchesSearch(q, h.name, "herb") then
          flow:Card({ title = h.name, titleColor = C.green, sub = "Herb  ·  " .. h.count .. " mapped spots" })
        end
      end
      for _, o in ipairs(live.ores) do
        if MatchesSearch(q, o.name, "ore", "mining") then
          flow:Card({ title = o.name, titleColor = C.gold, sub = "Mining Vein  ·  " .. o.count .. " mapped spots" })
        end
      end
    end

  elseif state.tab == "quests" then
    flow:Section("Notable Quests (Color-Coded for Level " .. pLevel .. ")")
    flow:Paragraph("Colors follow WoW's quest difficulty schema relative to your character's level: Red (+5+), Orange (+3..4), Yellow (-2..+2), Green (Easy), Gray (Trivial).", C.muted)
    local logMap = ns.GetPlayerQuestLogMap()
    local qShown = 0
    for _, quest in ipairs(zone.quests or {}) do
      if FactionAllowed(quest.faction, pFaction) and MatchesSearch(q, quest.name, quest.giver, quest.type, quest.note) then
        qShown = qShown + 1
        local qc, _, diffLabel = ns.QuestDifficultyColor(quest.level, pLevel)
        local logStatus = logMap[quest.name:lower()]
        local badge = logStatus and ("  [" .. logStatus .. "]") or ""
        flow:Card({
          title = string.format("[%d] %s%s", quest.level or pLevel, quest.name, badge),
          titleColor = qc,
          sub = string.format("%s  ·  %s  ·  Giver: %s (%s)", quest.faction or "Neutral", quest.type or "Solo", quest.giver or "?", diffLabel),
          subColor = FactionColor(quest.faction),
          note = quest.note,
          coords = quest.x and { quest.x, quest.y } or nil,
          mapID = zone.mapID,
          waypointLabel = (quest.giver or quest.name),
        })
      end
    end
    if qShown == 0 then flow:Paragraph("No quests match your current filter.", C.muted) end
  end

  flow:Finish()
end

ns.RefreshZoneGuideContent = RenderContent

local function BuildWindow()
  if win then return win end
  local C = Colors()
  win = ns.InterfaceWindow("EPUGuildZoneGuideWindow", UIParent, "EPU Zone Visitor's Guide", 900, 620)
  win:SetMovable(true)
  win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", win.StartMoving)
  win:SetScript("OnDragStop", win.StopMovingOrSizing)

  -- Left Zone Picker Panel
  local left = CreateFrame("Frame", nil, win)
  left:SetPoint("TOPLEFT", 10, -42)
  left:SetPoint("BOTTOMLEFT", 10, 10)
  left:SetWidth(226)
  MakeTex(left, "BACKGROUND", C.panel, 1):SetAllPoints()
  MakeEdges(left, C.line)

  local curBtn = Btn(left, "Current Zone", 210, 24)
  curBtn:SetPoint("TOPLEFT", 8, -8)
  curBtn:SetScript("OnClick", function()
    local cur = ns.GetCurrentPlayerZone()
    if cur then
      state.zoneId = cur.id
      win.contentScroll:SetVerticalScroll(0)
      RenderZoneList()
      RenderContent()
    else
      ns.Print("Your current zone isn't in the Zone Guide yet.")
    end
  end)

  local zSearch = ns.InterfaceInput(left, 210, "Search zones...")
  zSearch:SetPoint("TOPLEFT", 8, -38)
  zSearch:SetScript("OnTextChanged", function(self)
    state.zoneSearch = self:GetText() or ""
    RenderZoneList()
  end)

  -- Continent filter buttons
  local contBtns = {}
  local contDefs = { { "All", "All", 54 }, { "Kalimdor", "Kalimdor", 76 }, { "Eastern Kingdoms", "EK", 74 } }
  local cx = 8
  for _, def in ipairs(contDefs) do
    local b = Btn(left, def[2], def[3], 22)
    b:SetPoint("TOPLEFT", cx, -66)
    b.val = def[1]
    b:SetScript("OnClick", function(self)
      state.continent = self.val
      RenderZoneList()
    end)
    contBtns[#contBtns + 1] = b
    cx = cx + def[3] + 3
  end

  local lvlBtn = Btn(left, "Near my level: Off", 210, 22)
  lvlBtn:SetPoint("TOPLEFT", 8, -92)
  lvlBtn:SetScript("OnClick", function(self)
    state.nearLevel = not state.nearLevel
    self:SetText("Near my level: " .. (state.nearLevel and "On" or "Off"))
    RenderZoneList()
  end)

  local zScroll = CreateFrame("ScrollFrame", nil, left)
  zScroll:SetPoint("TOPLEFT", 4, -120)
  zScroll:SetPoint("BOTTOMRIGHT", -4, 6)
  zScroll:EnableMouseWheel(true)
  local zChild = CreateFrame("Frame", nil, zScroll)
  zChild:SetWidth(210)
  zChild:SetHeight(200)
  zScroll:SetScrollChild(zChild)
  zScroll:SetScript("OnMouseWheel", function(self, delta)
    local cur = self:GetVerticalScroll()
    local maxS = math.max(0, zChild:GetHeight() - self:GetHeight())
    self:SetVerticalScroll(math.max(0, math.min(maxS, cur - delta * 36)))
  end)
  win.zoneScroll = zScroll
  win.zoneChild = zChild
  win.zoneButtons = {}

  -- Right Visitor's Guide Panel
  local right = CreateFrame("Frame", nil, win)
  right:SetPoint("TOPLEFT", left, "TOPRIGHT", 10, 0)
  right:SetPoint("BOTTOMRIGHT", -10, 10)
  MakeTex(right, "BACKGROUND", C.panel2, 0.35):SetAllPoints()
  MakeEdges(right, C.line)

  local banner = CreateFrame("Frame", nil, right)
  banner:SetPoint("TOPLEFT", 8, -8)
  banner:SetPoint("TOPRIGHT", -8, -8)
  banner:SetHeight(64)
  MakeTex(banner, "BACKGROUND", C.panel, 1):SetAllPoints()
  MakeEdges(banner, C.line)

  win.bannerTitle = Font(banner, 17, C.gold)
  win.bannerTitle:SetPoint("TOPLEFT", 12, -8)
  win.bannerTitle:SetWidth(420); win.bannerTitle:SetJustifyH("LEFT")

  win.bannerMeta = Font(banner, 11, C.blue)
  win.bannerMeta:SetPoint("TOPRIGHT", -12, -11)
  win.bannerMeta:SetJustifyH("RIGHT")

  win.bannerSub = Font(banner, 12, C.text)
  win.bannerSub:SetPoint("TOPLEFT", 12, -32)
  win.bannerSub:SetPoint("TOPRIGHT", -12, -32)
  win.bannerSub:SetJustifyH("LEFT")

  -- Section Tabs
  win.tabButtons = {}
  local tabs = {
    { "overview", "Overview", 96 },
    { "vendors", "Vendors & Recipes", 136 },
    { "trainers", "Trainers", 88 },
    { "fishing", "Fishing & Nodes", 122 },
    { "quests", "Quests", 84 },
  }
  local tx = 8
  for _, t in ipairs(tabs) do
    local tb = CreateFrame("Button", nil, right)
    tb:SetSize(t[3], 26)
    tb:SetPoint("TOPLEFT", tx, -78)
    tb.bg = MakeTex(tb, "BACKGROUND", C.panel2, 1)
    tb.bg:SetAllPoints()
    MakeEdges(tb, C.line)
    tb.strip = MakeTex(tb, "BORDER", C.gold, 1)
    tb.strip:SetPoint("BOTTOMLEFT"); tb.strip:SetPoint("BOTTOMRIGHT"); tb.strip:SetHeight(2)
    tb.text = Font(tb, 11, C.text)
    tb.text:SetPoint("CENTER")
    tb.key = t[1]
    tb.text:SetText(t[2])
    tb:SetScript("OnClick", function(self)
      state.tab = self.key
      win.contentScroll:SetVerticalScroll(0)
      RenderContent()
    end)
    win.tabButtons[t[1]] = tb
    tx = tx + t[3] + 4
  end

  -- Content Search + My Faction toggle
  local cSearch = ns.InterfaceInput(right, 340, "Filter vendors, recipes, trainers, quests...")
  cSearch:SetPoint("TOPLEFT", 8, -110)
  cSearch:SetScript("OnTextChanged", function(self)
    state.contentSearch = self:GetText() or ""
    win.contentScroll:SetVerticalScroll(0)
    RenderContent()
  end)

  local facBtn = Btn(right, "My Faction: All", 150, 22)
  facBtn:SetPoint("TOPRIGHT", -8, -110)
  facBtn:SetScript("OnClick", function(self)
    state.myFactionOnly = not state.myFactionOnly
    self:SetText(state.myFactionOnly and "My Faction: Only" or "My Faction: All")
    win.contentScroll:SetVerticalScroll(0)
    RenderContent()
  end)

  local cScroll = CreateFrame("ScrollFrame", nil, right)
  cScroll:SetPoint("TOPLEFT", 8, -138)
  cScroll:SetPoint("BOTTOMRIGHT", -8, 8)
  cScroll:EnableMouseWheel(true)
  local cChild = CreateFrame("Frame", nil, cScroll)
  cChild:SetWidth(626)
  cChild:SetHeight(200)
  cScroll:SetScrollChild(cChild)
  cScroll:SetScript("OnMouseWheel", function(self, delta)
    local cur = self:GetVerticalScroll()
    local maxS = math.max(0, cChild:GetHeight() - self:GetHeight())
    self:SetVerticalScroll(math.max(0, math.min(maxS, cur - delta * 42)))
  end)
  win.contentScroll = cScroll
  win.contentChild = cChild
  win.flow = NewFlow(cChild, 626)

  return win
end

function ns.OpenZoneGuide(query)
  BuildWindow()
  if query and query ~= "" then
    local found = ns.FindZone(query)
    if found then
      state.zoneId = found.id
    else
      ns.Print("No zone matched '" .. query .. "'. Showing zone list.")
    end
  elseif not state.zoneId then
    local cur = ns.GetCurrentPlayerZone()
    if cur then state.zoneId = cur.id end
  end
  win.contentScroll:SetVerticalScroll(0)
  RenderZoneList()
  RenderContent()
  win:Show()
end
