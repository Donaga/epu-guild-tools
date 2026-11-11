"""Herb eligibility, market provenance, and personal recipe margins."""
from simcore import *

A = Client('Chris Baker')
A.ex("""
AHledgerAPI={GetPrice=function(id)
  if id==2447 then return {median=4000,minBuyout=3000,soldPerDay=120,market='Forever test market'} end
  if id==13468 then return {median=400000,soldPerDay=20} end
  if id==2996 then return {median=10000,soldPerDay=12} end
end}
TSM_API={GetCustomPriceValue=function(source,item)
  if item~='i:2447' then return end
  return ({dbregionsaleavg=5000,dbregionsoldperday=44,dbregionsalerate=.6})[source]
end}
Auctionator={API={v1={GetAuctionPriceByItemID=function(_,id) if id==2447 then return 6000 end end}}}
""")
check('local sales estimates leave sell-through unknown', A.ev("""
(function()
  for _,r in ipairs(__ns.GatheringMarketRows('ledger')) do
    if r.item==2447 then return r.price==4000 and r.volume==120 and r.rate==nil end
  end
end)()
"""))
check('skill filter excludes herbs beyond the current rank', A.ev("""
(function()
  for _,r in ipairs(__ns.GatheringMarketRows('ledger',70)) do
    if not r.skill or r.skill>70 then return false end
  end
  return true
end)()
"""))
check('TSM keeps sale price, volume, and rate in one regional view', A.ev("""
(function() local r=__ns.GatheringMarketRows('tsm')[1]; return r.item==2447 and r.price==5000 and r.volume==44 and r.rate==.6 end)()
"""))
check('Auctionator prices never supply a made-up volume or sell-through', A.ev("""
(function() local r=__ns.GatheringMarketRows('auctionator')[1]; return r.item==2447 and r.price==6000 and r.volume==nil and r.rate==nil end)()
"""))

# Exercise the profession scanner, including a second recipe with incomplete costs.
A.ex("""
GetTradeSkillLine=function() return 'Tailoring', 40 end
GetNumTradeSkills=function() return 3 end
GetTradeSkillInfo=function(i) return 'Recipe '..i,'optimal' end
GetTradeSkillItemLink=function(i) return 'item:'..({2996,2997,2998})[i] end
GetTradeSkillNumReagents=function(i) return i==2 and 2 or 1 end
GetTradeSkillReagentInfo=function(i,j) return 'Reagent',nil,j==1 and 3 or nil end
GetTradeSkillReagentItemLink=function(i,j) if j==1 then return 'item:2447' end end
GetTradeSkillNumMade=function(i) return 2,i==3 and 4 or 2 end
__ns.IsBoP=function() return false end
__fire('TRADE_SKILL_SHOW'); __advance(1)
""")
check('scan rejects incomplete reagent lists and variable outputs', A.ev("""
__ns.cdb.recipes.Tailoring.market[2996]~=nil and __ns.cdb.recipes.Tailoring.market[2997]==nil and __ns.cdb.recipes.Tailoring.market[2998]==nil
"""))
check('craft ranks fixed output minus the market cost of each reagent', A.ev("""
(function()
  local r=__ns.CraftingMarketRows('ledger',{Tailoring=40})[1]
  return r.revenue==20000 and r.cost==9000 and r.score==11000 and r.quantity==2
end)()
"""))
check('recipes from an unlearned profession do not appear', A.ev("#__ns.CraftingMarketRows('ledger',{})")==0)
A.ex("""
__ns.UI.nav.membertools:Click()
for _,row in ipairs(__ns.UI.rows) do
  if row.data and row.data.key=='market' then row:Click(); break end
end
""")
check('Member tools opens the in-game chart', A.ev('EPUGuildGatheringMarket:IsShown() and EPUGuildGatheringMarket.context:GetText():find("plotted")~=nil'))
check('no addon runtime errors', (A.ev('__errors') or 0)==0)
sys.exit(bool(check.failed))
