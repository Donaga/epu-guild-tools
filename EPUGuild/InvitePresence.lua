-- Non-guild presence is advisory. Never infer offline from a missing /who
-- result, alter the Friends list automatically, or poll the restricted /who API.
local ADDON,ns=...
local seen,remote,sent={},{},{}
local guild
local TTL=120
local function Plain(v) return not (issecretvalue and issecretvalue(v)) end
local function ResetGuild()
  local key=ns.GuildKey()
  if guild~=key then seen,remote,sent={},{},{};guild=key end
end
local function Name(v)
  if not Plain(v) or type(v)~='string' then return end
  local name=ns.Short(v)
  return name and name:lower()
end
local function Friends()
  local out={}
  local count=(C_FriendList and C_FriendList.GetNumFriends) or GetNumFriends
  local info=(C_FriendList and C_FriendList.GetFriendInfoByIndex) or GetFriendInfo
  if type(count)~='function' or type(info)~='function' then return out end
  local ok,n=pcall(count)
  if not ok or not Plain(n) or type(n)~='number' or n<0 or n>1000 then return out end
  for i=1,n do
    local good,name,_,_,_,online=pcall(info,i)
    if good and Plain(name) and type(name)=='table' then online=name.connected; name=name.name end
    if good and Plain(online) and type(online)=='boolean' then
      local key=Name(name);if key then out[key]=online end
    end
  end
  return out
end
local function Remember(name)
  local key=Name(name)
  if key then seen[key]=ns.Now() end
end
function ns.GuildInvitePresence(who)
  ResetGuild()
  local key=Name(who);if not key then return 'unknown','Unknown' end
  local ok,friends=pcall(Friends)
  if ok and friends[key]~=nil then
    return friends[key] and 'online' or 'offline',friends[key] and 'Online' or 'Offline','Friends list'
  end
  if seen[key] and ns.Now()-seen[key]<TTL then return 'online','Online','Seen in game recently' end
  local r=remote[key]
  if r and ns.Now()-r.at<TTL and (ns.roster[r.by] or {}).online then
    return 'reported','Online (reported)','Reported by '..r.by
  end
  return 'unknown','Unknown','No current game presence result'
end
local function Pending(id,r)
  local s=ns.CommunityState()
  return ns.ActiveGuildInvite(r) and not ns.GuildInviteOutcome(id)
    and s and (not s.inviteDismissed or s.inviteDismissed[id]~=r.who)
end
function ns.RefreshGuildInvitePresence()
  ResetGuild()
  if not ns.CanInviteGuild() then return end
  local g=ns.CasualStore();local s=ns.CommunityState()
  if not g or not s then return end
  s.inviteOnlineAlerts=s.inviteOnlineAlerts or {}
  local budget=1
  for id,r in pairs(g.inviteRequests) do
    if Pending(id,r) then
      local state=ns.GuildInvitePresence(r.who)
      if state=='online' or state=='reported' then
        local old=s.inviteOnlineAlerts[id]
        if not old or old.who~=r.who or old.revision~=r.revision or (old.online==false and ns.Now()-old.at>=600) then
          s.inviteOnlineAlerts[id]={who=r.who,revision=r.revision,at=ns.Now(),online=true}
          ns.Notify('Guild invite: online now',r.who..(state=='reported' and ' was reported online by a guild member.' or ' is online.')..' Open the request to invite.',nil,
            {category='invites',kind='guildinvite',key=id,revision='online:'..r.revision..':'..ns.Now()})
        end
        s.inviteOnlineAlerts[id].online=true
        -- Send only local positive observations, never echo a remote report.
        -- One short, expiring packet per pass keeps login traffic bounded.
        if state=='online' and budget>0 and (not sent[id] or ns.Now()-sent[id]>=60) then
          local requestID,revision,who,key=id,r.revision,r.who,guild
          if ns.SendEphemeral('I',{id=id,who=who,revision=revision,at=ns.Now()},15,function()
            local current=ns.CasualStore();current=current and current.inviteRequests[requestID]
            return ns.GuildKey()==key and ns.CanInviteGuild() and current and current.revision==revision
              and Pending(requestID,current) and ns.GuildInvitePresence(who)=='online'
          end,'invite-presence:'..id) then sent[id]=ns.Now();budget=budget-1 end
        end
      elseif state=='offline' and s.inviteOnlineAlerts[id] then s.inviteOnlineAlerts[id].online=false end
    end
  end
  for id in pairs(s.inviteOnlineAlerts) do if not g.inviteRequests[id] or not ns.ActiveGuildInvite(g.inviteRequests[id]) then s.inviteOnlineAlerts[id]=nil end end
  for key,t in pairs(seen) do if ns.Now()-t>=TTL then seen[key]=nil end end
  for key,r in pairs(remote) do if ns.Now()-r.at>=TTL then remote[key]=nil end end
  if ns.UI and ns.UI:IsShown() and ns.UI.view=='activities' and ns.UI.state.activities.kind=='invites' then ns.UI:Refresh() end
end
ns.comm.I=function(sender,p,channel)
  ResetGuild()
  if channel~='GUILD' or not ns.CanInviteGuild() or not ns.Member(sender) or not (ns.roster[sender] or {}).online or type(p)~='table' then return end
  local g=ns.CasualStore();local r=g and g.inviteRequests[p.id]
  if not r or not Pending(p.id,r) or p.who~=r.who or p.revision~=r.revision or not ns.StampOK(p.at)
    or p.at>ns.Now()+5 or p.at<ns.Now()-30 then return end
  local key=Name(r.who);local old=remote[key]
  if not old or p.at>old.at then remote[key]={at=p.at,by=sender};ns.RefreshGuildInvitePresence() end
end
function ns.TrackGuildInvite(id)
  local g=ns.CasualStore();local r=g and g.inviteRequests[id]
  if not ns.CanInviteGuild() or not r or not ns.ActiveGuildInvite(r) then return false end
  local add=(C_FriendList and C_FriendList.AddFriend) or AddFriend
  if type(add)~='function' then ns.Print('Add '..r.who..' to Friends to track online status.');return false end
  local ok=pcall(add,r.who)
  ns.Print(ok and 'Friend request attempted. Check the game response; Friends provides online/offline updates.' or 'The game blocked this action. Add the character through Friends.')
  return ok
end
local function Refresh() ns.Debounce('invitePresence',0.5,ns.RefreshGuildInvitePresence) end
ns.On('FRIENDLIST_UPDATE',Refresh)
ns.On('PLAYER_TARGET_CHANGED',function()
  pcall(function() if UnitIsPlayer and UnitIsPlayer('target') and UnitIsConnected and UnitIsConnected('target') then Remember(ns.UnitFullName('target')) end end)
  Refresh()
end)
ns.On('WHO_LIST_UPDATE',function()
  pcall(function()
    local count=(C_FriendList and C_FriendList.GetNumWhoResults) or GetNumWhoResults
    local info=(C_FriendList and C_FriendList.GetWhoInfo) or GetWhoInfo
    if type(count)~='function' or type(info)~='function' then return end
    local n=count();if not Plain(n) or type(n)~='number' or n>100 then return end
    for i=1,n do local r=info(i);if Plain(r) then Remember(type(r)=='table' and r.fullName or r) end end
  end)
  Refresh()
end)
ns.On('PLAYER_GUILD_UPDATE',ResetGuild)
ns.On('PLAYER_LOGIN',function()
  local function Tick() ns.RefreshGuildInvitePresence();C_Timer.After(15,Tick) end
  C_Timer.After(25,Tick)
end)
