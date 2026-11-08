-- Validation, deterministic records, verified identities and delivery accounting.
local ADDON, ns = ...

function ns.PositiveInt(n, max)
  return type(n) == "number" and n == n and n > 0 and n <= (max or 1000000) and n == math.floor(n)
end
function ns.StampOK(n)
  return type(n) == "number" and n == n and n >= 0 and n <= ns.Now() + 86400
end

-- Canonical ordering makes concurrent, equal-stamp edits converge regardless of arrival order.
function ns.Canonical(v)
  if type(v) == "string" then return "s" .. #v .. ":" .. v end
  if type(v) ~= "table" then return type(v) .. ":" .. tostring(v) .. ";" end
  local keys, out = {}, {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a,b) return type(a) .. tostring(a) < type(b) .. tostring(b) end)
  for _, k in ipairs(keys) do
    local key,value=ns.Canonical(k),ns.Canonical(v[k])
    out[#out + 1] = #key .. ":" .. key .. #value .. ":" .. value
  end
  return "{" .. table.concat(out, ";") .. "}"
end
function ns.Newer(a, b, field)
  if not b then return true end
  local av, bv = tonumber(a[field]) or 0, tonumber(b[field]) or 0
  return av > bv or (av == bv and ns.Canonical(a) > ns.Canonical(b))
end
function ns.Fingerprint(v)
  local s=ns.Canonical(v); local h=0
  for i=1,#s do h=(h*131+s:byte(i))%4294967296 end
  return tostring(h)
end
function ns.Remaining(r)
  return math.max(0, (tonumber(r.qty) or 0) - (tonumber(r.delivered) or 0))
end

local STATES = {pending=true, open=true, approved=true, filled=true, rejected=true, cancelled=true}
function ns.ValidRequest(r)
  return type(r) == "table" and ns.StampOK(r.u) and type(r.who) == "string" and ns.Member(r.who) ~= nil
    and (ns.PositiveInt(r.item) or (type(r.spell) == "string" and #r.spell <= 160))
    and ns.PositiveInt(r.qty) and STATES[r.status] == true
    and (r.to == nil or (type(r.to) == "string" and ns.Member(r.to) ~= nil))
    and (r.crafter == nil or (type(r.crafter) == "string" and ns.Member(r.crafter) ~= nil))
    and (r.delivered == nil or (type(r.delivered) == "number" and r.delivered >= 0 and r.delivered <= r.qty and r.delivered == math.floor(r.delivered)))
    and (r.note == nil or (type(r.note) == "string" and #r.note <= 320))
end
function ns.MemberMayUpdate(sender, cur, r)
  if r.who ~= sender then return false end
  if not cur then return (r.status == "pending" or r.status == "open") and not r.delivered end
  if cur.who ~= sender then return false end
  for _, f in ipairs({"who", "item", "spell", "crafter", "key", "mats", "t", "project", "delivered", "deliveries"}) do
    if ns.Canonical(cur[f]) ~= ns.Canonical(r[f]) then return false end
  end
  if r.status == "cancelled" then return ns.IsActiveRequest(cur) and r.qty == cur.qty and r.to == cur.to end
  return (cur.status == "pending" or cur.status == "open") and (r.status == "pending" or r.status == "open")
end

-- Per-item revisions and deletion tombstones preserve unrelated officer edits.
local function NeedState(g)
  if not g.needs.entries then
    g.needs.entries = {}
    for id, value in pairs(g.needs.list) do g.needs.entries[id] = {v=g.needs.v, by="", value=value} end
  end
  return g.needs.entries
end
function ns.NeedsSignature()
  local g = ns.G()
  return g and ns.Fingerprint(NeedState(g)) or ""
end
function ns.MergeNeeds(sender, nd)
  local g = ns.G()
  if ns.Unconf(g, "needs", "list") then g.needs = {v=0,list={}} end
  local entries = NeedState(g)
  local src = nd.entries
  if type(src) ~= "table" then
    src = {}
    for id in pairs(entries) do src[id] = {v=nd.v,by=sender,value=nd.list[id]} end
    for id, value in pairs(nd.list) do src[id] = {v=nd.v,by=sender,value=value} end
  end
  for id, e in pairs(src) do
    if ns.PositiveInt(id) and type(e) == "table" and ns.StampOK(e.v) and type(e.by) == "string" then
      local q = e.value and ns.NeedEntry(e.value)
      if (e.value == nil or ns.PositiveInt(q)) and ns.Newer(e, entries[id], "v") then
        entries[id] = {v=e.v,by=e.by,value=e.value}
        g.needs.list[id] = e.value
        g.needs.v = math.max(g.needs.v, e.v)
      end
    end
  end
  g.needs.v = math.max(g.needs.v, nd.v)
end
local send = ns.Send
ns.Send = function(kind, b, channel, target)
  if kind == "D" and b and b.needs and ns.IsTrusted(ns.me) then
    local g = ns.G()
    local entries = NeedState(g)
    local ids = {}
    for id in pairs(entries) do ids[id] = true end
    for id in pairs(g.needs.list) do ids[id] = true end
    for id in pairs(ids) do
      local e = entries[id]
      if not e or ns.Canonical(e.value) ~= ns.Canonical(g.needs.list[id]) then
        entries[id] = {v=g.needs.v,by=ns.me,value=g.needs.list[id]}
      end
    end
    if not b.sync then
      -- Coalesce rapid edits instead of queueing a growing full snapshot for each item.
      ns.Debounce("publishNeeds", 0.5, function() send("D", {needs=g.needs}, channel, target) end)
      local other,any={},false
      for k,v in pairs(b) do if k~="needs" then other[k]=v; any=true end end
      if not any then return end
      b=other
    end
  end
  return send(kind,b,channel,target)
end

function ns.VerifyCharacter(id)
  local g = ns.G()
  if not g then return end
  local cur = g.altVerified[ns.me]
  local chars = ns.MyChars()
  if cur and cur.id == id and ns.Canonical(cur.chars)==ns.Canonical(chars) then return end
  local proof = {id=id,chars=chars,t=ns.NextVersion(cur and cur.t)}
  g.altVerified[ns.me] = proof
  ns.Send("D", {altVerified={[ns.me]=proof}})
end

-- Only the character itself (or an officer relaying it) can publish its proof.
local merge = ns.Merge
ns.Merge = function(sender, b, catchingUp)
  if type(b) ~= "table" or not ns.Member(sender) then return false end
  local trusted, clean = ns.IsTrusted(sender), {}
  for k,v in pairs(b) do clean[k]=v end
  if type(b.needs)=="table" and (not ns.StampOK(b.needs.v) or type(b.needs.list)~="table") then clean.needs=nil end
  local function records(field,valid)
    if type(b[field])~="table" then clean[field]=nil; return end
    clean[field]={}
    for id,r in pairs(b[field]) do
      if (type(id)=="string" or type(id)=="number") and type(r)=="table" and ns.StampOK(r.t) and valid(r) then clean[field][id]=r end
    end
  end
  records("craft",function(r)
    if type(r.profs)~="table" then return false end
    for name,n in pairs(r.profs) do if type(name)~="string" or type(n)~="number" or n<0 or n>100000 then return false end end
    return true
  end)
  records("recipes",function(r)
    if type(r.profs)~="table" then return false end
    for name,p in pairs(r.profs) do
      if type(name)~="string" or type(p)~="table" or type(p.items)~="table" or (p.spells~=nil and type(p.spells)~="table")
        or (p.diff~=nil and type(p.diff)~="table") then return false end
      for _,id in pairs(p.items) do if not ns.PositiveInt(id) then return false end end
      for _,sp in pairs(p.spells or {}) do if type(sp)~="string" or #sp>160 then return false end end
    end
    return true
  end)
  records("mats",function(r)
    if type(r.r)~="table" or #r.r>100 or #r.r%2~=0 then return false end
    for _,n in pairs(r.r) do if not ns.PositiveInt(n) then return false end end
    return r.by==nil or type(r.by)=="string"
  end)
  if type(b.req) == "table" then
    clean.req = {}
    for id,r in pairs(b.req) do
      if type(id) == "string" and #id <= 180 and ns.ValidRequest(r) then
        local g=ns.G(); local limit=tonumber(g.policy.maxOpen) or 0
        if trusted or r.crafter or g.requests[id] or limit==0 or ns.OpenCountFor(sender)<limit then clean.req[id]=r end
      end
    end
  end
  if type(b.bank) == "table" then
    clean.bank = {}
    for key,s in pairs(b.bank) do
      local ok = type(key)=="string" and type(s)=="table" and ns.StampOK(s.v) and type(s.items)=="table"
      if ok then
        for id,n in pairs(s.items) do if not ns.PositiveInt(id) or not ns.PositiveInt(n) then ok=false; break end end
      end
      if ok and (s.money==nil or (type(s.money)=="number" and s.money>=0 and s.money<=1e15)) then clean.bank[key]=s end
    end
  end
  local g, changed = ns.G(), false
  if not g then return false end
  if type(b.altVerified)=="table" then
    for who,p in pairs(b.altVerified) do
      if (trusted or sender==who) and ns.Member(who) and type(p)=="table" and type(p.id)=="string" and #p.id<=100
        and ns.StampOK(p.t) and ns.Newer(p,g.altVerified[who],"t") then
        local chars={}
        for _,n in ipairs(type(p.chars)=="table" and p.chars or {who}) do
          if type(n)=="string" and #chars<50 then chars[#chars+1]=n end
        end
        g.altVerified[who]={id=p.id,t=p.t,chars=chars}; changed=true
      end
    end
  end
  if type(b.alts)=="table" and not trusted then
    clean.alts={}
    for id,a in pairs(b.alts) do
      local ok=type(a)=="table" and type(a.chars)=="table" and ns.StampOK(a.t)
      local own=g.altVerified[sender]
      ok=ok and own and own.id==id
      for _,n in ipairs(ok and a.chars or {}) do
        if n~=sender then
          local proof=g.altVerified[n]; local consent=false
          if proof and proof.id==id then for _,c in ipairs(proof.chars or {}) do if c==sender then consent=true end end end
          if not consent then ok=false end
        end
      end
      if ok then clean.alts[id]=a end
    end
  end
  local result = merge(sender, clean, catchingUp)
  if changed then ns.RebuildAlts(); ns.Changed() end
  if ns.MergePlanning and ns.MergePlanning(sender,b,trusted) then result=true end
  if ns.MergeCasual and ns.MergeCasual(sender,b,trusted) then result=true end
  return result or changed
end

-- Deliver each unit once. Mail prepared for one request never spills into others.
function ns.AutoFillFor(recipient, items, requestID)
  local g = ns.G()
  recipient = ns.Member(recipient)
  if not g or not recipient then return end
  local sent, rows = {}, {}
  for _,it in ipairs(items) do
    if ns.PositiveInt(it[1]) and ns.PositiveInt(it[2]) then sent[it[1]]=(sent[it[1]] or 0)+it[2] end
  end
  for id,r in pairs(g.requests) do
    if (not requestID or requestID==id or (type(requestID)=="table" and requestID[id])) and r.status=="approved" and (r.to or r.who)==recipient
      and ((r.crafter==ns.me) or (not r.crafter and ns.IsTrusted(ns.me))) then rows[#rows+1]={id=id,r=r} end
  end
  table.sort(rows,function(a,b) if a.r.t~=b.r.t then return (a.r.t or 0)<(b.r.t or 0) end return a.id<b.id end)
  for _,row in ipairs(rows) do
    local r,id=row.r,row.id
    local n=math.min(sent[r.item] or 0,ns.Remaining(r))
    if n>0 then
      sent[r.item]=sent[r.item]-n
      r.delivered=(r.delivered or 0)+n
      r.deliveries=r.deliveries or {}
      r.deliveries[#r.deliveries+1]={t=ns.Now(),by=ns.me,n=n}
      -- Bounded history; the cumulative total remains even after old details expire.
      if #r.deliveries>50 then table.remove(r.deliveries,1) end
      if ns.Remaining(r)==0 then r.status="filled" end
      r.by=ns.me; r.u=ns.NextVersion(r.u)
      ns.Send("D",{req={[id]=r}}); ns.Changed()
      ns.Print("Delivered "..n.." to "..recipient.."; "..ns.Remaining(r).." remaining.")
    end
  end
end
