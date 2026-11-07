-- Guild crafting projects and a configurable new-member checklist.
local ADDON, ns = ...
local DEFAULTS = {
  rules={title="Read the guild rules",text="Ask an officer where the current guild rules are posted."},
  addon={title="Install EPU Guild Tools",text="Open /epu and check that guild data has synced."},
  identity={title="Confirm your main and alts",text="Log onto each character with the addon; use /epu main to choose your main."},
  professions={title="Share your professions",text="Open your profession windows to share recipes with the guild."},
  discord={title="Link Discord",text="Use /link in Discord and ask an officer to approve it.",officer=true},
  mentor={title="Meet your mentor",text="An officer can assign a mentor and record starter supplies here.",officer=true},
}
function ns.PlanningStore()
  local g=ns.G(); if not g then return end
  g.projects=g.projects or {}; g.onboarding=g.onboarding or {}; g.onboardingSteps=g.onboardingSteps or {}
  return g
end
local function ID(prefix) return prefix..ns.me..":"..ns.Now()..":"..math.random(100000,999999) end
local function Publish(field,id,r)
  r.t=ns.NextVersion(r.t); r.by=ns.me
  ns.Send("D",{[field]={[id]=r}}); ns.Changed()
end
function ns.CreateProject(title,note)
  local g=ns.PlanningStore()
  if not g or not ns.IsTrusted(ns.me) then return end
  if type(title)~="string" or title:match("^%s*$") then return ns.Print("Enter a title for the project.") end
  local id=ID("P")
  g.projects[id]={title=title:sub(1,80),note=(note or ""):sub(1,500),tasks={},status="active"}
  Publish("projects",id,g.projects[id]); return id
end
function ns.AddProjectTask(id,key,crafter,qty,to,mats)
  local g=ns.PlanningStore(); local p=g and g.projects[id]
  qty=tonumber(qty); crafter=ns.Member(crafter); to=ns.Member(to or ns.me)
  if not p or p.status~="active" or not ns.IsTrusted(ns.me) then return end
  if not ns.PositiveInt(qty,1000) or not crafter or not to then return ns.Print("Enter a guild crafter, recipient and whole quantity from 1 to 1000.") end
  if #p.tasks>=30 then return ns.Print("A project can contain up to 30 craft tasks.") end
  local e=ns.RecipeFor(key); local capable=false
  for _,c in ipairs(e and e.crafters or {}) do if c.who==crafter then capable=true end end
  if not capable then return ns.Print("Choose a shared recipe and a guildmate who knows it.") end
  local rid=ns.NewCraftRequest(key,crafter,qty,mats or "bank","Project: "..p.title,to)
  if not rid then return end
  local r=g.requests[rid]; r.project=id
  ns.Send("D",{req={[rid]=r}})
  p.tasks[#p.tasks+1]={rid=rid,key=key,qty=qty,crafter=crafter,to=to}
  Publish("projects",id,p); return rid
end
function ns.ProjectProgress(p)
  local g=ns.PlanningStore(); local done,total=0,0
  for _,task in ipairs(p.tasks) do
    local r=g.requests[task.rid]
    total=total+task.qty
    done=done+math.min(task.qty,(r and r.status=="filled") and task.qty or (r and r.delivered or 0))
  end
  return done,total
end
function ns.ProjectMaterials(p)
  local g=ns.PlanningStore(); local need={}
  for _,task in ipairs(p.tasks) do
    local r=g.requests[task.rid]
    if r and r.status~="cancelled" and r.status~="rejected" and r.status~="filled" then
      for _,m in ipairs(ns.MatsFor(task.key)) do need[m.id]=(need[m.id] or 0)+m.n*ns.Remaining(r) end
    end
  end
  return need
end
function ns.StockProject(id)
  local g=ns.PlanningStore(); local p=g and g.projects[id]
  if not p or not ns.IsTrusted(ns.me) then return end
  for item,qty in pairs(ns.ProjectMaterials(p)) do
    local old=ns.NeedEntry(g.needs.list[item])
    if qty>old then ns.SetNeed(item,qty) end
  end
end
function ns.ArchiveProject(id)
  local g=ns.PlanningStore(); local p=g and g.projects[id]
  if not p or not ns.IsTrusted(ns.me) then return end
  for _,task in ipairs(p.tasks) do
    if ns.IsActiveRequest(g.requests[task.rid]) then return ns.Print("Finish or cancel this project's craft requests before archiving it.") end
  end
  p.status="archived"; Publish("projects",id,p)
end

function ns.OnboardingSteps()
  local g=ns.PlanningStore(); local out={}
  for id,d in pairs(DEFAULTS) do out[id]=d end
  for id,d in pairs(g and g.onboardingSteps or {}) do out[id]=d end
  local rows={}
  for id,d in pairs(out) do if not d.removed then rows[#rows+1]={id=id,title=d.title,text=d.text,officer=d.officer} end end
  table.sort(rows,function(a,b) return a.id<b.id end); return rows
end
function ns.SetOnboardingStep(id,title,text,officer,removed)
  local g=ns.PlanningStore()
  if not g or not ns.IsTrusted(ns.me) or type(id)~="string" or #id>80 or type(title)~="string" or title=="" then return end
  local cur=g.onboardingSteps[id]
  local r={t=cur and cur.t,title=title:sub(1,80),text=(text or ""):sub(1,500),officer=officer==true,removed=removed==true}
  g.onboardingSteps[id]=r; Publish("onboardingSteps",id,r)
end
local function Step(id)
  for _,s in ipairs(ns.OnboardingSteps()) do if s.id==id then return s end end
end
function ns.Checklist(name)
  local g=ns.PlanningStore(); local out={}
  for _,s in ipairs(ns.OnboardingSteps()) do
    local r=g.onboarding[name.."\031"..s.id]
    local done=r and r.done or false
    if s.id=="addon" and (name==ns.me or g.altVerified[name]) then done=true end
    if s.id=="identity" and g.altVerified[name] then done=true end
    out[#out+1]={id=s.id,title=s.title,text=s.text,officer=s.officer,done=done,note=r and r.note or ""}
  end
  return out
end
function ns.SetChecklist(name,id,done,note)
  local g=ns.PlanningStore(); local s=Step(id)
  name=ns.Member(name)
  if not g or not s or not name or (not ns.IsTrusted(ns.me) and (name~=ns.me or s.officer)) then return false end
  local key=name.."\031"..id; local cur=g.onboarding[key]
  local r={who=name,step=id,done=done==true,note=(note or ""):sub(1,300),t=cur and cur.t}
  g.onboarding[key]=r; Publish("onboarding",key,r); return true
end
function ns.MergePlanning(sender,b,trusted)
  local g=ns.PlanningStore(); local changed=false
  local function merge(field,valid)
    for id,r in pairs(type(b[field])=="table" and b[field] or {}) do
      if type(id)=="string" and #id<=180 and type(r)=="table" and ns.StampOK(r.t) and valid(id,r)
        and ns.Newer(r,g[field][id],"t") then g[field][id]=r; changed=true end
    end
  end
  merge("projects",function(_,r)
    if not trusted or type(r.title)~="string" or #r.title>80 or type(r.tasks)~="table" or #r.tasks>30
      or (r.status~="active" and r.status~="archived") then return false end
    for _,task in ipairs(r.tasks) do
      if type(task)~="table" or type(task.rid)~="string" or type(task.key)~="string" or not ns.PositiveInt(task.qty,1000)
        or type(task.crafter)~="string" or type(task.to)~="string" then return false end
    end
    return true
  end)
  merge("onboardingSteps",function(_,r) return trusted and type(r.title)=="string" and #r.title<=80 and type(r.text)=="string" and #r.text<=500 end)
  merge("onboarding",function(id,r)
    local s=type(r.step)=="string" and Step(r.step)
    return s and type(r.who)=="string" and ns.Member(r.who) and id==r.who.."\031"..r.step
      and (trusted or (sender==r.who and not s.officer)) and type(r.done)=="boolean" and type(r.note)=="string" and #r.note<=300
  end)
  if changed then ns.Changed() end; return changed
end
function ns.DeltaPlanning(b,since)
  local g=ns.PlanningStore()
  for _,f in ipairs({"projects","onboarding","onboardingSteps"}) do
    for id,r in pairs(g[f]) do if (r.t or 0)>since then b[f]=b[f] or {}; b[f][id]=r end end
  end
end
