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
local function GroupItems(rows)
  local items, order, ids = {}, {}, {}
  for _, row in ipairs(rows) do
    local item = row.r.item
    if not items[item] then order[#order+1] = item; items[item] = 0 end
    items[item] = items[item] + ns.Remaining(row.r)
    ids[row.id] = true
  end
  return items, order, ids
end

function ns.MemberMailPreview(rows)
  local items, order = GroupItems(rows)
  local lines, slots = {}, ATTACHMENTS_MAX_SEND or 12
  for _, item in ipairs(order) do
    local count
    count, slots = ns.PreviewMailItem(item, items[item], slots)
    lines[#lines+1] = {item=item, ready=count, remaining=items[item]}
  end
  return lines
end

function ns.BankFulfillmentQueue()
  local queue = {ready={}, pull={}, restock={}, review={}}
  local recipients = {}
  for id, request in pairs((ns.G() or {}).requests or {}) do
    if request.item and not request.crafter and ns.IsActiveRequest(request) then
      if request.status == "approved" then
        local who = request.to or request.who
        if ns.Member(who) then recipients[who] = true else queue.review[#queue.review+1] = id end
      else
        queue.review[#queue.review+1] = id
      end
    end
  end
  for who in pairs(recipients) do
    local rows = ns.MemberMailPlan(who)
    local group = {who=who, rows=rows, preview=ns.MemberMailPreview(rows), short=0}
    local ready = false
    for _, entry in ipairs(group.preview) do if entry.ready > 0 then ready = true; break end end
    local bankAvailable = false
    for _, row in ipairs(rows) do
      local short = ns.RequestRestock(row.id)
      group.short = group.short + short
      if short < ns.Remaining(row.r) then bankAvailable = true end
    end
    local category = ready and queue.ready or bankAvailable and queue.pull or queue.restock
    category[#category+1] = group
  end
  for _, groups in ipairs({queue.ready, queue.pull, queue.restock}) do
    table.sort(groups, function(a,b) return a.who < b.who end)
  end
  table.sort(queue.review)
  return queue
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
  local items,order,ids=GroupItems(rows)
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
