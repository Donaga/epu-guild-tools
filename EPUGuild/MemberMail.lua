-- Combine approved bank requests for one recipient without expanding quantities.
local ADDON, ns = ...
function ns.MemberMailPlan(target)
  local g=ns.G(); local rows={}
  target=ns.Member(target)
  if not g or not target then return rows end
  for id,r in pairs(g.requests) do
    if not r.crafter and r.item and r.status=="approved" and (r.to or r.who)==target and ns.Remaining(r)>0 then
      rows[#rows+1]={id=id,r=r}
    end
  end
  table.sort(rows,function(a,b) if a.r.t~=b.r.t then return (a.r.t or 0)<(b.r.t or 0) end return a.id<b.id end)
  return rows
end
function ns.MailMemberRequests(target)
  if not ns.IsTrusted(ns.me) then return ns.Print("Only officers and trusted bank characters can prepare bank request mail.") end
  target=ns.Member(target)
  if not target then return ns.Print("Choose a current guild member.") end
  if not ns.MailboxOpen() then return ns.Print("Open a mailbox first. Requested items must be in this character's bags.") end
  local rows=ns.MemberMailPlan(target)
  if #rows==0 then return ns.Print("No approved bank requests remain for this recipient.") end
  if not ns.MailIsEmpty() then return end
  if MailFrameTab2 and not SendMailFrame:IsShown() then MailFrameTab2:Click() end
  if SendMailNameEditBox then SendMailNameEditBox:SetText(target) end
  if SendMailSubjectEditBox then SendMailSubjectEditBox:SetText("Guild bank: "..#rows.." requests") end
  if ClearCursor then ClearCursor() end
  local items,order,ids={},{},{}
  for _,row in ipairs(rows) do
    ids[row.id]=true
    if not items[row.r.item] then order[#order+1]=row.r.item; items[row.r.item]=0 end
    items[row.r.item]=items[row.r.item]+ns.Remaining(row.r)
  end
  ns.mailRequestID=nil; ns.mailRequestIDs=ids
  local index,total,missing=1,0,0
  for _,item in ipairs(order) do
    local n,nextIndex=ns.AttachExactMailItem(item,items[item],index)
    index=nextIndex; total=total+n; missing=missing+items[item]-n
  end
  if total==0 then
    ns.mailRequestIDs=nil
    return ns.Print("No requested items could be attached. Check unlocked, mailable items in your bags.")
  end
  ns.Print("Prepared "..total.." item(s) for "..target.." across "..#rows.." approved request(s). Review the draft, then click Send."
    ..(missing>0 and (" "..missing.." item(s) are still missing or exceed the mail attachment limit; those quantities stay open.") or ""))
  return total
end
