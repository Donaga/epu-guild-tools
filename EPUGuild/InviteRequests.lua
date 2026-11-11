-- Discord invite requests share the existing officer-import/sync transport.
local ADDON,ns=...
ns.CASUAL_FIELDS[#ns.CASUAL_FIELDS+1]='inviteRequests'
ns.CASUAL_FIELDS[#ns.CASUAL_FIELDS+1]='syncHelpers'
ns.CASUAL_FIELDS[#ns.CASUAL_FIELDS+1]='inviteOutcomes'
local RANK_RULE = '@rank'
function ns.IsSyncHelper(name)
  local g = ns.CasualStore()
  name = ns.Short(name)
  if not g or not name or name == RANK_RULE then return false end
  local character = g.syncHelpers[name]
  if character then return character.enabled == true end
  local rule = g.syncHelpers[RANK_RULE]
  if not rule or not rule.enabled or type(rule.rank) ~= 'string' then return false end
  local member = ns.roster[name]
  local rank = member and member.rankName
  if name == ns.me then rank = select(2, GetGuildInfo('player')) end
  return type(rank) == 'string' and rank:lower() == rule.rank:lower()
end
function ns.SetSyncHelperRank(rank)
  if not ns.IsTrusted(ns.me) then ns.Print('Only officers can change sync-helper approval.'); return false end
  local g = ns.CasualStore()
  if not g then return false end
  rank = type(rank) == 'string' and rank:match('^%s*(.-)%s*$') or ''
  if rank == '' or #rank > 80 or rank:find('[%c|]') then return false end
  if rank:lower() ~= 'off' then
    local match
    for _, member in pairs(ns.roster) do
      if type(member.rankName) == 'string' and member.rankName:lower() == rank:lower() then
        match = member.rankName
        break
      end
    end
    if not match then ns.Print('Enter an exact rank name from the guild roster.'); return false end
    rank = match
  end
  local old = g.syncHelpers[RANK_RULE]
  local rule = { rank = rank, enabled = rank ~= 'off', by = ns.me, t = ns.NextVersion(old and old.t) }
  g.syncHelpers[RANK_RULE] = rule
  ns.Send('D', {syncHelpers = {[RANK_RULE] = rule}})
  ns.Changed()
  ns.Print(rule.enabled and ('Sync helper rank: '..rank..'. Each helper still needs their own connection folder.') or 'Rank-based helper approval turned off.')
  return true
end
function ns.SetSyncHelper(name,enabled)
  if not ns.IsTrusted(ns.me) then ns.Print('Only officers can change the sync-helper whitelist.'); return false end
  local member=ns.Member(name)
  if not member or type(name)~='string' or not name:find(' ',1,true) or member:lower()~=name:lower() then
    ns.Print('Enter the exact first and last name of a current guild character. Add each alt explicitly.'); return false
  end
  local g=ns.CasualStore(); local old=g.syncHelpers[member]
  local r={enabled=enabled==true,by=ns.me,t=ns.NextVersion(old and old.t)}
  g.syncHelpers[member]=r; ns.Send('D',{syncHelpers={[member]=r}}); ns.Changed()
  ns.Print(member..(r.enabled and ' can import guild invite requests as a sync helper.' or ' was removed from the sync-helper whitelist.'))
  return true
end
function ns.CanInviteGuild()
  if not IsInGuild() or type(CanGuildInvite)~='function' then return false end
  local ok,can=pcall(CanGuildInvite); return ok and can==true
end
local function Valid(id,r)
  if type(id)~='string' or #id>50 or not id:match('^[mc]%d+$') or type(r)~='table' then return false end
  if type(r.who)~='string' or #r.who>200 or not r.who:match('^%S+ %S+$') or r.who:find('[%z\001-\031|/\\<>%d]') then return false end
  return type(r.requester)=='string' and #r.requester<=80 and not r.requester:find('[%z\001-\031|]')
    and type(r.by)=='string' and #r.by<=80 and type(r.cancelled)=='boolean'
    and ns.StampOK(r.posted) and r.posted<=ns.Now()+300 and r.posted>=ns.Now()-14*86400
    and ns.StampOK(r.t) and r.t>=r.posted and r.t<=ns.Now()+300
    and ns.PositiveInt(r.revision,1e15)
end
function ns.ActiveGuildInvite(r)
  return r and not r.cancelled and ns.Now()-r.posted<7*86400 and not ns.Member(r.who)
end
function ns.NotifyGuildInvites()
  if not ns.CanInviteGuild() then return end
  local g=ns.CasualStore(); local s=ns.CommunityState(); if not g or not s then return end
  if ns.RefreshGuildInvitePresence then ns.RefreshGuildInvitePresence() end
  for id,r in pairs(g.inviteRequests) do
    local presence=ns.GuildInvitePresence and ns.GuildInvitePresence(r.who)
    if presence~='online' and presence~='reported' and ns.ActiveGuildInvite(r) and not ns.GuildInviteOutcome(id) and (not s.inviteDismissed or s.inviteDismissed[id]~=r.who) then
      ns.Notify('Guild invite requested',r.who..' · Discord: '..r.requester,nil,{category='invites',kind='guildinvite',key=id,revision=r.who..':'..r.posted})
    end
  end
end
local merge=ns.MergeCommunity
ns.MergeCommunity=function(sender,b,trusted)
  local changed=merge(sender,b,trusted)
  local g=ns.CasualStore()
  if trusted and g and type(b.syncHelpers)=='table' then
    for name,r in pairs(b.syncHelpers) do
      if type(name)=='string' and #name<=80 and type(r)=='table' and type(r.enabled)=='boolean' and type(r.by)=='string' and #r.by<=80
        and (name ~= RANK_RULE or (type(r.rank) == 'string' and #r.rank > 0 and #r.rank <= 80 and not r.rank:find('[%c|]')))
        and ns.StampOK(r.t) and r.t<=ns.Now()+300 and ns.Newer(r,g.syncHelpers[name],'t') then
        g.syncHelpers[name]={enabled=r.enabled,by=r.by,t=r.t,rank=name == RANK_RULE and r.rank or nil}; changed=true
      end
    end
  end
  if (trusted or ns.IsSyncHelper(sender)) and g and type(b.inviteRequests)=='table' then
    for id,r in pairs(g.inviteRequests) do if ns.Now()-(r.posted or 0)>14*86400 then g.inviteRequests[id]=nil end end
    local count=0 for _ in pairs(g.inviteRequests) do count=count+1 end
    for id,r in pairs(b.inviteRequests) do
      local old=g.inviteRequests[id]
      if Valid(id,r) and (trusted or r.by==sender) and (old or count<200) and (not old or r.revision>(old.revision or 0) or (r.revision==old.revision and ns.Newer(r,old,'t'))) then
        g.inviteRequests[id]={who=r.who,requester=r.requester,by=r.by,posted=r.posted,t=r.t,cancelled=r.cancelled,revision=r.revision}
        if not old then count=count+1 end; changed=true
      end
    end
  end
  if g and type(b.inviteOutcomes)=='table' then
    for id,r in pairs(b.inviteOutcomes) do
      local request=type(r)=='table' and g.inviteRequests[r.source]
      if type(id)=='string' and #id<=150 and request and (trusted or r.by==sender) and ns.Member(r.by)
        and id==r.source..'\030'..r.by and r.who==request.who and r.requestRevision==request.revision
        and (r.phase=='sent' or r.phase=='joined') and ns.StampOK(r.t) and r.t>=request.posted and r.t<=ns.Now()+300
        and ns.Newer(r,g.inviteOutcomes[id],'t') then
        g.inviteOutcomes[id]={source=r.source,who=r.who,by=r.by,t=r.t,phase=r.phase,requestRevision=r.requestRevision};changed=true
      end
    end
  end
  -- A helper may relay a new pending bank request, never an approval/status
  -- change or a replacement for an existing guild request.
  if not trusted and ns.IsSyncHelper(sender) and g and type(b.req)=='table' then
    for id,r in pairs(b.req) do
      if type(id)=='string' and id:match('^d%-%w+$') and #id<=180 and not g.requests[id] and ns.ValidRequest(r)
        and r.status=='pending' and r.via=='discord' and ns.StampOK(r.t) and ns.PositiveInt(r.qty,1000)
        and not r.crafter and not r.delivered and not r.project and ns.CanBankRequest(r.item) then
        g.requests[id]={who=r.who,to=r.to,item=r.item,qty=r.qty,note=r.note,t=r.t,u=r.u,via='discord',discord=r.discord,status='pending'};changed=true
      end
    end
  end
  if changed then ns.Changed(); ns.NotifyGuildInvites() end
  return changed
end
function ns.GuildInviteOutcome(source)
  local g=ns.CasualStore(); local request=g and g.inviteRequests[source]; local best
  if not request then return end
  for _,r in pairs(g.inviteOutcomes) do
    if r.source==source and r.who==request.who and r.requestRevision==request.revision then
      if not best or (r.phase=='joined' and best.phase~='joined') or (r.phase==best.phase and r.t>best.t) then best=r end
    end
  end
  return best
end
local function Outcome(source,phase)
  local g=ns.CasualStore(); local r=g and g.inviteRequests[source]
  if not r or r.cancelled or ns.Now()-r.posted>=7*86400 then return end
  local best=ns.GuildInviteOutcome(source)
  if best and (best.phase=='joined' or best.phase==phase) then return end
  local id=source..'\030'..ns.me;local old=g.inviteOutcomes[id]
  local result={source=source,who=r.who,by=ns.me,phase=phase,t=ns.NextVersion(old and old.t),requestRevision=r.revision}
  g.inviteOutcomes[id]=result;ns.Send('D',{inviteOutcomes={[id]=result}});ns.Changed()
end
local function ConfirmMessage(message)
  -- Protected/secret strings are never inspected. Unsupported clients simply
  -- retain "awaiting confirmation" until a roster join is observed.
  if not ns.IsReadableString(message) or not ns.CanInviteGuild() then return end
  local template=ERR_GUILD_INVITE_S
  if not ns.IsReadableString(template) then return end
  local before,after=template:match('^(.-)%%s(.-)$'); if not before then return end
  local function Escape(s)return (s:gsub('([%(%)%.%%%+%-%*%?%[%]%^%$])','%%%1')) end
  local name=message:match('^'..Escape(before)..'(.-)'..Escape(after)..'$')
  name=name and ns.Short(name); if not name then return end
  local g=ns.CasualStore()
  for source,r in pairs(g and g.inviteRequests or {}) do if r.who:lower()==name:lower() then Outcome(source,'sent') end end
end
ns.On('CHAT_MSG_SYSTEM',function(message) pcall(ConfirmMessage,message) end)
ns.On('UI_INFO_MESSAGE',function(_,message) pcall(ConfirmMessage,message) end)
ns.On('GUILD_ROSTER_UPDATE',function()
  if not ns.CanInviteGuild() and not ns.IsSyncHelper(ns.me) and not ns.IsTrusted(ns.me) then return end
  local g=ns.CasualStore()
  for source,r in pairs(g and g.inviteRequests or {}) do if ns.Member(r.who) then Outcome(source,'joined') end end
end)
ns.On('PLAYER_LOGIN',function()
  ns.db.syncHelperCharacter=ns.me;ns.db.syncHelperGuild=ns.GuildKey()
end)
ns.On('PLAYER_LOGOUT',function() ns.db.syncHelperExported=ns.Now() end)
function ns.ImportGuildInvite(e)
  if not ns.IsTrusted(ns.me) and not ns.IsSyncHelper(ns.me) then return false end
  local g=ns.CasualStore(); if not g then return false end
  local key=ns.GuildKey()
  if type(e.guild)~='string' or (key~=e.guild and key:sub(1,#e.guild+3)~=e.guild..' - ') then return false end
  if type(e.posted)~='number' or ns.Now()-e.posted>7*86400 then return true end
  local old=g.inviteRequests[e.source]
  if old and tonumber(e.revision) and e.revision<=old.revision then return true end
  local r={who=e.who,requester=e.requester,by=ns.me,posted=e.posted,cancelled=e.cancelled==true,revision=e.revision,t=ns.NextVersion(math.max(tonumber(e.t) or 0,old and old.t or 0))}
  if not Valid(e.source,r) then return false end
  if old and old.who==r.who and old.cancelled==r.cancelled and old.posted==r.posted then return true end
  local b={inviteRequests={[e.source]=r}}
  ns.MergeCommunity(ns.me,b,true)
  if not g.inviteRequests[e.source] or g.inviteRequests[e.source].revision~=r.revision then return false end
  ns.Send('D',b); return true
end
function ns.InviteRequestedCharacter(id)
  local g=ns.CasualStore(); local r=g and g.inviteRequests[id]
  if not ns.CanInviteGuild() or not ns.ActiveGuildInvite(r) then return false end
  if InCombatLockdown and InCombatLockdown() then ns.Print('Send the invite after combat.'); return false end
  local invite=(C_GuildInfo and C_GuildInfo.Invite) or GuildInvite
  if type(invite)~='function' then ns.Print('Use the copyable /ginvite command.'); return false end
  local ok=pcall(invite,r.who)
  ns.Print(ok and 'Invite attempted. Check the game response; the request stays open until they join.' or 'The game blocked the invite. Use the copyable /ginvite command.')
  return ok
end
ns.On('GUILD_ROSTER_UPDATE',function() ns.NotifyGuildInvites() end)
ns.On('PLAYER_LOGIN',function() C_Timer.After(20,ns.NotifyGuildInvites) end)
