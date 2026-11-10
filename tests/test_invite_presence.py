"""Non-guild presence: exact names, expiring reports and quiet manual invitations."""
from simcore import *
A=Client('Chris Baker'); B=Client('Tyler Baker'); P=Client('Pip Baker')
clients.update({c.name:c for c in (A,B,P)});tick(120)
for c in (A,B,P):
    c.ex('''CanGuildInvite=function() return true end
    __presenceNotices={};__ns.Notify=function(title,text,icon,context)
      if title=='Guild invite: online now' then table.insert(__presenceNotices,{title,text,context}) end
    end
    __ns.CasualStore().inviteRequests.m123={who='Fresh Applicant',requester='Applicant',by='Chris Baker',
      posted=__now,t=__now,cancelled=false,revision=123}
    ''')
P.ex('CanGuildInvite=function() return false end')
check('absent character is unknown, never presumed offline',A.ev("__ns.GuildInvitePresence('Fresh Applicant')")[:2]==('unknown','Unknown'))
A.ex('''__friends={{name='Fresh Applicant',connected=false},{name='Fresh Other',connected=true}}
C_FriendList={GetNumFriends=function() return #__friends end,GetFriendInfoByIndex=function(i) return __friends[i] end}
__ns.RefreshGuildInvitePresence()''')
check('exact full name required, not first-name match',A.ev("__ns.GuildInvitePresence('Fresh Applicant')")[:2]==('offline','Offline'))
check('offline has no online alert',A.ev('#__presenceNotices')==0)
A.ex("__friends[1].connected=true;__fire('FRIENDLIST_UPDATE')")
tick(2)
check('login sends an actionable notice',A.ev('#__presenceNotices')==1 and A.ev('__presenceNotices[1][3].key')=='m123')
check('positive sighting reaches another inviter',tick_until(lambda:B.ev("__ns.GuildInvitePresence('Fresh Applicant')")[0]=='reported',30))
check('other inviter gets online alert',B.ev('#__presenceNotices')==1)
check('member without invite permission has no online notice',P.ev('#__presenceNotices')==0)
tick(700)
check('continuously online does not nag every ten minutes',A.ev('#__presenceNotices')==1 and B.ev('#__presenceNotices')==1)
A.ex("__friends[1].connected=false;__ns.RefreshGuildInvitePresence();__friends[1].connected=true;__ns.RefreshGuildInvitePresence()")
check('new observed login after cooldown alerts again',A.ev('#__presenceNotices')==2)
A.ex("__friends[1].connected=false;__ns.RefreshGuildInvitePresence();__friends[1].connected=true;__ns.RefreshGuildInvitePresence()")
check('rapid reconnect does not spam',A.ev('#__presenceNotices')==2)
A.ex("__adds=0;C_FriendList.AddFriend=function(name) __adds=__adds+1;__added=name end")
check('tracking is an explicit user action',A.ev('__adds')==0 and A.ev("__ns.TrackGuildInvite('m123')") and A.ev('__added')=='Fresh Applicant')
P.ex('AddFriend=function() error("must not run") end')
check('tracking permission rechecked',not P.ev("__ns.TrackGuildInvite('m123')"))
A.ex("__ns.CommunityState().inviteDismissed={m123='Fresh Applicant'};__friends[1].connected=false;__ns.RefreshGuildInvitePresence();__now=__now+700;__friends[1].connected=true;__ns.RefreshGuildInvitePresence()")
check('dismissed request stays quiet',A.ev('#__presenceNotices')==2)
# Stop the reporting source. Old transient reports disappear, and unrelated
# /who results never establish that an absent character is offline.
A.ex('CanGuildInvite=function() return false end');tick(130)
check('stale remote sightings become unknown',B.ev("__ns.GuildInvitePresence('Fresh Applicant')")[0]=='unknown')
B.ex('''C_FriendList={GetNumWhoResults=function() return 1 end,GetWhoInfo=function() return {fullName='Fresh Other'} end}
__fire('WHO_LIST_UPDATE')''')
check('unrelated /who result does not mark offline',B.ev("__ns.GuildInvitePresence('Fresh Applicant')")[0]=='unknown')
B.ex("C_FriendList.GetWhoInfo=function() return {fullName='Fresh Applicant'} end;__fire('WHO_LIST_UPDATE')")
check('manual /who positive establishes recent presence',B.ev("__ns.GuildInvitePresence('Fresh Applicant')")[0]=='online')
B.ex('''C_FriendList=nil;GetNumFriends=function() return 1 end
GetFriendInfo=function() return 'Fresh Applicant',20,'Warrior','Duskwood',false end''')
check('legacy Friends API supported',B.ev("__ns.GuildInvitePresence('Fresh Applicant')")[0]=='offline')
B.ex('GetNumFriends=function() error("unavailable") end')
check('unavailable API falls back gracefully',B.ev("__ns.GuildInvitePresence('Never Seen')")[0]=='unknown')
B.ex("__ns.comm.I('Outsider',{id='m123',who='Fresh Applicant',revision=123,at=__now},'GUILD')")
check('unknown sender cannot report presence',B.ev("__ns.GuildInvitePresence('Never Seen')")[0]=='unknown')
check('no runtime errors',sum(c.ev('__errors') or 0 for c in (A,B,P))==0)
print('Invite presence:',check.failed,'failed');sys.exit(bool(check.failed))
