"""Someone logs off while EPU is still sending them a long whisper (for
example shared guild chat): no wall of "No player named ... is currently
playing." lines, and the rest isn't sent."""
from simcore import *
for n in ['Chris Baker', 'Tyler Baker']: clients[n] = Client(n)
tick(60)
A = clients['Chris Baker']
ERR = "No player named 'Laurelin Fishbank' is currently playing."
A.ex('for i=1,30 do __ns.Send("J",{lines={{t=time(),w="X",m=string.rep("y",240)}}},"WHISPER","Laurelin Fishbank") end')
tick(2)
queued = A.ev('__ns.QueueLength()')
check('a long answer is still on its way', queued > 0)
check('the error after an EPU whisper is hidden', A.ev('__filtered("CHAT_MSG_SYSTEM", %r)' % ERR) is True)
A.ex('__fire("CHAT_MSG_SYSTEM", %r)' % ERR)
check('the rest is not sent to someone who logged off', A.ev('__ns.QueueLength()') == 0)
check('the error for someone EPU never whispered still shows',
      A.ev('__filtered("CHAT_MSG_SYSTEM", "No player named \'Gillian Jet\' is currently playing.")') is False)
A.ex('SendChatMessage("you there?", "WHISPER", nil, "Laurelin Fishbank")')
check('the error still shows after a whisper you typed', A.ev('__filtered("CHAT_MSG_SYSTEM", %r)' % ERR) is False)
check('other system lines are untouched', A.ev('__filtered("CHAT_MSG_SYSTEM", "Donaga Gaelige has gone offline.")') is False)
print('Offline whisper tests:', check.failed, 'failed')
sys.exit(1 if check.failed else 0)
