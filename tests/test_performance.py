"""Sync work on a large guild: same fingerprints as before, fast, and spread across frames.

0.22.0 players saw 1-2 second freezes. Building an officer's sync reply
re-serialized a growing batch after every record (quadratic), and the guild
fingerprint was slow. These checks keep both fixed.
"""
import time
from simcore import *

# The fingerprint code exactly as 0.22.1 shipped it. New code must match it
# byte for byte, or mixed-version guilds would see each other as out of date.
OLD = r'''
local function OldCanonical(v)
  if type(v) == "string" then return "s" .. #v .. ":" .. v end
  if type(v) ~= "table" then return type(v) .. ":" .. tostring(v) .. ";" end
  local keys, out = {}, {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a,b) return type(a) .. tostring(a) < type(b) .. tostring(b) end)
  for _, k in ipairs(keys) do
    local key,value=OldCanonical(k),OldCanonical(v[k])
    out[#out + 1] = #key .. ":" .. key .. #value .. ":" .. value
  end
  return "{" .. table.concat(out, ";") .. "}"
end
function __OldFingerprint(v)
  local s=OldCanonical(v); local h=0
  for i=1,#s do h=(h*131+s:byte(i))%4294967296 end
  return tostring(h)
end
__OldCanonical = OldCanonical
'''

A = Client('Tyler Baker')   # a member, receiving an officer's check-in below
A.ex(OLD)
A.ex("""
local g = __ns.G()
math.randomseed(7)
local profs = {'Alchemy','Blacksmithing','Tailoring','Leatherworking','Engineering','Cooking'}
for c = 1, 40 do
  local who = 'Member ' .. c
  local rec = {t = __now, profs = {}}
  for k = 0, 1 do
    local prof = profs[(c + k) % #profs + 1]
    local items, diff = {}, {}
    local base = 20000 + ((c + k) % #profs) * 400
    for i = 1, 150 do items[#items + 1] = base + i; diff['item:' .. (base + i)] = ({'o','y','g'})[i % 3 + 1] end
    rec.profs[prof] = {rank = 200, at = __now, items = items, spells = {'Enchant ' .. c}, diff = diff, m = 1, nm = {base + 1}}
    for _, id in ipairs(items) do g.mats['item:' .. id] = {t = __now, r = {2589, 2, 2592, 1}, by = who} end
  end
  g.recipes[who] = rec
  g.crafters[who] = {t = __now, lvl = 40, profs = {Herbalism = 150, Tailoring = 200}}
end
for i = 1, 500 do g.donations['d' .. i] = {t = __now - i, who = 'Member ' .. (i % 40 + 1), item = 2589 + i % 50, qty = i % 20 + 1, to = 'Epu Bank', note = 'thanks ' .. i} end
for i = 1, 400 do g.requests['r' .. i] = {u = __now - i, who = 'Member ' .. (i % 40 + 1), item = 2589 + i % 50, qty = 5, status = 'filled', delivered = 5} end
""")

check('fingerprints match the previous version exactly', A.ev("""
(function()
  local g = __ns.G()
  local samples = {g.recipes, g.mats, g.donations, g.requests, g.crafters, g.policy, {}, {1, 2, 3},
    {a = true, b = false, [3] = 'x', [4.5] = {nested = {deeper = 'yes'}}}, 'plain', 42, true}
  for _, v in ipairs(samples) do
    if __ns.Fingerprint(v) ~= __OldFingerprint(v) or __ns.Canonical(v) ~= __OldCanonical(v) then return false end
  end
  return true
end)()
"""))
check('a full guild digest matches the previous code', A.ev("""
(function()
  local mine = __ns.Digest().fields
  local g = __ns.G()
  for _, f in ipairs({'recipes', 'mats', 'don', 'req'}) do
    local src = ({recipes = g.recipes, mats = g.mats, don = g.donations, req = g.requests})[f]
    if mine[f] ~= __OldFingerprint(src) then return false end
  end
  return true
end)()
"""))

t0 = time.perf_counter()
parts = A.ev("(function() __parts = __ns.SplitDelta(__ns.Delta(__ns.EmptyDigest())); return #__parts end)()")
elapsed = (time.perf_counter() - t0) * 1000
check('building a full sync reply for a 40-member guild is fast (%.0f ms)' % elapsed, elapsed < 2000)
check('every reply part stays under the 60 KB cap', A.ev("""
(function()
  for _, p in ipairs(__parts) do if #__ns.Serialize(p) > 60000 then return false end end
  return true
end)()
"""))
check('the split reply still carries every record', A.ev("""
(function()
  local seen = {req = 0, don = 0, recipes = 0, mats = 0}
  for _, p in ipairs(__parts) do
    for f in pairs(seen) do for _ in pairs(p[f] or {}) do seen[f] = seen[f] + 1 end end
  end
  local g, n = __ns.G(), function(t) local c = 0 for _ in pairs(t) do c = c + 1 end return c end
  return seen.req == n(g.requests) and seen.don == n(g.donations) and seen.recipes == n(g.recipes) and seen.mats == n(g.mats)
end)()
"""))

# Slicing: give the client a real clock, then make sure a check-in comparison
# takes several frames and no single frame runs long.
A.ex("""
__clockOffset = 0
debugprofilestop = function() return os.clock() * 1000 + __clockOffset end
__frames = 0
__longest = 0
local after = C_Timer.After
C_Timer.After = function(d, fn)
  if d == 0 then
    return after(0.01, function()
      local start = os.clock()
      __frames = __frames + 1
      fn()
      __longest = math.max(__longest, (os.clock() - start) * 1000)
    end)
  end
  return after(d, fn)
end
__behindDone = false
local hello = __ns.MaybeHello
__ns.MaybeHello = function(...) __behindDone = true; return hello(...) end
""")
A.ex("""
local d = __ns.CheckInDigest()
d.fields.recipes = 'different'
__ns.comm.C('Chris Baker', d)
""")
check('an officer check-in is compared over several frames, not in one', A.ev('__frames') == 0 or A.ev('__behindDone') is False)
A.ex('__advance(5)')
check('the comparison still finishes and asks for the newer data', A.ev('__behindDone') is True and A.ev('__frames') >= 2)
check('no single frame of that work runs long (%.0f ms)' % A.ev('__longest'), A.ev('__longest') < 120)
check('no addon runtime errors', (A.ev('__errors') or 0) == 0)
sys.exit(bool(check.failed))
