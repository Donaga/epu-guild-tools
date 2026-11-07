"""Connection-friendly login pacing and bounded retries; never suppress chat warnings."""
from simcore import *
A=Client('Chris Baker')
A.ex('''__advance(60); __timers={}; __out={}; __wire={}
ERR_CHAT_THROTTLED='Server message rate limited'
local real=C_ChatInfo.SendAddonMessage
C_ChatInfo.SendAddonMessage=function(...)
  table.insert(__wire,{at=GetTime(),message=select(2,...)})
  if __refuse then return Enum.SendAddonMessageResult.ChannelThrottle end
  return real(...)
end
__start=GetTime()
for i=1,10 do __ns.Send('Z',{i=i}) end
__advance(1)
''')
check('login-sized queue sends at most two packets in first second', A.ev('#__wire')==2)
check('initial packets are spaced rather than burst back-to-back', A.ev('__wire[2].at-__wire[1].at')>=0.55-0.001)
A.ex('__advance(20)')
check('paced queue drains without losing packets', A.ev('#__wire')==10 and A.ev('__ns.QueueLength()')==0)
check('normal pacing does not hit the prefix limit', A.ev('__dropped')==0)
A.ex('''__chatWire={}; local real=SendChatMessage
SendChatMessage=function(text,channel) table.insert(__chatWire,{text=text,channel=channel}); return real(text,channel) end
for i=1,6 do __ns.SendGuildChat('Needs line '..i) end
__advance(1)''')
check('visible guild posts share the conservative pacing',A.ev('#__chatWire')<=2)
A.ex('__advance(10)')
check('all queued guild post lines arrive',A.ev('#__chatWire')==6 and A.ev('__chatWire[6].channel')=='GUILD')
check('oversized visible chat is rejected before sending',A.ev('__ns.SendGuildChat(string.rep("x",256))') is False)
A.ex('__wire={}; __refuse=true; __ns.Send("Z",{retry=true})')
check('refused packet stays queued', A.ev('__ns.QueueLength()')==1)
check('first refusal starts a five-second cooldown', A.ev('__ns.NetworkStatus().pause')==5)
A.ex('__advance(4.9)')
check('no repeated send attempts during cooldown', A.ev('#__wire')==1)
A.ex('__advance(0.2)')
check('one retry occurs after cooldown', A.ev('#__wire')==2)
check('repeated refusal doubles the cooldown', A.ev('__ns.NetworkStatus().pause')==10)
A.ex('__refuse=false; __advance(11)')
check('retained packet succeeds after server recovers', A.ev('__ns.QueueLength()')==0 and A.ev('#__wire')==3)
check('retry sends the original packet', A.ev('__wire[1].message==__wire[3].message') is True)
A.ex('''__advance(1); __wire={}; __ns.Send('Z',{warning=true})
__fire('CHAT_MSG_SYSTEM',ERR_CHAT_THROTTLED)
__ns.Send('Z',{later=true})''')
check('server warning shortly after EPU traffic pauses its queue', A.ev('__ns.NetworkStatus().warnings')==1 and A.ev('__ns.NetworkStatus().pause')>0)
check('cooldown is visible in sync status', A.ev('__ns.SyncStatus()')[0]=='Sync cooling down')
A.ex('__advance(2)')
check('system warning prevents the next send attempt', A.ev('#__wire')==1)
A.ex('__advance(25)')
check('queue resumes after system warning cooldown', A.ev('__ns.QueueLength()')==0 and A.ev('#__wire')==2)
A.ex('__advance(5); __fire("CHAT_MSG_SYSTEM",ERR_CHAT_THROTTLED)')
check('warning with no recent EPU send is not attributed to EPU', A.ev('__ns.NetworkStatus().warnings')==1 and A.ev('__ns.NetworkStatus().pause')==0)
A.ex('__fire("CHAT_MSG_SYSTEM","Some unrelated system message")')
check('unrelated system messages are ignored', A.ev('__ns.NetworkStatus().warnings')==1)
A.ex('__refuse=true; __wire={}; __ns.Send("Z",{persistent=true}); __advance(180)')
check('persistent throttling uses bounded exponential backoff', A.ev('#__wire')<=7 and A.ev('__ns.NetworkStatus().pause')<=60)
check('persistent throttle still retains the message', A.ev('__ns.QueueLength()')==1)
A.ex('SlashCmdList.EPUGUILD("net")')
check('network diagnostics remain available', A.ev('__log[#__log]:find("Network:",1,true) ~= nil') is True)
check('no runtime errors', (A.ev('__errors') or 0)==0)
sys.exit(1 if check.failed else 0)
