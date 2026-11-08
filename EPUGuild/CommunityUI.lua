local ADDON,ns=...
local E,UI,C
local DAY=86400
local labels={events="Event calendar",quests="Quest matching",catchup="Catch-up",notifications="Notifications"}
local function Open(kind,key) UI:OpenDetails(kind,key) end
local function State() return UI.state.activities end
local function Whisper(name) if ChatFrame_SendTell then ChatFrame_SendTell(name) end end
function ns.InstallCommunityViews(views,env,categories)
  E=env; UI=E.UI; C=E.C
  for _,key in ipairs({"events","quests","catchup","notifications"}) do categories[#categories+1]={label=labels[key],value=key} end
end
function ns.CommunityFormKind(kind) return kind=="eventform" or kind=="questsettings" or kind=="noticeform" end
function ns.CommunityNewAction(kind)
  if kind=="events" then Open("eventform","new")
  elseif kind=="quests" then Open("questsettings","settings")
  elseif kind=="catchup" then Open("catchupreview","review")
  elseif kind=="notifications" then Open("noticeform","all")
  else return false end
  return true
end
local function ItemLabel(token)
  local kind,id=token:match("^(.-)\031(.*)$")
  local g=ns.CasualStore()
  local field=({event="guildEvents",activity="activityPosts",project="projects",request="requests",news="news"})[kind]
  local r=field and g and g[field] and g[field][id]
  if r then return kind=="request" and ns.RequestName(r,true) or r.title or "Guild post" end
  return "Post no longer available"
end
function ns.CommunityRows(g,q,st,bar)
  if not labels[st.kind] then
    if bar then bar.casualNew:SetLabel("New / edit") end
    return
  end
  local s,since=ns.CommunityState(); local out={}
  if not s then return out end
  if bar then
    bar.casualNear:Hide(); bar.casualMine:SetShown(st.kind=="events")
    bar.casualNew:SetLabel(st.kind=="events" and "New event" or (st.kind=="catchup" and "Review" or (st.kind=="quests" and "Sharing" or "Settings")))
  end
  if st.kind=="events" then
    for id,r in pairs(g.guildEvents) do
      local response=g.eventResponses[id.."\030"..ns.me]
      if r.ends>ns.Now() and (not st.mine or r.who==ns.me or (response and response.state~="declined")) and E.Match(q,r.title,r.note,r.zone,r.who) then
        local localTime,server=ns.EventTimes(r.starts); local n=ns.EventCounts(id)
        out[#out+1]={key="event:"..id,title=r.title,sub="Local "..localTime.." · Server "..server.." · "..r.zone,
          right=r.status=="cancelled" and "Cancelled" or (n.going.." going · "..n.tentative.." tentative"),at=r.starts,onClick=function() Open("event",id) end}
      end
    end
    table.sort(out,function(a,b) if a.at~=b.at then return a.at<b.at end return a.key<b.key end)
  elseif st.kind=="quests" then
    out[1]={key="questsettings",title="Quest sharing: "..(s.shareQuests and "on" or "off"),sub="Only explicitly selected quests are shared; up to eight. Click to change sharing.",onClick=function() Open("questsettings","settings") end}
    local quests,reason=ns.CurrentQuests(); local rows={}
    ns.ExpireQuestMatches()
    for id,r in pairs(quests) do
      if E.Match(q,r.title,r.progress) then
        local count=#ns.QuestMatches(id,quests)
        rows[#rows+1]={key="quest:"..id,title=r.title,sub=r.progress..(s.selectedQuests[id] and " · Selected" or " · Not shared"),right=count.." match(es)",onClick=function() Open("questmatch",id) end}
      end
    end
    table.sort(rows,function(a,b) return a.title<b.title end)
    for _,r in ipairs(rows) do out[#out+1]=r end
    if reason then out[#out+1]={key="questunavailable",title=reason,sub="No quest information is sent while the log is unavailable."} end
  elseif st.kind=="catchup" then
    for _,r in ipairs(ns.CatchupEntries()) do
      if E.Match(q,r.title,r.text) then out[#out+1]={key=r.id,title=r.title,sub=r.text,onClick=function() if r.kind=="news" then ns.MarkNewsRead(r.key) end; Open(r.kind,r.key) end} end
    end
  else
    out[#out+1]={key="notice:all",title="Notification mode: "..(s.mode or "instant"),sub="Quiet hours, sound and reminder preferences",onClick=function() Open("noticeform","all") end}
    for category,label in pairs(ns.NOTICE_CATEGORIES) do
      if E.Match(q,label) then out[#out+1]={key="notice:"..category,title=label,sub="Preference: "..(s.categories[category] or "inherit").." · Now: "..ns.NotificationPolicy(category),onClick=function() Open("noticeform",category) end} end
    end
    for token in pairs(s.muted) do
      if E.Match(q,ItemLabel(token)) then out[#out+1]={key="muted:"..token,title="Muted: "..ItemLabel(token),sub="Silent until you unmute this post",onClick=function() Open("postnotice",token) end} end
    end
    for token in pairs(s.followed) do
      if not s.muted[token] and E.Match(q,ItemLabel(token)) then out[#out+1]={key="followed:"..token,title="Following: "..ItemLabel(token),sub="Click to unfollow or mute updates",onClick=function() Open("postnotice",token) end} end
    end
    table.sort(out,function(a,b) return a.key<b.key end)
  end
  return out
end
function ns.CommunityFooter(kind)
  if kind=="events" then return "Dates are entered in your local time. Server display uses the current realm offset; recheck after clock changes."
  elseif kind=="quests" then return "Exact quest IDs match; phases and quest-chain eligibility can differ. Shared progress expires after three minutes."
  elseif kind=="catchup" then return "Latest relevant updates from data synced so far; active projects and upcoming events remain visible after review."
  elseif kind=="notifications" then return "Personal settings stay on this character. Quiet hours use your local clock; digests are read in Catch-up." end
end
local function RoleButtons(det,current,set)
  local specs={}
  for _,v in ipairs({"t","h","d"}) do local role=v; specs[#specs+1]={ns.HELPER_ROLES[role],function() set(role) end} end
  det:Buttons(specs)
end
function ns.AddPersonalActions(kind,key,det)
  if kind~="event" and kind~="activity" and kind~="project" and kind~="request" and kind~="news" then return end
  local s=ns.CommunityState(); if not s then return end
  local token=ns.PersonalToken(kind,key); local followed=s.followed[token]; local muted=s.muted[token]
  local buttons={}
  if kind~="news" then buttons[#buttons+1]={followed and "Unfollow updates" or "Follow updates",function() ns.FollowUpdates(kind,key,not followed); UI:FillDetails() end} end
  buttons[#buttons+1]={muted and "Unmute post" or "Mute post",function() ns.MuteUpdates(kind,key,not muted); UI:FillDetails() end}
  det:Gap(); det:Buttons(buttons)
end
function ns.FillCommunityDetails(kind,key,det)
  local g=ns.CasualStore(); local s,since=ns.CommunityState()
  if not g or not s then return false end
  if kind=="eventform" then
    local cur=g.guildEvents[key]
    if cur and cur.who~=ns.me then UI:CloseDetails(); return true end
    det:Reset(nil,nil,cur and "Edit guild event" or "New guild event","Dates use your computer's local timezone")
    local title=det:Field("Title",cur and cur.title or "",160)
    local zone=det:Field("Meet at",cur and cur.zone or "",160)
    local note=det:Field("Details",cur and cur.note or "",160)
    local when=det:Field("Local start",date("%Y-%m-%d %H:%M",cur and cur.starts or ns.Now()+DAY),160)
    local duration=det:Field("Minutes",tostring(cur and (cur.ends-cur.starts)/60 or 60),60,true)
    local slots=det:Field("Players",tostring(cur and cur.slots or 5),60,true)
    local preview=det:Text("",C.gold)
    det.y=det.y-30; preview:SetHeight(44)
    local function Preview()
      local epoch=ns.ParseEventLocal(when:GetText())
      if not epoch then preview:SetText("Use YYYY-MM-DD HH:MM in your local time."); return end
      local l,server=ns.EventTimes(epoch); preview:SetText("Local: "..l.."\nServer (current offset): "..server)
      det:Finish()
    end
    when.onChange=Preview; Preview()
    det:Text("Plan up to 28 days ahead. Start times are stored as one shared instant. Server-time display uses today's realm offset, which can change with daylight saving time.",C.muted)
    det:Buttons({{cur and "Save event" or "Create event",function()
      local start=ns.ParseEventLocal(when:GetText())
      if not start then return ns.Print("Enter a valid local date and time as YYYY-MM-DD HH:MM.") end
      local id=ns.SaveGuildEvent({title=title:GetText(),zone=zone:GetText(),note=note:GetText(),starts=start,minutes=tonumber(duration:GetText()),slots=tonumber(slots:GetText())},cur and key)
      if id then Open("event",id) end
    end,accent=true}})
  elseif kind=="event" then
    local r=g.guildEvents[key]; if not r then UI:CloseDetails(); return true end
    local localTime,server=ns.EventTimes(r.starts)
    det:Reset(nil,nil,r.title,r.status=="cancelled" and "Cancelled" or (r.ends<=ns.Now() and "Ended" or "Guild event"))
    det:Text("Local: "..localTime.."\nServer (current offset): "..server,C.gold)
    det:Text("Organiser: "..r.who.."\nMeet at: "..r.zone.."\nDuration: "..math.floor((r.ends-r.starts)/60).." minutes")
    det:Text(r.note)
    local n=ns.EventCounts(key)
    det:Text(n.going.." going / "..r.slots.." planned · "..n.tentative.." tentative")
    det:Text(n.t.." tank · "..n.h.." healer · "..n.d.." DPS",C.muted)
    for _,reply in ipairs(ns.EventResponses(key)) do
      local name=reply.who
      det:Text(name.." · "..reply.state.." · "..ns.HELPER_ROLES[reply.role]..(reply.note~="" and ("\n"..reply.note) or ""))
      det:Buttons({{"Whisper",function() Whisper(name) end}})
    end
    det:Text("Signups show interest; the organiser confirms the group. No automatic invitations or attendance penalties.",C.muted)
    if r.status=="scheduled" and r.ends>ns.Now() then
      local cur=g.eventResponses[key.."\030"..ns.me]; local role=cur and cur.role or "d"
      local status=det:Text("My role: "..ns.HELPER_ROLES[role],C.gold)
      RoleButtons(det,role,function(value) role=value; det.casualDraft=true; status:SetText("My role: "..ns.HELPER_ROLES[role]) end)
      local note=det:Field("My note",cur and cur.note or "",160); note.onChange=function() det.casualDraft=true end
      local function Reply(state) if ns.RespondGuildEvent(key,state,role,note:GetText()) then UI:FillDetails() end end
      det:Buttons({{"Going",function() Reply("going") end,accent=true},{"Tentative",function() Reply("tentative") end},{"Can't make it",function() Reply("declined") end}})
      if r.who==ns.me and r.starts>ns.Now() then det:Buttons({{"Edit event",function() Open("eventform",key) end}}) end
      if r.who==ns.me or ns.IsTrusted(ns.me) then det:Buttons({{"Cancel event",function() ns.CancelGuildEvent(key); UI:FillDetails() end}}) end
    end
  elseif kind=="questsettings" then
    det:Reset(nil,nil,"Selected quest sharing",s.shareQuests and "Sharing is on" or "Sharing starts off")
    local n=0 for _ in pairs(s.selectedQuests) do n=n+1 end
    det:Text(n.." quest(s) selected. Select quests from Quest matching, then enable sharing. Only their IDs, titles and objective progress are sent.")
    det:Text("Other members' progress is kept only in memory and expires after three minutes. No quest history is sent to Discord. Exact IDs match; different phases or chain requirements may still prevent playing together.",C.muted)
    det:Buttons({{s.shareQuests and "Stop sharing" or "Share selected quests",function() ns.SetQuestSharing(not s.shareQuests); UI:FillDetails() end,accent=true}})
  elseif kind=="questmatch" then
    local r=ns.CurrentQuests()[tonumber(key)]
    if not r then det:Reset(nil,nil,"Quest unavailable","It may have been completed or abandoned"); return true end
    key=tonumber(key)
    det:Reset(nil,nil,r.title,r.progress)
    local selected=s.selectedQuests[key]
    det:Text(selected and (s.shareQuests and "This quest is being shared." or "Selected; sharing is paused.") or "This quest is not selected for sharing.",C.gold)
    det:Buttons({{selected and "Unselect quest" or "Select to share",function() ns.SelectSharedQuest(key,not selected); UI:FillDetails() end}})
    if not s.shareQuests then det:Buttons({{"Sharing settings",function() Open("questsettings","settings") end}}) end
    local matches=ns.QuestMatches(key)
    if #matches==0 then det:Text("No online guildmates are currently sharing this exact quest. Both players need the new addon, and updates may take a short time.",C.muted) end
    for _,match in ipairs(matches) do
      local name=match.who
      det:Text(name.."\n"..match.quest.progress.." · updated "..math.floor(GetTime()-match.quest.at).."s ago")
      det:Buttons({{"Whisper",function() Whisper(name) end}})
    end
    det:Text("Check phases and quest-chain eligibility before travelling. Selecting a quest shares information; it does not accept or share the game quest for another player.",C.muted)
  elseif kind=="noticeform" then
    det:Reset(nil,nil,key=="all" and "Personal notifications" or ns.NOTICE_CATEGORIES[key],"Private to this character and guild")
    local value=det:Text("Mode: "..(key=="all" and (s.mode or "instant") or (s.categories[key] or "inherit")),C.gold)
    local specs={}
    for _,mode in ipairs(key=="all" and {"instant","digest","off"} or {"inherit","instant","digest","off"}) do
      local chosen=mode
      specs[#specs+1]={mode,function()
        if key=="all" then s.mode=chosen else s.categories[key]=chosen~="inherit" and chosen or nil end
        value:SetText("Mode: "..chosen); ns.Changed()
      end}
    end
    det:Buttons(specs)
    if key=="all" then
      local first=det:Field("Quiet start",s.quietStart or "",80); local last=det:Field("Quiet end",s.quietEnd or "",80)
      local lead=det:Field("Remind min",tostring(s.reminderMinutes or 15),60,true)
      det:Text("Quiet hours use local HH:MM and can span midnight. Leave both blank to disable. Quiet hours collect messages in Catch-up without pop-ups or sound.",C.muted)
      det:Buttons({{s.sound==false and "Enable sound" or "Mute sound",function(self) s.sound=s.sound==false; self:SetLabel(s.sound and "Mute sound" or "Enable sound") end}})
      det:Buttons({{"Save quiet hours",function()
        local minutes=tonumber(lead:GetText())
        if not minutes or minutes%1~=0 or minutes<5 or minutes>120 then return ns.Print("Choose a reminder lead time from 5 to 120 minutes.") end
        if ns.SetQuietHours(first:GetText(),last:GetText()) then s.reminderMinutes=minutes; ns.Print("Personal notification settings saved.") end
      end,accent=true}})
    end
    det:Text("Global Off/Digest takes precedence over category preferences. Muted posts stay silent. Follow a project, activity or event from its details. Event reminders apply to followed events and your signups.",C.muted)
  elseif kind=="digest" then
    local n=s.inbox[key]; if not n then UI:CloseDetails(); return true end
    det:Reset(nil,nil,n.title,"Personal digest · "..date("%m-%d %H:%M",n.at))
    det:Text(n.text)
    if n.kind and n.key then det:Buttons({{"Open item",function() if n.kind=="news" then ns.MarkNewsRead(n.key) end; Open(n.kind,n.key) end}}) end
    det:Buttons({{"Dismiss",function() s.inbox[key]=nil; UI:CloseDetails(); UI:Refresh() end}})
  elseif kind=="postnotice" then
    local itemKind,id=key:match("^(.-)\031(.*)$")
    det:Reset(nil,nil,ItemLabel(key),"Personal notification preference")
    det:Text(s.muted[key] and "This post is muted." or "You are following updates to this post.")
    det:Buttons({{s.muted[key] and "Unmute" or "Mute post",function() ns.MuteUpdates(itemKind,id,not s.muted[key]); UI:CloseDetails(); UI:Refresh() end}})
    if s.followed[key] then det:Buttons({{"Unfollow",function() ns.FollowUpdates(itemKind,id,false); UI:CloseDetails(); UI:Refresh() end}}) end
  elseif kind=="catchupreview" then
    det:Reset(nil,nil,"Your guild catch-up","Last visit: "..date("%Y-%m-%d %H:%M",since))
    det:Text("Catch-up collects unread announcements, recent personal request changes, active projects, upcoming events and your notification digest from available synced data.")
    det:Text("Reviewing clears the personal digest and advances this visit's marker. It does not mark announcements read or hide ongoing projects and events.",C.muted)
    det:Buttons({{"Mark reviewed",function() ns.MarkCatchupReviewed(); UI:CloseDetails(); UI:Refresh() end,accent=true},
      {"Notifications",function() State().kind="notifications"; UI:CloseDetails(); UI:Refresh() end}})
  else return false end
  return true
end
