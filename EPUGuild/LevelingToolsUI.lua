-- EPU Guild Tools: Leveling Advisor, Dungeon Readiness & 12-Level XP Guard,
-- and Waylaid Crates / Craftsman's Writs UI.
local _, ns = ...

local win
local state = {
  tab = "advisor",
  dungeonId = "hall_of_thanes",
  campTier = 3,
}

local function C() return ns.InterfaceColors end
local function Font(p, s, c) return ns.InterfaceFont(p, s, c) end
local function Btn(p, t, w, h) return ns.InterfaceButton(p, t, w, h) end

local function Tex(p, layer, col, a)
  local t = p:CreateTexture(nil, layer or "BACKGROUND")
  t:SetColorTexture(col[1], col[2], col[3], a or 1)
  return t
end

local function Edges(f, col)
  for _, s in ipairs({
    { "TOPLEFT", "TOPRIGHT", "h" }, { "BOTTOMLEFT", "BOTTOMRIGHT", "h" },
    { "TOPLEFT", "BOTTOMLEFT", "w" }, { "TOPRIGHT", "BOTTOMRIGHT", "w" },
  }) do
    local t = Tex(f, "BORDER", col, 1)
    t:SetPoint(s[1]); t:SetPoint(s[2])
    if s[3] == "h" then t:SetHeight(1) else t:SetWidth(1) end
  end
end

local function NewFlow(child, width)
  local flow = { child = child, width = width, y = -8, widgets = {} }
  local function Track(w) flow.widgets[#flow.widgets + 1] = w; return w end

  function flow:Clear()
    for _, w in ipairs(self.widgets) do w:Hide(); w:SetParent(nil) end
    self.widgets = {}; self.y = -8
  end

  function flow:Section(title)
    local col = C()
    self.y = self.y - 6
    local h = Track(Font(self.child, 13, col.gold))
    h:SetPoint("TOPLEFT", 10, self.y); h:SetWidth(self.width - 24); h:SetJustifyH("LEFT"); h:SetText(title)
    local r = Track(Tex(self.child, "BORDER", col.line, 1))
    r:SetPoint("TOPLEFT", 10, self.y - 18); r:SetSize(self.width - 24, 1)
    self.y = self.y - 26
  end

  function flow:Paragraph(text, color)
    local col = C()
    local fs = Track(Font(self.child, 12, color or col.text))
    fs:SetPoint("TOPLEFT", 12, self.y); fs:SetWidth(self.width - 28); fs:SetJustifyH("LEFT"); fs:SetWordWrap(true); fs:SetText(text)
    self.y = self.y - math.max(16, fs:GetStringHeight() or 16) - 6
  end

  function flow:Card(opts)
    local col = C()
    local card = Track(CreateFrame("Frame", nil, self.child))
    card:SetPoint("TOPLEFT", 10, self.y); card:SetWidth(self.width - 24)
    Tex(card, "BACKGROUND", opts.bg or col.panel, 1):SetAllPoints()
    Edges(card, opts.border or col.line)

    local rightPad = 10
    if opts.actionText and opts.onAction then
      local ab = Track(Btn(card, opts.actionText, opts.actionWidth or 110, 22))
      ab:SetPoint("TOPRIGHT", -8, -7)
      ab:SetScript("OnClick", opts.onAction)
      rightPad = (opts.actionWidth or 110) + 18
    end

    local curY = -8
    local t = Track(Font(card, 12, opts.titleColor or col.white))
    t:SetPoint("TOPLEFT", 10, curY); t:SetWidth(self.width - 24 - 10 - rightPad); t:SetJustifyH("LEFT"); t:SetWordWrap(true); t:SetText(opts.title or "")
    curY = curY - math.max(15, t:GetStringHeight() or 15) - 2

    if opts.sub and opts.sub ~= "" then
      local s = Track(Font(card, 11, opts.subColor or col.muted))
      s:SetPoint("TOPLEFT", 10, curY); s:SetWidth(self.width - 24 - 10 - rightPad); s:SetJustifyH("LEFT"); s:SetWordWrap(true); s:SetText(opts.sub)
      curY = curY - math.max(14, s:GetStringHeight() or 14) - 2
    end

    if opts.note and opts.note ~= "" then
      local n = Track(Font(card, 11, opts.noteColor or col.text))
      n:SetPoint("TOPLEFT", 10, curY); n:SetWidth(self.width - 44); n:SetJustifyH("LEFT"); n:SetWordWrap(true); n:SetText(opts.note)
      curY = curY - math.max(14, n:GetStringHeight() or 14) - 2
    end

    local h = math.max(36, -curY + 6)
    card:SetHeight(h)
    self.y = self.y - h - 5
  end

  function flow:Finish()
    self.child:SetHeight(math.max(200, -self.y + 16))
  end

  return flow
end

local function Render()
  if not win then return end
  local col = C()

  for _, tb in pairs(win.tabs) do
    local active = (tb.key == state.tab)
    local bg = active and col.selected or col.panel2
    local tc = active and col.gold or col.text
    tb.bg:SetColorTexture(bg[1], bg[2], bg[3], 1)
    tb.text:SetTextColor(tc[1], tc[2], tc[3])
    tb.strip:SetShown(active)
  end

  local flow = win.flow
  flow:Clear()

  if state.tab == "advisor" then
    local adv = ns.GetLevelingAdvice()
    flow:Section(string.format("Level %d Advisor (%s)", adv.level, adv.faction or "Neutral"))

    flow:Section("Recommended Zones Right Now (" .. #adv.zones .. ")")
    if #adv.zones == 0 then
      flow:Paragraph("No level-specific zones matched. Open the Zone Visitor's Guide to browse all 43 zones.", col.muted)
    else
      for _, z in ipairs(adv.zones) do
        local zId = z.id
        flow:Card({
          title = string.format("%s  (Levels %d–%d)", z.name, z.levelRange[1], z.levelRange[2]),
          sub = (z.continent or "") .. " · " .. (z.faction or "Neutral"),
          note = z.tagline,
          actionText = "Zone Guide",
          actionWidth = 96,
          onAction = function()
            if ns.OpenZoneGuide then ns.OpenZoneGuide(zId) end
          end,
        })
      end
    end

    flow:Section("Recommended Dungeons (" .. #adv.dungeons .. ")")
    for _, d in ipairs(adv.dungeons) do
      local dId = d.id
      flow:Card({
        title = string.format("%s  (Levels %d–%d)", d.name, d.levelRange[1], d.levelRange[2]),
        titleColor = col.gold,
        sub = d.zone .. " · Key/Attune: " .. (d.key or "None"),
        actionText = "Check Ready",
        actionWidth = 104,
        onAction = function()
          state.dungeonId = dId
          state.tab = "dungeons"
          win.scroll:SetVerticalScroll(0)
          Render()
        end,
      })
    end

    flow:Section("Milestones & Forever Reminders")
    for _, m in ipairs(adv.milestones) do
      flow:Card({ title = m.title, titleColor = col.green, note = m.note })
    end

    flow:Section("Common Quest-Item Bottlenecks (Bank & Crafters)")
    local isTrusted = ns.IsTrusted and ns.IsTrusted(ns.me)
    for _, b in ipairs(ns.QUEST_BOTTLENECKS or {}) do
      local bankQty, crafters = ns.CheckGuildStockAndCrafters(b.name, b.itemID)
      local cText = #crafters > 0 and (crafters[1].name .. (crafters[1].online and " (Online)" or " (Offline)")) or "No crafter synced"
      local itemID, itemName = b.itemID, b.name
      local actText, onAct
      if bankQty > 0 then
        actText = "Request (1)"
        onAct = function() if ns.NewRequest then ns.NewRequest(itemID, 1, "Leveling quest item") end end
      elseif isTrusted then
        actText = "Add Need +5"
        onAct = function() ns.AddLevelingNeed(itemID, 5, itemName); Render() end
      end
      flow:Card({
        title = string.format("%s (%s)", b.name, b.prof),
        sub = string.format("Bank: %d  ·  Crafter: %s", bankQty, cText),
        subColor = bankQty > 0 and col.green or col.muted,
        note = "Used in: " .. b.usedIn,
        actionText = actText,
        actionWidth = 104,
        onAction = onAct,
      })
    end
    if isTrusted then
      flow:Card({
        title = "Stock Leveling Quest Items (Guild Project)",
        titleColor = col.gold,
        sub = "Create a guild crafting project in Guild -> Projects to assign crafters.",
        actionText = "Create Project",
        actionWidth = 114,
        onAction = function()
          ns.CreateLevelingProject("Leveling Quest Supplies", "Craft bottleneck quest items (Bronze Tubes, Frost Oil, Water Breathing, etc.).")
        end,
      })
    end

  elseif state.tab == "dungeons" then
    local selected
    for _, d in ipairs(ns.DUNGEON_READINESS or {}) do
      if d.id == state.dungeonId then selected = d; break end
    end
    selected = selected or ns.DUNGEON_READINESS[1]

    -- 12-Level Trivial-XP Guard
    local xpCheck = ns.CheckTrivialXP(selected.levelRange[1], selected.levelRange[2])
    flow:Section("12-Level Trivial-XP Guard (WoW: Forever Rule)")
    if xpCheck.ok then
      flow:Card({
        title = "Party XP Check: Safe",
        titleColor = col.green,
        bg = col.greenBg,
        sub = string.format("Checked %d member(s) (Lv %d–%d) against %s (%d–%d).",
          #xpCheck.members, xpCheck.lowest.level, xpCheck.highest.level, selected.name, selected.levelRange[1], selected.levelRange[2]),
        note = "No member is 12+ levels above the dungeon or lowest party member.",
      })
    else
      for _, w in ipairs(xpCheck.warnings) do
        flow:Card({
          title = "TRIVIAL XP WARNING (12+ Level Gap)",
          titleColor = col.red,
          bg = col.redBg,
          note = w,
        })
      end
    end

    flow:Section("Select Dungeon")
    for _, d in ipairs(ns.DUNGEON_READINESS or {}) do
      local isSel = (d.id == selected.id)
      local dId = d.id
      flow:Card({
        title = (isSel and "> " or "") .. string.format("%s  (Lv %d–%d · %s)", d.name, d.levelRange[1], d.levelRange[2], d.zone),
        titleColor = isSel and col.gold or col.white,
        bg = isSel and col.selected or col.panel,
        sub = "Key / Attunement: " .. (d.key or "None"),
        actionText = isSel and "Waypoint" or "Inspect",
        actionWidth = 94,
        onAction = function()
          if isSel then
            ns.SetZoneWaypoint(d.mapID, d.x, d.y, d.name)
          else
            state.dungeonId = dId
            win.scroll:SetVerticalScroll(0)
            Render()
          end
        end,
      })
    end

    flow:Section("Key & Pre-Dungeon Quest Checklist: " .. selected.name)
    if selected.keyItemID then
      local has = ns.HasKeyItem(selected.keyItemID)
      flow:Card({
        title = selected.key .. (has and "  [HAVE]" or "  [MISSING]"),
        titleColor = has and col.green or col.gold,
        sub = has and "Found in your bags/keyring." or "At least one party member needs this key/item.",
      })
    elseif selected.key and selected.key ~= "None" then
      flow:Card({ title = "Requirement: " .. selected.key, titleColor = col.gold })
    end

    local logMap = ns.GetPlayerQuestLogMap and ns.GetPlayerQuestLogMap() or {}
    local pLevel = ns.GetPlayerLevel and ns.GetPlayerLevel() or 1
    for _, q in ipairs(selected.quests or {}) do
      local qc = ns.QuestDifficultyColor and ns.QuestDifficultyColor(q.level, pLevel) or col.white
      local status = logMap[q.name:lower()]
      local badge = status and ("  [" .. status .. "]") or ""
      local qMap, qx, qy, qGiver = selected.mapID, q.x, q.y, q.giver
      flow:Card({
        title = string.format("[%d] %s%s", q.level or pLevel, q.name, badge),
        titleColor = qc,
        sub = (q.faction or "Neutral") .. " · Giver: " .. (q.giver or "?"),
        actionText = (qx and qy) and string.format("%.1f, %.1f", qx, qy) or nil,
        actionWidth = 84,
        onAction = (qx and qy) and function() ns.SetZoneWaypoint(qMap, qx, qy, qGiver or q.name) end or nil,
      })
    end

    flow:Section("Guild Progress: Who Completed & Who Still Needs")
    local myDone = ns.GetMyReadiness()[selected.id]
    local selId, selName = selected.id, selected.name
    flow:Card({
      title = myDone and "Your Status: Completed / Keyed" or "Your Status: Still Needed",
      titleColor = myDone and col.green or col.gold,
      sub = "Broadcasts your key/attunement readiness to the guild.",
      actionText = myDone and "Mark Needed" or "Mark Ready",
      actionWidth = 110,
      onAction = function() ns.ToggleMyReadiness(selId); Render() end,
    })
    local completed, needed = ns.GetGuildReadiness(selected)
    local compNames = {}
    for _, m in ipairs(completed) do compNames[#compNames + 1] = m.name .. (m.level > 0 and (" (" .. m.level .. ")") or "") end
    local needNames = {}
    for i = 1, math.min(20, #needed) do
      local m = needed[i]
      needNames[#needNames + 1] = m.name .. " (" .. m.level .. (m.online and ", On)" or ")")
    end
    flow:Card({
      title = "Completed / Keyed (" .. #completed .. ")",
      titleColor = col.green,
      note = #compNames > 0 and table.concat(compNames, ", ") or "No guildmates have reported ready yet.",
    })
    flow:Card({
      title = "Still Needed in Level Range (" .. #needed .. ")",
      titleColor = col.gold,
      note = #needNames > 0 and table.concat(needNames, ", ") or "No guildmates in this bracket need it.",
    })
    if ns.IsTrusted and ns.IsTrusted(ns.me) then
      flow:Card({
        title = "Create Guild Prep Project for " .. selName,
        sub = "Track crafting consumables or key mats in Guild -> Projects.",
        actionText = "Create Project",
        actionWidth = 114,
        onAction = function()
          ns.CreateLevelingProject("Prep: " .. selName, "Supplies & crafting for " .. selName)
        end,
      })
    end

  elseif state.tab == "writs" then
    local pFaction = ns.GetPlayerFaction and ns.GetPlayerFaction() or "Alliance"
    local hub = ns.SUPPLY_HUBS[pFaction] or ns.SUPPLY_HUBS.Alliance
    flow:Section("Your Merchant's Favor Supply Hub (" .. pFaction .. ")")
    flow:Card({
      title = hub.name,
      titleColor = col.gold,
      sub = hub.zone,
      note = hub.note,
      actionText = string.format("%.1f, %.1f", hub.x, hub.y),
      actionWidth = 84,
      onAction = function() ns.SetZoneWaypoint(hub.mapID, hub.x, hub.y, hub.name) end,
    })

    local items = ns.ScanBagCratesAndWrits()
    flow:Section("Crates & Writs in Your Bags (" .. #items .. ")")
    if #items == 0 then
      flow:Paragraph("No Waylaid Crates, Craftsman's Writs, or Shipping Labels found in your bags right now.", col.muted)
    else
      for _, it in ipairs(items) do
        local sub = it.kind
        local actText, onAct
        if it.target then
          local bankQty, crafters = ns.CheckGuildStockAndCrafters(it.target, nil)
          local cText = #crafters > 0 and (crafters[1].name .. (crafters[1].online and " (Online)" or "")) or "None synced"
          sub = string.format("%s  ·  Target: %s  ·  Bank: %d  ·  Crafter: %s", it.kind, it.target, bankQty, cText)
          if it.kind == "Craftsman's Writ" then
            local wName = it.name
            actText = "Mark Done"
            onAct = function()
              ns.RecordWritCooldown(wName)
              ns.Print("Recorded 20h cooldown for " .. wName)
              Render()
            end
          end
        end
        flow:Card({
          title = it.name .. (it.count > 1 and (" x" .. it.count) or ""),
          titleColor = col.green,
          sub = sub,
          actionText = actText,
          actionWidth = 94,
          onAction = onAct,
        })
      end
    end

    flow:Section("Daily Craftsman's Writ Cooldowns")
    local cds = ns.GetWritCooldowns()
    local now = time()
    local activeCD = 0
    for wName, expires in pairs(cds) do
      if expires > now then
        activeCD = activeCD + 1
        local rem = expires - now
        local hrs = math.floor(rem / 3600)
        local mins = math.floor((rem % 3600) / 60)
        flow:Card({
          title = wName,
          sub = string.format("Ready in %dh %dm", hrs, mins),
          subColor = col.gold,
        })
      end
    end
    if activeCD == 0 then
      flow:Paragraph("No active Craftsman's Writ cooldowns recorded on this character.", col.muted)
    end

  elseif state.tab == "camping" then
    flow:Section("Camping Blueprints (Tier " .. (state.campTier == 0 and "2 & 3" or tostring(state.campTier)) .. ")")
    flow:Paragraph("Tier 1 camp items are learned from trainers (~Skill 20). Tier 2 (Skill 140) and Tier 3 (Skill 300) Blueprints drop from dungeon bosses.", col.muted)

    local myProfs = (ns.GuidePlayer and ns.GuidePlayer().professions) or {}
    local profNames = {}
    for _, pinfo in pairs(myProfs) do
      if pinfo.name then profNames[pinfo.name:lower()] = true end
    end

    for _, bp in ipairs(ns.CAMPING_BLUEPRINTS or {}) do
      if state.campTier == 0 or bp.tier == state.campTier then
        local knowsProf = profNames[bp.profession:lower()]
        local dId = bp.dungeonId
        flow:Card({
          title = string.format("[T%d · %s %d] %s%s", bp.tier, bp.profession, bp.skill, bp.name, knowsProf and "  (Your Prof)" or ""),
          titleColor = knowsProf and col.green or (bp.tier == 3 and col.gold or col.white),
          sub = "Drop / Source: " .. bp.source,
          note = bp.effect,
          actionText = dId and "Check Dungeon" or nil,
          actionWidth = 114,
          onAction = dId and function()
            state.dungeonId = dId
            state.tab = "dungeons"
            win.scroll:SetVerticalScroll(0)
            Render()
          end or nil,
        })
      end
    end
  end

  flow:Finish()
end

local function BuildWindow()
  if win then return win end
  local col = C()
  win = ns.InterfaceWindow("EPUGuildLevelingWindow", UIParent, "EPU WoW: Forever Leveling Tools", 880, 600)
  win:SetMovable(true)
  win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", win.StartMoving)
  win:SetScript("OnDragStop", win.StopMovingOrSizing)

  win.tabs = {}
  local tabDefs = {
    { "advisor", "Leveling Advisor", 130 },
    { "dungeons", "Dungeon Readiness & XP", 174 },
    { "writs", "Crates & Writs", 118 },
    { "camping", "T3 Camping Drops", 136 },
  }
  local tx = 14
  for _, def in ipairs(tabDefs) do
    local tb = CreateFrame("Button", nil, win)
    tb:SetSize(def[3], 26)
    tb:SetPoint("TOPLEFT", tx, -44)
    tb.bg = Tex(tb, "BACKGROUND", col.panel2, 1); tb.bg:SetAllPoints()
    Edges(tb, col.line)
    tb.strip = Tex(tb, "BORDER", col.gold, 1)
    tb.strip:SetPoint("BOTTOMLEFT"); tb.strip:SetPoint("BOTTOMRIGHT"); tb.strip:SetHeight(2)
    tb.text = Font(tb, 11, col.text); tb.text:SetPoint("CENTER"); tb.text:SetText(def[2])
    tb.key = def[1]
    tb:SetScript("OnClick", function(self)
      state.tab = self.key
      win.scroll:SetVerticalScroll(0)
      Render()
    end)
    win.tabs[def[1]] = tb
    tx = tx + def[3] + 6
  end

  local zgBtn = Btn(win, "Open Zone Guide", 130, 26)
  zgBtn:SetPoint("TOPRIGHT", -14, -44)
  zgBtn:SetScript("OnClick", function()
    if ns.OpenZoneGuide then ns.OpenZoneGuide() end
  end)

  local body = CreateFrame("Frame", nil, win)
  body:SetPoint("TOPLEFT", 14, -76)
  body:SetPoint("BOTTOMRIGHT", -14, 14)
  Tex(body, "BACKGROUND", col.panel2, 0.35):SetAllPoints()
  Edges(body, col.line)

  local scroll = CreateFrame("ScrollFrame", nil, body)
  scroll:SetPoint("TOPLEFT", 6, -6)
  scroll:SetPoint("BOTTOMRIGHT", -6, 6)
  scroll:EnableMouseWheel(true)
  local child = CreateFrame("Frame", nil, scroll)
  child:SetWidth(836); child:SetHeight(200)
  scroll:SetScrollChild(child)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local cur = self:GetVerticalScroll()
    local maxS = math.max(0, child:GetHeight() - self:GetHeight())
    self:SetVerticalScroll(math.max(0, math.min(maxS, cur - delta * 42)))
  end)

  win.scroll = scroll
  win.flow = NewFlow(child, 836)
  return win
end

function ns.OpenLevelingTools(tab)
  BuildWindow()
  if ns.SyncMyKeys then ns.SyncMyKeys() end
  if tab == "dungeons" or tab == "writs" or tab == "advisor" or tab == "camping" then
    state.tab = tab
  end
  win.scroll:SetVerticalScroll(0)
  Render()
  win:Show()
end
