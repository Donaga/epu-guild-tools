"""Chat history: whispers (and opt-in guild/officer chat) kept across reloads, on this PC only."""
from simcore import *

A = Client('Chris Baker'); clients[A.name] = A
tick(30)
A.ex('''function __labels() local t={} for _,b in ipairs(__ns.UI.details.pools.btn) do if b:IsShown() then t[#t+1]=b.text:GetText() end end return table.concat(t,"|") end
function __texts() local t={} for _,f in ipairs(__ns.UI.details.pools.text or {}) do if f:IsShown() then t[#t+1]=f:GetText() end end return table.concat(t,"\\n") end
function __click(label) for _,b in ipairs(__ns.UI.details.pools.btn) do if b:IsShown() and b.text:GetText()==label then b:GetScript("OnClick")(b); return true end end error("Missing "..label) end''')
A.ex('__fire("CHAT_MSG_WHISPER","need a tank for DM?","Tyler Baker-Forever")')
A.ex('__fire("CHAT_MSG_WHISPER_INFORM","sure, 10 min","Tyler Baker-Forever")')
A.ex('__fire("CHAT_MSG_GUILD","anyone selling linen?","Pip Baker")')
check('whispers are kept by default', A.ev('#__ns.ChatLog("whisper")') == 2)
check('guild chat is off until you turn it on', A.ev('#__ns.ChatLog("guild")') == 0)
check('outgoing whispers are marked', A.ev('__ns.ChatLog("whisper")[2].out') is True)
A.ex('__ns.SetChatKeep("guild", true); __fire("CHAT_MSG_GUILD","anyone selling linen?","Pip Baker")')
check('guild chat is kept once turned on', A.ev('#__ns.ChatLog("guild")') == 1)
A.ex('__isTrusted=false; __ns.IsTrusted=function() return false end; __ns.SetChatKeep("officer", true); __fire("CHAT_MSG_OFFICER","promo list","Pip Baker")')
check('officer chat is never kept for non-officers', A.ev('#__ns.ChatLog("officer")') == 0)
A.ex('__ns.IsTrusted=function() return true end; __fire("CHAT_MSG_OFFICER","promo list","Pip Baker")')
check('officers can keep officer chat', A.ev('#__ns.ChatLog("officer")') == 1)
A.ex('issecretvalue=function(v) return v=="SECRET" end; __fire("CHAT_MSG_WHISPER","SECRET","Tyler Baker-Forever"); issecretvalue=nil')
check('hidden combat messages are kept as a placeholder', 'hid this message' in A.ev('__ns.ChatLog("whisper")[3].msg'))
# replay after a reload
A.ex('__log={}; __ns.chatReplayed=nil; __ns.ReplayChat()')
log = A.ev('table.concat(__log,"\\n")')
check('a reload puts recent whispers back in chat', 'need a tank for DM?' in log and 'To ' in log and 'whispers:' in log)
check('and guild chat when kept', '[Guild]' in log)
check('replayed names are clickable player links', '|Hplayer:Tyler Baker-Forever|h' in log)
A.ex('__ns.cdb.chatkeep.replay=false; __log={}; __ns.ReplayChat()')
check('replay can be turned off', A.ev('#__log') == 0)
# the panel
A.ex('__ns.ShowChatHistory("whisper")')
lb = A.ev('__labels()'); tx = A.ev('__texts()')
check('the panel has channel tabs including officer chat for officers', 'Whispers' in lb and 'Guild chat' in lb and 'Officer chat' in lb)
check('the panel lists saved whispers', 'need a tank for DM?' in tx)
check('Whisper back lists recent people', 'Tyler Baker' in lb)
A.ex('__click("Clear whispers")')
check('Clear empties the channel', A.ev('#__ns.ChatLog("whisper")') == 0)
A.ex('SlashCmdList.EPUGUILD("chat")')
check('/epu chat opens it', A.ev('__ns.UI.details.kind') == 'chathistory')
print('Chat history tests:', check.failed, 'failed')
sys.exit(1 if check.failed else 0)
