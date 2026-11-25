"""Pop-out messenger: the typing box can sit at the bottom instead of the top.

Chat settings (the Opts popup, opened from the messenger, Settings > Pop-out chat
and log windows, or /epu logs; and the Chat page's settings) flips it. The
messages, the search box and the tabs lay out around it either way.
"""
from simcore import *

A = Client('Chris Baker')
clients[A.name] = A
tick(30)
# Record anchor points (the stubs drop them) so the layout can be checked.
A.ex('''local M = getmetatable(CreateFrame("Frame"))
M.SetPoint = function(self, p, a, b, c, d)
  self._pts = self._pts or {}
  local x, y
  if type(a) == "number" then x, y = a, b elseif type(b) == "string" then x, y = c, d else x, y = 0, 0 end
  if p then self._pts[p] = (x or 0) .. "," .. (y or 0) end
end
M.ClearAllPoints = function(self) self._pts = {} end
function __pt(w, p) return w._pts and w._pts[p] end
function __popLabels() local t={} for _,b in ipairs(EPUGuildChatOptsPopup.pool.used) do if b:IsShown() and b.text then t[#t+1]=b.text:GetText() end end return table.concat(t,"|") end
function __popClick(label) for _,b in ipairs(EPUGuildChatOptsPopup.pool.used) do if b:IsShown() and b.text and b.text:GetText()==label then b:GetScript("OnClick")(b); return true end end error("Missing "..label) end
function __labels() local t={} for _,b in ipairs(__ns.UI.details.pools.btn) do if b:IsShown() then t[#t+1]=b.text:GetText() end end return table.concat(t,"|") end
function __click(label) for _,b in ipairs(__ns.UI.details.pools.btn) do if b:IsShown() and b.text:GetText()==label then b:GetScript("OnClick")(b); return true end end error("Missing "..label) end''')
A.ex('__fire("CHAT_MSG_GUILD","anyone selling linen?","Pip Baker")')
A.ex('__ns.ChatOptions().windows="tabs"; __ns.OpenMessenger("guild")')
M = 'EPUGuildMessenger'


def pt(w, p):
    return A.ev(f'__pt({M}.{w}, "{p}")')


check('the messenger opens', A.ev(f'{M}:IsShown()'))
check('by default the typing box is at the top, under the tabs',
      A.ev('__ns.ChatBoxAtBottom()') is False and pt('box', 'TOPLEFT') == '10,-34' and pt('send', 'TOPRIGHT') == '-10,-34')
check('by default the messages sit under the box', pt('scroll', 'TOPLEFT') == '12,-66' and pt('scroll', 'BOTTOMRIGHT') == '-12,16')
check('the tabs are at the top', A.ev(f'__pt({M}.tabs[1], "TOPLEFT")') == '10,-7')

# --- entry point: Settings > Pop-out chat and log windows opens Chat settings with the toggle ---
A.ex('__ns.UI:Show(); __ns.UI:SetView("settings")')
A.ex('for _,r in ipairs(__ns.UI.rows) do if r:IsShown() and r.data and r.data.key=="logs" then r:GetScript("OnClick")(r) end end')
check('Settings opens Chat settings', A.ev('EPUGuildChatOptsPopup ~= nil and EPUGuildChatOptsPopup:IsShown()'))
check('Chat settings offers the typing box place', 'Typing box: Top' in A.ev('__popLabels()'))
A.ex('__popClick("Typing box: Top")')
check('the setting is saved', A.ev('__ns.ChatBoxAtBottom()') is True and A.ev('__ns.ChatOptions().boxBottom') is True)
check('the button shows the new place', 'Typing box: Bottom' in A.ev('__popLabels()'))
check('the typing box moves to the bottom at once',
      pt('box', 'BOTTOMLEFT') == '10,10' and pt('box', 'BOTTOMRIGHT') == '-74,10' and pt('box', 'TOPLEFT') is None)
check('Send sits beside it, clear of the resize grip', pt('send', 'BOTTOMRIGHT') == '-20,10')
check('the messages fill the space between the tabs and the box',
      pt('scroll', 'TOPLEFT') == '12,-34' and pt('scroll', 'BOTTOMRIGHT') == '-12,40')
check('the tabs stay at the top', A.ev(f'__pt({M}.tabs[1], "TOPLEFT")') == '10,-7')
check('the box and Send are still shown', A.ev(f'{M}.box:IsShown() and {M}.send:IsShown()'))

# typing still sends
A.ex(f'__log={{}}; {M}.box:SetText("hi all"); {M}.send:GetScript("OnClick")({M}.send)')
check('Send still works with the box at the bottom', '[GUILD] hi all' in A.ev('table.concat(__log,"\\n")'))

# search takes the box's place at the bottom
A.ex(f'{M}.findBtn:GetScript("OnClick")({M}.findBtn)')
check('the search box takes the typing box place at the bottom',
      A.ev(f'{M}.find:IsShown()') and pt('find', 'BOTTOMLEFT') == '10,10' and pt('find', 'BOTTOMRIGHT') == '-20,10')
A.ex(f'{M}.findBtn:GetScript("OnClick")({M}.findBtn)')

# one window per person: no tabs, so the messages start right under the title bar
A.ex('__ns.ChatOptions().windows="separate"; __w = __ns.OpenMessenger("w:Tyler Baker")')
W = '__w'
check('a per-person window puts its box at the bottom too',
      A.ev(f'__pt({W}.box, "BOTTOMLEFT")') == '10,10' and A.ev(f'__pt({W}.scroll, "TOPLEFT")') == '12,-8')
check('an empty conversation points to the box below', 'Type below' in A.ev(f'{W}.text:GetText()'))

# the Chat page's settings flip it back, and open windows follow
A.ex('__ns.UI:OpenDetails("chatsettings","all")')
check('the Chat page settings show the place too', 'Pop-out typing box: Bottom' in A.ev('__labels()'))
A.ex('__click("Pop-out typing box: Bottom")')
check('switching back puts the box at the top', A.ev('__ns.ChatBoxAtBottom()') is False and pt('box', 'TOPLEFT') == '10,-34'
      and pt('box', 'BOTTOMLEFT') is None and pt('scroll', 'TOPLEFT') == '12,-66')
check('a per-person window goes back to the top too',
      A.ev(f'__pt({W}.box, "TOPLEFT")') == '10,-8' and A.ev(f'__pt({W}.scroll, "TOPLEFT")') == '12,-40')
check('an empty conversation points to the box above again', 'Type above' in A.ev(f'{W}.text:GetText()'))
check('the Chat page button follows', 'Pop-out typing box: Top' in A.ev('__labels()'))

check('no runtime errors', A.ev('__errors') in (None, 0))
print('Chat box position tests:', check.failed, 'failed')
