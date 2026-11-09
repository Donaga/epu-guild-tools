-- Guild events and personal preferences. Quest positions/progress live elsewhere
-- in session memory; neither the event store nor the companion saves that data.
local ADDON, ns = ...
local DAY=86400
ns.EVENT_TYPES={dungeon="Dungeon",leveling="Leveling",quest="Quest / elite help",fishing="Fishing",profession="Profession",farming="Farming",other="Other"}
ns.EVENT_TYPE_ORDER={"dungeon","leveling","quest","fishing","profession","farming","other"}
ns.EVENT_ROLES={t="Tank",h="Healer",d="DPS",g="Helper",c="Crafter",m="Mentor"}
for _,f in ipairs({"guildEvents","eventResponses"}) do ns.CASUAL_FIELDS[#ns.CASUAL_FIELDS+1]=f end
local baselines={}
function ns.CommunityState()
  if not ns.cdb then return end
  local key=ns.GuildKey(); if not key then return end
  ns.cdb.community=ns.cdb.community or {}
  local s=ns.cdb.community[key]
  if not s then s={}; ns.cdb.community[key]=s end
  s.categories=s.categories or {}; s.followed=s.followed or {}; s.muted=s.muted or {}
  s.inbox=s.inbox or {}; s.seen=s.seen or {}; s.selectedQuests=s.selectedQuests or {}
  if not baselines[key] then baselines[key]=s.lastSeen or ns.Now() end
  return s,baselines[key]
end
function ns.PersonalToken(kind,id) return kind.."\031"..tostring(id) end
function ns.FollowUpdates(kind,id,on)
  local s=ns.CommunityState(); if not s then return end
  s.followed[ns.PersonalToken(kind,id)]=on and true or nil; ns.Changed()
end
function ns.MuteUpdates(kind,id,on)
  local s=ns.CommunityState(); if not s then return end
  s.muted[ns.PersonalToken(kind,id)]=on and true or nil; ns.Changed()
end
local function Count(t) local n=0 for _ in pairs(t) do n=n+1 end return n end
local function Int(n,lo,hi) return type(n)=="number" and n==n and n>=lo and n<=hi and n%1==0 end
local function Text(s,n,required) return type(s)=="string" and #s<=n and (not required or s:find("%S")) end
local function Clean(s,n) return tostring(s or ""):gsub("[%z\001-\031]",""):sub(1,n):match("^%s*(.-)%s*$") end
local function Revision(r) return type(r)=="table" and ns.StampOK(r.t) and r.t<=ns.Now()+300 and r.t>=ns.Now()-30*DAY end
local function ValidEvent(id,r)
  return Revision(r) and Text(r.who,80,true) and Text(r.by,80,true)
    and #id<=180 and id:sub(1,#r.who+1)==r.who.."\031" and Text(r.title,80,true) and Text(r.note,500) and Text(r.zone,80)
    and ns.StampOK(r.created) and r.created<=r.t and Int(r.starts,r.created-300,r.t+28*DAY)
    and Int(r.ends,r.starts+15*60,r.starts+8*3600) and Int(r.slots,2,40)
    and (r.status=="scheduled" or r.status=="cancelled")
    and (r.kind==nil or ns.EVENT_TYPES[r.kind]~=nil)
    and (r.minLevel==nil or Int(r.minLevel,1,100))
    and (r.maxLevel==nil or Int(r.maxLevel,r.minLevel or 1,100))
end
local function ValidResponse(id,r)
  return Revision(r) and Text(r.event,180,true) and Text(r.who,80,true) and ns.Member(r.who)
    and id==r.event.."\030"..r.who and (r.state=="going" or r.state=="tentative" or r.state=="declined")
    and ns.EVENT_ROLES[r.role]~=nil and Text(r.note,160)
end
local serial=0
local pending={}
local function Publish(f,id,r)
  r.t=ns.NextVersion(r.t)
  local key=ns.GuildKey(); pending[key]=pending[key] or {}
  pending[key][f]=pending[key][f] or {}; pending[key][f][id]=r
  ns.Debounce("eventPublish:"..key,1,function()
    local b=pending[key]; pending[key]=nil
    if b and ns.GuildKey()==key then ns.Send("D",b) end
  end)
  ns.Changed()
end
function ns.SaveGuildEvent(opts,id)
  local g=ns.CasualStore(); if not g then return end
  opts=opts or {}; local cur=id and g.guildEvents[id]
  if id and (not cur or cur.who~=ns.me or cur.status~="scheduled" or cur.ends<ns.Now()) then return ns.Print("Only the organiser can edit an active event.") end
  if not cur then
    local n=0 for _,r in pairs(g.guildEvents) do if r.who==ns.me and r.status=="scheduled" and r.ends>ns.Now() then n=n+1 end end
    if n>=10 or Count(g.guildEvents)>=500 then return ns.Print("Close an existing event first; you can have ten upcoming events.") end
    serial=serial+1; id=ns.me.."\031E:"..ns.Now()..":"..math.random(100000,999999)..":"..serial
  end
  local starts=tonumber(opts.starts); local minutes=tonumber(opts.minutes)
  if not Int(starts,ns.Now()+60,ns.Now()+28*DAY) or not Int(minutes,15,480) then return ns.Print("Choose a future start within 28 days, lasting 15–480 minutes.") end
  local r={who=ns.me,by=ns.me,title=Clean(opts.title,80),note=Clean(opts.note,500),zone=Clean(opts.zone,80),
    starts=starts,ends=starts+minutes*60,slots=tonumber(opts.slots) or 5,status="scheduled",created=cur and cur.created or ns.Now(),t=cur and cur.t or ns.Now(),
    kind=opts.kind or (cur and cur.kind) or "other",minLevel=tonumber(opts.minLevel) or (cur and cur.minLevel) or 1,maxLevel=tonumber(opts.maxLevel) or (cur and cur.maxLevel) or 60}
  if not ValidEvent(id,r) then return ns.Print("Choose an activity type, title, 2–40 players and a suggested level range from 1 to 100 (minimum no higher than maximum).") end
  g.guildEvents[id]=r; Publish("guildEvents",id,r)
  ns.FollowUpdates("event",id,true)
  if not cur then ns.RespondGuildEvent(id,"going",r.kind=="dungeon" and (((ns.ProfileOf(ns.me) or {}).roles or "d"):match("[thd]") or "d") or "g","") end
  return id
end
function ns.CancelGuildEvent(id)
  local g=ns.CasualStore(); local r=g and g.guildEvents[id]
  if not r or (r.who~=ns.me and not ns.IsTrusted(ns.me)) then return false end
  r.status="cancelled"; r.by=ns.me; Publish("guildEvents",id,r); return true
end
function ns.RespondGuildEvent(id,state,role,note)
  local g=ns.CasualStore(); local e=g and g.guildEvents[id]
  if not e or e.status~="scheduled" or e.ends<=ns.Now() then return ns.Print("That event is cancelled or has ended.") end
  if not ns.Member(e.who) then return ns.Print("The organiser has left the guild. Ask an officer to cancel or replace this event.") end
  local key=id.."\030"..ns.me; local cur=g.eventResponses[key]
  local r={who=ns.me,event=id,state=state,role=role,note=Clean(note,160),t=cur and cur.t or ns.Now()}
  if not ValidResponse(key,r) then return end
  g.eventResponses[key]=r; Publish("eventResponses",key,r)
  ns.FollowUpdates("event",id,state~="declined"); return true
end
function ns.AddonEventResponses(id)
  local g=ns.CasualStore(); local out={}
  for _,r in pairs(g and g.eventResponses or {}) do if r.event==id and ns.Member(r.who) then out[#out+1]=r end end
  table.sort(out,function(a,b) return a.who<b.who end); return out
end
function ns.EventResponses(id)
  local out=ns.AddonEventResponses(id)
  return ns.WithCalendarResponses and ns.WithCalendarResponses(id,out) or out
end
function ns.EventCounts(id)
  local n={going=0,tentative=0,declined=0,t=0,h=0,d=0,g=0,c=0,m=0}
  for _,r in ipairs(ns.EventResponses(id)) do n[r.state]=n[r.state]+1; if r.state=="going" then n[r.role]=n[r.role]+1 end end
  return n
end
function ns.OwnCommunityRecords(b)
  local g=ns.CasualStore(); if not g then return false end
  local any=false
  for id,e in pairs(g.guildEvents) do
    if e.who==ns.me and e.ends>ns.Now() then b.guildEvents=b.guildEvents or {}; b.guildEvents[id]=e; any=true end
  end
  for id,r in pairs(g.eventResponses) do
    local e=g.guildEvents[r.event]
    if r.who==ns.me and e and e.ends>ns.Now() then b.eventResponses=b.eventResponses or {}; b.eventResponses[id]=r; any=true end
  end
  return any
end
function ns.MergeCommunity(sender,b,trusted)
  local g=ns.CasualStore(); if not g then return false end
  local changed=false
  local definitions={guildEvents={valid=ValidEvent,cap=500,keys={"who","by","title","note","zone","starts","ends","slots","status","created","t","kind","minLevel","maxLevel"}},
    eventResponses={valid=ValidResponse,cap=5000,keys={"who","event","state","role","note","t"}}}
  for f,d in pairs(definitions) do
    if type(b[f])=="table" then
      local size=Count(g[f])
      for id,r in pairs(b[f]) do
        if type(id)=="string" and d.valid(id,r) and (trusted or r.who==sender) then
          local cur=g[f][id]; local allowed=true
          if cur and f=="guildEvents" then
            allowed=r.who==cur.who and r.created==cur.created and (cur.status~="cancelled" or r.status=="cancelled")
          end
          if allowed and (cur or size<d.cap) and ns.Newer(r,cur,"t") then
            local copy={} for _,k in ipairs(d.keys) do copy[k]=r[k] end
            g[f][id]=copy; if not cur then size=size+1 end; changed=true
          end
        end
      end
    end
  end
  if changed then ns.Changed() end
  return changed
end

-- Local wall-clock input is round-tripped to reject invalid dates and DST gaps.
function ns.ParseEventLocal(value)
  local y,m,d,h,min=tostring(value or ""):match("^(%d%d%d%d)%-(%d%d)%-(%d%d) (%d%d):(%d%d)$")
  if not y then return end
  y,m,d,h,min=tonumber(y),tonumber(m),tonumber(d),tonumber(h),tonumber(min)
  if not Int(y,2000,2100) or not Int(m,1,12) or not Int(d,1,31) or not Int(h,0,23) or not Int(min,0,59) then return end
  local ok,epoch=pcall(time,{year=y,month=m,day=d,hour=h,min=min,sec=0})
  if ok and epoch and date("%Y-%m-%d %H:%M",epoch)==value then return epoch end
end
-- Convert calendar wall fields to an epoch-like number without the PC timezone.
local function Civil(c)
  local y,m,d=c.year,c.month,c.monthDay
  if not Int(y,2000,2100) or not Int(m,1,12) or not Int(d,1,31) or not Int(c.hour,0,23) or not Int(c.minute,0,59) then return end
  y=y-(m<=2 and 1 or 0)
  local era=math.floor(y/400); local yo=y-era*400
  local doy=math.floor((153*(m+(m>2 and -3 or 9))+2)/5)+d-1
  local days=era*146097+yo*365+math.floor(yo/4)-math.floor(yo/100)+doy-719468
  return days*DAY+c.hour*3600+c.minute*60
end
function ns.ServerClockOffset()
  if not C_DateAndTime or not C_DateAndTime.GetCurrentCalendarTime then return end
  local ok,c=pcall(C_DateAndTime.GetCurrentCalendarTime)
  local wall=ok and type(c)=="table" and Civil(c)
  if not wall then return end
  -- API has minute precision. Realm timezone offsets use whole minutes.
  local offset=wall-math.floor(ns.Now()/60)*60
  if math.abs(offset)<=14*3600 then return offset end
end
function ns.EventTimes(epoch)
  local localTime=date("%Y-%m-%d %H:%M",epoch)
  local offset=ns.ServerClockOffset()
  return localTime,offset and date("!%Y-%m-%d %H:%M",epoch+offset) or "Unavailable"
end

function ns.CatchupEntries()
  local g=ns.CasualStore(); local s,since=ns.CommunityState(); local out={}
  if not g or not s then return out end
  local function Add(id,title,text,kind,key,at) out[#out+1]={id=id,title=title,text=text,kind=kind,key=key,at=at or 0} end
  for id,n in pairs((ns.GuildStore() or {}).news or {}) do
    if not n.removed and ((n.u or n.t or 0)>since or not (ns.cdb.newsRead or {})[id]) then Add("news:"..id,"News: "..(n.title or "Guild announcement"),n.text or "","news",id,n.u or n.t) end
  end
  for id,p in pairs(g.projects) do
    if p.status=="active" then local done,total=ns.ProjectProgress(p); Add("project:"..id,p.title,done.." / "..total.." delivered","project",id,p.t) end
  end
  for id,e in pairs(g.guildEvents) do
    if e.ends>ns.Now() and e.status=="scheduled" then local l,server=ns.EventTimes(e.starts); Add("event:"..id,e.title,"Local: "..l.." · Server: "..server,"event",id,e.starts) end
  end
  for id,r in pairs(g.requests) do
    if (r.who==ns.me or r.to==ns.me or r.crafter==ns.me) and (r.u or 0)>since then Add("request:"..id,ns.RequestName(r,true),"Request: "..r.status.." · "..ns.Remaining(r).." remaining","request",id,r.u) end
  end
  for token,n in pairs(s.inbox) do Add("digest:"..token,n.title,n.text,"digest",token,n.at) end
  local priority={digest=1,news=2,request=3,event=4,project=5}
  table.sort(out,function(a,b)
    if priority[a.kind]~=priority[b.kind] then return priority[a.kind]<priority[b.kind] end
    if a.at~=b.at then if a.kind=="event" then return a.at<b.at end return a.at>b.at end
    return a.id<b.id
  end)
  while #out>100 do table.remove(out) end
  return out
end
function ns.MarkCatchupReviewed()
  local s=ns.CommunityState(); if not s then return end
  baselines[ns.GuildKey()]=ns.Now(); s.lastSeen=ns.Now(); wipe(s.inbox); ns.Changed()
end
ns.On("PLAYER_LOGIN",function() ns.CommunityState() end)
ns.On("PLAYER_LOGOUT",function()
  for key in pairs(baselines) do if ns.cdb.community and ns.cdb.community[key] then ns.cdb.community[key].lastSeen=ns.Now() end end
end)
