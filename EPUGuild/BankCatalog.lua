-- Requestable items come from actual bank inventory/history, never wish lists
-- or the game's complete item database. History carries no stock quantity.
local ADDON,ns=...
function ns.BankHistory(snapshot,items,holder)
  local seen={}
  for id,value in pairs((snapshot or {}).seen or {}) do if ns.PositiveInt(id) and value==true then seen[id]=true end end
  for id,n in pairs((snapshot or {}).items or {}) do if ns.PositiveInt(id) and type(n)=='number' and n>0 then seen[id]=true end end
  for id,n in pairs(items or {}) do if ns.PositiveInt(id) and type(n)=='number' and n>0 then seen[id]=true end end
  if holder then for _,d in pairs((ns.G() or {}).donations or {}) do
    if d.to==holder and ns.PositiveInt(d.item) and (tonumber(d.n) or 0)>0 then seen[d.item]=true end
  end end
  return seen
end
function ns.BankCatalog()
  local catalog={}; local g=ns.G(); if not g then return catalog end
  for holder,s in pairs(g.bank) do for id in pairs(ns.BankHistory(s,nil,holder)) do catalog[id]=true end end
  -- Donation records can predate the new persistent history field.
  for _,d in pairs(g.donations) do
    if (g.bank[d.to] or d.to==ns.GB_KEY) and ns.PositiveInt(d.item) and (tonumber(d.n) or 0)>0 then catalog[d.item]=true end
  end
  return catalog
end
function ns.CanBankRequest(id)
  return ns.PositiveInt(id) and ns.BankCatalog()[id]==true
end
function ns.BankRequestStock(id)
  local held,asked=ns.BankCount(id),0
  for _,r in pairs((ns.G() or {}).requests or {}) do
    if ns.IsActiveRequest(r) then
      if not r.crafter and r.item==id then asked=asked+ns.Remaining(r)
      elseif r.crafter and r.status=='approved' and r.mats=='bank' then
        for _,m in ipairs(ns.MatsFor(r.key)) do if m.id==id then asked=asked+m.n*ns.Remaining(r) end end
      end
    end
  end
  return held,asked,math.max(0,held-asked)
end
function ns.BankRequestAvailability(id)
  local held,asked,free=ns.BankRequestStock(id)
  return held..' in bank · '..free..' available'..(asked>0 and (' · '..asked..' already requested') or '')..(held==0 and ' · Out of stock; requests wait for restock' or '')
end
function ns.RequestRestock(rid)
  local g=ns.G(); local r=g and g.requests[rid]
  if not r or r.crafter or not ns.IsActiveRequest(r) then return 0 end
  local remaining=ns.Remaining(r); local pool=ns.BankCount(r.item); local queue={}
  for id,v in pairs(g.requests) do
    if ns.IsActiveRequest(v) and not v.crafter and v.item==r.item then queue[#queue+1]={id=id,r=v}
    elseif v.crafter and v.status=='approved' and v.mats=='bank' then
      for _,m in ipairs(ns.MatsFor(v.key)) do if m.id==r.item then pool=math.max(0,pool-m.n*ns.Remaining(v)) end end
    end
  end
  table.sort(queue,function(a,b)
    local x,y=a.r.status=='approved',b.r.status=='approved'
    if x~=y then return x end
    if (a.r.t or 0)~=(b.r.t or 0) then return (a.r.t or 0)<(b.r.t or 0) end
    return a.id<b.id
  end)
  for _,entry in ipairs(queue) do
    local need=ns.Remaining(entry.r)
    if entry.id==rid then return math.max(0,remaining-pool) end
    pool=math.max(0,pool-need)
  end
  return remaining
end
