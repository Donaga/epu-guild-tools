-- Delegated Discord signups use the same explicit helper grants as bank imports.
local ADDON,ns=...
function ns.ValidBridgeEventResponse(sender,r)
  local g=ns.CasualStore();local event=g and g.guildEvents[r.event]
  return ns.IsSyncHelper(sender) and r.via=='discord' and r.bridgeBy==sender
    and event and event.status=='scheduled' and event.ends>ns.Now()
end
function ns.ImportEventResponse(e)
  if not ns.IsTrusted(ns.me) and not ns.IsSyncHelper(ns.me) then return false end
  local key=ns.GuildKey()
  if type(e.guild)~='string' or (key~=e.guild and key:sub(1,#e.guild+3)~=e.guild..' - ') then return false end
  if not ns.StampOK(e.t) or e.t>ns.Now()+300 or not ns.PositiveInt(e.revision,1e15)
    or type(e.event)~='string' or #e.event>180 or type(e.who)~='string' or not ns.Member(e.who)
    or type(e.id)~='string' or #e.id>80 or type(e.note)~='string' or #e.note>160
    or not ns.EVENT_ROLES[e.role] or (e.state~='going' and e.state~='tentative' and e.state~='declined') then return false end
  if ns.Now()-e.t>7*86400 then return true end
  local g=ns.CasualStore();local event=g and g.guildEvents[e.event]
  if not event then return false end -- wait for guild event sync
  if event.status~='scheduled' or event.ends<=ns.Now() then return true end
  local id=e.event..'\030'..e.who;local old=g.eventResponses[id]
  if old and (old.t>e.t or (old.sourceRevision or 0)>=e.revision) then return true end
  local r={event=e.event,who=e.who,state=e.state,role=e.role,note=e.note,t=ns.NextVersion(old and old.t),
    via='discord',bridgeBy=ns.me,sourceID=e.id,sourceRevision=e.revision}
  local b={eventResponses={[id]=r}}
  ns.MergeCommunity(ns.me,b,true)
  if not g.eventResponses[id] or g.eventResponses[id].sourceID~=e.id then return false end
  ns.Send('D',b);ns.Changed();return true
end
