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
local countLabel = bubble:CreateFontString(nil, 'OVERLAY', 'NumberFontNormal')
countLabel:SetPoint('BOTTOMRIGHT', 1, 0)

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

local count, nextEvent = 0, nil
function ns.RefreshEventBubble()
  local state = ns.CommunityState()
  local guild = state and ns.CasualStore()
  count, nextEvent = 0, nil
  if guild and state.eventBubble ~= false then
    local now = ns.Now()
    for _, event in pairs(guild.guildEvents) do
      if event.status == 'scheduled' and event.starts > now then
        count = count + 1
        if not nextEvent or event.starts < nextEvent.starts then nextEvent = event end
      end
    end
  end
  countLabel:SetText(count > 99 and '99+' or tostring(count))
  if count > 0 and not bubble:IsShown() then PlaceBubble() end
  bubble:SetShown(count > 0)
end

bubble:SetScript('OnEnter', function(self)
  GameTooltip:SetOwner(self, 'ANCHOR_LEFT')
  GameTooltip:SetText(count == 1 and '1 upcoming guild event' or (count..' upcoming guild events'))
  if nextEvent then
    GameTooltip:AddLine(nextEvent.title:gsub('[%c|]', ''), 1, 1, 1, true)
    GameTooltip:AddLine(date('%a, %b %d at %I:%M %p', nextEvent.starts)..' (local)', 1, 1, 1)
  end
  GameTooltip:AddLine('Click to open Events. Right-click for settings. Drag to move.', 0.85, 0.85, 0.85, true)
  GameTooltip:Show()
end)
bubble:SetScript('OnLeave', function() GameTooltip:Hide() end)
bubble:SetScript('OnClick', function(self, button)
  if self.draggedAt and GetTime() - self.draggedAt < 0.25 then return end
  if button == 'RightButton' then
    SlashCmdList.EPUGUILD('notifications')
    ns.UI:OpenDetails('noticeform', 'all')
  else
    local state = ns.UI.state.activities
    state.eventDate, state.eventType, state.mine = nil, nil, nil
    SlashCmdList.EPUGUILD('calendar')
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
end
bubble:SetScript('OnDragStop', StopDrag)
bubble:SetScript('OnHide', StopDrag)
ns.On('PLAYER_LOGIN', ns.RefreshEventBubble)
ns.On('PLAYER_GUILD_UPDATE', function()
  if not bubble.moving then PlaceBubble() end
  ns.RefreshEventBubble()
end)
ns.On('DISPLAY_SIZE_CHANGED', function() if bubble:IsShown() and not bubble.moving then PlaceBubble() end end)
