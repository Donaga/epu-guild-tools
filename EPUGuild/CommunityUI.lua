local ADDON,ns=...
local E,UI,C
local DAY=86400
local eventIcons={
  dungeon="Interface\\Icons\\INV_Misc_Key_03",
  leveling="Interface\\Icons\\INV_Misc_Map_01",
  quest="Interface\\Icons\\INV_Misc_Note_01",
  fishing="Interface\\Icons\\Trade_Fishing",
  profession="Interface\\Icons\\Trade_BlackSmithing",
  farming="Interface\\Icons\\Trade_Mining",
  other="Interface\\Icons\\INV_Misc_GroupLooking",
}
local memberTools={
  {key="guides", title="Your guides", hint="Find leveling, talent, and profession guides for your character.",
    icon="Interface\\Icons\\INV_Misc_Book_09"},
  {key="quests", title="Quests", hint="Your quests and the guildmates on them (also in the sidebar).",
    icon="Interface\\Icons\\INV_Misc_Map_01", open=function() ns.OpenMemberTools("quests") end},
  {key="catchup", title="Catch-up", hint="Review missed guild updates and notifications.",
    icon="Interface\\Icons\\INV_Scroll_03"},
  {key="notifications", title="Notifications", hint="Set alerts, sounds, and quiet hours.",
    icon="Interface\\Icons\\INV_Misc_PocketWatch_01"},
  -- Pop-up windows that used to open only by slash command (/epu zone,
  -- /epu leveling, /epu gold). Each tile hides itself if its file isn't loaded.
  {key="zoneguide", title="Zone guide", hint="Dungeons, flight paths, vendors, trainers, fishing and quests for any zone (/epu zone).",
    icon="Interface\\Icons\\INV_Misc_Map02", available=function() return ns.OpenZoneGuide~=nil end,
    open=function() ns.OpenZoneGuide() end},
  {key="leveling", title="Leveling and dungeons", hint="Leveling advisor, dungeon readiness, gear by level, writs, camping blueprints and raid prep (/epu leveling).",
    icon="Interface\\Icons\\INV_Sword_04", available=function() return ns.OpenLevelingTools~=nil end,
    open=function() ns.OpenLevelingTools("advisor") end},
  {key="gold", title="Gold and budget", hint="Where your gold comes from and goes, by category, with a budget (/epu gold).",
    icon="Interface\\Icons\\INV_Misc_Coin_01", available=function() return ns.OpenGoldTracker~=nil end,
    open=function() ns.OpenGoldTracker() end},
  -- Personal trackers (PersonalTrackers.lua); hidden if that file isn't loaded.
  {key="trackers", title="Personal trackers", hint="Lockouts and profession cooldowns across your alts, farming sessions, consumables, rep and PvP (/epu trackers).",
    icon="Interface\\Icons\\INV_Misc_PocketWatch_02", available=function() return ns.OpenPersonalTrackers~=nil end,
    open=function() ns.OpenPersonalTrackers() end},
  -- Spell rank checker (SpellRanks.lua); hidden if that file isn't loaded.
  {key="spellranks", title="Spell ranks", hint="Find action bar buttons still on an old spell rank after training, and update them (/epu ranks).",
    icon="Interface\\Icons\\INV_Misc_Book_11", available=function() return ns.OpenSpellRanks~=nil end,
    open=function() ns.OpenSpellRanks() end},
  {key="chat", title="Chat history", hint="Whispers (and, if you choose, guild and officer chat) kept after a reload.",
    icon="Interface\\Icons\\INV_Letter_15", open=function() ns.ShowChatHistory() end},
  {key="market", title="Gathering market", hint="Compare gathering prices, craft profit at current prices, and cheap skill-ups.",
    icon="Interface\\Icons\\INV_Misc_Coin_02", open=function() ns.ShowGatheringMarket() end},
  {key="mats", title="Needed mats", hint="List the materials you need; guildmates see it on the item's tooltip before they vendor it.",
    icon="Interface\\Icons\\INV_Fabric_Linen_01", open=function() ns.ShowNeededMats() end},
}
local toolActions={guides="Settings",quests="Sharing",catchup="Review",notifications="Settings"}
local dungeonGroups={
  -- Classic ranges are the commonly suggested ones; treat them as a guide.
  {label='Classic · Early', entries={
    {'Ragefire Chasm','Orgrimmar',13,18}, {'The Deadmines','Westfall',17,26}, {'Wailing Caverns','The Barrens',17,24},
    {'Shadowfang Keep','Silverpine Forest',22,30}, {'Blackfathom Deeps','Ashenvale',24,32}, {'The Stockade','Stormwind City',24,32},
    {'Gnomeregan','Dun Morogh',29,38}, {'Razorfen Kraul','The Barrens',29,38},
  }},
  {label='Classic · Mid levels', entries={
    {'Scarlet Monastery: Graveyard','Tirisfal Glades',28,38}, {'Scarlet Monastery: Library','Tirisfal Glades',29,39},
    {'Scarlet Monastery: Armory','Tirisfal Glades',32,42}, {'Scarlet Monastery: Cathedral','Tirisfal Glades',35,45},
    {'Razorfen Downs','The Barrens',37,46}, {'Uldaman','Badlands',41,51}, {'Zul’Farrak','Tanaris',44,54}, {'Maraudon','Desolace',46,55},
    {'Sunken Temple','Swamp of Sorrows',50,56},
  }},
  {label='Classic · Late', entries={
    {'Blackrock Depths','Blackrock Mountain',52,60}, {'Lower Blackrock Spire','Blackrock Mountain',55,60},
    {'Upper Blackrock Spire','Blackrock Mountain',58,60}, {'Dire Maul: East','Feralas',55,60}, {'Dire Maul: North','Feralas',57,60},
    {'Dire Maul: West','Feralas',57,60}, {'Scholomance','Western Plaguelands',58,60},
    {'Stratholme: Main Gate','Eastern Plaguelands',58,60}, {'Stratholme: Service Gate','Eastern Plaguelands',58,60},
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
-- name, zone, min level, max level, raid size
local raidList={
  {'Zul’Gurub','Stranglethorn Vale',60,60,20}, {'Ruins of Ahn’Qiraj','Silithus',60,60,20},
  {'Molten Core','Blackrock Mountain',60,60,40}, {'Onyxia’s Lair','Dustwallow Marsh',60,60,40},
  {'Blackwing Lair','Blackrock Mountain',60,60,40}, {'Temple of Ahn’Qiraj','Silithus',60,60,40},
  {'Naxxramas','Eastern Plaguelands',60,60,40},
}
local dungeons={}
for _,group in ipairs(dungeonGroups) do
  for _,entry in ipairs(group.entries) do dungeons[entry[1]]=entry end
end
for _,entry in ipairs(raidList) do dungeons[entry[1]]=entry end
ns.RAIDS=raidList
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

function ns.OpenMemberTools(kind, guideScope)
  UI:Show()
  UI:CloseDetails()
  UI.search:SetText("")
  if kind=="quests" then return UI:SetView("quests") end
  UI.state.membertools.kind=kind
  UI.state.membertools.guideScope=guideScope
  UI:SetView("membertools")
end

function ns.InstallCommunityViews(views,env)
  E=env; UI=E.UI; C=E.C
  -- Quests: your quest log with the guildmates on each quest, and who is
  -- questing near you. Sharing which quests you have is on unless turned off.
  -- Chat: a small message center. Conversations on the left (guild and
  -- officer chat pinned on top when kept, then one per person you whispered),
  -- the open conversation on the right with a reply box.
  UI.state.chat={}
  views.chat={
    label="Chat",
    detailsWide=true,
    icon="Interface\\Icons\\INV_Letter_15",
    count=function() return ns.ChatUnread and (ns.ChatUnread()+ns.ChatUnreadGuild()) or 0 end,
    -- open on the latest conversation, like a messenger
    onSelect=function()
      UI.search:SetText("")
      UI:SetView("chat")
      if not (UI.details:IsShown() and (UI.details.kind=="chatwith" or UI.details.kind=="chatnew" or UI.details.kind=="chatsettings")) then
        local first=ns.ChatConversations()[1]
        if first then Open("chatwith","w:"..first.who) end
      end
    end,
    tools=function(bar)
      bar:Add(E.Btn(bar,"New message",100,22,"accent"),"right",function() Open("chatnew","new") end,
        "Start a whisper to a guildmate")
      bar:Add(E.Btn(bar,"Pop out",64,22),"right",function()
        local d=UI.details
        ns.OpenMessenger(d:IsShown() and d.kind=="chatwith" and d.key or nil)
      end,"Open a small chat window you can move, resize and minimize")
      bar:Add(E.Btn(bar,"Chat settings",100,22),"right",function() Open("chatsettings","all") end,
        "What to keep, showing the last hour after a reload, and clearing saved chat")
    end,
    rows=function(g,q)
      local out={}
      for _,ch in ipairs(ns.CHAT_GROUP_CHANNELS) do
        if ns.ChatKeep(ch) then
          local log=ns.ChatLog(ch); local e=log[#log]
          if E.Match(q,ns.CHAT_CHANNELS[ch].label,e and e.msg) then
            local n=ns.ChatUnreadFor(ch)
            out[#out+1]={key="chat:"..ch,title=ns.CHAT_CHANNELS[ch].label..(n>0 and (" |cff66a6ff("..n..")|r") or ""),
              icon=ns.CHAT_CHANNELS[ch].icon,
              sub=e and ((ns.Short and ns.Short(e.who) or e.who)..(e.sys and " " or ": ")..e.msg) or "Nothing yet",
              right=e and ((n>0 and ("|cff66a6ff"..n.." new|r · ") or "")..ns.ChatAgo(e.t)) or "",
              onClick=function() if ns.ChatFocus then ns.ChatFocus(nil) end; Open("chatwith",ch) end}
          end
        end
      end
      for _,c in ipairs(ns.ChatConversations()) do
        local e=c.last
        local short=ns.Short and ns.Short(c.who) or c.who
        if E.Match(q,c.who,e.msg) then
          local icon,coords
          if ns.roster[short] then icon,coords=ns.ClassIcon(ns.roster[short].classFile) end
          out[#out+1]={key="chat:w:"..c.who,title=short..(c.unread>0 and (" |cff4ade80("..c.unread..")|r") or ""),
            icon=icon or "Interface\\Icons\\INV_Letter_15", iconCoords=coords,
            dot=(ns.roster[short] or {}).online,
            sub=(e.out and "You: " or "")..e.msg,right=(c.unread>0 and ("|cff4ade80"..c.unread.." new|r · ") or "")..ns.ChatAgo(e.t),
            onClick=function() if ns.ChatFocus then ns.ChatFocus(nil) end; Open("chatwith","w:"..c.who) end,
            onRightClick=function(self) if ns.GuildmateMenu and ns.roster[short] then ns.GuildmateMenu(self,short) end end}
        end
      end
      -- search: every saved message that matches, newest first
      if q and #q>=2 and ns.SearchChat then
        local hits=ns.SearchChat(q,100)
        for i,h in ipairs(hits) do
          local e=h.e
          local who=ns.Short and ns.Short(e.who) or e.who
          local where=h.channel=="whisper" and ("Whisper · "..(e.out and ("You to "..who) or who)) or (ns.CHAT_CHANNELS[h.channel].label.." · "..(e.out and "You" or who))
          out[#out+1]={key="chatfind:"..i..":"..(e.t or 0),title=where,icon=ns.CHAT_CHANNELS[h.channel].icon or "Interface\\Icons\\INV_Letter_15",
            sub=e.msg,right=date("%d %b %H:%M",e.t),compact=true,
            onClick=function() ns.ChatFocus(h.key,e.t,q); Open("chatwith",h.key) end}
        end
      end
      return out
    end,
    empty="No conversations yet. Whispers show up here as they come in, or click New message.",
    init=nil,
    footer=function() return "Saved on this PC only, shared by all your characters here, and never sent to the guild. Keeps the last week." end,
  }
  ns.ChatView=views.chat
  UI.state.quests={}
  views.quests={
    label="Quests",
    icon="Interface\\Icons\\INV_Misc_Map_01",
    count=function()
      local n=0
      for name in pairs(ns.questLists or {}) do if ns.QuestNearby and ns.QuestNearby(name) and #ns.SharedQuestIDs(name)>0 then n=n+1 end end
      return n
    end,
    tools=function(bar)
      bar.questSharing=bar:Add(E.Btn(bar,"Sharing",80,22),"right",function() Open("questsettings","settings") end,
        "What guildmates can see about your quests")
      bar:Add(E.Btn(bar,"Ask for quest help",120,22,"accent"),"right",function() ns.OpenCreate("help") end,
        "Post a quest help request to the Groups page")
    end,
    rows=function(g,q) return ns.QuestPageRows(q) end,
    empty="Your quest log is empty. Pick up a quest and guildmates on it show up here.",
    footer=function()
      return ns.QuestListSharing() and "Sharing which quests you have and your zone with online guildmates. Click Sharing to turn it off."
        or "Quest sharing is off: guildmates won't see your quests and you won't get Same quest nearby heads-ups."
    end,
  }
  UI.state.membertools={kind="all"}
  views.membertools={
    label="Member tools",
    icon="Interface\\Icons\\INV_Misc_Book_09",
    onSelect=function() ns.OpenMemberTools("all") end,
    tools=function(bar)
      bar.allTools=bar:Add(E.Btn(bar,"All tools",80,22),"left",function() ns.OpenMemberTools("all") end)
      bar.toolTitle=ns.InterfaceFont(bar,12,C.muted)
      bar.toolTitle:SetPoint("LEFT",bar.allTools,"RIGHT",10,0)
      bar.toolAction=bar:Add(E.Btn(bar,"Settings",80,22),"right",function()
        ns.CommunityNewAction(UI.state.membertools.kind)
      end)
      bar.saved=bar:Add(E.Btn(bar,"Saved",50,22),"right",function()
        local state=ns.GuideState()
        state.savedOnly=not state.savedOnly
        UI:Refresh()
      end)
      bar.allGuides=bar:Add(E.Btn(bar,"All guides",74,22),"right",function() ns.OpenMemberTools("guides") end)
    end,
    rows=function(g,q)
      local state=UI.state.membertools
      local bar=views.membertools.bar
      local isHome=state.kind=="all"
      bar.allTools:SetShown(not isHome)
      bar.toolTitle:SetShown(not isHome)
      bar.toolAction:SetShown(not isHome)
      bar.saved:SetShown(state.kind=="guides")
      bar.allGuides:SetShown(state.kind=="guides" and state.guideScope=="profession")
      if isHome then
        local rows={}
        for _,tool in ipairs(memberTools) do
          if (not tool.available or tool.available()) and E.Match(q,tool.title,tool.hint) then
            local key=tool.key
            rows[#rows+1]={key=key,title=tool.title,sub=tool.hint,icon=tool.icon,right="Open",
              onClick=tool.open or function() ns.OpenMemberTools(key) end}
          end
        end
        return rows
      end
      for _,tool in ipairs(memberTools) do
        if tool.key==state.kind then bar.toolTitle:SetText(tool.title); break end
      end
      bar.toolAction:SetLabel(toolActions[state.kind])
      if state.kind=="guides" then
        if state.guideScope=="profession" then bar.toolTitle:SetText("Profession guides") end
        bar.saved:SetOn(ns.GuideState().savedOnly==true)
      end
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
    picker=ns.InterfaceWindow("EPUGuildActivityDatePicker",UI,"Activity calendar",420,350)
    picker.heading=ns.InterfaceFont(picker,14,C.white)
    picker.heading:SetPoint("TOP",0,-43)
    picker.days={}
    for i,name in ipairs({"Sun","Mon","Tue","Wed","Thu","Fri","Sat"}) do
      local label=ns.InterfaceFont(picker,11,C.muted)
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
    local prev=E.Btn(picker,"<",32,22); prev:SetPoint("TOPLEFT",12,-37); prev:SetScript("OnClick",function() Move(-1) end)
    local next=E.Btn(picker,">",32,22); next:SetPoint("TOPRIGHT",-12,-37); next:SetScript("OnClick",function() Move(1) end)
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
    picker.timeText=ns.InterfaceFont(picker,12,C.text)
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
    picker.hint=ns.InterfaceFont(picker,11,C.muted)
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
      self.apply.disabledTip='Choose a valid future start time within 28 days.'
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
function ns.CommunityFormKind(kind) return kind=="eventform" or kind=="questsettings" or kind=="noticeform" or kind=="runform" end
function ns.CommunityNewAction(kind)
  if kind=="all" or kind=="dungeon" or kind=="dungeons" then ns.OpenCreate("group")
  elseif kind=="runs" then ns.OpenCreate("group","today")
  elseif kind=="events" then ns.OpenCreate("event")
  elseif kind=="help" then ns.OpenCreate("help")
  elseif kind=="helpers" then ns.OpenCreate("helper")
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
  if st.kind=="runs" then return ns.RunRequestRows(g,q,st,bar) end
  if st.kind=="dungeons" then return ns.DungeonCatalogRows(g,q,st,bar) end
  if st.kind~="events" and not toolActions[st.kind] then
    if bar then bar.casualNew:SetLabel("New / edit") end
    return
  end
  local s,since=ns.CommunityState(); local out={}
  if not s then return out end
  if bar then
    bar.casualNear:SetShown(st.kind=="events"); bar.casualMine:SetShown(st.kind=="events")
    if st.kind=="events" then
      bar.casualNear:SetLabel("Event type")
      bar.casualNear.tip=st.eventType and ns.EVENT_TYPES[st.eventType] or "All activity types"
      bar.casualNear:SetOn(st.eventType~=nil)
      bar.casualNear:SetScript("OnClick",function(self)
        local options={{label="All types",value="all"}}
        for _,kind in ipairs(ns.EVENT_TYPE_ORDER) do options[#options+1]={label=ns.EVENT_TYPES[kind],value=kind,icon=eventIcons[kind]} end
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
        out[#out+1]={key="event:"..id,icon=eventIcons[r.kind or "other"],title=ns.EVENT_TYPES[r.kind or "other"].." · "..r.title,sub="Local "..localTime.." · "..r.zone.." · levels "..(r.minLevel or 1).."–"..(r.maxLevel or 60),
          right=r.status=="cancelled" and "Cancelled" or (n.going.." going · "..n.tentative.." tentative"),at=r.starts,onClick=function() Open("event",id) end}
      end
    end
    table.sort(out,function(a,b) if a.at~=b.at then return a.at<b.at end return a.key<b.key end)
  elseif st.kind=="quests" then
    out[1]={key="questsettings",title="Same quest nearby: "..(ns.QuestListSharing() and "on" or "off").." · Progress sharing: "..(s.shareQuests and "on" or "off"),
      sub="Guildmates in your zone on the same quest get a heads-up. Click to change what you share.",onClick=function() Open("questsettings","settings") end}
    local quests,reason=ns.CurrentQuests(); local rows={}
    ns.ExpireQuestMatches()
    for id,r in pairs(quests) do
      if E.Match(q,r.title,r.progress) then
        local count=#ns.QuestMatches(id,quests)
        rows[#rows+1]={key="quest:"..id,title=r.title,sub=r.progress..(s.selectedQuests[id] and " · Progress shared" or ""),
          right=count==0 and "no one yet" or (count==1 and "1 guildmate" or (count.." guildmates")),onClick=function() Open("questmatch",id) end}
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
  if kind=="runs" then return "Ask for a dungeon run and the times that suit you; guildmates mark the times they can make. Times show in your local time." end
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
  if (kind=="runform" or kind=="run") and ns.FillRunDetails then return ns.FillRunDetails(kind,key,det) end
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
    if not cur and ns.CreateSwitcher then ns.CreateSwitcher(det,"event") end
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
      for _,value in ipairs(ns.EVENT_TYPE_ORDER) do options[#options+1]={label=ns.EVENT_TYPES[value],value=value,icon=eventIcons[value]} end
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
    local roleSlots={}
    if expanded then
      for i,role in ipairs({"t","h","d"}) do
        local count=cur and cur.places and cur.places[role]
        roleSlots[i]=det:Field(ns.EVENT_ROLES[role].." slots",values[i+8] or (count and tostring(count) or ""),60,true)
      end
      det:Text("For a dungeon waitlist, fill all three role counts. They must add up to Players.",C.muted)
    end
    if not expanded then
      for i=5,8 do det.pools.box[i]:Hide();det.pools.label[i]:Hide() end
      det.y=before
    end
    summary=det:Text(duration:GetText().." minutes · "..slots:GetText().." players · levels "..low:GetText().."–"..high:GetText(),C.muted)
    if dungeon then UpdateLabels() end
    det:Buttons({{expanded and 'Hide group options' or 'Group options',function()
      local previous=values
      local values={} for i=1,8 do values[i]=det.pools.box[i]:GetText() end
      for i=1,3 do values[i+8]=roleSlots[i] and roleSlots[i]:GetText() or previous[i+8] end
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
      local places
      if activityType=="dungeon" then
        local counts={}
        for i=1,3 do counts[i]=roleSlots[i] and roleSlots[i]:GetText() or values[i+8] or "" end
        if counts[1]~="" or counts[2]~="" or counts[3]~="" then
          places={t=tonumber(counts[1]),h=tonumber(counts[2]),d=tonumber(counts[3])}
          if not places.t or not places.h or not places.d or places.t+places.h+places.d~=tonumber(slots:GetText()) then
            return ns.Print("Tank, Healer and DPS slots must add up to Players.")
          end
        elseif expanded or values[9]~=nil then
          places=false
        end
      end
      local id=ns.SaveGuildEvent({title=title:GetText(),zone=zone:GetText(),note=note:GetText(),starts=start,minutes=tonumber(duration:GetText()),slots=tonumber(slots:GetText()),kind=activityType,dungeon=dungeon,minLevel=tonumber(low:GetText()),maxLevel=tonumber(high:GetText()),announceGuild=announceGuild,places=places},cur and key)
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
    if r.note~="" then det:Text(r.note) end
    local n=ns.EventCounts(key)
    det:Text(n.going.." going / "..r.slots.." planned · "..n.tentative.." tentative")
    det:Text(n.t.." tank · "..n.h.." healer · "..n.d.." DPS\n"..n.g.." helper · "..n.c.." crafter · "..n.m.." mentor",C.muted)
    if r.places then
      det:Text("Group slots · "..r.places.t.." tank · "..r.places.h.." healer · "..r.places.d.." DPS",C.gold)
    end
    local replies=ns.EventResponses(key)
    local responseLabels={going="Going",tentative="Tentative",declined="Can't make it"}
    if r.status=="scheduled" and r.ends>ns.Now() then
      local cur=g.eventResponses[key.."\030"..ns.me]; local role=cur and cur.role or (r.kind=="dungeon" and "d" or "g")
      det:Section("Your response")
      if cur then det:Text(ns.EventPlaceStatus(r,cur) or responseLabels[cur.state],C.muted) end
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
    end
    det:Section("Signups ("..#replies..")")
    local snapshot=ns.CalendarSignupSnapshot(key)
    if snapshot then
      det:Text("WoW calendar synced "..math.floor(GetTime()-snapshot.at).."s ago. One signup per member.",C.muted)
    end
    if #replies==0 then det:Text("No signups yet.",C.muted) end
    for _,reply in ipairs(replies) do
      local name=reply.who
      local signup=g.eventResponses[key.."\030"..name]
      local place=reply.state=="going" and signup and ns.EventPlaceStatus(r,signup)
      det:Text(name.." · "..(place or responseLabels[reply.state] or reply.state).." · "..ns.EVENT_ROLES[reply.role].." · "..(reply.source or "EPU"),
        place=="Confirmed" and C.green or place=="Waitlist" and C.gold or C.text)
      if reply.note~="" then det:Text(reply.note,C.muted) end
      local buttons={{"Whisper",function() Whisper(name) end}}
      if place and r.who==ns.me and r.status=="scheduled" and r.ends>ns.Now() then
        buttons[#buttons+1]={place=="Confirmed" and "Release place" or "Confirm place",function()
          if ns.ConfirmEventPlace(key,name,place~="Confirmed") then UI:FillDetails() end
        end}
      end
      det:Buttons(buttons)
    end
    if r.status=="scheduled" and r.ends>ns.Now() then
      det:Section((r.who==ns.me or ns.IsTrusted(ns.me)) and "Manage event" or "Calendar")
      det:Buttons({{"WoW calendar",function() Open("eventcalendar",key) end}})
      if r.who==ns.me and r.starts>ns.Now() then det:Buttons({{"Edit event",function() Open("eventform",key) end}}) end
      if r.who==ns.me then
        det:Buttons({{"Repeat weekly",function(self)
          E.OpenMenu(self,{{label="1 more week",value=1},{label="2 more weeks",value=2},{label="3 more weeks",value=3}},
            nil,function(weeks) ns.RepeatGuildEventWeekly(key,weeks); UI:FillDetails() end)
        end}})
      end
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
    det:Reset(nil,nil,"Quest sharing","What guildmates can see about your quests")
    det:Section("Same quest nearby")
    det:Text("Shares which quests are in your log and the zone you're in, so a guildmate in the same zone on the same quest gets a heads-up, and so do you. Nothing is saved or sent to Discord.")
    det:Buttons({{(ns.QuestListSharing() and "[x] " or "[ ] ").."Tell nearby guildmates when we share a quest",function()
      ns.SetQuestListSharing(not ns.QuestListSharing()); UI:FillDetails() end,accent=true}})
    det:Text("Heads-ups follow your notification settings (Same quest nearby) and wait until combat ends.",C.muted)
    det:Section("Progress sharing (optional)")
    local n=0 for _ in pairs(s.selectedQuests) do n=n+1 end
    det:Text(n.." quest(s) selected. Select quests from Quest matching, then enable sharing. Only their IDs, titles and objective progress are sent.")
    det:Text("Other members' progress is kept only in memory and expires after three minutes. No quest history is sent to Discord. Exact IDs match; different phases or chain requirements may still prevent playing together.",C.muted)
    det:Buttons({{s.shareQuests and "Stop sharing progress" or "Share progress on selected quests",function() ns.SetQuestSharing(not s.shareQuests); UI:FillDetails() end}})
  elseif kind=="questmatch" then
    local r=ns.CurrentQuests()[tonumber(key)]
    if not r then det:Reset(nil,nil,"Quest unavailable","It may have been completed or abandoned"); return true end
    key=tonumber(key)
    det:Reset(r.group and "Interface\\Icons\\INV_Misc_GroupNeedMore" or "Interface\\Icons\\INV_Misc_Note_02",nil,r.title,r.progress..(r.group and (" · group quest ("..r.group..")") or ""))
    local questTitle=r.title
    det:Buttons({{"Ask for help with this",function() ns.OpenCreate("help",{title=questTitle}) end,accent=r.group~=nil,
      tip="Posts a quest help request on the Groups page with this quest filled in."}})
    local selected=s.selectedQuests[key]
    det:Section("Guildmates on this quest")
    local matches=ns.QuestMatches(key)
    if #matches==0 then det:Text("No online guildmates have this quest right now. They need EPU 0.27.1 or newer, and it can take a minute to show up.",C.muted) end
    for _,match in ipairs(matches) do
      local name=match.who
      local near=ns.QuestNearby and ns.QuestNearby(name)
      det:Text(name..(near and " |cff4ade80· nearby|r" or "").."\n"..match.quest.progress.." · updated "..math.floor(GetTime()-match.quest.at).."s ago")
      det:Buttons({{"Whisper",function() Whisper(name) end},{"Invite",function()
        local invite=(C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit; if invite then invite(name) end end}})
    end
    det:Section("Share my progress (optional)")
    det:Text(selected and (s.shareQuests and "Guildmates see your objective progress on this quest." or "Picked, but progress sharing is off.")
      or "Guildmates see that you have this quest. Pick it to also show your objective progress (up to eight quests).",C.muted)
    det:Buttons({{selected and "Stop showing progress" or "Show my progress",function()
      ns.SelectSharedQuest(key,not selected)
      if not selected and not s.shareQuests then ns.SetQuestSharing(true) end
      UI:FillDetails() end}})
    det:Text("Check phases and quest-chain steps before travelling.",C.muted)
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
      det:Buttons({{s.eventBubble==false and 'Show Events and actions bubble' or 'Hide Events and actions bubble',function(self)
        s.eventBubble=s.eventBubble==false
        self:SetLabel(s.eventBubble and 'Hide Events and actions bubble' or 'Show Events and actions bubble')
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

---------------------------------------------------------------------------
-- Run requests board and forms
---------------------------------------------------------------------------
ns.DUNGEON_GROUPS=dungeonGroups
function ns.DungeonRange(name)
  local d=dungeons[name]
  return d and d[3] and {d[3],d[4]} or nil
end
local runIcon="Interface\\Icons\\INV_Misc_Key_14"
local runDrafts,interestDrafts={},{}
local SLOT=1800
local function Clock(epoch)
  local h,m=tonumber(date("%H",epoch)),date("%M",epoch)
  return ((h+11)%12+1)..":"..m.." "..(h<12 and "AM" or "PM")
end
local function DayStart(offset)
  local d=date("*t",ns.Now()); d.day=d.day+offset; d.hour=0; d.min=0; d.sec=0; d.isdst=nil
  return time(d)
end
local function DayLabel(epoch)
  local today=date("%Y-%m-%d",ns.Now())
  if date("%Y-%m-%d",epoch)==today then return "Today" end
  if date("%Y-%m-%d",epoch)==date("%Y-%m-%d",DayStart(1)) then return "Tomorrow" end
  return date("%a %b ",epoch)..tonumber(date("%d",epoch))
end
function ns.RunRangeText(s,e)
  local endText=(date("%Y-%m-%d",e-1)~=date("%Y-%m-%d",s)) and (DayLabel(e).." "..Clock(e)) or Clock(e)
  return DayLabel(s).." "..Clock(s).."–"..endText
end
-- Moments on the 30-minute grid for one day: {epoch...} from start to midnight.
local function DayTimes(offset)
  local out={}
  local start,stop=DayStart(offset),DayStart(offset+1)
  local t=start
  while t<=stop do out[#out+1]=t; t=t+SLOT end
  return out
end
local function RoleText(roles) return roles.t.." tank · "..roles.h.." healer · "..roles.d.." DPS" end
local function WindowsText(w)
  local parts={}
  for _,x in ipairs(w or {}) do parts[#parts+1]=ns.RunRangeText(x.s,x.e) end
  return table.concat(parts,"; ")
end

function ns.RunRequestRows(g,q,st,bar)
  if bar then
    bar.casualNew:SetLabel("Request a run")
    bar.casualAvailability:Hide()
    bar.casualMine:SetShown(true); bar.casualNear:SetShown(true)
  end
  local out={}
  local lvl=(ns.roster[ns.me] or {}).level or 1
  for id,r in pairs(g.runRequests or {}) do
    local info=dungeons[r.dungeon]
    local mine=g.runInterest[id.."\030"..ns.me]
    local active=ns.RunActive(r)
    local scheduled=r.status=="scheduled" and r.event and g.guildEvents[r.event]
    if (active or (scheduled and scheduled.ends>ns.Now())) and ns.Member(r.who)
      and (not st.mine or r.who==ns.me or (mine and mine.state=="in"))
      and (not st.near or not info or not info[3] or (lvl>=info[3]-3 and lvl<=info[4]+3))
      and E.Match(q,r.dungeon,r.note,r.who,ns.RUN_PURPOSES[r.purpose]) then
      local n=#ns.RunInterested(id)+1
      local best=active and ns.RunBestTimes(id,1)[1]
      local first=r.windows[1]
      out[#out+1]={key="run:"..id,icon=runIcon,title=r.dungeon.." · "..ns.RUN_PURPOSES[r.purpose],
        sub=r.who.." · "..ns.RunRangeText(first.s,first.e)..(#r.windows>1 and (" +"..(#r.windows-1).." more") or "")
          ..(info and info[3] and (" · levels "..info[3].."–"..info[4]) or ""),
        right=scheduled and ("Scheduled "..DayLabel(scheduled.starts).." "..Clock(scheduled.starts))
          or (n.." in"..(best and #best.who>1 and (" · best "..DayLabel(best.s).." "..Clock(best.s)) or "")),
        at=first.s,onClick=function() Open("run",id) end}
    end
  end
  table.sort(out,function(a,b) if a.at~=b.at then return a.at<b.at end return a.key<b.key end)
  return out
end

local function ChooseDungeon(self,current,apply)
  local groups={}
  for i,group in ipairs(dungeonGroups) do groups[#groups+1]={label=group.label,value=i} end
  E.OpenMenu(self,groups,nil,function(index)
    local entries={}
    for _,entry in ipairs(dungeonGroups[index].entries) do
      entries[#entries+1]={label=entry[1],value=entry[1],right=entry[3] and (entry[3]..'–'..entry[4]) or nil}
    end
    E.OpenMenu(self,entries,current,apply)
  end)
end
local function TimeMenu(self,offset,current,after,before,apply)
  local options={}
  for _,t in ipairs(DayTimes(offset)) do
    if (not after or t>after) and (not before or t<before) and t+SLOT>ns.Now() then
      options[#options+1]={label=(t==DayStart(offset+1) and "Midnight" or Clock(t)),value=t}
    end
  end
  if #options==0 then return ns.Print("No times left on that day.") end
  E.OpenMenu(self,options,current,apply)
end
local function DefaultWindow(offset)
  local start=offset==0 and ns.RunSlot(ns.Now(),true) or DayStart(offset)+19*3600
  local stop=math.min(start+3*3600,DayStart(offset+1))
  if offset==0 and start>=DayStart(1) then return DefaultWindow(1) end
  return {day=offset,s=start,e=stop}
end
-- Quick time ranges for run requests (asked for by guildmates): one click
-- instead of setting From and To by hand. Today's ranges that are already
-- over are left out; one that has started begins at the next half hour.
local DAY_PARTS={{"Morning",8,12},{"Afternoon",12,17},{"Evening",18,22}}
local function DayPartButtons(day,cur_s,cur_e,apply)
  local specs={}
  for _,p in ipairs(DAY_PARTS) do
    local s0,e0=DayStart(day)+p[2]*3600,DayStart(day)+p[3]*3600
    if e0>ns.Now()+1800 then
      local s1=math.max(s0,day==0 and ns.RunSlot(ns.Now(),true) or s0)
      specs[#specs+1]={p[1],function() apply(s1,e0) end,on=cur_s==s1 and cur_e==e0,
        tip="Set the time to "..p[1]:lower()..", "..Clock(s1).." to "..Clock(e0)}
    end
  end
  return specs
end
ns.RunDayParts=DAY_PARTS
local function OffsetOf(epoch)
  for i=0,7 do if epoch>=DayStart(i) and epoch<DayStart(i+1) then return i end end
  return 0
end

function ns.FillRunDetails(kind,key,det)
  local g=ns.CasualStore(); if not g then return false end
  if kind=="runform" then
    local cur=key~="new" and g.runRequests[key]
    if cur and cur.who~=ns.me then UI:CloseDetails(); return true end
    local d=runDrafts[key]
    if not d then
      d={dungeon=cur and cur.dungeon,purpose=cur and cur.purpose or "e",note=cur and cur.note or "",
        role=cur and cur.role or (((ns.ProfileOf(ns.me) or {}).roles or "d"):match("[thd]") or "d"),windows={}}
      for _,x in ipairs(cur and cur.windows or {}) do d.windows[#d.windows+1]={day=OffsetOf(x.s),s=x.s,e=x.e} end
      if #d.windows==0 then d.windows[1]=DefaultWindow(0) end
      runDrafts[key]=d
    end
    local function Again() det.casualDraft=true; UI:FillDetails() end
    det:Reset(runIcon,nil,cur and "Edit run request" or "Request a dungeon run","Times are in your local time")
    det:Section("Dungeon")
    local info=d.dungeon and dungeons[d.dungeon]
    det:Buttons({{d.dungeon or "Choose dungeon",function(self) ChooseDungeon(self,d.dungeon,function(name) d.dungeon=name; Again() end) end,accent=not d.dungeon}})
    if info then det:Text(info[2]..(info[3] and (" · suggested levels "..info[3].."–"..info[4]) or ""),C.muted) end
    det:Section("Why")
    local why={}
    for _,p in ipairs(ns.RUN_PURPOSE_ORDER) do
      why[#why+1]={ns.RUN_PURPOSES[p],function() d.purpose=p; Again() end,on=d.purpose==p}
    end
    det:Buttons(why)
    det:Section("My role")
    local roles={}
    for _,role in ipairs({"t","h","d"}) do roles[#roles+1]={ns.EVENT_ROLES[role],function() d.role=role; Again() end,on=d.role==role} end
    det:Buttons(roles)
    det:Section("When (up to three)")
    for i,w in ipairs(d.windows) do
      det:Buttons({
        {DayLabel(DayStart(w.day)),function(self)
          local options={}
          for o=0,7 do options[#options+1]={label=DayLabel(DayStart(o)),value=o} end
          E.OpenMenu(self,options,w.day,function(o) d.windows[i]=DefaultWindow(o); Again() end)
        end},
        {"From "..Clock(w.s),function(self) TimeMenu(self,w.day,w.s,nil,w.e,function(t) w.s=t; Again() end) end},
        {"To "..(w.e==DayStart(w.day+1) and "midnight" or Clock(w.e)),function(self)
          TimeMenu(self,w.day,w.e,w.s,nil,function(t) w.e=t; Again() end)
        end},
        #d.windows>1 and {"Remove",function() table.remove(d.windows,i); Again() end} or nil,
      })
      local parts=DayPartButtons(w.day,w.s,w.e,function(a,b) w.s,w.e=a,b; Again() end)
      if #parts>0 then det:Buttons(parts) end
    end
    if #d.windows<3 then
      det:Buttons({{"Add another day",function()
        local last=d.windows[#d.windows]
        local o=math.min(7,(last and last.day or -1)+1)
        d.windows[#d.windows+1]=DefaultWindow(o)
        Again()
      end}})
    end
    local note=det:Field("Notes",d.note,160); note.onChange=function() d.note=note:GetText(); det.casualDraft=true end
    det:Text("Guildmates see these times in their own time zone and tick the ones that work for them.",C.muted)
    det:Buttons({{cur and "Save" or "Post request",function()
      if not d.dungeon then return ns.Print("Choose a dungeon first.") end
      d.note=note:GetText()
      local id=ns.SaveRunRequest({dungeon=d.dungeon,purpose=d.purpose,role=d.role,note=d.note,windows=d.windows},cur and key)
      if id then runDrafts[key]=nil; Open("run",id) end
    end,accent=true},{"Cancel",function() runDrafts[key]=nil; UI:CloseDetails() end}})
    return true
  end
  -- kind == "run"
  local r=g.runRequests[key]; if not r then UI:CloseDetails(); return true end
  local info=dungeons[r.dungeon]
  local active=ns.RunActive(r)
  local scheduled=r.status=="scheduled" and r.event and g.guildEvents[r.event]
  det:Reset(runIcon,nil,r.dungeon,ns.RUN_PURPOSES[r.purpose].." · asked by "..r.who)
  if info then det:Text(info[2]..(info[3] and (" · suggested levels "..info[3].."–"..info[4]) or ""),C.muted) end
  if r.note~="" then det:Text(r.note) end
  det:Text(r.who.." ("..ns.EVENT_ROLES[r.role]..") can do: "..WindowsText(r.windows))
  if scheduled then
    det:Text("Scheduled for "..DayLabel(scheduled.starts).." "..Clock(scheduled.starts)..".",C.green)
    det:Buttons({{"Open event",function() Open("event",r.event) end,accent=true}})
  elseif not active then
    det:Text(r.status=="closed" and "This request was closed." or "These times have passed.",C.muted)
  end
  local mayManage=r.who==ns.me or ns.IsTrusted(ns.me)
  if active then
    det:Section("Best times")
    local best=ns.RunBestTimes(key,3)
    if #best==0 then det:Text("No times left.",C.muted) end
    for _,b in ipairs(best) do
      det:Text(ns.RunRangeText(b.s,b.e).." · "..#b.who.." "..(#b.who==1 and "person" or "people").." ("..RoleText(b.roles)..")",#b.who>1 and C.gold or C.text)
      det:Text(table.concat(b.who,", "),C.muted)
      if mayManage then
        det:Buttons({{"Schedule "..DayLabel(b.s).." "..Clock(b.s),function()
          local id=ns.ScheduleRunRequest(key,b.s,90,info)
          if id then Open("event",id) end
        end,tip="Creates a 90-minute guild event. Everyone interested who picked this time is signed up automatically."}})
      end
    end
  end
  local interested=ns.RunInterested(key)
  det:Section("Interested ("..(#interested+1)..")")
  det:Text(r.who.." · "..ns.EVENT_ROLES[r.role].." · asked for the run",C.muted)
  for _,x in ipairs(interested) do
    det:Text(x.who.." · "..ns.EVENT_ROLES[x.role].." · "..WindowsText(x.windows))
    if x.note~="" then det:Text(x.note,C.muted) end
  end
  if active and r.who~=ns.me then
    local cur=g.runInterest[key.."\030"..ns.me]
    local d=interestDrafts[key]
    if not d then
      d={role=cur and cur.role or (((ns.ProfileOf(ns.me) or {}).roles or "d"):match("[thd]") or "d"),note=cur and cur.note or "",windows={}}
      for i,w in ipairs(r.windows) do
        local mine
        for _,x in ipairs(cur and cur.state=="in" and cur.windows or {}) do
          if x.s<w.e and x.e>w.s then mine={s=math.max(x.s,w.s),e=math.min(x.e,w.e)} break end
        end
        d.windows[i]={on=(not cur or cur.state~="in") or mine~=nil,s=mine and mine.s or math.max(w.s,ns.RunSlot(ns.Now())),e=mine and mine.e or w.e}
      end
      interestDrafts[key]=d
    end
    local function Again() det.casualDraft=true; UI:FillDetails() end
    det:Section(cur and cur.state=="in" and "You're in. Change your times" or "Can you make it?")
    local roles={}
    for _,role in ipairs({"t","h","d"}) do roles[#roles+1]={ns.EVENT_ROLES[role],function() d.role=role; Again() end,on=d.role==role} end
    det:Buttons(roles)
    for i,w in ipairs(r.windows) do
      local x=d.windows[i]
      if w.e>ns.Now() then
        local offset=OffsetOf(w.s)
        det:Buttons({
          {(x.on and "[x] " or "[ ] ")..DayLabel(w.s),function() x.on=not x.on; Again() end,on=x.on},
          {"From "..Clock(x.s),function(self) TimeMenu(self,offset,x.s,w.s-1,math.min(x.e,w.e),function(t) x.s=t; Again() end) end},
          {"To "..Clock(x.e),function(self) TimeMenu(self,offset,x.e,math.max(x.s,w.s),w.e+1,function(t) x.e=t; Again() end) end},
        })
      end
    end
    local note=det:Field("Note",d.note,160); note.onChange=function() d.note=note:GetText(); det.casualDraft=true end
    local function Send(state)
      local windows={}
      for i,x in ipairs(d.windows) do if x.on and r.windows[i] and x.e>x.s then windows[#windows+1]={s=x.s,e=x.e} end end
      if ns.RespondRunRequest(key,state,d.role,windows,note:GetText()) then interestDrafts[key]=nil; UI:FillDetails() end
    end
    det:Buttons({{cur and cur.state=="in" and "Update" or "I'm in",function() Send("in") end,accent=true},
      cur and cur.state=="in" and {"Not anymore",function() Send("out") end} or nil})
  end
  det:Section("Contact")
  local buttons={}
  if r.who~=ns.me then buttons[#buttons+1]={"Whisper "..(r.who:match("^(%S+)") or r.who),function() Whisper(r.who) end} end
  if r.who==ns.me and active then buttons[#buttons+1]={"Edit",function() Open("runform",key) end} end
  if mayManage and active then buttons[#buttons+1]={"Close request",function() ns.CloseRunRequest(key); UI:FillDetails() end} end
  if #buttons>0 then det:Buttons(buttons) end
  return true
end

---------------------------------------------------------------------------
-- Groups: one place for everything people want to do together. "Now"
-- posts are quick dungeon posts (they expire); later days are run
-- requests; scheduled events show alongside.
---------------------------------------------------------------------------
local groupIcons={dungeon="Interface\\Icons\\INV_Misc_Key_03",help="Interface\\Icons\\INV_Misc_Note_01",
  run=runIcon,event="Interface\\Icons\\INV_Misc_GroupLooking"}
local function WhenOf(s,e)
  local now=ns.Now()
  if s<=now+3600 and (e or s)>now then return "now" end
  if date("%Y-%m-%d",s)==date("%Y-%m-%d",now) then return "today" end
  return "week"
end
function ns.ShowGroups(board)
  UI.state.activities.kind=board or "all"; UI.search:SetText(""); UI:SetView("activities")
end
local function ShowIn(kind,key) return function() ns.ShowGroups(); UI:OpenDetails(kind,key) end end
function ns.OpenGroups()
  local g=ns.CasualStore(); local out={}
  if not g then return out end
  local now=ns.Now()
  for id,r in pairs(g.activityPosts or {}) do
    if (r.kind=="dungeon" or r.kind=="help") and ns.ActiveActivity(r) then
      local n=ns.ActivityCounts(id)
      out[#out+1]={key="activity:"..id,who=r.who,when="now",at=r.created,icon=groupIcons[r.kind],place=r.kind=="dungeon" and r.title or nil,
        title=(r.kind=="help" and "Help: " or "")..r.title,
        sub=r.who.." · "..n.ready.."/"..r.slots.." ready · "..n.t.." tank · "..n.h.." healer · "..n.d.." DPS · "..math.max(0,math.ceil((r.expires-now)/60)).." min left",
        open=ShowIn("activity",id)}
    end
  end
  for id,r in pairs(g.runRequests or {}) do
    if ns.RunActive(r) then
      local first
      for _,w in ipairs(r.windows) do if w.e>now and (not first or w.s<first.s) then first=w end end
      local best=ns.RunBestTimes(id,1)[1]
      local n=#ns.RunInterested(id)+1
      out[#out+1]={key="run:"..id,who=r.who,when=WhenOf(first.s,first.e),at=first.s,icon=runIcon,place=r.dungeon,
        title=r.dungeon.." · "..ns.RUN_PURPOSES[r.purpose],
        sub=r.who.." · "..ns.RunRangeText(first.s,first.e).." · "..n.." in"..(best and #best.who>1 and (" · best "..DayLabel(best.s).." "..Clock(best.s)) or ""),
        open=ShowIn("run",id)}
    end
  end
  for id,e in pairs(g.guildEvents or {}) do
    if e.status=="scheduled" and e.ends>now and e.starts<now+7*DAY then
      local n=ns.EventCounts(id)
      out[#out+1]={key="event:"..id,who=e.who,when=WhenOf(e.starts,e.ends),at=e.starts,icon=eventIcons[e.kind or "other"] or groupIcons.event,
        title=e.title,sub="Event · "..DayLabel(e.starts).." "..Clock(e.starts).." · "..e.who.." · "..n.going.."/"..e.slots.." going",
        open=ShowIn("event",id)}
    end
  end
  table.sort(out,function(a,b) if a.at~=b.at then return a.at<b.at end return a.key<b.key end)
  return out
end
function ns.GroupRows(q,st)
  local out={}
  local sections={{"now","Right now","Quick groups and help that expire in a few hours"},{"today","Later today",nil},{"week","This week",nil}}
  local all=ns.OpenGroups()
  for _,sec in ipairs(sections) do
    local first=true
    for _,x in ipairs(all) do
      local mine=not (st and st.mine) or x.who==ns.me
      if x.when==sec[1] and mine and E.Match(q,x.title,x.sub) then
        if first then out[#out+1]={key="cat:"..sec[1],title="|cfff2c14e"..sec[2].."|r",sub=sec[3]}; first=false end
        out[#out+1]={key=x.key,icon=x.icon,title=x.title,sub=x.sub,onClick=x.open}
      end
    end
  end
  return out
end

local groupDrafts={}
local GROUP_TYPES={{"dungeon","Dungeon"},{"raid","Raid"},{"pvp","PvP"},{"other","Other"}}
local function GroupDraft()
  local d=groupDrafts.new
  if not d then
    local lvl=(ns.roster[ns.me] or {}).level or 1
    d={type="dungeon",title="",when="now",minutes=120,purpose="e",note="",chat=false,
      role=(((ns.ProfileOf(ns.me) or {}).roles or "d"):match("[thd]") or "d"),lvl=lvl}
    groupDrafts.new=d
  end
  return d
end
local function Announce(d,name)
  if not d.chat or not SendChatMessage then return end
  local when=d.when=="now" and "now" or (DayLabel(d.s).." "..Clock(d.s))
  local why=(d.type=="dungeon" or d.type=="raid") and d.purpose~="e" and (" ("..ns.RUN_PURPOSES[d.purpose]:lower()..")") or ""
  local msg=("[EPU] "..(ns.me:match("^(%S+)") or ns.me).." wants a group for "..name..why..", "..when..". "
    ..ns.EVENT_ROLES[d.role].." · type /epu groups to join"):sub(1,250)
  pcall(SendChatMessage,msg,"GUILD")
end
function ns.PostGroup(d)
  local name=(d.type=="dungeon" and d.dungeon) or d.title or ""
  name=tostring(name):gsub("[%z\001-\031]",""):sub(1,80):match("^%s*(.-)%s*$")
  if name=="" then return ns.Print(d.type=="dungeon" and "Choose a dungeon first." or "Say what the group is for.") end
  local info=dungeons[name]
  local purposeText=(d.type=="dungeon" or d.type=="raid") and ns.RUN_PURPOSES[d.purpose] or nil
  local id,kind
  if d.when=="now" then
    local lvl=d.lvl or 1
    id=ns.SaveActivity("dungeon",{title=name,zone=info and info[2] or (ns.roster[ns.me] or {}).zone or "",
      note=(purposeText and (purposeText..". ") or "")..(d.note or ""),
      minLevel=info and info[3] or math.max(1,lvl-5),maxLevel=info and info[4] or math.min(60,lvl+5),
      slots=info and info[5] or (d.type=="raid" and 10 or 5),minutes=d.minutes})
    if id then ns.RespondActivity(id,d.role,"ready",""); kind="activity" end
  else
    id=ns.SaveRunRequest({dungeon=name,purpose=purposeText and d.purpose or "e",role=d.role,note=d.note,windows={{s=d.s,e=d.e}}})
    kind="run"
  end
  if not id then return end
  Announce(d,name)
  groupDrafts.new=nil
  return kind,id
end
local function FillGroupForm(det)
  local d=GroupDraft()
  local function Again() det.casualDraft=true; UI:FillDetails() end
  det:Reset(groupIcons.event,nil,"Create","Pick what you'd like to do")
  ns.CreateSwitcher(det,"group")
  det:Section("Activity")
  local types={}
  for _,t in ipairs(GROUP_TYPES) do types[#types+1]={t[2],function() d.type=t[1]; Again() end,on=d.type==t[1]} end
  det:Buttons(types)
  if d.type=="dungeon" then
    local info=d.dungeon and dungeons[d.dungeon]
    det:Buttons({{d.dungeon or "Choose dungeon",function(self) ChooseDungeon(self,d.dungeon,function(name) d.dungeon=name; Again() end) end,accent=not d.dungeon}})
    if info then det:Text(info[2]..(info[3] and (" · levels "..info[3].."–"..info[4]) or ""),C.muted) end
  else
    if d.type=="raid" then
      det:Buttons({{d.title~="" and d.title or "Choose raid",function(self)
        local items={}
        for _,r in ipairs(raidList) do items[#items+1]={label=r[1],value=r[1],right=r[5].." players"} end
        E.OpenMenu(self,items,d.title,function(name) d.title=name; Again() end)
      end,accent=d.title==""}})
    end
    local title=det:Field(d.type=="raid" and "Or type the raid" or d.type=="pvp" and "Battleground or activity" or "What the group is for",d.title,80)
    title.onChange=function() d.title=title:GetText(); det.casualDraft=true end
  end
  if d.type=="dungeon" or d.type=="raid" then
    local why={}
    for _,p in ipairs(ns.RUN_PURPOSE_ORDER) do why[#why+1]={ns.RUN_PURPOSES[p],function() d.purpose=p; Again() end,on=d.purpose==p} end
    det:Section("Going for")
    det:Buttons(why)
  end
  det:Section("When")
  local whens={{"Now",function() d.when="now"; Again() end,on=d.when=="now"}}
  for o=0,6 do
    whens[#whens+1]={o==0 and "Today" or o==1 and "Tomorrow" or date("%a",DayStart(o)),function()
      d.when=o; local w=DefaultWindow(o); d.s,d.e=w.s,w.e; Again()
    end,on=d.when==o}
  end
  det:Buttons(whens)
  if d.when=="now" then
    local spans={}
    for _,m in ipairs({60,120,240}) do spans[#spans+1]={"Open "..(m/60).." h",function() d.minutes=m; Again() end,on=d.minutes==m} end
    det:Buttons(spans)
    det:Text("Shows under Right now and closes on its own after that. Pick Today, Tomorrow or a day to request a run instead.",C.muted)
  else
    if not d.s then local w=DefaultWindow(d.when); d.s,d.e=w.s,w.e end
    local parts=DayPartButtons(d.when,d.s,d.e,function(a,b) d.s,d.e=a,b; Again() end)
    if #parts>0 then det:Buttons(parts) end
    det:Buttons({
      {"From "..Clock(d.s),function(self) TimeMenu(self,d.when,d.s,nil,d.e,function(t) d.s=t; Again() end) end},
      {"To "..(d.e==DayStart(d.when+1) and "midnight" or Clock(d.e)),function(self) TimeMenu(self,d.when,d.e,d.s,nil,function(t) d.e=t; Again() end) end},
    })
    det:Text("|cfff2c14eRun request:|r guildmates mark interest and tick the times that suit them; the best overlap can become an event.",C.muted)
    det:Buttons({{"Pick one fixed start instead",function() ns.OpenCreate("event") end,
      tip="Makes a guild event with a set start time, sign-ups and role slots, using what you picked here."}})
  end
  det:Section("My role")
  local roles={}
  for _,role in ipairs({"t","h","d"}) do roles[#roles+1]={ns.EVENT_ROLES[role],function() d.role=role; Again() end,on=d.role==role} end
  det:Buttons(roles)
  local note=det:Field("Note",d.note,120); note.onChange=function() d.note=note:GetText(); det.casualDraft=true end
  det:Buttons({{(d.chat and "[x] " or "[ ] ").."Also post in guild chat",function() d.chat=not d.chat; Again() end,on=d.chat,
    tip="Also posts one line in guild chat, so guildmates without EPU see it too."}})
  det:Buttons({{d.when=="now" and "Post group" or "Post run request",function()
    d.note=note:GetText()
    local kind,id=ns.PostGroup(d)
    if kind then UI:OpenDetails(kind,id) end
  end,accent=true},{"Cancel",function() groupDrafts.new=nil; UI:CloseDetails() end}})
  return true
end

---------------------------------------------------------------------------
-- Dungeon catalogue: every dungeon and raid with its levels, who in the guild
-- is online and in range, and any open group or run request for it.
---------------------------------------------------------------------------
local artCache
local function InstanceArt(name)
  if not artCache then
    artCache={}
    pcall(function()
      if not (EJ_GetNumTiers and EJ_SelectTier and EJ_GetInstanceByIndex) then return end
      for tier=1,EJ_GetNumTiers() do
        EJ_SelectTier(tier)
        for _,raid in ipairs({false,true}) do
          local i=1
          while true do
            local id,iname,_,_,button1,_,button2=EJ_GetInstanceByIndex(i,raid)
            if not id then break end
            if iname then artCache[iname:lower()]=button2 or button1 end
            i=i+1
          end
        end
      end
    end)
  end
  local key=tostring(name):lower():gsub("’","'")
  return artCache[key] or artCache[tostring(name):lower()] or artCache[(key:match("^([^:]+)") or key):gsub("%s+$","")]
end
ns.InstanceArt=InstanceArt
local raidIcon="Interface\\Icons\\INV_Misc_Head_Dragon_01"
local function InRange(lvl,info) return info[3] and lvl>=info[3] and lvl<=info[4] end
local function GuildmatesInRange(info)
  local out={}
  if not info[3] then return out end
  for name,r in pairs(ns.roster) do
    if r.online and name~=ns.me and r.level and r.level>=info[3] and r.level<=info[4] then out[#out+1]=name end
  end
  table.sort(out,function(a,b) local la,lb=ns.roster[a].level,ns.roster[b].level if la~=lb then return la>lb end return a<b end)
  return out
end
local function GroupsFor(name)
  local out={}
  for _,x in ipairs(ns.OpenGroups()) do if x.place==name then out[#out+1]=x end end
  return out
end
function ns.DungeonCatalogRows(g,q,st,bar)
  if bar then
    bar.casualNew:SetLabel("Create")
    bar.casualAvailability:Hide()
    bar.casualMine:Hide(); bar.casualNear:Show()
    bar.casualNear:SetLabel("Near my level"); bar.casualNear:SetOn(st.near)
    bar.casualNear.tip="Only dungeons where your level is inside the suggested range."
  end
  local lvl=(ns.roster[ns.me] or {}).level or 1
  local groupsByPlace={}
  for _,x in ipairs(ns.OpenGroups()) do if x.place then groupsByPlace[x.place]=(groupsByPlace[x.place] or 0)+1 end end
  local out={}
  local function Header(key,label)
    out[#out+1]={key="cat:"..key,title="|cfff2c14e"..label.."|r",header=true,
      columns={{text="Levels",w=60,align="CENTER"},{text="Zone",w="flex"},{text="Online in range",w=104,align="CENTER"},{text="Open",w=46,align="CENTER"}}}
  end
  local function Add(entry,raid)
    local name,zone=entry[1],entry[2]
    local mine=InRange(lvl,entry)
    if st.near and not mine then return end
    if not E.Match(q,name,zone) then return end
    local inRange=#GuildmatesInRange(entry)
    local open=groupsByPlace[name] or 0
    local levels=entry[3] and (entry[3]==entry[4] and tostring(entry[3]) or (entry[3].."–"..entry[4])) or "?"
    out[#out+1]={key="dungeon:"..name,icon=InstanceArt(name) or (raid and raidIcon or groupIcons.dungeon),
      title=(mine and "|cff4ade80" or "")..name..(mine and "|r" or ""),titleWidth=210,
      sub=zone.." · levels "..levels..(raid and (" · "..entry[5].." players") or "")..(inRange>0 and (" · "..inRange.." online in range") or "")
        ..(open>0 and (" · "..open.." open") or ""),
      right=mine and "|cff4ade80Your level|r" or nil,
      columns={{text=levels,w=60,align="CENTER",color=mine and {0.29,0.87,0.50} or nil},{text=zone,w="flex"},
        {text=inRange>0 and tostring(inRange) or "–",w=104,align="CENTER"},
        {text=open>0 and ("|cfff2c14e"..open.."|r") or "–",w=46,align="CENTER"}},
      onClick=function() Open("dungeoninfo",name) end}
  end
  for gi,group in ipairs(dungeonGroups) do
    local before=#out
    Header("dg"..gi,group.label)
    for _,entry in ipairs(group.entries) do Add(entry,false) end
    if #out==before+1 then out[#out]=nil end
  end
  local before=#out
  Header("raids","Raids")
  for _,entry in ipairs(raidList) do Add(entry,true) end
  if #out==before+1 then out[#out]=nil end
  return out
end
local function FillDungeonInfo(det,name)
  local info=dungeons[name]
  if not info then UI:CloseDetails(); return true end
  local raid=info[5]~=nil
  local lvl=(ns.roster[ns.me] or {}).level or 1
  local levels=info[3] and (info[3]==info[4] and tostring(info[3]) or (info[3].."–"..info[4])) or "?"
  det:Reset(InstanceArt(name) or (raid and raidIcon or groupIcons.dungeon),nil,name,info[2].." · levels "..levels..(raid and (" · "..info[5].." players") or ""))
  if InRange(lvl,info) then det:Text("|cff4ade80Your level ("..lvl..") is in range.|r")
  elseif info[3] and lvl<info[3] then det:Text("You're level "..lvl..", "..(info[3]-lvl).." below the suggested range.",C.muted)
  elseif info[4] and lvl>info[4] then det:Text("You're level "..lvl..": above the range, good for helping others through.",C.muted) end
  local function Create(when)
    local d=GroupDraft()
    d.type=raid and "raid" or "dungeon"
    if raid then d.title=name else d.dungeon=name end
    if when=="later" and d.when=="now" then d.when=0; local w=DefaultWindow(0); d.s,d.e=w.s,w.e
    elseif when=="now" then d.when="now" end
    UI:OpenDetails("groupform","new")
  end
  det:Buttons({{"Start a group now",function() Create("now") end,accent=true,
      tip="Posts a group under Right now; guildmates join with their role."},
    {"Request a run",function() Create("later") end,
      tip="Pick a day and a time range; guildmates tick the times that suit them."}})
  det:Section("Open groups and run requests")
  local open=GroupsFor(name)
  if #open==0 then det:Text("None yet. Start one above.",C.muted) end
  for _,x in ipairs(open) do det:Buttons({{x.title,x.open,tip=x.sub}}) end
  det:Section("Guildmates online in range")
  local mates=GuildmatesInRange(info)
  if #mates==0 then det:Text(info[3] and "Nobody online in this range right now." or "No level range known.",C.muted) end
  for i,mate in ipairs(mates) do
    if i>12 then det:Text("+"..(#mates-12).." more",C.muted); break end
    local r=ns.roster[mate]
    local st=ns.GuildmateStatus and ns.GuildmateStatus(mate) or {}
    det:Buttons({{mate.." · "..r.level.." "..(r.class or "")..(r.zone and (" · "..r.zone) or "")..(st.lf and " · |cff4ade80looking|r" or ""),
      function(self) if ns.GuildmateMenu then ns.GuildmateMenu(self,mate) end end,tip="Whisper, invite or set a waypoint"}})
  end
  return true
end
local fillCommunity=ns.FillCommunityDetails
function ns.FillCommunityDetails(kind,key,det)
  if kind=="groupform" then return FillGroupForm(det) end
  if kind=="dungeoninfo" then return FillDungeonInfo(det,key) end
  return fillCommunity(kind,key,det)
end
local formKind=ns.CommunityFormKind
function ns.CommunityFormKind(kind) return kind=="groupform" or formKind(kind) end

-- One Create entry point: the same switcher heads every "new" form, so
-- groups, events, quest help and helper availability are one click apart.
local CREATE_KINDS={{"group","Group or run"},{"event","Scheduled event"},{"help","Ask for quest help"},{"helper","Offer to help"}}
local function EventDraftFromGroup()
  local d=groupDrafts.new
  if not d then return nil end
  local name=(d.type=="dungeon" and d.dungeon) or (d.title~="" and d.title) or nil
  local info=name and dungeons[name]
  local start=d.when~="now" and d.s or ns.Now()+1800
  local minutes=d.when~="now" and d.e and math.max(30,math.min(360,math.floor((d.e-d.s)/60))) or 90
  return {kind=(d.type=="dungeon" or d.type=="raid") and "dungeon" or "other",dungeon=info and name or nil,
    values={name,info and info[2] or nil,d.note~="" and d.note or nil,date("%Y-%m-%d %H:%M",start),tostring(minutes),
      tostring(info and info[5] or (d.type=="raid" and 10 or 5)),info and info[3] and tostring(info[3]) or nil,info and info[4] and tostring(info[4]) or nil}}
end
function ns.OpenCreate(what,when)
  if what=="event" then
    UI.details.eventFormDraft=EventDraftFromGroup()
    return UI:OpenDetails("eventform","new")
  elseif what=="help" then ns.helpDraft=when; return UI:OpenDetails("activityform","help")
  elseif what=="helper" then return UI:OpenDetails("helperform",ns.me) end
  local d=GroupDraft()
  if when=="today" and d.when=="now" then d.when=0; local w=DefaultWindow(0); d.s,d.e=w.s,w.e end
  return UI:OpenDetails("groupform","new")
end
function ns.CreateSwitcher(det,current)
  local specs={}
  for _,k in ipairs(CREATE_KINDS) do
    specs[#specs+1]={k[2],function() if k[1]~=current then ns.OpenCreate(k[1]) end end,on=k[1]==current,
      tip=({group="A group now, or later this week with flexible times",event="A set start time with sign-ups and role slots",
        help="Ask for a hand with a quest or area",helper="Let guildmates know you're free to help for a while"})[k[1]]}
  end
  det:Buttons(specs)
end

-- Rows for the Quests page.
function ns.QuestPageRows(q)
  local out={}
  local own,reason=ns.CurrentQuests()
  ns.ExpireQuestMatches()
  local myLevel=(ns.roster[ns.me] or {}).level or 1
  -- Questing near you: guildmates in your zone, most quests in common first
  local near={}
  for name,r in pairs(ns.roster) do
    if r.online and name~=ns.me and ns.QuestNearby and ns.QuestNearby(name) then
      local shared=#ns.SharedQuestIDs(name,own)
      if shared>0 or math.abs((r.level or 0)-myLevel)<=5 then near[#near+1]={name=name,r=r,shared=shared} end
    end
  end
  table.sort(near,function(a,b) if a.shared~=b.shared then return a.shared>b.shared end return a.name<b.name end)
  if #near>0 then
    out[#out+1]={key="cat:questnear",header=true,title="|cfff2c14eQuesting near you|r"}
    for i,x in ipairs(near) do
      if i>8 then break end
      if E.Match(q,x.name,x.r.zone) then
        local st=ns.GuildmateStatus and ns.GuildmateStatus(x.name) or {}
        out[#out+1]={key="questnear:"..x.name,title=x.name,icon=ns.ClassIcon and ns.ClassIcon(x.r.classFile) or nil,
          sub="Level "..(x.r.level or "?").." "..(x.r.class or "").." · "..(x.r.zone or "")..(st.lf and " · |cff4ade80looking for a partner|r" or ""),
          right=x.shared>0 and ("|cff4ade80"..x.shared..(x.shared==1 and " quest" or " quests").." in common|r") or "No shared quests",
          onClick=function(self) if ns.GuildmateMenu then ns.GuildmateMenu(self,x.name) end end,
          onRightClick=function(self) if ns.GuildmateMenu then ns.GuildmateMenu(self,x.name) end end}
      end
    end
  end
  -- Your quests
  local rows={}
  for id,r in pairs(own) do
    if E.Match(q,r.title,r.progress) then
      local matches=ns.QuestMatches(id,own)
      local nearby=0
      for _,m in ipairs(matches) do if ns.QuestNearby and ns.QuestNearby(m.who) then nearby=nearby+1 end end
      local names={}
      for i,m in ipairs(matches) do if i>3 then names[#names+1]="+"..(#matches-3); break end names[#names+1]=ns.Short and ns.Short(m.who) or m.who end
      rows[#rows+1]={key="quest:"..id,title=r.title,n=#matches,
        icon=r.group and "Interface\\Icons\\INV_Misc_GroupNeedMore" or "Interface\\Icons\\INV_Misc_Note_02",
        sub=r.progress..(r.group and (" · |cffffb347group quest ("..r.group..")|r") or "")..(#names>0 and (" · "..table.concat(names,", ")) or ""),
        right=#matches==0 and "No guildmates yet" or ("|cff4ade80"..#matches..(#matches==1 and " guildmate" or " guildmates")..(nearby>0 and (", "..nearby.." nearby") or "").."|r"),
        onClick=function() Open("questmatch",id) end}
    end
  end
  table.sort(rows,function(a,b) if (a.n>0)~=(b.n>0) then return a.n>0 end return a.title<b.title end)
  if #rows>0 then out[#out+1]={key="cat:questmine",header=true,title="|cfff2c14eYour quests|r"} end
  for _,r in ipairs(rows) do out[#out+1]=r end
  if reason then out[#out+1]={key="questunavailable",title=reason,sub="No quest information is sent while the log is unavailable."} end
  return out
end
