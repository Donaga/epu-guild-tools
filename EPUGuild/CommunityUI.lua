local ADDON,ns=...
local E,UI,C
local DAY=86400
local memberTools={
  {key="guides", title="Your guides", hint="Find leveling, talent, and profession guides for your character."},
  {key="quests", title="Quest matching", hint="Find guildmates working on the same quests."},
  {key="catchup", title="Catch-up", hint="Review missed guild updates and notifications."},
  {key="notifications", title="Notifications", hint="Set alerts, sounds, and quiet hours."},
}
local toolActions={guides="Settings",quests="Sharing",catchup="Review",notifications="Settings"}
local dungeonGroups={
  {label='Classic · Early', entries={
    {'Ragefire Chasm','Orgrimmar'}, {'The Deadmines','Westfall'}, {'Wailing Caverns','The Barrens'},
    {'Shadowfang Keep','Silverpine Forest'}, {'Blackfathom Deeps','Ashenvale'}, {'The Stockade','Stormwind City'},
    {'Gnomeregan','Dun Morogh'}, {'Razorfen Kraul','The Barrens'},
  }},
  {label='Classic · Mid levels', entries={
    {'Scarlet Monastery: Graveyard','Tirisfal Glades'}, {'Scarlet Monastery: Library','Tirisfal Glades'},
    {'Scarlet Monastery: Armory','Tirisfal Glades'}, {'Scarlet Monastery: Cathedral','Tirisfal Glades'},
    {'Razorfen Downs','The Barrens'}, {'Uldaman','Badlands'}, {'Zul’Farrak','Tanaris'}, {'Maraudon','Desolace'},
    {'Sunken Temple','Swamp of Sorrows'},
  }},
  {label='Classic · Late', entries={
    {'Blackrock Depths','Blackrock Mountain'}, {'Lower Blackrock Spire','Blackrock Mountain'},
    {'Upper Blackrock Spire','Blackrock Mountain'}, {'Dire Maul: East','Feralas'}, {'Dire Maul: North','Feralas'},
    {'Dire Maul: West','Feralas'}, {'Scholomance','Western Plaguelands'},
    {'Stratholme: Main Gate','Eastern Plaguelands'}, {'Stratholme: Service Gate','Eastern Plaguelands'},
  }},
  -- Suggested ranges from Blizzard's Forever dungeon overview (news/24301455).
  {label='Forever dungeons', entries={
    {'Hall of Thanes','Ironforge',13,18}, {'Ruins of Lordaeron','Tirisfal Glades',15,20},
    {'Excavation Site','Wetlands',24,29}, {'City of Dalaran','Alterac Mountains',28,33},
    {'The Drowned City','Stranglethorn Vale',35,40}, {'Krol’dok Stronghold','Riverglades',40,45},
    {'Alcaz Prison','Dustwallow Marsh',48,53}, {'Blackmaw Hold','Azshara',55,60},
    {'Shaper’s Terrace','Un’Goro Crater',58,60},
  }},
}
local dungeons={}
for _,group in ipairs(dungeonGroups) do
  for _,entry in ipairs(group.entries) do dungeons[entry[1]]=entry end
end
local function Open(kind,key) UI:OpenDetails(kind,key) end
local function State() return UI.state.activities end
local function Whisper(name) if ChatFrame_SendTell then ChatFrame_SendTell(name) end end
local function InviteRows(g,q)
  local out={}
  if not ns.CanInviteGuild() then
    out[1]={key='invitepermission',title='Guild invite permission required',sub='The game must report that this character can invite members.'}; return out
  end
  local s=ns.CommunityState()
  if not s then return out end
  local seen={}
  for id,r in pairs(g.inviteRequests or {}) do
    if ns.ActiveGuildInvite(r) and (not s.inviteDismissed or s.inviteDismissed[id]~=r.who) and not seen[r.who:lower()] and E.Match(q,r.who,r.requester) then
      seen[r.who:lower()]=true
      local outcome=ns.GuildInviteOutcome(id)
      local _,presence=ns.GuildInvitePresence(r.who)
      out[#out+1]={key='invite:'..id,title=r.who,sub='Requested by '..r.requester..' on Discord · '..date('%m-%d %H:%M',r.posted),right=presence..' · '..(outcome and 'Invite sent' or 'Needs invite'),onClick=function() Open('guildinvite',id) end}
    end
  end
  table.sort(out,function(a,b) return a.title<b.title end)
  return out
end

function ns.OpenMemberTools(kind)
  UI:Show()
  UI:CloseDetails()
  UI.search:SetText("")
  UI.state.membertools.kind=kind
  UI:SetView("membertools")
end

function ns.InstallCommunityViews(views,env)
  E=env; UI=E.UI; C=E.C
  UI.state.membertools={kind="all"}
  views.membertools={
    label="Member tools",
    icon="Interface\\Icons\\INV_Misc_Book_09",
    onSelect=function() ns.OpenMemberTools("all") end,
    tools=function(bar)
      bar.allTools=bar:Add(E.Btn(bar,"All tools",80,22),"left",function() ns.OpenMemberTools("all") end)
      bar.toolTitle=bar:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
      bar.toolTitle:SetPoint("LEFT",bar.allTools,"RIGHT",10,0)
      bar.toolAction=bar:Add(E.Btn(bar,"Settings",80,22),"right",function()
        ns.CommunityNewAction(UI.state.membertools.kind)
      end)
      bar.saved=bar:Add(E.Btn(bar,"Saved",50,22),"right",function()
        local state=ns.GuideState()
        state.savedOnly=not state.savedOnly
        UI:Refresh()
      end)
    end,
    rows=function(g,q)
      local state=UI.state.membertools
      local bar=views.membertools.bar
      local isHome=state.kind=="all"
      bar.allTools:SetShown(not isHome)
      bar.toolTitle:SetShown(not isHome)
      bar.toolAction:SetShown(not isHome)
      bar.saved:SetShown(state.kind=="guides")
      if isHome then
        local rows={}
        for _,tool in ipairs(memberTools) do
          if E.Match(q,tool.title,tool.hint) then
            local key=tool.key
            rows[#rows+1]={key=key,title=tool.title,sub=tool.hint,right="Open",onClick=function() ns.OpenMemberTools(key) end}
          end
        end
        return rows
      end
      for _,tool in ipairs(memberTools) do
        if tool.key==state.kind then bar.toolTitle:SetText(tool.title); break end
      end
      bar.toolAction:SetLabel(toolActions[state.kind])
      if state.kind=="guides" then bar.saved:SetOn(ns.GuideState().savedOnly==true) end
      return ns.CommunityRows(g,q,state)
    end,
    empty="Nothing to show here yet.",
    footer=function() return ns.CommunityFooter(UI.state.membertools.kind) or "" end,
  }
  views.invites={
    label="Guild invites",
    icon="Interface\\Icons\\INV_Letter_15",
    visible=ns.CanInviteGuild,
    tools=function(bar)
      bar:Add(E.Btn(bar,"How it works",80,22),"right",function() Open("invitehelp","help") end)
    end,
    rows=InviteRows,
    empty="No active guild invite requests.",
    footer=function()
      return "New Discord requests appear after a sync companion user logs in or reloads WoW and guild sync completes."
    end,
  }
end
local picker
local function PickDate(day)
  if picker.withTime then
    picker.selected = day
    picker:Paint(ns.ActivityCalendarDays(picker.year,picker.month))
  else
    picker:Hide()
    picker.chosen(day)
  end
end

function ns.ShowActivityDatePicker(initial,chosen,clock)
  if not picker then
    picker=CreateFrame("Frame","EPUGuildActivityDatePicker",UI,"BasicFrameTemplateWithInset")
    tinsert(UISpecialFrames,"EPUGuildActivityDatePicker")
    picker:SetSize(420,350); picker:SetPoint("CENTER"); picker:SetFrameStrata("DIALOG"); picker:SetClampedToScreen(true)
    picker.TitleText:SetText("Activity calendar · local dates")
    picker.heading=picker:CreateFontString(nil,"OVERLAY","GameFontNormal")
    picker.heading:SetPoint("TOP",0,-36)
    picker.days={}
    for i,name in ipairs({"Sun","Mon","Tue","Wed","Thu","Fri","Sat"}) do
      local label=picker:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
      label:SetPoint("TOPLEFT",15+(i-1)*56,-64); label:SetText(name)
    end
    for i=1,42 do
      local b=E.Btn(picker,"",52,30); b:SetPoint("TOPLEFT",12+((i-1)%7)*56,-82-math.floor((i-1)/7)*34)
      b:SetScript("OnClick",function() PickDate(b.day.key) end)
      picker.days[i]=b
    end
    local function Move(step)
      local days,y,m=ns.ActivityCalendarDays(picker.year,picker.month+step)
      picker.year=y; picker.month=m; picker:Paint(days)
    end
    local prev=E.Btn(picker,"<",32,22); prev:SetPoint("TOPLEFT",12,-32); prev:SetScript("OnClick",function() Move(-1) end)
    local next=E.Btn(picker,">",32,22); next:SetPoint("TOPRIGHT",-12,-32); next:SetScript("OnClick",function() Move(1) end)
    picker.clear=E.Btn(picker,"All dates",85,22); picker.clear:SetPoint("BOTTOMLEFT",12,12)
    picker.clear:SetScript("OnClick",function() PickDate(nil) end)
    picker.today=E.Btn(picker,"Today",65,22)
    local function Jump(offset)
      local d=date('*t',ns.Now())
      local at=time({year=d.year,month=d.month,day=d.day+offset,hour=12,min=0,sec=0})
      local day=date('*t',at)
      picker.year,picker.month=day.year,day.month
      PickDate(date('%Y-%m-%d',at))
    end
    picker.today:SetScript("OnClick",function() Jump(0) end)
    picker.tomorrow=E.Btn(picker,"Tomorrow",85,22); picker.tomorrow:SetPoint('BOTTOMLEFT',82,12)
    picker.tomorrow:SetScript('OnClick',function() Jump(1) end)
    picker.timeText=picker:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
    picker.timeText:SetPoint('TOPLEFT',12,-327)
    local function ClockMenu(button,values,key,label)
      local items={}
      for _,value in ipairs(values) do items[#items+1]={label=label(value),value=value} end
      E.OpenMenu(button,items,picker[key],function(value)
        picker[key]=value
        picker:Paint(ns.ActivityCalendarDays(picker.year,picker.month))
      end)
    end
    picker.hourButton=E.Btn(picker,'',70,22); picker.hourButton:SetPoint('TOPLEFT',12,-348)
    picker.hourButton:SetScript('OnClick',function(self)
      ClockMenu(self,{1,2,3,4,5,6,7,8,9,10,11,12},'hour',tostring)
    end)
    picker.minuteButton=E.Btn(picker,'',78,22); picker.minuteButton:SetPoint('LEFT',picker.hourButton,'RIGHT',6,0)
    picker.minuteButton:SetScript('OnClick',function(self)
      local minutes={0,15,30,45}
      if picker.minute%15~=0 then minutes[#minutes+1]=picker.minute; table.sort(minutes) end
      ClockMenu(self,minutes,'minute',function(value) return string.format('%02d',value) end)
    end)
    picker.periodButton=E.Btn(picker,'',60,22); picker.periodButton:SetPoint('LEFT',picker.minuteButton,'RIGHT',6,0)
    picker.periodButton:SetScript('OnClick',function(self) ClockMenu(self,{'AM','PM'},'period',tostring) end)
    picker.apply=E.Btn(picker,'Set date & time',112,22,'accent'); picker.apply:SetPoint('BOTTOMRIGHT',-12,12)
    picker.apply:SetScript('OnClick',function()
      if not picker.startValue then return end
      picker:Hide()
      picker.chosen(picker.startValue)
    end)
    picker.hint=picker:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
    picker.hint:SetPoint('BOTTOMLEFT',12,43)
    function picker:Paint(days)
      self.heading:SetText(date('%B %Y',time({year=self.year,month=self.month,day=1,hour=12,min=0,sec=0})))
      for i,day in ipairs(days) do
        local b=self.days[i]; b.day=day
        b:SetLabel(day.day..(day.count>0 and (" ("..day.count..")") or "")); b:SetAlpha(day.month==self.month and 1 or 0.45)
        b.tip=day.key.." · "..day.count.." upcoming activities"; b:SetOn(day.key==self.selected)
      end
      if not self.withTime then return end
      self.hourButton:SetLabel('Hour: '..self.hour)
      self.minuteButton:SetLabel(string.format('Min: %02d',self.minute))
      self.periodButton:SetLabel(self.period)
      local hour=self.hour%12+(self.period=='PM' and 12 or 0)
      local value=self.selected and string.format('%s %02d:%02d',self.selected,hour,self.minute)
      local start=value and ns.ParseEventLocal(value)
      self.startValue=start and start>=ns.Now()+60 and start<=ns.Now()+28*DAY and value or nil
      self.apply:SetEnabled(self.startValue~=nil)
      self.hint:SetText(self.startValue and date('%a, %b %d at %I:%M %p',start) or 'Choose a valid future time within 28 days.')
      self.timeText:SetText('Start time (your local time)')
    end
  end
  local y,m=tostring(initial or date("%Y-%m-%d",ns.Now())):match("^(%d+)%-(%d+)")
  if not y or tonumber(y)<2000 or tonumber(y)>2100 or not m or tonumber(m)<1 or tonumber(m)>12 then local c=date("*t",ns.Now()); y,m=c.year,c.month end
  local days,year,month=ns.ActivityCalendarDays(tonumber(y),tonumber(m))
  picker.withTime=clock~=nil
  picker:SetSize(420,picker.withTime and 430 or 350)
  picker.TitleText:SetText(picker.withTime and 'Choose date & time' or 'Activity calendar · local dates')
  picker.clear:SetShown(not picker.withTime)
  picker.today:ClearAllPoints()
  picker.today:SetPoint(picker.withTime and 'BOTTOMLEFT' or 'BOTTOMRIGHT',picker.withTime and 12 or -12,12)
  for _,widget in ipairs({picker.tomorrow,picker.hourButton,picker.minuteButton,picker.periodButton,picker.apply,picker.hint,picker.timeText}) do
    widget:SetShown(picker.withTime)
  end
  local h,mn=tostring(clock or ''):match('^(%d%d):(%d%d)$')
  h,mn=tonumber(h),tonumber(mn)
  if not h or h>23 or not mn or mn>59 then h,mn=19,0 end
  picker.hour=(h+11)%12+1; picker.minute=mn; picker.period=h>=12 and 'PM' or 'AM'
  picker.year=year; picker.month=month; picker.chosen=chosen; picker.selected=initial; picker:Paint(days); picker:Show()
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
  if bar and bar.casualAvailability then
    bar.casualAvailability:Show()
    bar.casualAvailability:SetLabel(st.kind=="events" and "Calendar" or "My availability")
    bar.casualAvailability:SetScript("OnClick",st.kind=="events" and function()
      ns.ShowActivityDatePicker(st.eventDate,function(day) st.eventDate=day; UI:Refresh() end)
    end or function() Open("helperform",ns.me) end)
  end
  if st.kind~="events" and not toolActions[st.kind] then
    if bar then bar.casualNew:SetLabel("New / edit") end
    return
  end
  local s,since=ns.CommunityState(); local out={}
  if not s then return out end
  if bar then
    bar.casualNear:SetShown(st.kind=="events"); bar.casualMine:SetShown(st.kind=="events")
    if st.kind=="events" then
      bar.casualNear:SetLabel("Type")
      bar.casualNear.tip=st.eventType and ns.EVENT_TYPES[st.eventType] or "All activity types"
      bar.casualNear:SetOn(st.eventType~=nil)
      bar.casualNear:SetScript("OnClick",function(self)
        local options={{label="All types",value="all"}}
        for _,kind in ipairs(ns.EVENT_TYPE_ORDER) do options[#options+1]={label=ns.EVENT_TYPES[kind],value=kind} end
        E.OpenMenu(self,options,st.eventType or "all",function(kind) st.eventType=kind~="all" and kind or nil; UI:Refresh() end)
      end)
      bar.casualAvailability:SetOn(st.eventDate~=nil)
    else bar.casualAvailability:SetOn(false) end
    bar.casualNew:SetLabel(st.kind=="events" and "New event" or (st.kind=="catchup" and "Review" or (st.kind=="quests" and "Sharing" or "Settings")))
  end
  if st.kind=="events" then
    for id,r in pairs(g.guildEvents) do
      local response=g.eventResponses[id.."\030"..ns.me]
      local myCalendar=ns.CalendarSignupSnapshot(id); myCalendar=myCalendar and myCalendar.rows[ns.me]
      if r.ends>ns.Now() and (not st.eventType or (r.kind or "other")==st.eventType)
        and (not st.eventDate or date("%Y-%m-%d",r.starts)==st.eventDate)
        and (not st.mine or r.who==ns.me or ((myCalendar or response) and (myCalendar or response).state~="declined")) and E.Match(q,r.title,r.note,r.zone,r.who,ns.EVENT_TYPES[r.kind or "other"]) then
        local localTime,server=ns.EventTimes(r.starts); local n=ns.EventCounts(id)
        out[#out+1]={key="event:"..id,title=ns.EVENT_TYPES[r.kind or "other"].." · "..r.title,sub="Local "..localTime.." · "..r.zone.." · levels "..(r.minLevel or 1).."–"..(r.maxLevel or 60),
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
  if kind=="events" then return (State().eventDate and ("Date: "..State().eventDate.." · Calendar > All dates to clear. ") or "Calendar selects a date; numbers show activities. ").."Local dates; open an activity for server time and signups."
  elseif kind=="quests" then return "Exact quest IDs match; phases and quest-chain eligibility can differ. Shared progress expires after three minutes."
  elseif kind=="catchup" then return "Latest relevant updates from data synced so far; active projects and upcoming events remain visible after review."
  elseif kind=="notifications" then return "Personal settings stay on this character. Quiet hours use your local clock; digests are read in Catch-up." end
end
local function RoleButtons(det,current,set,dungeon)
  local specs={}
  for _,v in ipairs(dungeon and {"t","h","d","g"} or {"g","c","m","t","h","d"}) do local role=v; specs[#specs+1]={ns.EVENT_ROLES[role],function() set(role) end} end
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
    local draft=det.eventFormDraft;det.eventFormDraft=nil
    local presets={dungeon={"Guild dungeon run",90,5},leveling={"Level together",60,5},quest={"Quest help",60,5},fishing={"Guild fishing trip",60,10},profession={"Profession help",60,5},farming={"Farm together",60,5},other={"Guild get-together",60,10}}
    local activityType=draft and draft.kind or (cur and cur.kind) or s.lastEventType or "leveling"
    if not presets[activityType] then activityType="other" end
    local preset=presets[activityType]
    local expanded=draft and draft.expanded or false
    local announceGuild=draft and draft.announceGuild or false
    local dungeon=cur and cur.dungeon
    if draft then dungeon=draft.dungeon end
    local defaultZone=(GetZoneText and GetZoneText()) or ''
    det:Reset(nil,nil,cur and "Edit guild event" or "New guild event","Dates use your computer's local timezone")
    local typeLabel=det:Text("Type: "..ns.EVENT_TYPES[activityType],C.gold)
    local title,zone,note,when,duration,slots,low,high,summary
    local function UpdateLabels()
      typeLabel:SetText('Type: '..ns.EVENT_TYPES[activityType]..(dungeon and (' · '..dungeon) or ''))
      summary:SetText(duration:GetText()..' minutes · '..slots:GetText()..' players · levels '..low:GetText()..'–'..high:GetText())
      det.casualDraft=true
    end
    local function ApplyType(value)
      local old,new=presets[activityType],presets[value]
      if not cur then
        if title:GetText()==old[1] then title:SetText(new[1]) end
        if duration:GetText()==tostring(old[2]) then duration:SetText(tostring(new[2])) end
        if slots:GetText()==tostring(old[3]) then slots:SetText(tostring(new[3])) end
      end
      if value~='dungeon' then dungeon=nil end
      activityType=value
      UpdateLabels()
    end
    local function ApplyDungeon(name)
      local old=dungeons[dungeon]
      local choice=dungeons[name]
      ApplyType('dungeon')
      if title:GetText()=='' or title:GetText()==presets.dungeon[1] or title:GetText()==dungeon then title:SetText(name) end
      if zone:GetText()=='' or (not cur and zone:GetText()==defaultZone) or (old and zone:GetText()==old[2]) then zone:SetText(choice[2]) end
      if low:GetText()==tostring(old and old[3] or 1) and high:GetText()==tostring(old and old[4] or 60) then
        low:SetText(tostring(choice[3] or 1)); high:SetText(tostring(choice[4] or 60))
      end
      dungeon=name
      UpdateLabels()
    end
    det:Buttons({{"Choose type",function(self)
      local options={}
      for _,value in ipairs(ns.EVENT_TYPE_ORDER) do options[#options+1]={label=ns.EVENT_TYPES[value],value=value} end
      E.OpenMenu(self,options,activityType,ApplyType)
    end},{'Choose dungeon',function(self)
      local groups={}
      for i,group in ipairs(dungeonGroups) do groups[#groups+1]={label=group.label,value=i} end
      E.OpenMenu(self,groups,nil,function(index)
        local entries={}
        for _,entry in ipairs(dungeonGroups[index].entries) do
          entries[#entries+1]={label=entry[1],value=entry[1],right=entry[3] and (entry[3]..'–'..entry[4]) or nil}
        end
        E.OpenMenu(self,entries,dungeon,ApplyDungeon)
      end)
    end}})
    local values=draft and draft.values or {}
    title=det:Field("Title",values[1] or (cur and cur.title) or preset[1],160)
    zone=det:Field("Meet at",values[2] or (cur and cur.zone) or defaultZone,160)
    note=det:Field("Details",values[3] or (cur and cur.note) or "",160)
    when=det:Field("Local start",values[4] or date("%Y-%m-%d %H:%M",cur and cur.starts or ns.Now()+1800),160)
    local before=det.y
    duration=det:Field("Minutes",values[5] or tostring(cur and (cur.ends-cur.starts)/60 or preset[2]),60,true)
    slots=det:Field("Players",values[6] or tostring(cur and cur.slots or preset[3]),60,true)
    low=det:Field("Min level",values[7] or tostring(cur and cur.minLevel or 1),60,true)
    high=det:Field("Max level",values[8] or tostring(cur and cur.maxLevel or 60),60,true)
    if not expanded then
      for i=5,8 do det.pools.box[i]:Hide();det.pools.label[i]:Hide() end
      det.y=before
    end
    summary=det:Text(duration:GetText().." minutes · "..slots:GetText().." players · levels "..low:GetText().."–"..high:GetText(),C.muted)
    if dungeon then UpdateLabels() end
    det:Buttons({{expanded and 'Hide group options' or 'Group options',function()
      local values={} for i=1,8 do values[i]=det.pools.box[i]:GetText() end
      det.eventFormDraft={values=values,kind=activityType,dungeon=dungeon,expanded=not expanded,announceGuild=announceGuild};UI:FillDetails()
    end}})
    local function Soon(minutes) when:SetText(date('%Y-%m-%d %H:%M',ns.Now()+minutes*60));det.casualDraft=true end
    det:Buttons({{'In 15 min',function() Soon(15) end},{'In 1 hour',function() Soon(60) end},{'Next 7pm',function()
      local d=date('*t',ns.Now());d.hour=19;d.min=0;d.sec=0;d.isdst=nil
      local start=time(d);if start<=ns.Now()+60 then d.day=d.day+1;d.isdst=nil;start=time(d) end
      when:SetText(date('%Y-%m-%d %H:%M',start));det.casualDraft=true
    end}})
    det:Buttons({{"Pick date & time",function()
      local initial=when:GetText()
      ns.ShowActivityDatePicker(initial:sub(1,10),function(value)
        if det.kind=='eventform' and det.key==key then when:SetText(value); det.casualDraft=true end
      end,initial:match(' (%d%d:%d%d)$') or '19:00')
    end}})
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
    if not cur then
      local function ChatLabel() return announceGuild and 'Announce in guild chat: On' or 'Announce in guild chat: Off' end
      det:Buttons({{ChatLabel(),function(self)
        announceGuild=not announceGuild
        self:SetLabel(ChatLabel())
        self:SetOn(announceGuild)
      end,tip='Post the title and start time once when you create the event.'}})
    end
    local function SaveEvent(calendar)
      local start=ns.ParseEventLocal(when:GetText())
      if not start then return ns.Print("Enter a valid local date and time as YYYY-MM-DD HH:MM.") end
      local id=ns.SaveGuildEvent({title=title:GetText(),zone=zone:GetText(),note=note:GetText(),starts=start,minutes=tonumber(duration:GetText()),slots=tonumber(slots:GetText()),kind=activityType,dungeon=dungeon,minLevel=tonumber(low:GetText()),maxLevel=tonumber(high:GetText()),announceGuild=announceGuild},cur and key)
      if id then
        s.lastEventType=activityType; Open(calendar and "eventcalendar" or "event",id)
        if calendar then ns.PrepareWoWCalendar(id) end
      end
    end
    det:Buttons({{cur and "Save event" or "Create event",function() SaveEvent(false) end,accent=true}})
    if not cur then
      det:Buttons({{"Create + WoW calendar",function() SaveEvent(true) end}})
      det:Text("Create event saves to EPU only. Create + WoW calendar also prepares a calendar draft; review it and press WoW's Create button to publish.",C.muted)
    end
  elseif kind=="event" then
    local r=g.guildEvents[key]; if not r then UI:CloseDetails(); return true end
    local localTime,server=ns.EventTimes(r.starts)
    det:Reset(nil,nil,r.title,r.status=="cancelled" and "Cancelled" or (r.ends<=ns.Now() and "Ended" or "Guild event"))
    det:Text("Local: "..localTime.."\nServer (current offset): "..server,C.gold)
    det:Text(ns.EVENT_TYPES[r.kind or "other"].." · Suggested levels "..(r.minLevel or 1).."–"..(r.maxLevel or 60)..(r.dungeon and r.dungeon~=r.title and ("\nDungeon: "..r.dungeon) or "").."\nOrganiser: "..r.who.."\nMeet at: "..r.zone.."\nDuration: "..math.floor((r.ends-r.starts)/60).." minutes")
    det:Text(r.note)
    local n=ns.EventCounts(key)
    det:Text(n.going.." going / "..r.slots.." planned · "..n.tentative.." tentative")
    det:Text(n.t.." tank · "..n.h.." healer · "..n.d.." DPS\n"..n.g.." helper · "..n.c.." crafter · "..n.m.." mentor",C.muted)
    local snapshot=ns.CalendarSignupSnapshot(key)
    det:Text(snapshot and ("WoW signups refreshed "..math.floor(GetTime()-snapshot.at).."s ago. Calendar status takes priority; each member is counted once.") or "Showing EPU signups. Open the linked WoW event to refresh calendar attendees; snapshots expire after 3 minutes.",C.muted)
    for _,reply in ipairs(ns.EventResponses(key)) do
      local name=reply.who
      det:Text(name.." · "..reply.state.." · "..ns.EVENT_ROLES[reply.role].." · "..(reply.source or "EPU")..(reply.note~="" and ("\n"..reply.note) or ""))
      det:Buttons({{"Whisper",function() Whisper(name) end}})
    end
    det:Text("Signups show interest; the organiser confirms the group. No automatic invitations or attendance penalties.",C.muted)
    if r.status=="scheduled" and r.ends>ns.Now() then
      local cur=g.eventResponses[key.."\030"..ns.me]; local role=cur and cur.role or (r.kind=="dungeon" and "d" or "g")
      local status=det:Text("My role: "..ns.EVENT_ROLES[role],C.gold)
      RoleButtons(det,role,function(value) role=value; det.casualDraft=true; status:SetText("My role: "..ns.EVENT_ROLES[role]) end,r.kind=="dungeon")
      local note=det:Field("My note",cur and cur.note or "",160); note.onChange=function() det.casualDraft=true end
      local function Reply(state) if ns.RespondGuildEvent(key,state,role,note:GetText()) then UI:FillDetails() end end
      det:Buttons({{"Going",function() Reply("going") end,accent=true},{"Tentative",function() Reply("tentative") end},{"Can't make it",function() Reply("declined") end}})
      if ns.OpenCalendarMatches(key) then
        det:Text("Also update my own WoW signup (wait for calendar confirmation):",C.muted)
        local function Both(state) ns.CalendarRespond(key,state,role,note:GetText()); UI:FillDetails() end
        det:Buttons({{"Going in both",function() Both("going") end},{"Tentative in both",function() Both("tentative") end},{"Decline in both",function() Both("declined") end}})
      end
      det:Buttons({{"WoW calendar",function() Open("eventcalendar",key) end}})
      if r.who==ns.me and r.starts>ns.Now() then det:Buttons({{"Edit event",function() Open("eventform",key) end}}) end
      if r.who==ns.me or ns.IsTrusted(ns.me) then det:Buttons({{"Cancel event",function() ns.CancelGuildEvent(key); UI:FillDetails() end}}) end
    end
  elseif kind=="eventcalendar" then
    local r=g.guildEvents[key]; if not r then UI:CloseDetails(); return true end
    det:Reset(nil,nil,"WoW calendar",r.title)
    det:Text("EPU events are not automatically published to WoW's calendar. Organiser: "..r.who..".",C.gold)
    if ns.OpenCalendarMatches(key) then
      det:Text("Linked WoW event is open. Refresh its attendees below.")
    elseif r.status~="scheduled" or r.starts<=ns.Now() then
      det:Text("Draft preparation is available only for scheduled events that have not started.")
    elseif r.who~=ns.me then
      det:Text("Ask "..r.who.." to open this activity on that character, choose Prepare WoW draft, then press Create in WoW's calendar. Only the organising character can prepare the linked copy.")
    else
      det:Text("1. Choose Prepare WoW draft.\n2. Review it and press WoW's Create button.\n3. Keep the EPU marker in the description. Opening the calendar alone does not publish this activity.")
    end
    det:Text("Open the linked event and refresh attendees here. WoW status takes priority over EPU after refresh; roles/notes remain in EPU. Only your own response can be sent to both. Calendar approval, locks and permissions still apply.",C.muted)
    det:Text("Edits and cancellations are separate: update both calendars. An EPU title/time change stops matching until the WoW copy is corrected. No background calendar scanning or automatic publishing.",C.gold)
    det:Buttons({{"Open WoW calendar",function() ns.OpenWoWCalendar() end},{"Refresh open event",function()
      if ns.ReadOpenCalendarSignups() then Open("event",key) else ns.Print("Open this activity's linked guild event and wait for its attendee list to load.") end
    end}})
    if r.who==ns.me and r.status=="scheduled" and r.starts>ns.Now() then det:Buttons({{"Prepare WoW draft",function() ns.PrepareWoWCalendar(key) end}}) end
    local l,server=ns.EventTimes(r.starts)
    det:Text("Local: "..l.."\nServer: "..server)
    det:Field("Copy title",ns.EventCalendarTitle(r),160)
    det:Field("Copy details",ns.EventCalendarDescription(key,r),160)
    det:Text("If draft preparation is unavailable, create a Guild event manually and copy these fields. The creator, copied title and server date/time must match. WoW limits the copy to 31 title / 255 description characters; full details stay in EPU. Use Ctrl+A / Ctrl+C in each field.",C.muted)
  elseif kind=='guildinvite' then
    local r=g.inviteRequests[key]
    if not r or not ns.CanInviteGuild() then UI:CloseDetails(); return true end
    det:Reset(nil,nil,r.who,'Discord guild invite request')
    det:Text('Requested by: '..r.requester..'\nReceived: '..date('%Y-%m-%d %H:%M',r.posted))
    local _,presence,source=ns.GuildInvitePresence(r.who)
    det:Text(presence..' · '..source,C.gold)
    det:Text('Add to Friends to receive login updates. Unknown means the game has not provided a current result. Online sightings expire after two minutes; another member’s report is advisory.',C.muted)
    det:Text('Confirm the character name before inviting. A request is not proof of character ownership. The game decides whether the name is valid and the player can join.',C.muted)
    local command=det:Field('Copy invite','/ginvite '..r.who,174)
    command:SetCursorPosition(0)
    local outcome=ns.GuildInviteOutcome(key)
    if outcome then det:Text((outcome.phase=='joined' and 'Joined the guild' or 'Invite sent')..' · reported by '..outcome.by..' at '..date('%m-%d %H:%M',outcome.t),C.gold)
    else det:Text('No game-confirmed invitation recorded yet.',C.muted) end
    if ns.ActiveGuildInvite(r) then
      det:Buttons({{'Open invite in chat',function() ns.PrepareGuildInvite(key) end,accent=true,tip='Review the /ginvite command in chat, then press Enter to send.'},{'Add to Friends',function() ns.TrackGuildInvite(key) end}})
    else det:Text(ns.Member(r.who) and 'This character is already in the guild.' or 'This request was withdrawn or expired.',C.gold) end
    det:Buttons({{'Dismiss for me',function()
      s.inviteDismissed=s.inviteDismissed or {}; s.inviteDismissed[key]=r.who; UI:CloseDetails(); UI:Refresh()
    end}})
  elseif kind=='invitehelp' then
    det:Reset(nil,nil,'Guild invite requests','From #guild-invite-requests')
    det:Text('Use /guildinvite in Discord and enter the required first and last name, or post a standalone line:\nCharacter: Donaga Gaelige')
    det:Text('Only that explicit format is imported. Conversation, code examples, quotes and bot messages are ignored. Duplicate active names are suppressed. Editing/deleting an accepted message updates/withdraws its request after another import.')
    det:Text('The companion officer must log in or /reload to load new requests. Online addon users then receive them through guild sync. Only characters with the game’s guild-invite permission receive alerts. Notifications respect quiet hours and personal settings. No automatic invites.',C.muted)
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
      det:Buttons({{s.eventBubble==false and 'Show Events bubble' or 'Hide Events bubble',function(self)
        s.eventBubble=s.eventBubble==false
        self:SetLabel(s.eventBubble and 'Hide Events bubble' or 'Show Events bubble')
        ns.RefreshEventBubble()
      end}})
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
