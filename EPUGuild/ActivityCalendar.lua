-- Optional native calendar bridge. Never writes another member's response.
local ADDON,ns=...
local snapshots={}
local function Clip(text,letters)
  local out={}
  for c in text:gmatch("[%z\001-\127\194-\244][\128-\191]*") do
    if #out>=letters then break end
    out[#out+1]=c
  end
  return table.concat(out)
end
function ns.EventCalendarTitle(r) return Clip(r.title,31) end
local function API(name,...)
  local f=C_Calendar and C_Calendar[name]
  if type(f)~="function" then return end
  local ok,value=pcall(f,...); if ok then return value end
end
function ns.EventCalendarMarker(id)
  -- Two independent 32-bit rolling values keep the marker short enough for
  -- WoW's 255-character description. Creator/title/time must also match.
  local a,b=5381,7919
  for i=1,#id do local n=id:byte(i); a=(a*131+n)%4294967296; b=(b*137+n)%4294967296 end
  return string.format("[EPU:%08x%08x]",a,b)
end
function ns.EventCalendarDescription(id,r)
  local text=ns.EventCalendarMarker(id).."\n"..ns.EVENT_TYPES[r.kind or "other"].." · "..math.floor((r.ends-r.starts)/60).." min · "..r.slots.." players\nMeet: "..r.zone.."\n"..
    (ns.EventCalendarTitle(r)~=r.title and (r.title.."\n") or "")..r.note
  return Clip(text,255)
end
local function Signature(r) return r.title.."\031"..r.starts end
local function Wall(c)
  if type(c)~="table" then return end
  if not (c.year and c.month and c.monthDay and c.hour and c.minute) then return end
  return string.format("%04d-%02d-%02d %02d:%02d",c.year,c.month,c.monthDay,c.hour,c.minute)
end
local function Matches(id,r,info)
  if CalendarCreateEventFrame and CalendarCreateEventFrame.mode=="create" and CalendarCreateEventFrame:IsShown() then return false end
  if not info or info.calendarType~="GUILD_EVENT" or ns.Member(info.creator)~=r.who or info.title~=ns.EventCalendarTitle(r) then return false end
  local _,server=ns.EventTimes(r.starts)
  return server~="Unavailable" and Wall(info.time)==server and type(info.description)=="string" and info.description:find(ns.EventCalendarMarker(id),1,true)~=nil
end
function ns.OpenCalendarMatches(id)
  local g=ns.CasualStore(); local r=g and g.guildEvents[id]
  return r and Matches(id,r,API("GetEventInfo")) or false
end
local function Status(value)
  local e=Enum and Enum.CalendarStatus
  if not e or type(value)~="number" then return end
  if value==e.Accepted or value==e.Confirmed or value==e.Signedup then return "going" end
  if value==e.Tentative or value==e.Standby then return "tentative" end
  if value==e.Declined or value==e.Out or value==e.NotSignedup then return "declined" end
end
function ns.ReadOpenCalendarSignups(complete)
  if complete==false or API("AreNamesReady")~=true then return false end
  local g=ns.CasualStore(); local info=API("GetEventInfo")
  if not g or not info then return false end
  local id,r
  for key,event in pairs(g.guildEvents) do if event.status=="scheduled" and event.ends>ns.Now() and Matches(key,event,info) then id,r=key,event; break end end
  if not id then return false end
  local count=API("GetNumInvites")
  if type(count)~="number" or count<0 or count>1000 then return false end
  local rows={}
  for i=1,count do
    local invite=API("EventGetInvite",i)
    if not invite or not invite.name then return false end -- incomplete lists never replace a full snapshot
    local who=ns.Member(invite.name); local state=Status(invite.inviteStatus)
    if who and state then rows[who]={who=who,state=state,role="g",note="",source="WoW calendar"} end
  end
  snapshots[ns.GuildKey().."\031"..id]={rows=rows,at=GetTime(),signature=Signature(r)}
  ns.Changed(); return true
end
function ns.CalendarSignupSnapshot(id)
  local g=ns.CasualStore(); local r=g and g.guildEvents[id]; local key=ns.GuildKey()
  local s=key and snapshots[key.."\031"..id]
  if r and s and s.signature==Signature(r) and GetTime()-s.at<180 then return s end
end
function ns.WithCalendarResponses(id,out)
  local s=ns.CalendarSignupSnapshot(id); if not s then return out end
  local by={}
  for _,r in ipairs(out) do by[r.who]=r end
  for who,r in pairs(s.rows) do
    local existing=by[who]; local copy={}
    for k,v in pairs(r) do copy[k]=v end
    if existing then copy.role=existing.role; copy.note=existing.note end
    by[who]=copy
  end
  out={} for _,r in pairs(by) do out[#out+1]=r end
  table.sort(out,function(a,b) return a.who<b.who end); return out
end
function ns.CalendarRespond(id,state,role,note)
  local g=ns.CasualStore(); local r=g and g.guildEvents[id]
  if not r or r.status~="scheduled" or r.ends<=ns.Now() or not ns.Member(r.who) or not ns.EVENT_ROLES[role] then return false end
  if InCombatLockdown and InCombatLockdown() then ns.Print("Update the calendar after combat."); return false end
  if API("IsActionPending")==true then ns.Print("Wait for the current calendar action to finish."); return false end
  if not ns.OpenCalendarMatches(id) then ns.Print("Open this activity's linked WoW event first."); return false end
  local info=API("GetEventInfo")
  if not info or info.isLocked then ns.Print("The WoW event is locked or unavailable."); return false end
  local method=({going="EventSignUp",tentative="EventTentative",declined="EventDecline"})[state]
  if not method or not C_Calendar or type(C_Calendar[method])~="function" then return false end
  local ok=pcall(C_Calendar[method])
  if not ok then ns.Print("WoW did not accept the action. Use the calendar's signup buttons."); return false end
  -- WoW's asynchronous acknowledgement updates the native snapshot. Do not
  -- invent a native response just because the API call returned successfully.
  ns.RespondGuildEvent(id,state,role,note)
  ns.Print("EPU signup saved; check the WoW calendar for confirmation."); return true
end
function ns.OpenWoWCalendar()
  if InCombatLockdown and InCombatLockdown() then ns.Print("Open the calendar after combat."); return false end
  if not CalendarFrame and C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn,"Blizzard_Calendar") end
  if not ToggleCalendar then ns.Print("WoW's calendar is unavailable on this client. EPU activities still work."); return false end
  if not CalendarFrame or not CalendarFrame:IsShown() then local ok=pcall(ToggleCalendar); if not ok then return false end end
  return CalendarFrame~=nil
end
function ns.PrepareWoWCalendar(id)
  local g=ns.CasualStore(); local r=g and g.guildEvents[id]
  if not r then return false end
  if r.who~=ns.me then ns.Print("Only the organising character ("..r.who..") can prepare this linked calendar copy."); return false end
  if r.status~="scheduled" or r.starts<=ns.Now() then ns.Print("Only scheduled events that have not started can be prepared."); return false end
  if InCombatLockdown and InCombatLockdown() then ns.Print("Prepare the calendar after combat."); return false end
  if API("IsEventOpen")==true or (CalendarCreateEventFrame and CalendarCreateEventFrame:IsShown()) then
    ns.Print("Close the current WoW event or draft first. It has been left untouched."); return false
  end
  if not ns.OpenWoWCalendar() then return false end
  local _,server=ns.EventTimes(r.starts)
  if server=="Unavailable" then ns.Print("Realm time is unavailable; use the copyable details."); return false end
  local y,m,d,h,min=server:match("^(%d+)%-(%d+)%-(%d+) (%d+):(%d+)$")
  y,m,d,h,min=tonumber(y),tonumber(m),tonumber(d),tonumber(h),tonumber(min)
  local required={"SetAbsMonth","GetMonthInfo","GetNumDayEvents","GetDayEvent","EventSetTitle","EventSetDescription","EventSetDate","EventSetTime","EventSetType","CreateGuildSignUpEvent"}
  for _,name in ipairs(required) do if not C_Calendar or type(C_Calendar[name])~="function" then ns.Print("Calendar publishing is unavailable; use the copyable details."); return false end end
  if not CalendarDayContextMenu_CreateGuildEvent or not CalendarFrame_Update or not CalendarCreateEvent_UpdateEventTime or not CalendarCreateEvent_UpdateEventType then
    ns.Print("This client's calendar form cannot be prepared by EPU. The organiser can create a guild signup event manually using Copy title and Copy details."); return false
  end
  local ok=pcall(function()
    C_Calendar.SetAbsMonth(m,y); CalendarFrame_Update()
    -- Refuse same-title duplicates on the selected date.
    local n=C_Calendar.GetNumDayEvents(0,d)
    for i=1,n do local e=C_Calendar.GetDayEvent(0,d,i)
      if e and e.calendarType=="GUILD_EVENT" and e.title==ns.EventCalendarTitle(r) then error("existing") end
    end
    local button
    for i=1,42 do local b=_G["CalendarDayButton"..i]; if b and b.day==d and b.monthOffset==0 then button=b; break end end
    if not button then error("day unavailable") end
    CalendarDayContextMenu_CreateGuildEvent(button)
    local f=CalendarCreateEventFrame
    CalendarCreateEventTitleEdit:SetText(ns.EventCalendarTitle(r))
    CalendarCreateEventDescriptionContainer.ScrollingEditBox:SetText(ns.EventCalendarDescription(id,r))
    C_Calendar.EventSetTitle(ns.EventCalendarTitle(r)); C_Calendar.EventSetDescription(ns.EventCalendarDescription(id,r))
    C_Calendar.EventSetDate(m,d,y); C_Calendar.EventSetTime(h,min)
    f.selectedMinute=min; f.selectedAM=h<12
    f.selectedHour=CalendarFrame.militaryTime and h or ((h+11)%12+1)
    CalendarCreateEvent_UpdateEventTime()
    f.selectedEventType=r.kind=="dungeon" and Enum.CalendarEventType.Dungeon or Enum.CalendarEventType.Other
    CalendarCreateEvent_UpdateEventType(f); C_Calendar.EventSetType(f.selectedEventType)
  end)
  if not ok then ns.Print("Draft could not be prepared, or a matching event already exists. Review WoW's calendar; no event was automatically published."); return false end
  ns.Print("Review the WoW draft, then press its Create button. Keep the EPU marker in the description to link signups."); return true
end
for _,event in ipairs({"CALENDAR_OPEN_EVENT","CALENDAR_UPDATE_EVENT","CALENDAR_UPDATE_INVITE_LIST"}) do
  ns.On(event,function(complete) ns.ReadOpenCalendarSignups(complete) end)
end

-- Calendar grid uses local noon for each date, avoiding 24-hour DST arithmetic.
function ns.ActivityCalendarDays(year,month)
  local first=time({year=year,month=month,day=1,hour=12,min=0,sec=0})
  local c=date("*t",first); local out={}; local g=ns.CasualStore()
  for i=1,42 do
    local epoch=time({year=c.year,month=c.month,day=i-(c.wday-1),hour=12,min=0,sec=0})
    local day=date("*t",epoch); local key=date("%Y-%m-%d",epoch); local n=0
    for _,r in pairs(g and g.guildEvents or {}) do if r.status=="scheduled" and r.ends>ns.Now() and date("%Y-%m-%d",r.starts)==key then n=n+1 end end
    out[i]={key=key,day=day.day,month=day.month,year=day.year,count=n}
  end
  return out,c.year,c.month
end
