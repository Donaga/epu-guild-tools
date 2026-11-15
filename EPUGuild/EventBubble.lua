local _, ns = ...

local bubble = CreateFrame('Button', 'EPUGuildEventBubble', UIParent)
bubble:SetSize(42, 42)
bubble:SetFrameStrata('MEDIUM')
bubble:SetClampedToScreen(true)
bubble:SetMovable(true)
bubble:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
bubble:RegisterForDrag('LeftButton')
bubble:Hide()

local function Round(texture)
  if not bubble.CreateMaskTexture then return end
  local mask = bubble:CreateMaskTexture()
  if mask then
    mask:SetTexture('Interface\\CharacterFrame\\TempPortraitAlphaMask', 'CLAMPTOBLACKADDITIVE', 'CLAMPTOBLACKADDITIVE')
    mask:SetAllPoints(texture)
    texture:AddMaskTexture(mask)
  end
end

local border = bubble:CreateTexture(nil, 'BACKGROUND')
border:SetAllPoints()
border:SetColorTexture(0.82, 0.63, 0.26, 0.95)
Round(border)
local icon = bubble:CreateTexture(nil, 'ARTWORK')
icon:SetPoint('TOPLEFT', 3, -3)
icon:SetPoint('BOTTOMRIGHT', -3, 3)
icon:SetTexture(ns.LOGO_SMALL)
Round(icon)
bubble:SetHighlightTexture('Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight')
local function Badge(point,y,bg,fg)
  local badge=CreateFrame("Frame",nil,bubble)
  badge:SetPoint(point,bubble,point,4,y)
  badge:SetHeight(17)
  local fill=badge:CreateTexture(nil,"BACKGROUND")
  fill:SetAllPoints()
  fill:SetColorTexture(bg[1],bg[2],bg[3],1)
  badge.text=ns.InterfaceFont(badge,12,fg)
  badge.text:SetPoint("CENTER")
  return badge
end
local eventBadge=Badge("BOTTOMRIGHT",-3,ns.InterfaceColors.panel2,ns.InterfaceColors.white)
local actionBadge=Badge("TOPRIGHT",3,{1,.65,.24},ns.InterfaceColors.bg)

local function PlaceBubble()
  local state = ns.CommunityState()
  local x, y = state and state.eventBubbleX, state and state.eventBubbleY
  bubble:ClearAllPoints()
  if type(x) == 'number' and x >= 0 and x <= 1 and type(y) == 'number' and y >= 0 and y <= 1 then
    bubble:SetPoint('CENTER', UIParent, 'BOTTOMLEFT', x * UIParent:GetWidth(), y * UIParent:GetHeight())
  else
    bubble:SetPoint('CENTER', UIParent, 'CENTER', 260, -90)
  end
end

local sections = {
  {'review', 'Bank requests to review'},
  {'fulfill', 'Approved bank requests to fill'},
  {'respond', 'Craft requests to answer'},
  {'craft', 'Accepted crafts to finish'},
  {'places', 'Event signups to review'},
  {'invites', 'Guild invites to send'},
  {'inbox', 'Discord updates to import'},
}

function ns.GetBubbleActions(guild, state)
  local actions = {}
  for _, section in ipairs(sections) do actions[section[1]] = {} end
  local officer = ns.IsTrusted(ns.me)
  for id, request in pairs(guild.requests or {}) do
    local pending = request.status == 'pending' or request.status == 'open'
    local group
    if request.crafter == ns.me and ns.me then
      group = pending and actions.respond or request.status == 'approved' and actions.craft
    elseif officer and not request.crafter then
      group = pending and actions.review or request.status == 'approved' and ns.Remaining(request) > 0 and actions.fulfill
    end
    if group then group[#group+1] = id end
  end
  for _, reply in pairs(guild.eventResponses or {}) do
    local event = (guild.guildEvents or {})[reply.event]
    if event and event.who == ns.me and event.status == 'scheduled' and event.starts > ns.Now()
      and ns.Member(reply.who) and ns.EventPlaceStatus(event, reply) == 'Waitlist' and (event.places[reply.role] or 0) > 0 then
      actions.places[#actions.places+1] = reply
    end
  end
  if ns.CanInviteGuild() then
    local byName = {}
    for id, invite in pairs(guild.inviteRequests or {}) do
      if ns.ActiveGuildInvite(invite) and (not state.inviteDismissed or state.inviteDismissed[id] ~= invite.who)
        and not ns.GuildInviteOutcome(id) then
        local key = invite.who:lower()
        if not byName[key] or id < byName[key] then byName[key] = id end
      end
    end
    for _, id in pairs(byName) do actions.invites[#actions.invites+1] = id end
    table.sort(actions.invites)
  end
  if officer then
    local done = ns.db and ns.db.inboxDone or {}
    for _, entry in ipairs(EPUGuildInbox or {}) do
      if type(entry) == 'table' and entry.id and not done[entry.id] then actions.inbox[#actions.inbox+1] = entry.id end
    end
  end
  for _, kind in ipairs({'review', 'fulfill', 'respond', 'craft'}) do
    table.sort(actions[kind], function(a, b)
      local first, second = guild.requests[a].t or 0, guild.requests[b].t or 0
      return first < second or first == second and a < b
    end)
  end
  table.sort(actions.places, function(a,b)
    local first, second = guild.guildEvents[a.event].starts, guild.guildEvents[b.event].starts
    return first < second or first == second and a.who < b.who
  end)
  return actions
end

local count, nextEvent, total, actions = 0, nil, 0, {}
function ns.RefreshEventBubble()
  local state = ns.CommunityState()
  local guild = state and ns.CasualStore()
  count, nextEvent, total, actions = 0, nil, 0, {}
  if guild and state.eventBubble ~= false then
    local now = ns.Now()
    for _, event in pairs(guild.guildEvents) do
      if event.status == 'scheduled' and event.starts > now then
        count = count + 1
        if not nextEvent or event.starts < nextEvent.starts then nextEvent = event end
      end
    end
    actions = ns.GetBubbleActions(guild, state)
    for _, group in pairs(actions) do total = total + #group end
  end
  for _, entry in ipairs({{eventBadge,count},{actionBadge,total}}) do
    local badge,n=entry[1],entry[2]
    badge.text:SetText(n>99 and "99+" or tostring(n))
    badge:SetWidth(math.max(17,badge.text:GetStringWidth()+8))
    badge:SetShown(n>0)
  end
  local visible = count > 0 or total > 0
  local changed = visible ~= bubble:IsShown()
  if visible and changed then PlaceBubble() end
  bubble:SetShown(visible)
  if changed then ns.UpdateMinimapButton() end
end

local function OpenEvents()
  local state = ns.UI.state.activities
  state.eventDate, state.eventType, state.mine = nil, nil, nil
  SlashCmdList.EPUGUILD('calendar')
end

local function OpenView(view)
  ns.UI:CloseDetails()
  ns.UI.search:SetText('')
  ns.UI:SetView(view)
end

function ns.FillBubbleActions(det)
  local guild, state = ns.G(), ns.CommunityState()
  if not guild or not state then return end
  local current = ns.GetBubbleActions(guild, state)
  det:Reset(nil, nil, 'Needs your attention', ns.me)
  det:Buttons({{'Open Events', OpenEvents}})
  local empty = true
  for _, section in ipairs(sections) do
    local kind, group = section[1], current[section[1]]
    if #group > 0 then
      empty = false
      det:Text(section[2]..' ('..#group..')')
      if kind == 'inbox' then
        det:Buttons({{'Open Discord tools', function() OpenView('officer') end}})
      elseif kind == 'fulfill' then
        det:Buttons({{'Open bank fulfillment', function() ns.UI:OpenDetails('fulfillment', 'all') end}})
      else
        for i = 1, math.min(#group, 20) do
          local entry = group[i]
          if kind == 'places' then
            det:Text(guild.guildEvents[entry.event].title..' · '..entry.who)
            det:Buttons({{'Review signup', function() ns.UI:OpenDetails('event', entry.event) end}})
          elseif kind == 'invites' then
            det:Text(guild.inviteRequests[entry].who)
            det:Buttons({{'Open invite', function() ns.UI:OpenDetails('guildinvite', entry) end}})
          else
            local request = guild.requests[entry]
            det:Text(ns.RequestName(request, true)..' · '..request.who)
            det:Buttons({{'Open request', function() ns.UI:OpenDetails('request', entry) end}})
          end
        end
        if #group > 20 then
          local view = kind == 'places' and 'activities' or kind == 'invites' and 'invites' or 'requests'
          det:Buttons({{'Open full list', function()
            if view == 'activities' then OpenEvents()
            else
              if view == 'requests' then
                local filters = ns.UI.state.requests
                filters.filter, filters.mine, filters.crafts = 'open', false, false
              end
              OpenView(view)
            end
          end}})
        end
      end
    end
  end
  if empty then det:Text('Nothing needs your attention right now.') end
end

bubble:SetScript('OnEnter', function(self)
  GameTooltip:SetOwner(self, 'ANCHOR_LEFT')
  GameTooltip:SetText(count == 1 and '1 upcoming guild event' or (count..' upcoming guild events'))
  if nextEvent then
    GameTooltip:AddLine(nextEvent.title:gsub('[%c|]', ''), 1, 1, 1, true)
    GameTooltip:AddLine(date('%a, %b %d at %I:%M %p', nextEvent.starts)..' (local)', 1, 1, 1)
  end
  for _, section in ipairs(sections) do
    local n = #(actions[section[1]] or {})
    if n > 0 then GameTooltip:AddLine(section[2]..': '..n, 1, 0.75, 0.35) end
  end
  GameTooltip:AddLine((total > 0 and 'Click for actions. ' or 'Click to open Events. ')..'Right-click for settings. Drag to move.', 0.85, 0.85, 0.85, true)
  GameTooltip:Show()
end)
bubble:SetScript('OnLeave', function() GameTooltip:Hide() end)
bubble:SetScript('OnClick', function(self, button)
  if self.draggedAt and GetTime() - self.draggedAt < 0.25 then return end
  if button == 'RightButton' then
    SlashCmdList.EPUGUILD('notifications')
    ns.UI:OpenDetails('noticeform', 'all')
  elseif total > 0 then
    ns.UI:Show()
    ns.UI:OpenDetails('bubbleactions', 'all')
  else
    OpenEvents()
  end
end)
bubble:SetScript('OnDragStart', function(self)
  GameTooltip:Hide()
  self.moving = true
  self:StartMoving()
end)
local function StopDrag(self)
  if not self.moving then return end
  self.moving = nil
  self:StopMovingOrSizing()
  self:SetUserPlaced(false)
  self.draggedAt = GetTime()
  local state = ns.CommunityState()
  local x, y = self:GetCenter()
  if state and x and y then
    state.eventBubbleX = math.max(0, math.min(1, x / UIParent:GetWidth()))
    state.eventBubbleY = math.max(0, math.min(1, y / UIParent:GetHeight()))
  end
  ns.UpdateMinimapButton()
end
bubble:SetScript('OnDragStop', StopDrag)
bubble:SetScript('OnHide', StopDrag)
ns.On('PLAYER_LOGIN', ns.RefreshEventBubble)
ns.On('PLAYER_GUILD_UPDATE', function()
  if not bubble.moving then PlaceBubble() end
  ns.RefreshEventBubble()
end)
ns.On('DISPLAY_SIZE_CHANGED', function() if bubble:IsShown() and not bubble.moving then PlaceBubble() end end)
