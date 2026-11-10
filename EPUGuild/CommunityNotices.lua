-- Personal routing: instant, digest or off, with local quiet hours and mutes.
local ADDON,ns=...
ns.NOTICE_CATEGORIES={catchup="Returning-player hint",requests="Bank requests",crafts="Craft requests",news="Guild news",milestones="Milestones",activities="Followed activities",projects="Followed projects",events="Followed events",reminders="Event reminders",invites="Guild invite requests"}
local function Clock(value)
  local h,m=tostring(value or ""):match("^(%d%d):(%d%d)$")
  h,m=tonumber(h),tonumber(m)
  if h and m and h<24 and m<60 then return h*60+m end
end
function ns.SetQuietHours(first,last)
  local s=ns.CommunityState(); if not s then return false end
  if first=="" and last=="" then s.quietStart=nil; s.quietEnd=nil; return true end
  local a,b=Clock(first),Clock(last)
  if not a or not b or a==b then return ns.Print("Enter different local start/end times as HH:MM, or leave both blank.") end
  s.quietStart=first; s.quietEnd=last; return true
end
function ns.InQuietHours()
  local s=ns.CommunityState(); if not s then return false end
  local a,b=Clock(s.quietStart),Clock(s.quietEnd)
  if not a or not b or a==b then return false end
  local now=Clock(date("%H:%M",ns.Now()))
  if not now then return false end
  return a<b and now>=a and now<b or a>b and (now>=a or now<b)
end
function ns.NotificationPolicy(category,key,kind)
  if category=='invites' and not ns.CanInviteGuild() then return 'off' end
  local s=ns.CommunityState(); if not s then return "instant" end
  if key and s.muted[ns.PersonalToken(kind or category,key)] then return "off" end
  local mode=s.mode or "instant"
  local override=s.categories[category]
  if mode=="off" or override=="off" then return "off" end
  if mode=="digest" or override=="digest" or ns.InQuietHours() or ns.personalCatchingUp then return "digest" end
  return "instant"
end
local function Trim(map,max)
  local rows={} for key,n in pairs(map) do rows[#rows+1]={key=key,at=type(n)=="table" and (n.at or 0) or 0,order=type(n)=="table" and (n.order or 0) or 0} end
  table.sort(rows,function(a,b) if a.at~=b.at then return a.at>b.at end if a.order~=b.order then return a.order>b.order end return a.key<b.key end)
  for i=max+1,#rows do map[rows[i].key]=nil end
end
function ns.RoutePersonalNotice(title,text,icon,context,replay)
  local s=ns.CommunityState(); if not s then return true end
  context=context or ns.noticeContext or {category=title=="Guild milestone" and "milestones" or "requests"}
  local category=context.category or "requests"
  local token=ns.PersonalToken(context.kind or category,context.key or title)
  local revision=tostring(context.revision or text or "")
  local seenKey=category.."\030"..token
  if not replay and s.seen[seenKey] and s.seen[seenKey].revision==revision then return false end
  s.noticeSerial=(s.noticeSerial or 0)+1
  s.seen[seenKey]={revision=revision,at=ns.Now(),order=s.noticeSerial}; Trim(s.seen,500)
  local policy=ns.NotificationPolicy(category,context.key,context.kind)
  if context.digest and policy=="instant" then policy="digest" end
  if policy=="digest" then
    s.inbox[seenKey]={title=tostring(title or ""):sub(1,100),text=tostring(text or ""):sub(1,600),at=ns.Now(),order=s.noticeSerial,
      category=category,kind=context.kind,key=context.key,revision=revision}
    Trim(s.inbox,100); ns.Changed()
  end
  return policy=="instant"
end
function ns.DeferOverflowNotice(title,text,icon,context)
  local c={digest=true}
  for k,v in pairs(context or {}) do c[k]=v end
  ns.RoutePersonalNotice(title,text,icon,c,true)
end
function ns.OpenPersonalNotice(c)
  if not c or not c.kind or not c.key or not ns.UI then return false end
  if c.kind=='guildinvite' and not ns.CanInviteGuild() then return false end
  local view=({event="activities",activity="activities",guildinvite="activities",project="projects",request="requests",news="news"})[c.kind]
  if not view then return false end
  ns.UI:Show()
  if c.kind=="guildinvite" then ns.UI.state.activities.kind='invites'
  elseif c.kind=="event" then ns.UI.state.activities.kind="events"
  elseif c.kind=="activity" then local r=ns.CasualStore().activityPosts[c.key]; ns.UI.state.activities.kind=r and r.kind or "help" end
  ns.UI:SetView(view); ns.UI:OpenDetails(c.kind,c.key); return true
end
function ns.DeferQueuedNotice(n)
  if ns.db and ns.db.settings.notices==false then return true end
  local context=n.context or {category=n.title=="Guild milestone" and "milestones" or "requests"}
  if ns.NotificationPolicy(context.category,context.key,context.kind)=="instant" then return false end
  ns.RoutePersonalNotice(n.title,n.text,n.icon,context,true); return true
end
function ns.PersonalSoundsEnabled()
  local s=ns.CommunityState(); return not s or s.sound~=false
end
function ns.QueueCommunityNotice(category,kind,key,title,text,revision)
  if ns.Notify then ns.Notify(title,text,nil,{category=category,kind=kind,key=key,revision=revision}) end
end
function ns.NewsIsMuted(id) return ns.NotificationPolicy("news",id,"news")=="off" end
function ns.AllowNewsPopup(force)
  if force then return true end
  if ns.db and ns.db.settings.newsPopups==false then return false end
  local unread=ns.UnreadNews(); local instant=false
  for _,e in ipairs(unread) do
    if not e.motd then
      local policy=ns.NotificationPolicy("news",e.id,"news")
      if policy=="instant" then instant=true
      elseif policy=="digest" then ns.RoutePersonalNotice("News: "..e.title,e.text,nil,{category="news",kind="news",key=e.id,revision=e.u or e.t}) end
    end
  end
  return instant
end
local changed=ns.OnRequestChanged
ns.OnRequestChanged=function(id,r,old)
  local previous=ns.noticeContext
  ns.noticeContext={category=r.crafter and "crafts" or "requests",kind="request",key=id,revision=r.u or r.t}
  local ok,result=pcall(changed,id,r,old)
  ns.noticeContext=previous
  if not ok then error(result) end
  return result
end
local respond=ns.RespondActivity
ns.RespondActivity=function(id,role,state,note)
  local result=respond(id,role,state,note)
  if result then ns.FollowUpdates("activity",id,state~="withdrawn") end
  return result
end
local merge=ns.Merge
ns.Merge=function(sender,b,catchingUp)
  local g=ns.CasualStore(); local before,candidates={},{}
  if g then
    for _,f in ipairs({"projects","requests","activityPosts","guildEvents","activityReplies","eventResponses"}) do
      before[f]={}; candidates[f]={}
      local src=type(b)=="table" and type(b[f])=="table" and b[f] or {}
      for id in pairs(src) do candidates[f][id]=true; if g[f][id] then before[f][id]=ns.Fingerprint(g[f][id]) end end
    end
  end
  local oldFlag=ns.personalCatchingUp; ns.personalCatchingUp=catchingUp==true
  local ok,result=pcall(merge,sender,b,catchingUp)
  ns.personalCatchingUp=oldFlag
  if not ok then error(result) end
  local s=ns.CommunityState()
  if g and s and not catchingUp and sender~=ns.me then
    local defs={projects={kind="project",category="projects"},activityPosts={kind="activity",category="activities"},guildEvents={kind="event",category="events"}}
    for f,d in pairs(defs) do
      for id in pairs(candidates[f]) do
        local r=g[f][id]
        if r and before[f][id]~=ns.Fingerprint(r) and s.followed[ns.PersonalToken(d.kind,id)] then
          ns.QueueCommunityNotice(d.category,d.kind,id,r.title,"Updated by "..sender.." · "..tostring(r.status or ""),r.t)
        end
      end
    end
    for id in pairs(candidates.requests) do
      local r=g.requests[id]
      if r and r.who~=ns.me and r.to~=ns.me and r.crafter~=ns.me and before.requests[id]~=ns.Fingerprint(r) and s.followed[ns.PersonalToken("request",id)] then
        ns.QueueCommunityNotice(r.crafter and "crafts" or "requests","request",id,"Request updated",ns.RequestName(r,true).." · "..r.status,r.u or r.t)
      end
    end
    for _,f in ipairs({"activityReplies","eventResponses"}) do
      local kind=f=="activityReplies" and "activity" or "event"
      for id in pairs(candidates[f]) do
        local r=g[f][id]
        local parent=r and (r.post or r.event)
        if r and before[f][id]~=ns.Fingerprint(r) and s.followed[ns.PersonalToken(kind,parent)] then
          ns.QueueCommunityNotice(kind=="event" and "events" or "activities",kind,parent,"Guild response",r.who..": "..r.state,r.who..":"..r.t)
        end
      end
    end
  end
  return result
end
function ns.CheckEventReminders()
  local g=ns.CasualStore(); local s=ns.CommunityState(); if not g or not s then return end
  local lead=tonumber(s.reminderMinutes) or 15
  s.remindersSent=s.remindersSent or {}
  for id,start in pairs(s.remindersSent) do
    local e=g.guildEvents[id]
    if not e or e.ends<=ns.Now() or e.starts~=start then s.remindersSent[id]=nil end
  end
  for id,e in pairs(g.guildEvents) do
    local token=ns.PersonalToken("event",id)
    local reply=g.eventResponses[id.."\030"..ns.me]
    if e.status=="scheduled" and e.starts>ns.Now() and e.starts-ns.Now()<=lead*60
      and (s.followed[token] or (reply and reply.state~="declined")) and s.remindersSent[id]~=e.starts then
      s.remindersSent[id]=e.starts
      ns.QueueCommunityNotice("reminders","event",id,"Event starting soon",e.title.." · "..math.ceil((e.starts-ns.Now())/60).." minutes", "reminder:"..e.starts)
    end
  end
end
local hinted={}
function ns.MaybeReturningHint()
  local s,since=ns.CommunityState(); local key=ns.GuildKey()
  if not s or not key or hinted[key] or ns.Now()-since<86400 or (ns.db and ns.db.settings.notices==false)
    or ns.NotificationPolicy("catchup")~="instant" then return false end
  local n=#ns.CatchupEntries()
  if n==0 then return false end
  hinted[key]=true
  ns.Print("Welcome back! "..n.." guild update(s) and active item(s) are available. Use /epu catchup when you're ready.")
  return true
end
ns.On("PLAYER_LOGIN",function()
  local function Tick() ns.CheckEventReminders(); C_Timer.After(30,Tick) end
  C_Timer.After(45,Tick)
  local attempts=0
  local function Returning()
    attempts=attempts+1
    if ns.NetworkStatus().queued>0 and attempts<6 then C_Timer.After(15,Returning); return end
    ns.MaybeReturningHint()
  end
  C_Timer.After(60,Returning)
end)
