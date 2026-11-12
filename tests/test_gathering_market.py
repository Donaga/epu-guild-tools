"""Herb eligibility, market provenance, and personal recipe margins."""
from simcore import *

A = Client('Chris Baker')
A.ex("""
AHledgerAPI={GetPrice=function(id)
  if id==2447 then return {median=4000,minBuyout=3000,soldPerDay=120,market='Forever test market',updated='2026-11-11',snapshot=true} end
  if id==13468 then return {median=400000,soldPerDay=20} end
  if id==2996 then return {median=10000,soldPerDay=12} end
end}
TSM_API={GetCustomPriceValue=function(source,item)
  if item~='i:2447' then return end
  return ({dbregionsaleavg=5000,dbregionsoldperday=44,dbregionsalerate=.6})[source]
end}
Auctionator={API={v1={GetAuctionPriceByItemID=function(_,id) if id==2447 then return 6000 end end}}}
""")
check('local prices use the current lowest listing and leave sell-through unknown', A.ev("""
(function()
  for _,r in ipairs(__ns.GatheringMarketRows('ledger')) do
    if r.item==2447 then return r.price==3000 and r.basis=='low' and r.volume==120 and r.rate==nil and r.updated=='2026-11-11' and r.snapshot end
  end
end)()
"""))
check('skill filter excludes herbs beyond the current rank', A.ev("""
(function()
  for _,r in ipairs(__ns.GatheringMarketRows('ledger',70)) do
    if (r.skill and r.skill>70) or (not r.skill and not r.unconfirmed) then return false end
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
  return r.revenue==20000 and r.cost==9000 and r.score==10000 and r.quantity==2
end)()
"""))
check('recipes from an unlearned profession do not appear', A.ev("#__ns.CraftingMarketRows('ledger',{})")==0)
A.ex("""
local scan = __ns.cdb.recipes.Tailoring.market
scan[4238]={quantity=1,reagents={2996,3,2320,3}}
scan[2996]={quantity=1,reagents={2589,2}}
GetItemCount=function(id) return ({[2996]=3,[2589]=4,[2320]=15})[id] or 0 end
__plan=__ns.CraftingMaterialPlan('ledger',{item=4238,recipe=scan[4238]},5,{Tailoring=40})
UnitClass=function() return 'Mage','MAGE' end
UnitFactionGroup=function() return 'Alliance' end
C_SkillInfo={GetSkillLineInfoByID=function(id)
  local name=({[182]='Herbalism',[197]='Tailoring',[356]='Fishing'})[id]
  if name then return {skillID=id,name=name,rank=90} end
end}
""")
check('five bags subtract carried bolts and cloth once', A.ev('__plan.direct[2996]==12 and __plan.steps[2996]==12 and __plan.base[2589]==20'))
check('carried thread is sufficient and unknown cloth price leaves buy estimate blank', A.ev('__plan.direct[2320]==0 and __plan.base[2320]==nil and __plan.baseCost==nil'))
A.ex("""
__ns.UI.nav.membertools:Click()
for _,row in ipairs(__ns.UI.rows) do
  if row.data and row.data.key=='market' then row:Click(); break end
end
""")
check('Market opens inside the main window on personal crafting', A.ev('__ns.UI.view=="market" and EPUGuildGatheringMarket:IsShown() and EPUGuildGatheringMarket:GetParent():GetParent()==__ns.UI and EPUGuildGatheringMarket.context:GetText():find("learned crafting professions")~=nil'))
A.ex('__ns.UI.search:SetText("does-not-exist")')
check('main window search filters market items', A.ev('EPUGuildGatheringMarket.empty:IsShown()'))
A.ex('EPUGuildGatheringMarket.professionGuides:Click()')
check('profession shortcut hides the market and opens all learned professions', A.ev("""
(function()
  local shown={}
  for _,row in ipairs(__ns.UI.rows) do
    if row:IsShown() and row.data then shown[row.data.key]=true end
  end
  return __ns.UI.view=='membertools' and not EPUGuildGatheringMarket:IsShown()
    and shown['guidechoice:profession:182'] and shown['guidechoice:profession:197']
    and shown['guidechoice:profession:356'] and not shown['guidechoice:leveling']
end)()
"""))
A.ex("SlashCmdList.EPUGUILD('market')")
check('slash command returns to the same Market tab', A.ev('__ns.UI.view=="market" and EPUGuildGatheringMarket:IsShown()'))
A.ex('EPUGuildGatheringMarket.gatherTab:Click()')
check('Gather opens the herb chart on demand', A.ev('EPUGuildGatheringMarket.chart:IsShown() and EPUGuildGatheringMarket.context:GetText():find("plotted")~=nil'))

A.ex("""
local hbd = {}
__routeX, __routeMap = .1, 37
hbd.GetPlayerZonePosition = function() return __routeX,.2,__routeMap end
hbd.GetZoneSize = function() return 1000,1000 end
LibStub = function(name) if name=='HereBeDragons-2.0' then return hbd end end
GetPlayerFacing=function() return 0 end
__ns.HERB_SPOTS[37] = {[2447]={{.15,.2},{.4,.2},{.8,.2}},[765]={{.11,.2}}}
for _, control in ipairs(__frames) do
  if control.row and control.row.item==2447 then control:Click(); break end
end
local market=EPUGuildGatheringMarket
market.yieldInput:SetText('30')
market.yieldInput:GetScript('OnEnterPressed')(market.yieldInput)
__estimate=market.selected.gph
__ns.GatheringRouteCommand('start',2447)
function __routeTick() EPUGuildRouteArrow:GetScript('OnUpdate')(EPUGuildRouteArrow,1) end
""")
check('a saved personal yield is multiplied by the current lowest listing', A.ev('__estimate')==90000)
check('a standalone route starts at the nearest spot for the chosen herb', A.ev("EPUGuildRouteArrow:IsShown() and EPUGuildRouteArrow.title:GetText():find('50 yd')~=nil"))
A.ex('__routeX=.15; __routeTick()')
check('arrival advances to the next unvisited spot', A.ev("EPUGuildRouteArrow.progress:GetText()=='Recorded spot 2 of 3'"))
A.ex("SlashCmdList.EPUGUILD('route next')")
check('manual skip continues through unvisited spots', A.ev("EPUGuildRouteArrow.progress:GetText()=='Recorded spot 3 of 3'"))
A.ex('__routeMap=42; __routeTick()')
check('leaving the zone hides the route arrow', not A.ev('EPUGuildRouteArrow:IsShown()'))
A.ex('__ns.RecordGatheringSpot(2447)')
check('manually recorded spots work in zones with no bundled data', A.ev('#(__ns.GatheringRoutePreview(2447))')==1)
check('no addon runtime errors', (A.ev('__errors') or 0)==0)

B = Client('Chris Baker')
B.ex("""
GetNumSkillLines=nil
GetSkillLineInfo=nil
C_SkillInfo={GetSkillLineInfoByID=function(id)
  if id==197 then return {skillID=id,name='Tailoring',rank=100} end
  if id==185 then return {skillID=id,name='Cooking',rank=105} end
end}
GetItemCount=function(id) return id==2447 and 1 or 0 end
__ns.cdb.recipes={Tailoring={market={
  [30000]={quantity=2,reagents={2447,2}},
  [30001]={quantity=1,reagents={2449,1}},
  [30002]={quantity=1,reagents={2447,1}},
  [30003]={quantity=1,reagents={2447,1}},
  [30004]={quantity=1,reagents={2447,1}},
  [30005]={quantity=1,reagents={785,1}},
}}}
AHledgerAPI={GetPrice=function(id)
  return ({
    [2447]={median=5000,minBuyout=4000}, [2449]={median=4000,minBuyout=3500},
    [30000]={median=10000,soldPerDay=3}, [30001]={median=5000,soldPerDay=12300},
    [30002]={median=8000,soldPerDay=10}, [30003]={median=5200,soldPerDay=100},
    [30004]={median=10000,soldPerDay=0}, [30005]={median=10000,soldPerDay=50},
  })[id]
end}
function __recommendations(sort, source) return __ns.CraftingMarketRows(source or 'ledger',{Tailoring=100},sort) end
""")
check('buy recommendations exclude losses after the faction cut, zero sales and missing materials prices', B.ev('#__recommendations("volume")')==3)
check('sort by daily sales prioritizes the fastest-selling profitable recipe', B.ev('__recommendations("volume")[1].item')==30001)
check('sort by profit prioritizes the largest margin after the faction cut', B.ev('__recommendations("profit")[1].item')==30000)
check('profit percentage is net profit divided by ingredient cost', B.ev('__recommendations("roi")[1].roi')==90)
check('combined ranking uses profit per finished item and market sales', B.ev('__recommendations("opportunity")[1].opportunity')==9225000)
check('the material budget uses the higher of median and lowest buyout', B.ev('__recommendations("profit")[1].profit')==9000)
check('a batch shopping list subtracts carried ingredients while keeping the same budget per unit', B.ev("""
(function()
  local plan=__ns.CraftingMaterialPlan('ledger',__recommendations('profit')[1],2,{Tailoring=100})
  return plan.direct[2447]==3 and plan.buyCost==15000
end)()
"""))
B.ex("""
SlashCmdList.EPUGUILD('market')
EPUGuildGatheringMarket.buyTab:Click()
EPUGuildGatheringMarket.buySort:Click()
EPUGuildMenu.rows[2]:Click()
""")
check('Buy & Craft sort menu changes the displayed sort', B.ev('EPUGuildGatheringMarket.buySort:GetText()')=='Sold/day')
check('large daily sales and small profits are readable in the recipe list', B.ev("""
(function()
  for _, button in ipairs(__frames) do
    if button.row and button.row.item==30001 and button.summary then
      return button.summary:GetText():find("7s 50c",1,true) and button.summary:GetText():find("12,300 sold/day",1,true)
    end
  end
end)()
"""))
B.ex("""
__ns.cdb.recipes.Blacksmithing={market={[30006]={quantity=1,reagents={2447,1}}}}
EPUGuildGatheringMarket.craftTab:Click()
""")
check('market shows unscanned learned professions and hides an old unlearned profession', B.ev("""
(function()
  local frame=EPUGuildGatheringMarket
  return #frame.professionChoices==2 and frame.professionChoices[1].label=='Cooking'
    and frame.professionChoices[1].right=='Open to scan'
    and frame.context:GetText():find('1 to scan',1,true)~=nil
end)()
"""))
B.ex("""
EPUGuildGatheringMarket.professionFilter:Click()
EPUGuildMenu.rows[2]:Click()
GetNumTradeSkills=nil
C_TradeSkillUI={
  OpenTradeSkill=function(id) __opened=id; __fire('TRADE_SKILL_DATA_SOURCE_CHANGED'); return true end,
  GetBaseProfessionInfo=function() return {professionID=185,professionName='Cooking',skillLevel=105} end,
  GetAllRecipeIDs=function() return {555} end,
  GetRecipeInfo=function() return {learned=true,name='Test cooked item'} end,
  GetRecipeSchematic=function() return {
    outputItemID=30006,quantityMin=1,quantityMax=1,
    reagentSlotSchematics={{quantityRequired=1,reagents={{itemID=2447}}}},
  } end,
}
EPUGuildGatheringMarket.openProfession:Click()
EPUGuildMenu.rows[1]:Click()
__advance(1.1)
""")
check('open-to-scan uses the selected learned profession and refreshes the current filter after a modern scan', B.ev("""
__opened==185 and __ns.cdb.recipes.Cooking.market[30006]~=nil
  and EPUGuildGatheringMarket.professionFilter:GetText()=="Cooking"
  and not EPUGuildGatheringMarket.empty:IsShown()
"""))
check('modern profession scan leaves no runtime errors', (B.ev('__errors') or 0)==0)
B.ex("""
local original=C_SkillInfo.GetSkillLineInfoByID
C_SkillInfo.GetSkillLineInfoByID=function(id)
  if id==186 then return {skillID=id,name='Mining',rank=70} end
  return original(id)
end
EPUGuildGatheringMarket.gatherTab:Click()
""")
check('Gather defaults to Mining for a miner with no Herbalism and offers an ore route', B.ev("""
EPUGuildGatheringMarket.gatherProfession:GetText()=='Mining'
  and EPUGuildGatheringMarket.routeButton:IsShown()
  and EPUGuildGatheringMarket.routeButton:GetText()=='Start ore route'
  and EPUGuildGatheringMarket.chart:IsShown()
"""))
check('Mining skill filters ore and fishing catalogs do not invent a fixed threshold', B.ev("""
(function()
  local mining=__ns.GatheringMarketRows('ledger',70,186)
  local ids={}
  for _,r in ipairs(mining) do ids[r.item]=true end
  return ids[2770] and ids[2771] and not ids[2772]
    and #__ns.GatheringMarketRows('ledger',1,356)>0 and #__ns.GatheringMarketRows('ledger',1,393)>0
end)()
"""))
B.ex("EPUGuildGatheringMarket.gatherProfession:Click(); EPUGuildMenu.rows[4]:Click()")
check('the gathering profession menu switches to Fishing', B.ev("EPUGuildGatheringMarket.gatherProfession:GetText()=='Fishing'"))
B.ex("EPUGuildGatheringMarket.buyTab:Click(); EPUGuildGatheringMarket.professionFilter:Click(); EPUGuildMenu.rows[1]:Click()")
check('the gold highlight follows the selected sort', B.ev("""
(function()
  for _,button in ipairs(__frames) do
    if button.row and button.row.item==30000 and button.name then
      return button.name:GetText():find('Top pick',1,true)~=nil
    end
  end
end)()
"""))

# --- 0.22.0 review fixes ----------------------------------------------------
C = Client('Chris Baker')
C.ex("""
__ns.IsBoP=function() return false end
GetNumSkillLines=nil
GetSkillLineInfo=nil
C_SkillInfo={GetSkillLineInfoByID=function(id)
  local name=({[164]='Blacksmithing',[182]='Herbalism',[393]='Skinning',[186]='Mining'})[id]
  if name then return {skillID=id,name=name,rank=157} end
end}
GetItemCount=function() return 0 end
__ns.VENDOR_PRICES={[2880]=100,[2320]=10}
AHledgerAPI={CREDIT='Prices from AHledger (ahledger.com)',GetPrice=function(id)
  return ({
    [90001]={median=249,minBuyout=75,soldPerDay=100,quantity=900,updated=__now-7*3600,snapshot=true},
    [2835]={median=3,minBuyout=3}, [2840]={median=100,minBuyout=79},
    [90002]={median=5000,minBuyout=4800,soldPerDay=10,quantity=5},
    [2320]={median=900,minBuyout=800},
    [90003]={median=700,soldPerDay=4},
    [90004]={median=300,minBuyout=9000,soldPerDay=4},
    [90005]={median=400,minBuyout=380,soldPerDay=50,quantity=20},
    [2589]={median=20,minBuyout=20},
  })[id]
end}
__ns.cdb.recipes={Blacksmithing={professionID=164,diff={['item:90001']='o',['item:90002']='y',['item:90003']='g'},market={
  [90001]={quantity=1,reagents={2835,1,2840,1}},
  [90002]={quantity=1,reagents={2840,2,2880,1,2320,1}},
  [90003]={quantity=1,reagents={2589,2}},
  [90004]={quantity=1,reagents={2589,2}},
  [90005]={quantity=1,reagents={2840,3},alts={{quantity=2,reagents={2589,4}}}},
}}}
function __craft(sort, skill)
  local out={}
  for _,r in ipairs(__ns.CraftingMarketRows('ledger',{Blacksmithing=157},sort,nil,skill)) do out[r.item]=r end
  return out
end
""")
check('craft profit sells at the current lowest listing, not the median', C.ev("""
(function() local r=__craft()[90001]; return r.price==75 and r.basis=='low' and r.cost==82 and r.profit==-11 and r.tag=='Loss' end)()
"""))
check('a craft that loses money at the current low leaves Buy & Craft', C.ev("__craft('roi')[90001]==nil"))
check('with nothing listed the median is used and the row says so', C.ev("""
(function() local r=__craft()[90003]; return r.price==700 and r.basis=='unlisted' and r.tag=='No listings' end)()
"""))
check('a lone listing above the median cannot inflate profit', C.ev("""
(function() local r=__craft()[90004]; return r.price==300 and r.basis=='median' end)()
"""))
check('vendor reagents use the vendor price when it is cheaper or the only price', C.ev("""
(function() local r=__craft()[90002]; return r.cost==79*2+100+10 and r.profit==4560-268 end)()
"""))
check('the shopping list marks vendor-priced ingredients', C.ev("""
(function()
  SlashCmdList.EPUGUILD('market')
  for _, control in ipairs(__frames) do
    if control.row and control.row.item==90002 and control.summary then control:Click(); break end
  end
  for _, control in ipairs(__frames) do
    if type(control.label)=='table' and control.label.GetText and control.label:GetText():find('(vendor)',1,true) then return true end
  end
end)()
"""))
C.ex("EPUGuildGatheringMarket.selected=nil; __ns.RefreshGatheringMarket()")
check('days of supply tag slow and fast sellers', C.ev("""
(function() local rows=__craft(); return rows[90001].supplyDays==9 and rows[90002].tag=='Sells now' end)()
"""))
check('stock already listed discounts the profit and demand ranking', C.ev("""
(function() local r=__craft('opportunity')[90002]; return r.supplyDays==.5 and r.opportunity==r.profit*10 end)()
"""))
check('an alternate recipe for the same item is compared and the cheaper one wins', C.ev("""
(function() local r=__craft()[90005]; return r.quantity==2 and r.cost==80 end)()
"""))
check('skill-up sort keeps orange and yellow recipes and puts the cheapest first', C.ev("""
(function()
  local rows=__ns.CraftingMarketRows('ledger',{Blacksmithing=157},nil,nil,true)
  return #rows==2 and rows[1].item==90002 and rows[2].item==90001 and rows[2].skillNet==-11
end)()
"""))
C.ex("EPUGuildGatheringMarket.craftSort:Click()")
check('Craft offers a skill-up sort with plain wording', C.ev("""
(function()
  local frame=EPUGuildGatheringMarket
  if frame.craftSort:GetText()~='Sort: Skill-ups' then return false end
  for _, control in ipairs(__frames) do
    if control.row and control.row.item==90001 and control.summary and control:IsShown() then
      return control.summary:GetText():find('costs 11c/craft',1,true)~=nil and control.summary:GetText():find('orange',1,true)~=nil
    end
  end
end)()
"""))
C.ex("EPUGuildGatheringMarket.craftSort:Click()")
check('gathering professions are not listed as crafts to scan', C.ev("""
(function()
  local labels={}
  for _,option in ipairs(EPUGuildGatheringMarket.professionChoices) do labels[option.label]=true end
  return labels.Blacksmithing and labels.Mining and not labels.Herbalism and not labels.Skinning
end)()
"""))
check('the header warns about a bundled snapshot and old prices without hovering', C.ev("""
(function()
  local text=EPUGuildGatheringMarket.sourceText:GetText()
  return text:find('bundled snapshot',1,true)~=nil and text:find('7 hours old',1,true)~=nil and text:find('AHledger',1,true)~=nil
end)()
"""))
check('the footer names the price basis for the open tab', C.ev("__ns.UI.footerText:GetText():find('current lowest listing',1,true)~=nil"))
C.ex("""
local frame=EPUGuildGatheringMarket
frame.scroll:SetHeight(60)
frame.scroll:SetVerticalScroll(30)
__fire('SKILL_LINES_CHANGED')
__keptScroll=frame.scroll:GetVerticalScroll()
frame.buyTab:Click()
__resetScroll=frame.scroll:GetVerticalScroll()
frame.craftTab:Click()
""")
check('a skill-up refresh keeps the list position and a new view resets it', C.ev('__keptScroll==30 and __resetScroll==0'))

C.ex("""
local hbd = {}
__map=1429
hbd.GetPlayerZonePosition = function() return .1,.2,__map end
hbd.GetZoneSize = function() return 1000,1000 end
LibStub = function(name) if name=='HereBeDragons-2.0' then return hbd end end
GetPlayerFacing=function() return 0 end
GatherMate2={GetNodesForZone=function() error('GatherMate2 changed') end, DecodeLoc=function() end}
__errors=0
EPUGuildGatheringMarket.gatherTab:Click()
""")
check('a failing GatherMate2 never breaks Market', (C.ev('__errors') or 0)==0 and C.ev('EPUGuildGatheringMarket.chart:IsShown()'))
check('bundled spots cover Elwynn herbs and copper', C.ev("#(__ns.GatheringRoutePreview(2447,182))>0 and #(__ns.GatheringRoutePreview(2770,186))>0"))
check('herb routes leave ore spots out', C.ev("""
(function()
  local herbs,ores=#(__ns.GatheringRoutePreview(nil,182)),#(__ns.GatheringRoutePreview(nil,186))
  return herbs>0 and ores>0 and herbs==#(__ns.GatheringRoutePreview(2447,182))+#(__ns.GatheringRoutePreview(765,182))
end)()
"""))
check('Gather starts on this zone when it has recorded spots', C.ev("""
EPUGuildGatheringMarket.zoneFilter:GetText()=='This zone: On'
"""))
C.ex("__map=1453; __ns.RefreshGatheringMarket()")
check('a zone with no spots falls back to every material', C.ev("EPUGuildGatheringMarket.zoneFilter:GetText()=='This zone: Off' and not EPUGuildGatheringMarket.empty:IsShown()"))
C.ex("__map=1429; SlashCmdList.EPUGUILD('route ore')")
check('/epu route ore starts a mining route', C.ev("EPUGuildRouteArrow:IsShown() and EPUGuildRouteArrow.title:GetText():find('Ore route',1,true)~=nil"))
C.ex("SlashCmdList.EPUGUILD('route stop')")
C.ex("""
__map=1453
__said=nil
local say=__ns.Print
__ns.Print=function(text) __said=text end
SlashCmdList.EPUGUILD('route')
__ns.Print=say
""")
check('an empty zone explains how to record a first spot', C.ev("__said:find('Record spot',1,true)~=nil"))
check('unknown-skill herbs can still be recorded', C.ev("""
(function()
  __map=1429
  local frame=EPUGuildGatheringMarket
  frame.zoneFilter:Click(); if frame.zoneFilter:GetText()~='This zone: Off' then frame.zoneFilter:Click() end
  frame.skill:Click()
  for _, control in ipairs(__frames) do
    if control.row and control.row.item==248821 and control.summary and control:IsShown() then control:Click(); break end
  end
  return frame.selected and frame.selected.item==248821 and frame.markTarget._enabled~=false
end)()
"""))
check('fix-pass leaves no addon runtime errors', (C.ev('__errors') or 0)==0)

D = Client('Chris Baker')
D.ex("""
GetNumTradeSkills=nil
C_TradeSkillUI={
  GetBaseProfessionInfo=function() return {professionID=164,professionName='Blacksmithing',skillLevel=157} end,
  GetAllRecipeIDs=function() return {1,2,3,4,5} end,
  GetRecipeInfo=function(id) return {learned=true,name='Recipe '..id} end,
  GetRecipeSchematic=function(id)
    if id==4 then return {quantityMin=1,quantityMax=1,reagentSlotSchematics={{quantityRequired=1,reagents={{itemID=10940}}}}} end
    if id==5 then return {outputItemID=7080,quantityMin=1,quantityMax=1,
      reagentSlotSchematics={{quantityRequired=1,reagents={{itemID=7077},{itemID=7078}}}}} end
    return {outputItemID=id==3 and 7079 or 7076,quantityMin=1,quantityMax=id==3 and 3 or 1,
      reagentSlotSchematics={{quantityRequired=1,reagents={{itemID=id==1 and 7077 or 12808}}}}}
  end,
}
__fire('TRADE_SKILL_SHOW'); __advance(2)
""")
check('the modern scan counts why recipes are left out of Market', D.ev("""
(function()
  local s=__ns.cdb.recipes.Blacksmithing.stats
  return s.total==5 and s.priced==2 and s.variable==1 and s.service==1 and s.options==1
end)()
"""))
check('two recipes for one item are both kept', D.ev("""
(function()
  local m=__ns.cdb.recipes.Blacksmithing.market[7076]
  return m.reagents[1]==7077 and #m.alts==1 and m.alts[1].reagents[1]==12808
end)()
"""))
D.ex("""
__errors=0
__said=nil
local say=__ns.Print
__ns.Print=function(text) __said=(__said or '')..text end
C_TradeSkillUI.GetRecipeSchematic=function() error('schematic shape changed') end
__fire('TRADE_SKILL_SHOW'); __advance(2)
__fire('TRADE_SKILL_SHOW'); __advance(2)
__ns.Print=say
""")
check('a failed profession scan is reported once instead of silently', D.ev("__errors==1 and __said:find('could not read',1,true)~=nil"))

sys.exit(bool(check.failed))
