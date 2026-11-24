-- EPU Guild Tools: Leveling Advisor, Dungeon Readiness & 12-Level XP Guard,
-- and Waylaid Crates / Craftsman's Writs UI.
local _, ns = ...

local win
local state = {
  tab = "advisor",
  dungeonId = "hall_of_thanes",
  campTier = 3,
  gearRole = "Auto",
  gearAllLevels = false,
  raidSize = 10,
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
  local edges = {}
  for _, s in ipairs({
    { "TOPLEFT", "TOPRIGHT", "h" }, { "BOTTOMLEFT", "BOTTOMRIGHT", "h" },
    { "TOPLEFT", "BOTTOMLEFT", "w" }, { "TOPRIGHT", "BOTTOMRIGHT", "w" },
  }) do
    local t = Tex(f, "BORDER", col, 1)
    t:SetPoint(s[1]); t:SetPoint(s[2])
    if s[3] == "h" then t:SetHeight(1) else t:SetWidth(1) end
    edges[#edges + 1] = t
  end
  return edges
end

local function Paint(t, col, a) t:SetColorTexture(col[1], col[2], col[3], a or 1) end

-- Widgets come from a pool, so switching tabs or refreshing reuses the last
-- draw's widgets instead of making new ones each time (the game never frees them).
local function NewFlow(child, width)
  local flow = { child = child, width = width, y = -8, pool = ns.NewWidgetPool(child) }

  function flow:Clear()
    self.pool:ReleaseAll()
    self.y = -8
  end

  function flow:Section(title)
    local col = C()
    self.y = self.y - 6
    local h = self.pool:Font(13, col.gold, "section")
    h:SetPoint("TOPLEFT", 10, self.y); h:SetWidth(self.width - 24); h:SetText(title)
    local r = self.pool:Texture("BORDER", "rule")
    Paint(r, col.line)
    r:SetPoint("TOPLEFT", 10, self.y - 18); r:SetSize(self.width - 24, 1)
    self.y = self.y - 26
  end

  function flow:Paragraph(text, color)
    local col = C()
    local fs = self.pool:Font(12, color or col.text, "paragraph")
    fs:SetPoint("TOPLEFT", 12, self.y); fs:SetWidth(self.width - 28); fs:SetWordWrap(true); fs:SetText(text)
    self.y = self.y - math.max(16, fs:GetStringHeight() or 16) - 6
  end

  function flow:Card(opts)
    local col = C()
    local card, inner = self.pool:Frame("card", function(f)
      f.bg = Tex(f, "BACKGROUND", col.panel, 1)
      f.bg:SetAllPoints()
      f.edges = Edges(f, col.line)
    end)
    card:SetPoint("TOPLEFT", 10, self.y); card:SetWidth(self.width - 24)
    Paint(card.bg, opts.bg or col.panel)
    for _, e in ipairs(card.edges) do Paint(e, opts.border or col.line) end

    local rightPad = 10
    if opts.actionText and opts.onAction then
      local ab = inner:Button(opts.actionText, opts.actionWidth or 110, 22)
      ab:SetPoint("TOPRIGHT", -8, -7)
      ab:SetScript("OnClick", opts.onAction)
      rightPad = (opts.actionWidth or 110) + 18
    end

    local curY = -8
    local function Line(size, color, tag, text, w, minH)
      local fs = inner:Font(size, color, tag)
      fs:SetPoint("TOPLEFT", 10, curY); fs:SetWidth(w); fs:SetWordWrap(true); fs:SetText(text)
      curY = curY - math.max(minH, fs:GetStringHeight() or minH) - 2
    end
    Line(12, opts.titleColor or col.white, "title", opts.title or "", self.width - 24 - 10 - rightPad, 15)
    if opts.sub and opts.sub ~= "" then
      Line(11, opts.subColor or col.muted, "sub", opts.sub, self.width - 24 - 10 - rightPad, 14)
    end
    if opts.note and opts.note ~= "" then
      Line(11, opts.noteColor or col.text, "note", opts.note, self.width - 44, 14)
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
        note = (isSel and not (d.x and d.y)) and "The entrance isn't mapped yet: the zone guide has the area." or nil,
        actionText = isSel and ((d.x and d.y) and "Waypoint" or "Zone guide") or "Inspect",
        actionWidth = 94,
        onAction = function()
          if isSel then
            if d.x and d.y then ns.SetZoneWaypoint(d.mapID, d.x, d.y, d.name)
            elseif ns.OpenZoneGuide then ns.OpenZoneGuide(d.zone) end
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
      -- A giver in a city or another zone carries its own map.
      local qMap, qx, qy, qGiver = q.mapID or selected.mapID, q.x, q.y, q.giver
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
      sub = "Shared with the guild, including guildmates who log in later. Keys in your bags tick themselves.",
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

    -- Raid attunements: the game confirms these from quests or items in your bags.
    flow:Section("Raid Attunements")
    for _, a in ipairs(ns.RAID_ATTUNEMENTS or {}) do
      local aId = a.id
      local mine = ns.IsAttuned(aId)
      local done, missing = ns.GetGuildAttunement(aId)
      local names = {}
      for i = 1, math.min(20, #done) do names[#names + 1] = done[i].name .. (done[i].online and " (On)" or "") end
      flow:Card({
        title = a.name .. (mine and ": you're attuned" or ": not attuned yet"),
        titleColor = mine and col.green or col.gold,
        sub = a.note,
        note = string.format("Attuned (%d): %s\nLevel 55+ still needing it: %d", #done,
          #names > 0 and table.concat(names, ", ") or "nobody has reported it yet", #missing),
        actionText = mine and "Mark Needed" or "Mark Done",
        actionWidth = 110,
        onAction = function() ns.ToggleMyReadiness(aId); Render() end,
      })
    end

    -- Guild reputation with the factions that matter for keys, raids and gear.
    flow:Section("Guild Reputation")
    local any = false
    for _, f in ipairs(ns.GUILD_REP_FACTIONS or {}) do
      local list = ns.GetGuildRep(f.id)
      if #list > 0 then
        any = true
        local parts = {}
        for i = 1, math.min(15, #list) do
          local e = list[i]
          parts[#parts + 1] = string.format("%s %s%s", e.name, ns.StandingName(e.s),
            (e.m or 0) > 0 and string.format(" %d/%d", e.v, e.m) or "")
        end
        if #list > 15 then parts[#parts + 1] = string.format("and %d more", #list - 15) end
        flow:Card({ title = string.format("%s (%d)", f.name, #list), titleColor = col.white, note = table.concat(parts, ", ") })
      end
    end
    if not any then
      flow:Card({ title = "No reputation shared yet", sub = "Guildmates' standings show here once they log in with this version." })
    end
    local sharing = ns.ShareRep()
    flow:Card({
      title = sharing and "Sharing your reputation with the guild" or "Your reputation is private",
      titleColor = sharing and col.green or col.gold,
      sub = "Argent Dawn, Timbermaw, Cenarion Circle, Thorium Brotherhood and other raid factions.",
      actionText = sharing and "Stop sharing" or "Share",
      actionWidth = 110,
      onAction = function() ns.SetShareRep(not sharing); Render() end,
    })

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
        local owners = ns.GetGuildCampingCoverage and ns.GetGuildCampingCoverage(bp.name) or {}
        local iHave = false
        local ownerNames = {}
        for _, o in ipairs(owners) do
          if o.name == ns.me then iHave = true end
          ownerNames[#ownerNames + 1] = o.name .. (o.online and " (On)" or "")
        end
        local bpName = bp.name
        flow:Card({
          title = string.format("[T%d · %s %d] %s%s", bp.tier, bp.profession, bp.skill, bp.name, knowsProf and "  (Your Prof)" or ""),
          titleColor = iHave and col.green or (knowsProf and col.blue or (bp.tier == 3 and col.gold or col.white)),
          sub = "Drop / Source: " .. bp.source,
          note = bp.effect .. "\nGuildmates with station: " .. (#ownerNames > 0 and table.concat(ownerNames, ", ") or "None reported yet"),
          actionText = iHave and "Have It" or "Mark Learned",
          actionWidth = 108,
          onAction = function()
            if ns.ToggleMyCampingStation then ns.ToggleMyCampingStation(bpName) end
            Render()
          end,
        })
      end
    end

  elseif state.tab == "gear" then
    local autoRole, className, specName = ns.PlayerGearRole()
    local activeRole = state.gearRole == "Auto" and autoRole or state.gearRole
    local pLevel = ns.GetPlayerLevel and ns.GetPlayerLevel() or 1
    flow:Section(string.format("Dungeon Gear Guide (%s%s · Role: %s · Lv %d)",
      className, specName and (" - " .. specName) or "", activeRole, pLevel))

    -- Role & Level controls as quick cards
    local nextRole = ({ Auto = "Tank", Tank = "Healer", Healer = "Melee", Melee = "Caster", Caster = "All", All = "Auto" })[state.gearRole] or "Auto"
    flow:Card({
      title = "Filter: Role = " .. state.gearRole .. (state.gearRole == "Auto" and (" (" .. autoRole .. ")") or ""),
      sub = "Click to cycle: Auto -> Tank -> Healer -> Melee -> Caster -> All",
      actionText = "Switch: " .. nextRole,
      actionWidth = 114,
      onAction = function() state.gearRole = nextRole; Render() end,
    })
    flow:Card({
      title = state.gearAllLevels and "Showing: All Dungeon Levels" or ("Showing: Dungeons Near Level " .. pLevel),
      actionText = state.gearAllLevels and "Near My Level" or "Show All",
      actionWidth = 114,
      onAction = function() state.gearAllLevels = not state.gearAllLevels; Render() end,
    })

    local shownD = 0
    for _, dg in ipairs(ns.DUNGEON_GEAR or {}) do
      local lr = dg.levelRange
      local inLevel = state.gearAllLevels or (pLevel >= (lr[1] - 4) and pLevel <= (lr[2] + 4))
      if inLevel then
        local matches = {}
        for _, it in ipairs(dg.items or {}) do
          if activeRole == "All" or it.role == "All" or it.role == activeRole then
            matches[#matches + 1] = it
          end
        end
        if #matches > 0 then
          shownD = shownD + 1
          local dId = dg.id
          flow:Section(string.format("%s (Levels %d–%d)", dg.name, lr[1], lr[2]))
          for _, it in ipairs(matches) do
            flow:Card({
              title = it.name,
              titleColor = col.gold,
              sub = string.format("%s  ·  %s  ·  Drop: %s", it.role, it.slot, it.source),
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
        end
      end
    end
    if shownD == 0 then
      flow:Paragraph("No dungeons matched this level/role filter. Click 'Show All' above to browse all dungeons.", col.muted)
    end

  elseif state.tab == "runs" then
    if not (ns.IsTrusted and ns.IsTrusted(ns.me)) then
      flow:Section("Officer Only")
      flow:Paragraph("Guild Dungeon Run tracking & attendance stats are currently restricted to officers.", col.muted)
    else
      local party = ns.GetCurrentPartyGuildStatus and ns.GetCurrentPartyGuildStatus() or { members = {}, nonGuild = {} }
      local selected
      for _, d in ipairs(ns.DUNGEON_READINESS or {}) do
        if d.id == state.dungeonId then selected = d; break end
      end
      selected = selected or ns.DUNGEON_READINESS[1]
      local targetDungeon = party.instance or selected.name
      local targetId = party.instance and nil or selected.id

      flow:Section("Log Guild Dungeon Run (Officer Only)")
      local pTitle = party.fullGuild and string.format("Full Guild Party Ready (%d guildmates)", #party.members)
        or string.format("Current Party: %d guildmate(s), %d non-guild", #party.members, #party.nonGuild)
      flow:Card({
        title = pTitle,
        titleColor = party.fullGuild and col.green or col.gold,
        bg = party.fullGuild and col.greenBg or col.panel,
        sub = "Target Dungeon: " .. targetDungeon .. "  (change in Dungeon Readiness tab or enter instance)",
        note = "Members: " .. table.concat(party.members, ", "),
        actionText = "Log Run",
        actionWidth = 96,
        onAction = function()
          ns.LogGuildDungeonRun(targetDungeon, targetId, party.members, party.fullGuild, "")
          Render()
        end,
      })

      local stats = ns.GetGuildDungeonStats()
      local gh = stats.guildHealth
      flow:Section("Guild Health & Roster Stats")
      flow:Card({
        title = string.format("Members: %d  ·  Online: %d  ·  Using EPU: %d", gh.totalMembers, gh.onlineCount, gh.epuUsers),
        titleColor = col.blue,
        sub = string.format("Levels — 1–19: %d  |  20–39: %d  |  40–59: %d  |  60: %d",
          gh.brackets.low, gh.brackets.mid, gh.brackets.high, gh.brackets.cap),
        note = string.format("Profile Roles — Tanks: %d  ·  Healers: %d  ·  DPS: %d",
          gh.roles.tank, gh.roles.healer, gh.roles.dps),
      })

      flow:Section("Dungeon Completion Matrix (Full Guild Clears)")
      for _, d in ipairs(ns.DUNGEON_READINESS or {}) do
        local ds = stats.byDungeon[d.id] or stats.byDungeon[d.name]
        local fullCount = ds and ds.full or 0
        local totCount = ds and ds.total or 0
        local lastStr = (ds and ds.lastT > 0) and date("%Y-%m-%d", ds.lastT) or "Never"
        flow:Card({
          title = string.format("%s  (Lv %d–%d)", d.name, d.levelRange[1], d.levelRange[2]),
          titleColor = fullCount > 0 and col.green or col.gold,
          sub = string.format("Full Guild Clears: %d  ·  Total Guild Runs: %d  ·  Last: %s", fullCount, totCount, lastStr),
        })
      end

      flow:Section("Attendance Leaderboard (Last 30 Days & All-Time)")
      if #stats.attendance == 0 then
        flow:Paragraph("No guild dungeon runs logged yet. Form a guild group and click 'Log Run' above!", col.muted)
      else
        for i = 1, math.min(15, #stats.attendance) do
          local m = stats.attendance[i]
          flow:Card({
            title = string.format("#%d  %s", i, m.name),
            titleColor = col.white,
            sub = string.format("30d Runs: %d  ·  Full Guild: %d  ·  Total: %d  ·  Unique Dungeons: %d",
              m.recent30, m.full, m.total, m.uniqueDungeons),
          })
        end
      end

      flow:Section("Needs a Guild Run (Active Lv 13+, 0 Runs in 30d)")
      if #stats.zeroRunMembers == 0 then
        flow:Paragraph("Everyone active has been in a logged guild run in the last 30 days!", col.green)
      else
        local names = {}
        for i = 1, math.min(20, #stats.zeroRunMembers) do
          local zm = stats.zeroRunMembers[i]
          names[#names + 1] = string.format("%s (Lv %d%s)", zm.name, zm.level, zm.online and ", On" or "")
        end
        flow:Card({
          title = #stats.zeroRunMembers .. " guildmate(s) without a recent guild run",
          titleColor = col.gold,
          note = table.concat(names, "  ·  "),
        })
      end

      flow:Section("Recent Logged Runs (" .. #stats.runs .. ")")
      for i = 1, math.min(12, #stats.runs) do
        local r = stats.runs[i]
        local rId = r.id
        flow:Card({
          title = string.format("%s  (%s)", r.dungeon, r.fullGuild and "Full Guild" or "Partial Guild"),
          titleColor = r.fullGuild and col.green or col.white,
          sub = string.format("%s  ·  Logged by %s  ·  %d member(s)", date("%Y-%m-%d %H:%M", r.t or 0), r.by or "?", #(r.members or {})),
          note = (r.note and r.note ~= "" and (r.note .. "\n") or "") .. table.concat(r.members or {}, ", "),
          actionText = "Void",
          actionWidth = 68,
          onAction = function() ns.VoidGuildDungeonRun(rId); Render() end,
        })
      end
    end

  elseif state.tab == "raid" then
    local myRaid = ns.GetMyRaidStatus and ns.GetMyRaidStatus() or { amulet = false, fireRes = 0, role = "DPS" }
    flow:Section("Dec 9 Raid Launch: Your Readiness")
    flow:Card({
      title = string.format("Drakefire Amulet (Onyxia): %s  ·  Fire Resistance: %d  ·  Role: %s",
        myRaid.amulet and "READY" or "MISSING", myRaid.fireRes or 0, myRaid.role or "DPS"),
      titleColor = myRaid.amulet and col.green or col.gold,
      sub = "Broadcasts your amulet, Fire Resistance, and role to the guild.",
      actionText = "Sync Status",
      actionWidth = 104,
      onAction = function()
        if ns.SyncMyRaidStatus then ns.SyncMyRaidStatus() end
        ns.Print("Synced your Raid Readiness status.")
        Render()
      end,
    })

    flow:Section("Forever Dec 9 Raids (No Classic World Buffs Inside)")
    for _, r in ipairs(ns.FOREVER_RAIDS or {}) do
      flow:Card({
        title = string.format("%s  (%d-Player · %d Bosses)", r.name, r.size, r.bosses),
        titleColor = col.gold,
        sub = "Attunement: " .. r.attunement .. "  ·  " .. r.location,
        note = r.notes,
      })
    end

    local nextSize = ({ [10] = 20, [20] = 40, [40] = 10 })[state.raidSize] or 10
    local squads, poolCount = {}, 0
    if ns.BuildRaidSquads then squads, poolCount = ns.BuildRaidSquads(state.raidSize) end
    squads, poolCount = squads or {}, poolCount or 0
    flow:Section(string.format("Squad Builder (%d-Man Teams · %d Guildmates Lv 58+)", state.raidSize, poolCount))
    flow:Card({
      title = "Team Size: " .. state.raidSize .. "-Player (" .. #squads .. " squad(s))",
      sub = "Auto-balances Tanks, Healers, and DPS from guild profiles & synced raid status.",
      actionText = "Switch: " .. nextSize .. "m",
      actionWidth = 106,
      onAction = function() state.raidSize = nextSize; Render() end,
    })
    for _, sq in ipairs(squads) do
      local names = {}
      for _, m in ipairs(sq.members) do
        names[#names + 1] = string.format("%s (%s%s)", m.name, m.role:sub(1, 1), m.amulet and ", Ony" or "")
      end
      flow:Card({
        title = string.format("Squad %d (%d/%d) — Tanks: %d · Healers: %d · DPS: %d",
          sq.index, #sq.members, state.raidSize, #sq.tanks, #sq.healers, #sq.dps),
        titleColor = #sq.members >= state.raidSize and col.green or col.white,
        note = #names > 0 and table.concat(names, "  ·  ") or "No level 58+ members in roster yet.",
      })
    end

    flow:Section("Raid Consumables & Bank Prep")
    local isTrusted = ns.IsTrusted and ns.IsTrusted(ns.me)
    for _, rc in ipairs(ns.RAID_CONSUMABLES or {}) do
      local bankQty, crafters = ns.CheckGuildStockAndCrafters(rc.name, rc.itemID)
      local cText = #crafters > 0 and (crafters[1].name .. (crafters[1].online and " (On)" or "")) or "No crafter synced"
      local itemID, itemName = rc.itemID, rc.name
      flow:Card({
        title = rc.name,
        sub = string.format("Guild Bank: %d  ·  Crafter: %s", bankQty, cText),
        subColor = bankQty > 0 and col.green or col.muted,
        note = rc.use,
        actionText = isTrusted and "Add Need +20" or nil,
        actionWidth = 112,
        onAction = isTrusted and function() ns.AddLevelingNeed(itemID, 20, itemName); Render() end or nil,
      })
    end
    if isTrusted then
      flow:Card({
        title = "Create Dec 9 Raid Consumables Project",
        titleColor = col.gold,
        sub = "Spin up a Guild Project in Guild -> Projects for Flasks & Protection Potions.",
        actionText = "Create Project",
        actionWidth = 116,
        onAction = function()
          ns.CreateLevelingProject("Dec 9 Raid Consumables", "Flasks, Greater Fire/Nature/Shadow Protection Potions, and Mongoose/Arcane Elixirs.")
        end,
      })
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
    { "advisor", "Advisor", 76 },
    { "dungeons", "Readiness", 90 },
    { "gear", "Gear", 64 },
    { "writs", "Writs", 68 },
    { "camping", "Camping", 80 },
    { "raid", "Dec 9 Raids", 98 },
  }
  if ns.IsTrusted and ns.IsTrusted(ns.me) then
    tabDefs[#tabDefs + 1] = { "runs", "Guild Runs", 96 }
  end
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
  if tab == "dungeons" or tab == "writs" or tab == "advisor" or tab == "camping" or tab == "gear" or tab == "runs" or tab == "raid" then
    state.tab = tab
  end
  win.scroll:SetVerticalScroll(0)
  Render()
  win:Show()
end
