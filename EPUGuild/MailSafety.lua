-- Verify actual attachment quantities rather than trusting a split request.
local ADDON,ns=...
local expected={}
local checking=false
local preparing
local review, originalRecipient
local function CountOK(n) return not (issecretvalue and issecretvalue(n)) and ns.PositiveInt(n) end
local function Attachment(slot)
  local link=GetSendMailItemLink and GetSendMailItemLink(slot)
  if not link or not GetSendMailItem then return end
  local _,_,_,count=GetSendMailItem(slot)
  return ns.ItemID(link),count
end

local function UpdateReview()
  if not review then return end
  if not originalRecipient or not ns.MailboxOpen() or not SendMailFrame:IsShown() then review:Hide(); return end
  local groups, order, pending = {}, {}, false
  for slot=1,(ATTACHMENTS_MAX_SEND or 12) do
    local id,count=Attachment(slot)
    local planned=expected[slot]
    if id and CountOK(count) and not (planned and (planned.settling or planned.id~=id or planned.n~=count)) then
      if not groups[id] then
        groups[id]={count=0,stacks=0}
        order[#order+1]=id
      end
      local group=groups[id]
      group.count,group.stacks=group.count+count,group.stacks+1
    elseif id or (HasSendMailItem and HasSendMailItem(slot)) then
      pending=true
    end
  end
  local recipient=SendMailNameEditBox and SendMailNameEditBox:GetText() or ""
  review.recipient:SetText(recipient~="" and "To "..recipient or "Choose a recipient")
  local lines={}
  for _,id in ipairs(order) do
    local group=groups[id]
    lines[#lines+1]=group.count.." "..ns.ItemName(id,true).." · "..group.stacks..(group.stacks==1 and " stack" or " stacks")
  end
  if #lines==0 then lines[1]=pending and "Waiting for attachment quantities" or "No items attached" end
  review.fullItems=table.concat(lines,"\n")
  review.items:SetText(#lines>2 and (lines[1].."\n+"..(#lines-1).." more items (hover to review)") or review.fullItems)
  local warning = recipient~=originalRecipient and "Recipient changed. Check before sending."
    or preparing and "Preparing attachments. Wait before sending."
    or pending and "Some attachment quantities are unverified."
  review.warning:SetText(warning or "")
  review.warning:SetShown(not not warning)
  local height=45+math.max(14,review.items:GetStringHeight() or 14)+(warning and 17 or 0)
  review:SetHeight(height)
  review:ClearAllPoints()
  local top, screen = MailFrame:GetTop(), UIParent:GetTop()
  if top and screen and top*MailFrame:GetEffectiveScale()+(height+8)*review:GetEffectiveScale()
      <=screen*UIParent:GetEffectiveScale() then
    review:SetPoint("BOTTOMLEFT",MailFrame,"TOPLEFT",0,6)
  else
    review:SetPoint("TOPLEFT",MailFrame,"TOPRIGHT",8,0)
  end
  review:Show()
end

function ns.BeginBankMailReview(recipient)
  if not review then
    review=CreateFrame("Frame","EPUGuildBankMailReview",SendMailFrame)
    review:SetWidth(268)
    review:SetFrameStrata("DIALOG")
    review:SetClampedToScreen(true)
    review:EnableMouse(true)
    local bg=review:CreateTexture(nil,"BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.08,0.10,0.14,0.98)
    local marker=review:CreateTexture(nil,"ARTWORK")
    marker:SetPoint("TOPLEFT"); marker:SetPoint("BOTTOMLEFT"); marker:SetWidth(2)
    marker:SetColorTexture(0.95,0.76,0.31,1)
    local colors=ns.InterfaceColors
    local title=ns.InterfaceFont(review,11,colors.gold)
    title:SetPoint("TOPLEFT",10,-6); title:SetText("Bank mail review")
    review.recipient=ns.InterfaceFont(review,12,colors.white)
    review.recipient:SetPoint("TOPLEFT",10,-21); review.recipient:SetPoint("TOPRIGHT",-10,-21)
    review.items=ns.InterfaceFont(review,11,colors.text)
    review.items:SetPoint("TOPLEFT",10,-39); review.items:SetPoint("TOPRIGHT",-10,-39)
    review.items:SetWordWrap(true)
    if review.items.SetMaxLines then review.items:SetMaxLines(2) end
    review.warning=ns.InterfaceFont(review,11,colors.gold)
    review.warning:SetPoint("BOTTOMLEFT",10,5); review.warning:SetPoint("BOTTOMRIGHT",-10,5)
    review:SetScript("OnEnter",function(self)
      GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
      GameTooltip:SetText(self.recipient:GetText(),1,1,1,1,true)
      GameTooltip:AddLine(self.fullItems,0.9,0.9,0.9,true)
      if self.warning:IsShown() then GameTooltip:AddLine(self.warning:GetText(),1,0.8,0.35,true) end
      GameTooltip:Show()
    end)
    review:SetScript("OnLeave",function() GameTooltip:Hide() end)
    if SendMailNameEditBox then SendMailNameEditBox:HookScript("OnTextChanged",UpdateReview) end
    SendMailFrame:HookScript("OnShow",UpdateReview)
    SendMailFrame:HookScript("OnHide",function() review:Hide() end)
  end
  originalRecipient=recipient
  UpdateReview()
end
local function Verify()
  if checking then return end
  if not ns.MailboxOpen() then wipe(expected); return end
  checking=true
  for slot,e in pairs(expected) do
    local id,n=Attachment(slot)
    if not e.settling and id and CountOK(n) then
      if id~=e.id or n~=e.n then
        expected[slot]=nil
        -- Clear the expectation first: detaching can fire this event again.
        if ClearCursor then ClearCursor() end
        ClickSendMailItemButton(slot)
        if ClearCursor then ClearCursor() end
        e.failed=true
        ns.Print("Stopped mail preparation: the game attached a different item or quantity. That attachment was removed.")
      else
        e.verified=true
      end
    elseif not e.settling and not id and e.verified then expected[slot]=nil
    end
  end
  checking=false
end
local function CheckAttachments()
  Verify()
  UpdateReview()
end
ns.On("MAIL_SEND_INFO_UPDATE",CheckAttachments)
local function Reset()
  preparing=nil
  wipe(expected)
  originalRecipient=nil
  if review then review:Hide() end
end
ns.On("MAIL_CLOSED",Reset)
ns.On("MAIL_SEND_SUCCESS",Reset)

function ns.MailIsEmpty()
  if preparing then
    ns.Print("EPU is still preparing the attachments. Wait for the draft to finish.")
    return false
  end
  for i=1,(ATTACHMENTS_MAX_SEND or 12) do
    if (HasSendMailItem and HasSendMailItem(i)) or (GetSendMailItemLink and GetSendMailItemLink(i)) then
      ns.Print("This mail already has attachments. Send or remove them before preparing a different request.")
      return false
    end
  end
  if (GetSendMailMoney and GetSendMailMoney()>0) or (GetSendMailCOD and GetSendMailCOD()>0) then
    ns.Print("This mail already contains gold or COD. Clear it before preparing a request.")
    return false
  end
  return true
end

local function ReadSlot(bag,slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local info=C_Container.GetContainerItemInfo(bag,slot)
    if info then return info.itemID or ns.ItemID(info.hyperlink),info.stackCount,info.isLocked,info.isBound end
  elseif GetContainerItemInfo then
    local _,n,locked,_,_,_,link,_,_,id,bound=GetContainerItemInfo(bag,slot)
    return id or ns.ItemID(link),n,locked,bound
  end
end

function ns.PreviewMailItem(item, qty, slots)
  local attached = 0
  for _, bag in ipairs(ns.BagList()) do
    for slot = 1, ((C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots)(bag) or 0) do
      if attached >= qty or slots == 0 then return attached, slots end
      local id, count, locked, bound = ReadSlot(bag, slot)
      if id == item and not locked and not bound then
        if not CountOK(count) then return attached, slots end
        attached = attached + math.min(count, qty - attached)
        slots = slots - 1
      end
    end
  end
  return attached, slots
end

function ns.AttachExactMailItem(item,qty,index,usedSlots)
  if not ns.PositiveInt(qty) then return 0,index end
  if not GetSendMailItem or not GetSendMailItemLink then
    ns.Print("Mail item information is unavailable. Reopen the mailbox before preparing a request.")
    return 0,index
  end
  local need=qty
  for _,bag in ipairs(ns.BagList()) do
    for slot=1,((C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots)(bag) or 0) do
      if need<=0 or index>(ATTACHMENTS_MAX_SEND or 12) then return qty-need,index end
      local id,n,locked,bound=ReadSlot(bag,slot)
      local slotKey=bag..":"..slot
      if id==item and not locked and not bound and not (usedSlots and usedSlots[slotKey]) then
        if not CountOK(n) then
          ns.Print("Item quantities are still loading. Wait a moment and try preparing the mail again.")
          return qty-need,index
        end
        if (HasSendMailItem and HasSendMailItem(index)) or GetSendMailItemLink(index) then return qty-need,index end
        local take=math.min(n,need)
        local operation=(take<n) and ((C_Container and C_Container.SplitContainerItem) or SplitContainerItem)
          or ((C_Container and C_Container.PickupContainerItem) or PickupContainerItem)
        if not operation then return qty-need,index end
        local ok
        if take<n then ok=pcall(operation,bag,slot,take) else ok=pcall(operation,bag,slot) end
        local kind,cursorID=GetCursorInfo()
        if not ok or kind~="item" or cursorID~=item then
          if ClearCursor then ClearCursor() end
          ns.Print("The item could not be split or picked up. Wait for it to unlock and try again.")
          return qty-need,index
        end
        local e={id=item,n=take,settling=usedSlots~=nil}; expected[index]=e
        ClickSendMailItemButton(index)
        if usedSlots then
          usedSlots[slotKey]=true
          return take,index+1,e
        end
        Verify()
        if e.failed then return qty-need,index end
        -- Recheck after client mail updates; do not repeat the pickup on a delay.
        C_Timer.After(0.1,CheckAttachments)
        need=need-take; index=index+1
      end
    end
  end
  return qty-need,index
end

-- Wait for each attachment to settle before picking up the next stack.
function ns.AttachBankMailStacks(item, qty, recipient, finished)
  local draft={count=0,index=1,attached={},usedSlots={}}
  preparing=draft
  local function Finish()
    preparing=nil
    UpdateReview()
    finished(draft.count)
  end
  local function SameDraft()
    if not ns.MailboxOpen() or not SendMailFrame:IsShown()
      or SendMailNameEditBox:GetText()~=recipient or GetCursorInfo() then return false end
    for slot=1,(ATTACHMENTS_MAX_SEND or 12) do
      local id,count=Attachment(slot)
      local previous=draft.attached[slot]
      if previous then
        if id~=item or not CountOK(count) or count~=previous then return false end
      elseif (HasSendMailItem and HasSendMailItem(slot)) or id then return false end
    end
    return true
  end
  local function NextStack()
    if not SameDraft() then
      preparing=nil
      UpdateReview()
      return ns.Print("Stopped preparing bank mail because the draft or cursor changed. Review the attachments before sending.")
    end
    local remaining=qty-draft.count
    if remaining<=0 or draft.index>(ATTACHMENTS_MAX_SEND or 12) then return Finish() end
    local available=ns.BankSortMailLimit(item)
    if available<=0 then return Finish() end
    local slot=draft.index
    local take,nextIndex,entry=ns.AttachExactMailItem(item,math.min(remaining,available),slot,draft.usedSlots)
    if not entry then return Finish() end
    local function Confirm(attempt)
      if preparing~=draft then return end
      if expected[slot]~=entry then preparing=nil; UpdateReview(); return end
      local id,count=Attachment(slot)
      if id==item and CountOK(count) and count==take then
        entry.settling=nil
        entry.verified=true
        draft.attached[slot]=take
        draft.count=draft.count+take
        draft.index=nextIndex
        return NextStack()
      end
      if attempt<4 then
        C_Timer.After(0.2,function() Confirm(attempt+1) end)
        return
      end
      entry.settling=nil
      Verify()
      if not entry.failed then
        ns.Print("Couldn't verify the last attachment. Clear any unverified attachment before sending.")
      end
      Finish()
    end
    C_Timer.After(0.2,function() Confirm(1) end)
  end
  NextStack()
end
