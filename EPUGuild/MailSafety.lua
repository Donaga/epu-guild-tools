-- Verify actual attachment quantities rather than trusting a split request.
local ADDON,ns=...
local expected={}
local checking=false
local function CountOK(n) return not (issecretvalue and issecretvalue(n)) and ns.PositiveInt(n) end
local function Attachment(slot)
  local link=GetSendMailItemLink and GetSendMailItemLink(slot)
  if not link or not GetSendMailItem then return end
  local _,_,_,count=GetSendMailItem(slot)
  return ns.ItemID(link),count
end
local function Verify()
  if checking then return end
  if not ns.MailboxOpen() then wipe(expected); return end
  checking=true
  for slot,e in pairs(expected) do
    local id,n=Attachment(slot)
    if id and CountOK(n) then
      if id~=e.id or n~=e.n then
        expected[slot]=nil
        -- Clear the expectation first: detaching can fire this event again.
        if ClearCursor then ClearCursor() end
        ClickSendMailItemButton(slot)
        if ClearCursor then ClearCursor() end
        e.failed=true
        ns.Print("Stopped mail preparation: the game attached a different quantity. That attachment was removed. Split the requested amount manually and try again.")
      else
        e.verified=true
      end
    elseif not id and e.verified then expected[slot]=nil
    end
  end
  checking=false
end
ns.On("MAIL_SEND_INFO_UPDATE",Verify)
ns.On("MAIL_CLOSED",function() wipe(expected) end)
ns.On("MAIL_SEND_SUCCESS",function() wipe(expected) end)

function ns.MailIsEmpty()
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

function ns.AttachExactMailItem(item,qty,index)
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
      if id==item and not locked and not bound then
        if not CountOK(n) then
          ns.Print("Item quantities are still loading. Wait a moment and try preparing the mail again.")
          return qty-need,index
        end
        if GetSendMailItemLink and GetSendMailItemLink(index) then return qty-need,index end
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
        local e={id=item,n=take}; expected[index]=e
        ClickSendMailItemButton(index)
        Verify()
        if e.failed then return qty-need,index end
        -- Recheck after client mail updates; do not repeat the pickup on a delay.
        C_Timer.After(0.1,Verify)
        need=need-take; index=index+1
      end
    end
  end
  return qty-need,index
end
