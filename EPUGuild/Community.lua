-- Guild events and personal preferences. Quest positions/progress live elsewhere
-- in session memory; neither the event store nor the companion saves that data.
local ADDON, ns = ...
local DAY=86400
ns.EVENT_TYPES={dungeon="Dungeon",leveling="Leveling",quest="Quest / elite help",fishing="Fishing",profession="Profession",farming="Farming",other="Other"}
ns.EVENT_TYPE_ORDER={"dungeon","leveling","quest","fishing","profession","farming","other"}
ns.EVENT_ROLES={t="Tank",h="Healer",d="DPS",g="Helper",c="Crafter",m="Mentor"}
for _,f in ipairs({"guildEvents","eventResponses","runRequests","runInterest"}) do ns.CASUAL_FIELDS[#ns.CASUAL_FIELDS+1]=f end
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
local function ValidPlaces(r)
  if r.places==nil then return r.confirmed==nil end
  if r.kind~="dungeon" or type(r.places)~="table" or type(r.confirmed)~="table" then return false end
  local p=r.places
  if not Int(p.t,0,40) or not Int(p.h,0,40) or not Int(p.d,0,40) or p.t+p.h+p.d~=r.slots then return false end
  local used={t=0,h=0,d=0}
  for who,place in pairs(r.confirmed) do
    if not Text(who,80,true) or type(place)~="table" or not ns.StampOK(place.at) then return false end
    local role=place.role
    if type(role)~="string" or used[role]==nil then return false end
    used[role]=used[role]+1
    if used[role]>p[role] then return false end
  end
  return true
end
local function ValidEvent(id,r)
  return Revision(r) and Text(r.who,80,true) and Text(r.by,80,true)
    and #id<=180 and id:sub(1,#r.who+1)==r.who.."\031" and Text(r.title,80,true) and Text(r.note,500) and Text(r.zone,80)
    and ns.StampOK(r.created) and r.created<=r.t and Int(r.starts,r.created-300,r.t+28*DAY)
    and Int(r.ends,r.starts+15*60,r.starts+8*3600) and Int(r.slots,2,40)
    and (r.status=="scheduled" or r.status=="cancelled")
    and (r.kind==nil or ns.EVENT_TYPES[r.kind]~=nil)
    and (r.dungeon==nil or (r.kind=="dungeon" and Text(r.dungeon,80,true)))
    and (r.minLevel==nil or Int(r.minLevel,1,100))
    and (r.maxLevel==nil or Int(r.maxLevel,r.minLevel or 1,100))
    and ValidPlaces(r)
end
local function ValidResponse(id,r)
  return Revision(r) and Text(r.event,180,true) and Text(r.who,80,true) and ns.Member(r.who)
    and id==r.event.."\030"..r.who and (r.state=="going" or r.state=="tentative" or r.state=="declined")
    and ns.EVENT_ROLES[r.role]~=nil and Text(r.note,160)
    and (r.via==nil or (r.via=='discord' and Text(r.bridgeBy,80,true) and ns.Member(r.bridgeBy)
      and Text(r.sourceID,80,true) and ns.PositiveInt(r.sourceRevision,1e15)))
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
  if f=='guildEvents' and ns.RefreshEventBubble then ns.RefreshEventBubble() end
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
  if r.kind == 'dungeon' then r.dungeon = opts.dungeon end
  if r.kind=="dungeon" and opts.places~=false and (opts.places or cur and cur.places) then
    r.places=opts.places or cur.places
    r.confirmed={}
    if cur then
      for who,place in pairs(cur.confirmed or {}) do
        local reply=g.eventResponses[id.."\030"..who]
        if ns.Member(who) and reply and reply.state=="going" and place.at==reply.t and place.role==reply.role then
          r.confirmed[who]=place
        end
      end
    end
  end
  if not ValidEvent(id,r) then return ns.Print("Choose an activity type, title, 2–40 players and a suggested level range from 1 to 100 (minimum no higher than maximum).") end
  g.guildEvents[id]=r; Publish("guildEvents",id,r)
  if not cur and opts.announceGuild then
    local _, realm = ns.EventTimes(r.starts)
    local when = realm ~= 'Unavailable' and (realm..' realm time') or (date('!%Y-%m-%d %H:%M',r.starts)..' UTC')
    local title = r.title:gsub('[%c|]', '')
    if ns.SendGuildChat('Guild event: '..title..' ('..when..'). Open EPU Events with /epu calendar to sign up.') == false then
      ns.Print('Event created. Guild chat announcement could not be queued.')
    end
  end
  ns.FollowUpdates("event",id,true)
  if not cur then ns.RespondGuildEvent(id,"going",r.kind=="dungeon" and (((ns.ProfileOf(ns.me) or {}).roles or "d"):match("[thd]") or "d") or "g","") end
  return id
end
function ns.RepeatGuildEventWeekly(id, occurrences)
  local g=ns.CasualStore(); local event=g and g.guildEvents[id]
  if not event or event.who~=ns.me or event.status~="scheduled" then return ns.Print("Only the organiser can repeat a scheduled event.") end
  if not Int(occurrences,1,3) then return ns.Print("Choose one to three additional weeks.") end
  local starts, upcoming={},0
  for _,r in pairs(g.guildEvents) do
    if r.who==ns.me and r.status=="scheduled" and r.ends>ns.Now() then upcoming=upcoming+1 end
  end
  local original=date("*t",event.starts)
  for week=1,occurrences do
    local nextDate=date("*t",event.starts)
    nextDate.day=nextDate.day+7*week; nextDate.isdst=nil
    local start=time(nextDate)
    local localDate=start and date("*t",start)
    if not Int(start,ns.Now()+60,ns.Now()+28*DAY) or localDate.hour~=original.hour or localDate.min~=original.min then
      return ns.Print("Choose dates within 28 days at a valid local time.")
    end
    local duplicate=false
    for _,r in pairs(g.guildEvents) do
      if r.who==ns.me and r.status=="scheduled" and r.title==event.title and r.starts==start then duplicate=true; break end
    end
    if not duplicate then starts[#starts+1]=start end
  end
  if upcoming+#starts>10 or Count(g.guildEvents)+#starts>500 then return ns.Print("Close an existing event first; you can have ten upcoming events.") end
  for _,start in ipairs(starts) do
    ns.SaveGuildEvent({title=event.title,zone=event.zone,note=event.note,starts=start,minutes=(event.ends-event.starts)/60,
      slots=event.slots,kind=event.kind,dungeon=event.dungeon,minLevel=event.minLevel,maxLevel=event.maxLevel,
      places=event.places and {t=event.places.t,h=event.places.h,d=event.places.d}})
  end
  ns.Print(#starts.." weekly event(s) created.")
  return #starts
end

function ns.EventPlaceStatus(event,reply)
  if event.places and reply.state=="going" then
    local place=event.confirmed and event.confirmed[reply.who]
    return place and place.role==reply.role and place.at==reply.t and "Confirmed" or "Waitlist"
  end
end

function ns.ConfirmEventPlace(id,who,confirm)
  local g=ns.CasualStore(); local event=g and g.guildEvents[id]
  if not event or event.who~=ns.me or event.status~="scheduled" or event.ends<=ns.Now() or not event.places then return end
  local confirmed={}
  for name,place in pairs(event.confirmed or {}) do
    local reply=g.eventResponses[id.."\030"..name]
    if ns.Member(name) and reply and ns.EventPlaceStatus(event,reply)=="Confirmed" then confirmed[name]=place end
  end
  if confirm then
    local reply=g.eventResponses[id.."\030"..who]
    if not reply or not ns.Member(who) or reply.state~="going" or event.places[reply.role]==nil then return end
    confirmed[who]={role=reply.role,at=reply.t}
  else
    confirmed[who]=nil
  end
  local before=event.confirmed
  event.confirmed=confirmed
  if not ValidPlaces(event) then event.confirmed=before; return ns.Print("That role has no open slots. Release a place or adjust the group first.") end
  Publish("guildEvents",id,event)
  return true
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
  for id,r in pairs(g.runRequests or {}) do
    if r.who==ns.me and ns.RunActive(r) then b.runRequests=b.runRequests or {}; b.runRequests[id]=r; any=true end
  end
  for id,r in pairs(g.runInterest or {}) do
    if r.who==ns.me and ns.RunActive(g.runRequests[r.request]) then b.runInterest=b.runInterest or {}; b.runInterest[id]=r; any=true end
  end
  return any
end
function ns.MergeCommunity(sender,b,trusted)
  local g=ns.CasualStore(); if not g then return false end
  local changed=false
  local definitions={guildEvents={valid=ValidEvent,cap=500,keys={"who","by","title","note","zone","starts","ends","slots","status","created","t","kind","minLevel","maxLevel","dungeon","places","confirmed"}},
    eventResponses={valid=ValidResponse,cap=5000,keys={"who","event","state","role","note","t","via","bridgeBy","sourceID","sourceRevision"}},
    runRequests={valid=function(id,r) return ns.ValidRunRequest(id,r) end,cap=300,keys={"who","t","created","dungeon","purpose","note","role","windows","status","event","by"}},
    runInterest={valid=function(id,r) return ns.ValidRunInterest(id,r) end,cap=3000,keys={"who","t","request","state","role","windows","note"}}}
  for f,d in pairs(definitions) do
    if type(b[f])=="table" then
      local size=Count(g[f])
      for id,r in pairs(b[f]) do
        local cur=g[f][id]
        if type(id)=="string" and d.valid(id,r) and (trusted or r.who==sender
          or (f=="guildEvents" and not cur and ns.ValidBridgeEventCreate and ns.ValidBridgeEventCreate(sender,id,r))
          or (f=='eventResponses' and ns.ValidBridgeEventResponse and ns.ValidBridgeEventResponse(sender,r))) then
          local allowed=true
          if cur and f=="guildEvents" then
            allowed=r.who==cur.who and r.created==cur.created and (cur.status~="cancelled" or r.status=="cancelled")
          elseif cur and f=="runRequests" then
            allowed=r.who==cur.who and r.created==cur.created
          end
          if allowed and (cur or size<d.cap) and ns.Newer(r,cur,"t") then
            local copy={} for _,k in ipairs(d.keys) do copy[k]=r[k] end
            g[f][id]=copy; if not cur then size=size+1 end; changed=true
          end
        end
      end
    end
  end
  if changed then
    ns.Changed()
    if b.guildEvents and ns.RefreshEventBubble then ns.RefreshEventBubble() end
    if (b.runRequests or b.guildEvents) and ns.CheckScheduledRuns then ns.Debounce("runCheck",2,ns.CheckScheduledRuns) end
  end
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

---------------------------------------------------------------------------
-- Run requests: "I want to run this dungeon, anyone else?" A member picks a
-- dungeon, why (quests or loot) and up to three time ranges. Guildmates mark
-- which of those times suit them; the best overlap can become a guild event.
---------------------------------------------------------------------------
ns.RUN_PURPOSES={q="Quests",l="Loot farming",e="Quests or loot"}
ns.RUN_PURPOSE_ORDER={"q","l","e"}
local SLOT=1800
local RUN_ROLES={t=true,h=true,d=true}
local function Windows(w,max)
  if type(w)~="table" or #w<1 or #w>max then return false end
  for k in pairs(w) do if not Int(k,1,max) then return false end end
  for _,x in ipairs(w) do
    if type(x)~="table" or not Int(x.s,1e9,4e9) or not Int(x.e,1e9,4e9) or x.e<=x.s or x.e-x.s>14*3600
      or x.s%SLOT~=0 or x.e%SLOT~=0 then return false end
  end
  return true
end
function ns.ValidRunRequest(id,r)
  return Revision(r) and Text(r.who,80,true) and ns.Member(r.who) and #id<=180 and id:sub(1,#r.who+1)==r.who.."\031"
    and Int(r.created,1e9,4e9) and Text(r.dungeon,80,true) and ns.RUN_PURPOSES[r.purpose]~=nil and Text(r.note,200)
    and RUN_ROLES[r.role]==true and (r.status=="open" or r.status=="closed" or r.status=="scheduled")
    and (r.event==nil or Text(r.event,180,true)) and (r.status~="scheduled" or r.event~=nil)
    and (r.by==nil or (Text(r.by,80,true) and ns.Member(r.by))) and Windows(r.windows,3)
end
function ns.ValidRunInterest(id,r)
  return Revision(r) and Text(r.request,180,true) and Text(r.who,80,true) and ns.Member(r.who)
    and id==r.request.."\030"..r.who and (r.state=="in" or r.state=="out") and RUN_ROLES[r.role]==true
    and Text(r.note,120) and (r.state=="out" and r.windows==nil or Windows(r.windows,6))
end
local function LastEnd(w) local e=0 for _,x in ipairs(w or {}) do if x.e>e then e=x.e end end return e end
function ns.RunActive(r)
  return r and r.status=="open" and ns.Member(r.who) and LastEnd(r.windows)>ns.Now()
end
-- Snap a moment to the 30-minute grid the time pickers use.
function ns.RunSlot(epoch,up) local n=math.floor(epoch/SLOT)*SLOT; if up and n<epoch then n=n+SLOT end return n end
local function CleanWindows(w,max)
  local out={}
  for _,x in ipairs(w or {}) do
    local s,e=tonumber(x.s),tonumber(x.e)
    if s and e then
      s,e=ns.RunSlot(s),ns.RunSlot(e,true)
      if e>ns.Now() and e>s then out[#out+1]={s=s,e=e} end
    end
  end
  table.sort(out,function(a,b) return a.s<b.s end)
  while #out>max do table.remove(out) end
  return out
end
function ns.SaveRunRequest(opts,id)
  local g=ns.CasualStore(); if not g then return end
  local cur=id and g.runRequests[id]
  if cur and cur.who~=ns.me then return ns.Print("Only the member who asked can edit this run request.") end
  if not cur then
    local open=0 for _,r in pairs(g.runRequests) do if r.who==ns.me and ns.RunActive(r) then open=open+1 end end
    if open>=3 then return ns.Print("Close one of your run requests first; you can have three open.") end
    if Count(g.runRequests)>=300 then return ns.Print("The guild has too many run requests; try again later.") end
    serial=serial+1; id=ns.me.."\031"..ns.Now().."\031"..serial
  end
  local windows=CleanWindows(opts.windows,3)
  if #windows==0 then return ns.Print("Pick at least one day and time range that hasn't passed yet.") end
  for _,x in ipairs(windows) do
    if x.e-x.s>14*3600 then return ns.Print("Keep each time range under 14 hours.") end
    if x.s>ns.Now()+8*DAY then return ns.Print("Pick times within the next week.") end
  end
  local r={who=ns.me,t=cur and cur.t or ns.Now(),created=cur and cur.created or ns.Now(),dungeon=Clean(opts.dungeon,80),
    purpose=opts.purpose,note=Clean(opts.note,200),role=opts.role or "d",windows=windows,status="open"}
  if not ns.ValidRunRequest(id,r) then return ns.Print("Choose a dungeon, quests or loot, your role and at least one time range.") end
  g.runRequests[id]=r; Publish("runRequests",id,r)
  return id
end
function ns.CloseRunRequest(id)
  local g=ns.CasualStore(); local r=g and g.runRequests[id]
  if not r or (r.who~=ns.me and not ns.IsTrusted(ns.me)) or r.status~="open" then return false end
  r.status="closed"; r.by=ns.me~=r.who and ns.me or nil; Publish("runRequests",id,r); return true
end
function ns.RespondRunRequest(id,state,role,windows,note)
  local g=ns.CasualStore(); local req=g and g.runRequests[id]
  if not ns.RunActive(req) then return ns.Print("That run request has closed or its times have passed.") end
  if req.who==ns.me then return ns.Print("You asked for this run, so you're already counted.") end
  local key=id.."\030"..ns.me; local cur=g.runInterest[key]
  local r={who=ns.me,t=cur and cur.t or ns.Now(),request=id,state=state,role=role or "d",note=Clean(note,120)}
  if state=="in" then
    r.windows=CleanWindows(windows,6)
    if #r.windows==0 then return ns.Print("Tick at least one time that works for you.") end
  end
  if not ns.ValidRunInterest(key,r) then return end
  g.runInterest[key]=r; Publish("runInterest",key,r)
  ns.FollowUpdates("run",id,state=="in")
  return true
end
function ns.RunInterested(id)
  local g=ns.CasualStore(); local out={}
  for _,r in pairs(g and g.runInterest or {}) do
    if r.request==id and r.state=="in" and ns.Member(r.who) then out[#out+1]=r end
  end
  table.sort(out,function(a,b) return a.who<b.who end)
  return out
end
local function Covers(w,s,e)
  for _,x in ipairs(w or {}) do if x.s<=s and x.e>=e then return true end end
  return false
end
-- The time ranges that suit the most people (the requester included):
-- { {s=,e=,who={names},roles={t=,h=,d=}}, ... } best first.
function ns.RunBestTimes(id,limit)
  local g=ns.CasualStore(); local req=g and g.runRequests[id]
  if not req then return {} end
  local people={{who=req.who,role=req.role,windows=req.windows}}
  for _,r in ipairs(ns.RunInterested(id)) do people[#people+1]=r end
  local now=ns.RunSlot(ns.Now())
  local runs={}
  for _,w in ipairs(req.windows) do
    local cur
    for s=math.max(w.s,now),w.e-SLOT,SLOT do
      local who={}
      for _,p in ipairs(people) do if Covers(p.windows,s,s+SLOT) then who[#who+1]=p.who end end
      local sig=table.concat(who,"\031")
      if cur and cur.sig==sig and cur.e==s then cur.e=s+SLOT
      else cur={s=s,e=s+SLOT,who=who,sig=sig}; runs[#runs+1]=cur end
    end
  end
  for _,r in ipairs(runs) do
    r.roles={t=0,h=0,d=0}
    for _,p in ipairs(people) do
      for _,name in ipairs(r.who) do if name==p.who then r.roles[p.role]=r.roles[p.role]+1 end end
    end
    r.sig=nil
  end
  table.sort(runs,function(a,b)
    if #a.who~=#b.who then return #a.who>#b.who end
    if (a.e-a.s)~=(b.e-b.s) then return (a.e-a.s)>(b.e-b.s) end
    return a.s<b.s
  end)
  local out={}
  for i=1,math.min(limit or 3,#runs) do out[i]=runs[i] end
  return out
end
-- Turn a run request into a guild event at a chosen start.
function ns.ScheduleRunRequest(id,start,minutes,dungeonInfo)
  local g=ns.CasualStore(); local req=g and g.runRequests[id]
  if not ns.RunActive(req) then return ns.Print("That run request has closed or its times have passed.") end
  if req.who~=ns.me and not ns.IsTrusted(ns.me) then return ns.Print("The member who asked, or an officer, can schedule this run.") end
  local interested=#ns.RunInterested(id)+1
  local note=ns.RUN_PURPOSES[req.purpose]..". From "..req.who.."'s run request"..(req.note~="" and (": "..req.note) or ".")
  local eventId=ns.SaveGuildEvent({title=req.dungeon..(req.purpose=="q" and " (quests)" or req.purpose=="l" and " (loot)" or ""),
    zone=dungeonInfo and dungeonInfo[2] or "",note=note,starts=start,minutes=minutes or 90,slots=math.max(5,math.min(40,interested)),
    kind="dungeon",dungeon=req.dungeon,minLevel=dungeonInfo and dungeonInfo[3] or 1,maxLevel=dungeonInfo and dungeonInfo[4] or 60})
  if not eventId then return end
  req=g.runRequests[id]
  req.status="scheduled"; req.event=eventId; req.by=ns.me~=req.who and ns.me or nil
  Publish("runRequests",id,req)
  return eventId
end
-- When a run you were interested in becomes an event at a time you said
-- works, sign up for it with your role (once). Otherwise just let you know.
function ns.CheckScheduledRuns()
  local g=ns.CasualStore(); local s=ns.CommunityState()
  if not g or not s or not ns.me then return end
  s.runJoined=s.runJoined or {}
  for id,req in pairs(g.runRequests) do
    local e=req.status=="scheduled" and req.event and g.guildEvents[req.event]
    if e and e.status=="scheduled" and e.ends>ns.Now() and not s.runJoined[id] then
      local mine=req.who==ns.me and {role=req.role,windows=req.windows} or g.runInterest[id.."\030"..ns.me]
      if mine and (mine.state==nil or mine.state=="in") and e.who~=ns.me then
        s.runJoined[id]=true
        local already=g.eventResponses[req.event.."\030"..ns.me]
        if not already and Covers(mine.windows,e.starts,e.starts+SLOT) then
          ns.RespondGuildEvent(req.event,"going",mine.role,"From the run request")
          ns.Print("Signed you up for "..e.title.." on "..date("%a %H:%M",e.starts).." (from the run request). Open Guild activities to change it.")
        elseif not already then
          ns.Print(e.title.." is scheduled for "..date("%a %H:%M",e.starts)..", outside the times you picked. Open Guild activities to sign up.")
        end
      end
    end
  end
end
ns.On("PLAYER_LOGIN",function() C_Timer.After(30,function() pcall(ns.CheckScheduledRuns) end) end)
