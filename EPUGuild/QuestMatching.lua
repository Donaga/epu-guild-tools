-- Explicitly selected quests only. Remote progress is transient, never saved.
local ADDON,ns=...
local remote,sent={},{}
local sentAt,revisions={},{}
local guild,lastHeartbeat
local logReady=false
ns.sharedQuests=remote
local function Changed()
  if ns.UI and ns.UI:IsShown() and ns.UI.view=="membertools" and ns.UI.state.membertools.kind=="quests" then
    ns.Debounce("questView",0.5,function() if ns.UI:IsShown() then ns.UI:Refresh() end end)
  end
end
local function SafeNumber(n,lo,hi)
  if issecretvalue and issecretvalue(n) then return false end
  return type(n)=="number" and n==n and n>=lo and n<=hi and n%1==0
end
local function Clean(s,n)
  if issecretvalue and issecretvalue(s) then return "" end
  return type(s)=="string" and s:gsub("[%z\001-\031]",""):sub(1,n) or ""
end
local function ReadQuests()
  local out={}
  local countAPI=(C_QuestLog and C_QuestLog.GetNumQuestLogEntries) or GetNumQuestLogEntries
  if not countAPI then return out,"Quest-log information is unavailable on this client." end
  local ok,n=pcall(countAPI)
  if not ok or not SafeNumber(n,0,500) then return out,"Quest-log information is temporarily unavailable." end
  for i=1,n do
    local success,q=pcall(function()
      if C_QuestLog and C_QuestLog.GetInfo then return C_QuestLog.GetInfo(i) end
      if GetQuestLogTitle then
        local title,level,_,header,_,complete,_,id=GetQuestLogTitle(i)
        return {title=title,level=level,isHeader=header,isComplete=complete==1,questID=id}
      end
    end)
    if success and type(q)=="table" and not q.isHeader and not q.isHidden and SafeNumber(q.questID,1,2147483647) then
      local id=q.questID; local title=Clean(q.title,60)
      if title~="" then
        local done=q.isComplete==true
        if C_QuestLog and C_QuestLog.IsComplete then local yes,value=pcall(C_QuestLog.IsComplete,id); if yes then done=value==true end end
        local pieces={}
        if C_QuestLog and C_QuestLog.GetQuestObjectives then
          local yes,objectives=pcall(C_QuestLog.GetQuestObjectives,id)
          if yes and type(objectives)=="table" then
            for j,o in ipairs(objectives) do
              if j>4 then break end
              if SafeNumber(o.numFulfilled,0,1000000) and SafeNumber(o.numRequired,1,1000000) then pieces[#pieces+1]=o.numFulfilled.."/"..o.numRequired
              elseif type(o.finished)=="boolean" then pieces[#pieces+1]=o.finished and "Done" or "In progress" end
            end
          end
        elseif GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
          local yes,count=pcall(GetNumQuestLeaderBoards,i)
          if yes and SafeNumber(count,0,50) then
            local completed=0
            for j=1,count do local valid,_,_,finished=pcall(GetQuestLogLeaderBoard,j,i); if valid and finished then completed=completed+1 end end
            pieces[1]=completed.."/"..count.." objectives complete"
          end
        end
        out[id]={id=id,title=title,progress=done and "Ready to turn in" or (#pieces>0 and table.concat(pieces,"; "):sub(1,48) or "In progress"),done=done}
      end
    end
  end
  return out
end
function ns.CurrentQuests()
  local ok,quests,reason=pcall(ReadQuests)
  if not ok then return {},"Quest-log information is temporarily unavailable." end
  return quests,reason
end
local function ResetGuild()
  local key=ns.GuildKey()
  if guild~=key then
    for id in pairs(sent) do ns.CancelEphemeral("quest:"..id) end
    ns.CancelEphemeral("quest:off"); wipe(sent); wipe(sentAt); wipe(revisions); wipe(remote); guild=key; lastHeartbeat=nil
  end
end
local function Withdraw(id)
  local key=guild
  ns.CancelEphemeral("quest:"..id)
  ns.SendEphemeral("Q",{id=id,off=true},180,function() return ns.GuildKey()==key and IsInGuild() end,"quest:"..id)
  sent[id]=nil; sentAt[id]=nil
end
function ns.SetQuestSharing(on)
  ResetGuild()
  local s=ns.CommunityState(); if not s then return end
  s.shareQuests=on==true
  if not on then
    for id in pairs(sent) do ns.CancelEphemeral("quest:"..id) end
    wipe(sent); wipe(sentAt)
    local key=guild
    ns.SendEphemeral("Q",{off=true},180,function() return ns.GuildKey()==key and IsInGuild() end,"quest:off")
  else ns.CancelEphemeral("quest:off"); lastHeartbeat=nil; ns.UpdateQuestSharing() end
  Changed()
end
function ns.SelectSharedQuest(id,on)
  local s=ns.CommunityState(); if not s then return false end
  local own=ns.CurrentQuests()
  if not own[id] then return ns.Print("That quest is no longer in your quest log.") end
  local count=0 for _,v in pairs(s.selectedQuests) do if v then count=count+1 end end
  if on and not s.selectedQuests[id] and count>=8 then return ns.Print("Select up to eight quests. Unselect another quest first.") end
  s.selectedQuests[id]=on and true or nil
  if not on and sent[id] then Withdraw(id) end
  ns.Debounce("questUpdate",2,ns.UpdateQuestSharing); Changed(); return true
end
function ns.UpdateQuestSharing()
  ResetGuild()
  local s=ns.CommunityState(); if not s or not s.shareQuests or not guild then return end
  local quests,reason=ns.CurrentQuests()
  -- An unavailable log is not evidence of abandonment. Expire remote data
  -- naturally and wait for a successful read before changing selections.
  if reason then return end
  if next(quests) then logReady=true end
  for id in pairs(s.selectedQuests) do
    if not quests[id] then
      local present
      if C_QuestLog and C_QuestLog.IsOnQuest then
        local ok,value=pcall(C_QuestLog.IsOnQuest,id); if ok and type(value)=="boolean" then present=value end
      elseif GetQuestLogIndexByID then
        local ok,index=pcall(GetQuestLogIndexByID,id); if ok and type(index)=="number" then present=index>0 end
      elseif logReady then present=false end
      if present==false then s.selectedQuests[id]=nil; if sent[id] then Withdraw(id) end end
    end
  end
  local status=ns.NetworkStatus()
  if status.queued>0 or status.pause>0 then return end
  local heartbeat=not lastHeartbeat or ns.Now()-lastHeartbeat>=90
  local key=guild
  for id in pairs(s.selectedQuests) do
    local q=quests[id]
    local questID=id
    if q and s.selectedQuests[id]==true then
      local signature=q.title..q.progress..tostring(q.done)
      if (heartbeat or not sent[id] or sent[id]~=signature) and (not sentAt[id] or GetTime()-sentAt[id]>=10) then
        revisions[id]=ns.NextVersion(revisions[id])
        local payload={id=id,title=q.title,p=q.progress,done=q.done,u=revisions[id]}
        local accepted=ns.SendEphemeral("Q",payload,15,function()
          local current=ns.CommunityState()
          if ns.GuildKey()~=key or not current or not current.shareQuests or current.selectedQuests[questID]~=true then return false end
          if C_QuestLog and C_QuestLog.IsOnQuest then local ok,value=pcall(C_QuestLog.IsOnQuest,questID); return ok and value==true end
          return ns.CurrentQuests()[questID]~=nil
        end,"quest:"..id)
        if accepted then sent[id]=signature; sentAt[id]=GetTime() end
      end
    end
  end
  if heartbeat then lastHeartbeat=ns.Now() end
end
function ns.ExpireQuestMatches()
  ResetGuild()
  local changed=false
  for name,quests in pairs(remote) do
    local member=ns.roster[name]
    for id,q in pairs(quests) do if not member or not member.online or GetTime()-q.at>=180 then quests[id]=nil; changed=true end end
    if not next(quests) then remote[name]=nil end
  end
  if changed then Changed() end
end
ns.comm.Q=function(sender,q,channel)
  ResetGuild()
  if not guild or not IsInGuild() or channel~="GUILD" or sender==ns.me or not ns.Member(sender) or not (ns.roster[sender] or {}).online or type(q)~="table" then return end
  if q.off==true then
    if q.id==nil then remote[sender]=nil elseif SafeNumber(q.id,1,2147483647) and remote[sender] then remote[sender][q.id]=nil end
    Changed(); return
  end
  if not SafeNumber(q.id,1,2147483647) or type(q.title)~="string" or #q.title>60 or q.title==""
    or type(q.p)~="string" or #q.p>48 or type(q.done)~="boolean" or not ns.StampOK(q.u) or q.u<ns.Now()-180 or q.u>ns.Now()+300 then return end
  remote[sender]=remote[sender] or {}
  local old=remote[sender][q.id]
  if old and q.u<=old.u then return end
  local n=0 for _ in pairs(remote[sender]) do n=n+1 end
  if not old and n>=8 then return end
  remote[sender][q.id]={id=q.id,title=q.title,progress=q.p,done=q.done,u=q.u,at=GetTime()}
  Changed()
end
function ns.QuestMatches(id,own)
  if not own then ns.ExpireQuestMatches(); own=ns.CurrentQuests() end
  local rows={}
  if not own[id] then return rows end
  for name,quests in pairs(remote) do if quests[id] then rows[#rows+1]={who=name,quest=quests[id]} end end
  table.sort(rows,function(a,b) return a.who<b.who end); return rows
end
ns.On("QUEST_LOG_UPDATE",function() logReady=true; ns.Debounce("questUpdate",15,ns.UpdateQuestSharing) end)
ns.On("PLAYER_GUILD_UPDATE",ResetGuild)
ns.On("PLAYER_LOGIN",function()
  local function Tick() ns.ExpireQuestMatches(); ns.UpdateQuestSharing(); C_Timer.After(30,Tick) end
  C_Timer.After(35,Tick)
end)
