"""Typed activities, date controls and optional native calendar bridge."""
from simcore import *
A=Client('Chris Baker'); B=Client('Tyler Baker'); clients[A.name]=A; clients[B.name]=B
tick(120)
event=A.ev("__ns.SaveGuildEvent({kind='fishing',title='Relaxed fishing',zone='Canals',starts=__now+3600,minutes=60,slots=10,minLevel=10,maxLevel=40})")
for c in (A,B): c.rt.globals()['event']=event
check('typed activity sync preserves type and level range',tick_until(lambda:B.ev('(__ns.CasualStore().guildEvents[event] or {}).kind')=='fishing',60) and B.ev('__ns.CasualStore().guildEvents[event].minLevel')==10)
check('noncombat organiser defaults to helper',A.ev('__ns.EventResponses(event)[1].role')=='g')
B.ex("__ns.RespondGuildEvent(event,'going','m','Can help beginners')")
check('mentor signup syncs and counts',tick_until(lambda:A.ev('__ns.EventCounts(event).m')==1,60))
check('invalid activity type rejected',A.ev("__ns.SaveGuildEvent({kind='bogus',title='Bad',starts=__now+3600,minutes=60})") is None)
check('reversed level range rejected',A.ev("__ns.SaveGuildEvent({title='Bad',starts=__now+3600,minutes=60,minLevel=40,maxLevel=10})") is None)
A.ex("""local r={} for k,v in pairs(__ns.CasualStore().guildEvents[event]) do r[k]=v end
r.kind='forged'; r.t=__now+1; __ns.Merge('Chris Baker',{guildEvents={[event]=r}})""")
check('invalid synced type cannot replace event',A.ev('__ns.CasualStore().guildEvents[event].kind')=='fishing')
A.ex("""__long={title=string.rep('é',40),zone=string.rep('Zone',20),note=string.rep('é',500),starts=__now+3600,ends=__now+7200,slots=10,kind='other'}
__copyTitle=__ns.EventCalendarTitle(__long); __copyDescription=__ns.EventCalendarDescription(event,__long)""")
check('native text limits preserve whole Unicode characters',len(A.ev('__copyTitle'))==31 and len(A.ev('__copyDescription'))<=255)
check('compact marker survives native description limit',A.ev('__copyDescription:find(__ns.EventCalendarMarker(event),1,true)==1'))
A.ex("""__ns.UI:Show(); __ns.UI:SetView('activities')
function __click(label)
 for _,b in ipairs(__ns.UI.details.pools.btn) do if b:IsShown() and b.text:GetText()==label then b:Click(); return end end error('Missing '..label)
end
function __rows() local n=0 for _,r in ipairs(__ns.UI.rows) do if r:IsShown() then n=n+1 end end return n end
__ns.UI.state.activities.kind='events'; __ns.UI:Refresh()
""")
check('activities is the initial board',A.ev('__ns.UI.state.activities.kind')=='events')
check('activity row is visible',A.ev('__rows()')==1)
A.ex("__ns.UI.state.activities.eventType='dungeon'; __ns.UI:Refresh()")
check('type filter excludes other types',A.ev('__rows()')==0)
A.ex("__ns.UI.state.activities.eventType='fishing'; __ns.UI.state.activities.eventDate='2001-01-01'; __ns.UI:Refresh()")
check('type and date filters combine',A.ev('__rows()')==0)
A.ex("__ns.UI.state.activities.eventDate=date('%Y-%m-%d',__ns.CasualStore().guildEvents[event].starts); __ns.UI:Refresh()")
check('matching date displays activity',A.ev('__rows()')==1)
A.ex("""__bar=__ns.UI.bars.activities; __bar.casualNear:Click(); EPUGuildMenu.rows[1]:Click()
__bar.casualAvailability:Click(); EPUGuildActivityDatePicker.chosen(nil); EPUGuildActivityDatePicker:Hide()""")
check('actual type menu and date clear reset filters',A.ev('__ns.UI.state.activities.eventType') is None and A.ev('__ns.UI.state.activities.eventDate') is None)
check('activities toolbar fits minimum width',A.ev('__bar.leftX+__bar.rightX<=480'))
A.ex("__ns.UI.state.activities.kind='help'; __ns.UI:Refresh(); __bar.casualNear:Click(); __bar.casualAvailability:Click()")
check('switching board restores level and availability controls',A.ev('__ns.UI.state.activities.near') is True and A.ev('__ns.UI.details.kind')=='helperform')
A.ex("__ns.UI.state.activities.kind='events'; __ns.UI:Refresh()")
A.ex("__ns.UI:OpenDetails('eventform','new'); __click('Choose type'); EPUGuildMenu.rows[4]:Click(); __click('Pick date')")
check('date picker creates all 42 cells',A.ev('#EPUGuildActivityDatePicker.days')==42)
A.ex("EPUGuildActivityDatePicker.days[20]:Click()")
check('date selection preserves the form and local time',A.ev('__ns.UI.details.kind')=='eventform' and len(A.ev('__ns.UI.details.pools.box[4]:GetText()'))==16)
A.ex("""local b=__ns.UI.details.pools.box
b[1]:SetText('UI fishing'); b[4]:SetText(date('%Y-%m-%d %H:%M',__now+7200)); b[7]:SetText('5'); b[8]:SetText('60'); __click('Create event'); __ui=__ns.UI.details.key""")
check('actual type menu and form create fishing activity',A.ev('__ns.CasualStore().guildEvents[__ui].kind')=='fishing' and A.ev('__ns.CasualStore().guildEvents[__ui].minLevel')==5)
A.ex("__grid=__ns.ActivityCalendarDays(2028,2)")
check('leap day appears once in month grid',A.ev('(function() local n=0 for _,d in ipairs(__grid) do if d.key=="2028-02-29" then n=n+1 end end return n end)()')==1)
A.ex("local days,y,m=__ns.ActivityCalendarDays(2026,13); __normal=(y==2027 and m==1)")
check('month navigation crosses year boundary',A.ev('__normal'))
check('missing native calendar falls back safely',A.ev('__ns.PrepareWoWCalendar(event)') is False)

# Native values/structs follow Forever's generated CalendarDocumentation.lua.
A.ex("""Enum=Enum or {}; Enum.CalendarStatus={Accepted=2,Declined=3,Confirmed=4,Out=5,Standby=6,Signedup=7,NotSignedup=8,Tentative=9}
Enum.CalendarEventType={Dungeon=1,Other=4}
local c=date('!*t',__now)
C_DateAndTime={GetCurrentCalendarTime=function() local t=date('!*t',__now); return {year=t.year,month=t.month,monthDay=t.day,hour=t.hour,minute=t.min} end}
local r=__ns.CasualStore().guildEvents[event]; local c=date('!*t',r.starts)
__info={title=r.title,description=__ns.EventCalendarDescription(event,r),creator=r.who,calendarType='GUILD_EVENT',time={year=c.year,month=c.month,monthDay=c.day,hour=c.hour,minute=c.min}}
__invites={{name='Chris Baker',inviteStatus=7},{name='Tyler Baker',inviteStatus=3},{name='Pip Baker',inviteStatus=9},{name='Unknown Person',inviteStatus=7}}
C_Calendar={GetEventInfo=function() return __info end,AreNamesReady=function() return true end,GetNumInvites=function() return #__invites end,EventGetInvite=function(i) return __invites[i] end}
""")
check('linked event accepts native attendee snapshot',A.ev('__ns.ReadOpenCalendarSignups()') is True)
check('deduped calendar decline overrides addon going',A.ev('__ns.EventCounts(event).going')==1 and A.ev('__ns.EventCounts(event).declined')==1 and A.ev('#__ns.EventResponses(event)')==3)
check('calendar attendees retain EPU role and note',A.ev('(function() for _,r in ipairs(__ns.EventResponses(event)) do if r.who=="Tyler Baker" then return r.role=="m" and r.note=="Can help beginners" and r.source=="WoW calendar" end end end)()'))
A.ex("__invites[2].inviteStatus=7; __fire('CALENDAR_UPDATE_INVITE_LIST',false)")
check('partial native list cannot overwrite complete snapshot',A.ev('__ns.EventCounts(event).going')==1)
A.ex("__fire('CALENDAR_UPDATE_INVITE_LIST',true)")
check('native list updates refresh combined attendees',A.ev('__ns.EventCounts(event).going')==2)
A.ex("__info.creator='Pip Baker'")
check('another creator cannot impersonate linked event',A.ev('__ns.ReadOpenCalendarSignups()') is False)
A.ex("__info.creator='Chris Baker'; __info.title='Different event'")
check('different event cannot contaminate signups',A.ev('__ns.ReadOpenCalendarSignups()') is False)
A.ex("__info.title='Relaxed fishing'; __info.time.minute=(__info.time.minute+1)%60")
check('changed native time must be reconciled before matching',A.ev('__ns.OpenCalendarMatches(event)') is False)
A.ex("__info.time.minute=(__info.time.minute+59)%60; __sent=0; C_Calendar.EventTentative=function() __sent=__sent+1 end")
check('explicit both action updates only own response',A.ev("__ns.CalendarRespond(event,'tentative','g','Maybe')") is True and A.ev('__sent')==1 and A.ev("__ns.CasualStore().eventResponses[event..'\\030'..__ns.me].state")=='tentative')
check('unacknowledged call does not invent native status',A.ev('__ns.EventCounts(event).going')==2)
A.ex("__info.isLocked=true")
check('locked event cannot send native response',A.ev("__ns.CalendarRespond(event,'tentative','g','')") is False and A.ev('__sent')==1)
A.ex("__info.isLocked=false; C_Calendar.IsActionPending=function() return true end")
check('pending native actions cannot be sent twice',A.ev("__ns.CalendarRespond(event,'tentative','g','')") is False and A.ev('__sent')==1)
A.ex("C_Calendar.IsActionPending=function() return false end")
A.ex("__info.isLocked=false; C_Calendar.EventTentative=function() error('restricted') end")
check('restricted native response leaves EPU unchanged',A.ev("__ns.CalendarRespond(event,'tentative','m','Changed')") is False and A.ev("__ns.CasualStore().eventResponses[event..'\\030'..__ns.me].note")=='Maybe')
A.ex("__advance(181)")
check('calendar snapshots expire to clearly separate EPU data',A.ev('__ns.CalendarSignupSnapshot(event)') is None and A.ev('#__ns.EventResponses(event)')==2)

# Draft creation writes a draft only; AddEvent is intentionally never called.
A.ex("""__info=nil; __created=0; __published=0; __set={}; __dayEvents={}
CalendarFrame=NewMock(); CalendarFrame.militaryTime=false; CalendarFrame:Show()
CalendarCreateEventFrame=NewMock(); CalendarCreateEventFrame:Hide()
CalendarCreateEventTitleEdit=NewMock(); CalendarCreateEventDescriptionContainer={ScrollingEditBox=NewMock()}
ToggleCalendar=function() CalendarFrame:Show() end
C_Calendar.IsEventOpen=function() return false end
C_Calendar.SetAbsMonth=function(m,y) __set.month=m; __set.year=y end
C_Calendar.GetMonthInfo=function() return {month=__set.month,year=__set.year} end
C_Calendar.GetNumDayEvents=function() return #__dayEvents end
C_Calendar.GetDayEvent=function(_,_,i) return __dayEvents[i] end
C_Calendar.CreateGuildSignUpEvent=function() end
C_Calendar.AddEvent=function() __published=__published+1 end
C_Calendar.EventSetTitle=function(v) __set.title=v end
C_Calendar.EventSetDescription=function(v) __set.description=v end
C_Calendar.EventSetDate=function(m,d,y) __set.day=d end
C_Calendar.EventSetTime=function(h,m) __set.hour=h; __set.minute=m end
C_Calendar.EventSetType=function(t) __set.kind=t end
CalendarFrame_Update=function() local c=date('!*t',__ns.CasualStore().guildEvents[event].starts); CalendarDayButton1=NewMock(); CalendarDayButton1.day=c.day; CalendarDayButton1.monthOffset=0 end
CalendarDayContextMenu_CreateGuildEvent=function(b) __created=__created+1; CalendarCreateEventFrame:Show() end
CalendarCreateEvent_UpdateEventTime=function() end; CalendarCreateEvent_UpdateEventType=function() end
""")
check('native draft uses guild event UI without publishing',A.ev('__ns.PrepareWoWCalendar(event)') is True and A.ev('__created')==1 and A.ev('__published')==0)
check('native draft includes link marker and server clock',A.ev('__set.description:find(__ns.EventCalendarMarker(event),1,true)~=nil') and A.ev('__set.title')=='Relaxed fishing' and A.ev('__set.hour')==A.ev("tonumber(select(2,__ns.EventTimes(__ns.CasualStore().guildEvents[event].starts)):sub(12,13))"))
check('existing native draft is never overwritten',A.ev('__ns.PrepareWoWCalendar(event)') is False and A.ev('__created')==1)
A.ex("CalendarCreateEventFrame:Hide(); __dayEvents={{title='Relaxed fishing',calendarType='GUILD_EVENT'}}")
check('matching title on same date prevents duplicate draft',A.ev('__ns.PrepareWoWCalendar(event)') is False and A.ev('__created')==1)
A.ex("__ns.UI:OpenDetails('eventform','new')")
check('new event has a useful title and group options start collapsed',bool(A.ev('__ns.UI.details.pools.box[1]:GetText()')) and not A.ev('__ns.UI.details.pools.box[5]:IsShown()'))
A.ex("__ns.UI.details.pools.box[1]:SetText('My custom event');__ns.UI.details.pools.box[3]:SetText('Bring bait');__click('Group options')")
check('expanding options preserves edits',A.ev('__ns.UI.details.pools.box[1]:GetText()')=='My custom event' and A.ev('__ns.UI.details.pools.box[3]:GetText()')=='Bring bait' and A.ev('__ns.UI.details.pools.box[5]:IsShown()'))
A.ex("__ns.UI.details.pools.box[6]:SetText('12');__click('Hide group options');__click('Choose type');EPUGuildMenu.rows[1]:Click()")
check('type preset preserves custom title and group size',A.ev('__ns.UI.details.pools.box[1]:GetText()')=='My custom event' and A.ev('__ns.UI.details.pools.box[6]:GetText()')=='12')
A.ex("__click('In 15 min')")
check('quick start uses local time and preserves draft',abs(A.ev('__ns.ParseEventLocal(__ns.UI.details.pools.box[4]:GetText())-__now')-900)<60)
# Reuse the fixed-height date preview as the news heading, reproducing the
# screenshot sequence rather than only exercising a fresh font string.
A.ex("__ginfo='A friendly guild. Everyone is welcome.';__motd='Welcome!';__ns.UI.details.pools.text[2]:SetHeight(44);__ns.UI:OpenDetails('motd','motd')")
check('news heading clears stale fixed text height',A.ev('__ns.UI.details.pools.text[2]._h')==14)
check('new activity UI raises no runtime errors',A.ev('__errors') in (None,0))
print('Typed activities and native calendar:',check.failed,'failed')
sys.exit(bool(check.failed))
