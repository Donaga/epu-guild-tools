-- Short-lived guild activities, voluntary helpers and reusable starter kits.
local ADDON, ns = ...
local DAY, MAX_DURATION = 86400, 4*3600
ns.CASUAL_FIELDS={"activityPosts","activityReplies","helpers","kitTemplates"}
ns.HELPER_ROLES={t="Tank",h="Healer",d="DPS",c="Crafter",m="Mentor"}
local function Text(s,n,required)
  return type(s)=="string" and #s<=n and (not required or s:find("%S")~=nil)
end
local function Clean(s,n) return tostring(s or ""):gsub("[%z\001-\031]",""):sub(1,n):match("^%s*(.-)%s*$") end
local function Count(t) local n=0 for _ in pairs(t) do n=n+1 end return n end
local function Int(n,lo,hi) return type(n)=="number" and n==n and n>=lo and n<=hi and n%1==0 end
local function Roles(s)
  local out=""
  for _,r in ipairs({"t","h","d","c","m"}) do if tostring(s or ""):find(r,1,true) then out=out..r end end
  return out
end
function ns.CasualStore()
  local g=ns.PlanningStore()
  if g then for _,f in ipairs(ns.CASUAL_FIELDS) do g[f]=g[f] or {} end end
  return g
end
local function Revision(r)
  return type(r)=="table" and ns.StampOK(r.t) and r.t<=ns.Now()+300
end
local function Fresh(r)
  return Revision(r) and r.t>=ns.Now()-30*DAY
end
local function OwnedID(id,who) return type(id)=="string" and #id<=180 and id:sub(1,#who+1)==who.."\031" end
local function Window(r)
  return ns.StampOK(r.created) and r.created<=ns.Now()+300 and Int(r.expires,r.created,r.created+MAX_DURATION) and r.t>=r.created
end
local function ValidPost(id,r)
  return Fresh(r) and Text(r.who,80,true) and ns.Member(r.who) and OwnedID(id,r.who)
    and (r.kind=="help" or r.kind=="dungeon") and Text(r.title,80,true) and Text(r.note,320) and Text(r.zone,80)
    and Int(r.minLevel,1,100) and Int(r.maxLevel,r.minLevel,100) and Int(r.slots,2,40)
    and (r.status=="open" or r.status=="closed") and Text(r.by,80,true) and ns.Member(r.by) and Window(r)
end
local function ValidReply(id,r)
  return Fresh(r) and Text(r.post,180,true) and Text(r.who,80,true) and ns.Member(r.who)
    and id==r.post.."\030"..r.who and (r.role=="t" or r.role=="h" or r.role=="d")
    and (r.state=="ready" or r.state=="tentative" or r.state=="withdrawn") and Text(r.note,160)
end
local function ValidHelper(id,r)
  return Fresh(r) and id==r.who and Text(r.who,80,true) and ns.Member(r.who)
    and Text(r.roles,5) and Roles(r.roles)==r.roles and Text(r.note,160) and type(r.off)=="boolean" and Window(r)
end
local function ValidKit(id,r)
  if not Revision(r) or not Text(r.by,80,true) or not Text(id,180,true) or not Text(r.title,80,true) or not Text(r.note,500)
    or type(r.removed)~="boolean" or type(r.lines)~="table" or #r.lines<1 or #r.lines>12 or Count(r.lines)~=#r.lines then return false end
  for _,line in ipairs(r.lines) do
    if type(line)~="table" or not ns.PositiveInt(line.item) or not ns.PositiveInt(line.qty,1000)
      or (line.mode~="bank" and line.mode~="craft") then return false end
  end
  return true
end
local validators={activityPosts=ValidPost,activityReplies=ValidReply,helpers=ValidHelper,kitTemplates=ValidKit}
local caps={activityPosts=2000,activityReplies=10000,helpers=1000,kitTemplates=500}
local fields={activityPosts={"who","kind","title","note","zone","minLevel","maxLevel","slots","status","created","expires","t","by"},
  activityReplies={"post","who","role","state","note","t"},helpers={"who","roles","note","off","created","expires","t"},
  kitTemplates={"title","note","removed","lines","t","by"}}
local function Copy(f,r)
  local out={}
  for _,key in ipairs(fields[f]) do out[key]=r[key] end
  if f=="kitTemplates" then
    out.lines={}
    for _,l in ipairs(r.lines) do out.lines[#out.lines+1]={item=l.item,qty=l.qty,mode=l.mode} end
  end
  return out
end
local pending={}
local function Publish(field,id,r)
  local key=ns.GuildKey()
  r.t=ns.NextVersion(r.t)
  pending[key]=pending[key] or {}
  pending[key][field]=pending[key][field] or {}; pending[key][field][id]=r
  ns.Debounce("casualPublish:"..key,1,function()
    local b=pending[key]; pending[key]=nil
    if b and ns.GuildKey()==key then ns.Send("D",b) end
  end)
  ns.Changed()
end
local idSequence=0
local function ID(store)
  local id
  repeat idSequence=idSequence+1; id=ns.me.."\031"..ns.Now()..":"..math.random(100000,999999)..":"..idSequence until not store[id]
  return id
end
function ns.ActiveActivity(r)
  return r and r.status=="open" and r.expires>ns.Now() and ns.Member(r.who)~=nil
end
function ns.SaveActivity(kind,opts,id)
  local g=ns.CasualStore(); if not g or (kind~="help" and kind~="dungeon") then return end
  opts=opts or {}; local cur=id and g.activityPosts[id]
  if id and (not cur or cur.who~=ns.me or not ns.ActiveActivity(cur)) then return ns.Print("Only the author can edit an open activity.") end
  if not cur then
    if Count(g.activityPosts)>=caps.activityPosts then return ns.Print("Activity history is full. Older records will expire automatically.") end
    local n=0
    for _,r in pairs(g.activityPosts) do if r.who==ns.me and r.kind==kind and ns.ActiveActivity(r) then n=n+1 end end
    if n>=3 then return ns.Print("Close an existing post first; you can have three open posts of each kind.") end
  end
  local duration=tonumber(opts.minutes) or 60
  if not Int(duration,15,240) then return ns.Print("Choose an expiry between 15 and 240 minutes.") end
  local now=ns.Now()
  local r={who=ns.me,kind=cur and cur.kind or kind,title=Clean(opts.title,80),note=Clean(opts.note,320),zone=Clean(opts.zone,80),
    minLevel=tonumber(opts.minLevel) or 1,maxLevel=tonumber(opts.maxLevel) or 60,slots=tonumber(opts.slots) or 5,
    status="open",created=cur and cur.created or now,expires=cur and cur.expires or now+duration*60,t=cur and cur.t or now,by=ns.me}
  id=id or ID(g.activityPosts)
  if not ValidPost(id,r) then return ns.Print("Enter a title, levels from 1 to 100, and 2 to 40 planned players.") end
  g.activityPosts[id]=r; Publish("activityPosts",id,r)
  if not cur then ns.RespondActivity(id,((ns.ProfileOf(ns.me) or {}).roles or ""):match("[thd]") or "d","ready","") end
  return id
end
function ns.CloseActivity(id)
  local g=ns.CasualStore(); local r=g and g.activityPosts[id]
  if not r or (r.who~=ns.me and not ns.IsTrusted(ns.me)) then return false end
  r.status="closed"; r.by=ns.me; Publish("activityPosts",id,r); return true
end
function ns.RespondActivity(id,role,state,note)
  local g=ns.CasualStore(); local post=g and g.activityPosts[id]
  if not post or not ns.ActiveActivity(post) then return ns.Print("That activity has closed or expired.") end
  local key=id.."\030"..ns.me; local cur=g.activityReplies[key]
  local r={post=id,who=ns.me,role=role,state=state,note=Clean(note,160),t=cur and cur.t or ns.Now()}
  if not ValidReply(key,r) then return end
  g.activityReplies[key]=r; Publish("activityReplies",key,r); return true
end
function ns.ActivityReplies(id)
  local g=ns.CasualStore(); local rows={}
  for _,r in pairs(g and g.activityReplies or {}) do
    if r.post==id and r.state~="withdrawn" and ns.Member(r.who) then rows[#rows+1]=r end
  end
  table.sort(rows,function(a,b) if a.state~=b.state then return a.state=="ready" end return a.who<b.who end)
  return rows
end
function ns.ActivityCounts(id)
  local out={ready=0,tentative=0,t=0,h=0,d=0}
  for _,r in ipairs(ns.ActivityReplies(id)) do
    out[r.state]=out[r.state]+1
    if r.state=="ready" then out[r.role]=out[r.role]+1 end
  end
  return out
end
function ns.SetHelperAvailability(roles,note,minutes,off)
  local g=ns.CasualStore(); if not g then return end
  minutes=tonumber(minutes) or 60
  if not Int(minutes,15,240) then return ns.Print("Choose an expiry between 15 and 240 minutes.") end
  roles=Roles(roles)
  if roles=="" and not off then return ns.Print("Choose at least one way you can help.") end
  local cur=g.helpers[ns.me]; local now=ns.Now()
  local r={who=ns.me,roles=roles,note=Clean(note,160),off=off==true,created=now,expires=now+minutes*60,t=cur and cur.t or now}
  g.helpers[ns.me]=r; Publish("helpers",ns.me,r); return true
end
function ns.ActiveHelper(r)
  local member=r and ns.roster[r.who]
  return r and not r.off and r.expires>ns.Now() and member and member.online
end
function ns.HelperRoleText(roles)
  local out={}
  for r in (roles or ""):gmatch(".") do if ns.HELPER_ROLES[r] then out[#out+1]=ns.HELPER_ROLES[r] end end
  return table.concat(out," / ")
end

local examples={
  ["example:bags"]={title="Starter bags",note="Editable example: four Linen Bags. Adjust items for your guild.",lines={{item=4238,qty=4,mode="bank"}}},
  ["example:firstaid"]={title="First Aid supplies",note="Editable example: a bundle of Linen Cloth.",lines={{item=2589,qty=20,mode="bank"}}},
  ["example:tailoring"]={title="Tailoring supplies",note="Editable example: cloth and thread. Adjust quantities for your guild.",lines={{item=2589,qty=40,mode="bank"},{item=2320,qty=20,mode="bank"}}},
}
function ns.KitTemplates()
  local g=ns.CasualStore(); local out={}
  for id,r in pairs(examples) do out[id]=r end
  for id,r in pairs(g and g.kitTemplates or {}) do if not r.removed then out[id]=r end end
  return out
end
function ns.SaveKitTemplate(id,title,note,lines,removed)
  local g=ns.CasualStore(); if not g or not ns.IsTrusted(ns.me) then return end
  if id and not g.kitTemplates[id] then id=nil end -- examples are copied, never edited globally
  if not id and Count(g.kitTemplates)>=caps.kitTemplates then return ns.Print("The guild template limit has been reached.") end
  id=id or ID(g.kitTemplates); local cur=g.kitTemplates[id]
  local r={title=Clean(title,80),note=Clean(note,500),lines=lines,removed=removed==true,by=ns.me,t=cur and cur.t or ns.Now()}
  if not ValidKit(id,r) then return ns.Print("Add 1 to 12 items, with whole quantities from 1 to 1000 and bank or craft fulfilment.") end
  g.kitTemplates[id]=Copy("kitTemplates",r); Publish("kitTemplates",id,g.kitTemplates[id]); return id
end
function ns.LaunchStarterKit(id,target,assignments,revision)
  local g=ns.CasualStore(); local kit=ns.KitTemplates()[id]
  if not g or not ns.IsTrusted(ns.me) or not kit then return end
  target=ns.Member(target)
  if not target then return ns.Print("Choose a current guild member for this kit.") end
  if revision and revision~=ns.Fingerprint(kit) then return ns.Print("This template changed. Reopen the kit preview before creating requests.") end
  for _,p in pairs(g.projects) do
    if p.kit==id and p.recipient==target and p.status=="active" then return ns.Print("This member already has an active project for this kit. Review it before creating another.") end
  end
  assignments=assignments or {}
  local plan={}
  for i,l in ipairs(kit.lines) do
    local crafter
    if l.mode~='craft' and not ns.CanBankRequest(l.item) then return ns.Print('The bank has not stocked '..ns.ItemName(l.item,true)..'. Use a craft task or stock this item before applying the kit.') end
    if l.mode=="craft" then
      crafter=ns.Member(assignments[i]); local e=ns.RecipeFor("item:"..l.item); local capable=false
      for _,c in ipairs(e and e.crafters or {}) do if c.who==crafter then capable=true end end
      if not crafter or not capable then return ns.Print("Choose a guild crafter who has shared the recipe for "..ns.ItemName(l.item,true)..".") end
    end
    plan[#plan+1]={item=l.item,qty=l.qty,mode=l.mode,crafter=crafter}
  end
  local pid=ns.CreateProject(kit.title.." - "..target,kit.note)
  if not pid then return end
  local p=g.projects[pid]; p.kit=id; p.recipient=target
  for _,l in ipairs(plan) do
    local rid
    if l.mode=="craft" then rid=ns.NewCraftRequest("item:"..l.item,l.crafter,l.qty,"bank","Starter kit: "..kit.title,target)
    else rid=ns.NewRequest(l.item,l.qty,"Starter kit: "..kit.title,nil,target) end
    local r=g.requests[rid]; r.project=pid
    ns.Send("D",{req={[rid]=r}})
    p.tasks[#p.tasks+1]={rid=rid,key="item:"..l.item,qty=l.qty,crafter=l.crafter or "Guild bank",to=target}
  end
  p.t=ns.NextVersion(p.t); p.by=ns.me; ns.Send("D",{projects={[pid]=p}})
  ns.SetChecklist(target,"starterkit",false,"Starter kit project: "..p.title)
  ns.Changed(); return pid
end

function ns.MergeCasual(sender,b,trusted)
  local g=ns.CasualStore(); if not g then return false end
  local changed=false
  for _,f in ipairs(ns.CASUAL_FIELDS) do
    local src=b[f]
    if type(src)=="table" and validators[f] then
      local size=Count(g[f])
      for id,r in pairs(src) do
        if type(id)=="string" and validators[f](id,r) then
          local cur=g[f][id]
          local allowed=(f=="kitTemplates" and trusted) or (f~="kitTemplates" and (trusted or r.who==sender))
          if f=="activityPosts" and cur then allowed=allowed and r.who==cur.who and r.kind==cur.kind and r.created==cur.created end
          if f=="activityPosts" and cur and cur.status=="closed" and r.status~="closed" then allowed=false end
          if allowed and (cur or size<caps[f]) and ns.Newer(r,cur,"t") then
            g[f][id]=Copy(f,r); if not cur then size=size+1 end; changed=true
          end
        end
      end
    end
  end
  if changed then ns.Changed() end
  return changed
end
function ns.PruneCasual()
  local g=ns.CasualStore(); if not g then return end
  for _,f in ipairs(ns.CASUAL_FIELDS) do
    if f~="kitTemplates" then
      for id,r in pairs(g[f]) do if not Fresh(r) then g[f][id]=nil end end
    end
  end
end
ns.On("PLAYER_LOGIN",function()
  ns.PruneCasual()
  local function OwnRecent()
    local g=ns.CasualStore(); if not g then return end
    local b={}; local any=false
    for _,f in ipairs({"activityPosts","activityReplies","helpers"}) do
      for id,r in pairs(g[f]) do
        if r.who==ns.me and r.t>=ns.Now()-MAX_DURATION then
          b[f]=b[f] or {}; b[f][id]=r; any=true
        end
      end
    end
    if ns.OwnCommunityRecords and ns.OwnCommunityRecords(b) then any=true end
    return any and b or nil
  end
  -- Authors can answer a new member even when no officer is online. Forward
  -- only our own recent records, including withdrawals, never another member's.
  local hello=ns.comm.H
  ns.comm.H=function(sender,d,channel)
    if hello then hello(sender,d,channel) end
    if sender==ns.me or not ns.Member(sender) or channel~="GUILD" then return end
    if not OwnRecent() then return end
    ns.Debounce("casualOwnHello",10+math.random()*10,function()
      local b=OwnRecent()
      if b then for _,part in ipairs(ns.SplitDelta(b)) do ns.Send("D",part) end end
    end)
  end
  local function ExpiryTick()
    if ns.UI and ns.UI:IsShown() and ns.UI.view=="activities" then ns.UI:Refresh() end
    C_Timer.After(30,ExpiryTick)
  end
  C_Timer.After(30,ExpiryTick)
end)
ns.On("PLAYER_LOGOUT",ns.PruneCasual)
