-- An offline, attributed guide library filtered to the current character.
local ADDON,ns=...
ns.GUIDE_SPECS={DRUID={"Balance","Feral","Restoration"},HUNTER={"Beast Mastery","Marksmanship","Survival"},
  MAGE={"Arcane","Fire","Frost"},PALADIN={"Holy","Protection","Retribution"},PRIEST={"Discipline","Holy","Shadow"},
  ROGUE={"Assassination","Combat","Subtlety"},SHAMAN={"Elemental","Enhancement","Restoration"},
  WARLOCK={"Affliction","Demonology","Destruction"},WARRIOR={"Arms","Fury","Protection"}}
ns.GUIDE_PROFESSIONS={[129]="First Aid",[164]="Blacksmithing",[165]="Leatherworking",[171]="Alchemy",[182]="Herbalism",[185]="Cooking",
  [186]="Mining",[197]="Tailoring",[202]="Engineering",[333]="Enchanting",[356]="Fishing",[393]="Skinning"}
local function Number(n,lo,hi)
  if issecretvalue and issecretvalue(n) then return false end
  return type(n)=="number" and n==n and n>=lo and n<=hi and n%1==0
end
function ns.GuideState()
  if not ns.cdb then return end
  ns.cdb.guides=ns.cdb.guides or {}; local s=ns.cdb.guides
  s.saved=s.saved or {}; s.progress=s.progress or {}; return s
end
local function SpecKnown(class,spec)
  for _,name in ipairs(ns.GUIDE_SPECS[class] or {}) do if name==spec then return true end end
end
local function LiveProfessions()
  local result={}
  local function Add(id,name,rank)
    if not ns.GUIDE_PROFESSIONS[id] then
      for key,english in pairs(ns.GUIDE_PROFESSIONS) do if name==english then id=key; break end end
    end
    if ns.GUIDE_PROFESSIONS[id] and not result[id] and Number(rank,1,1000) then result[id]={name=name or ns.GUIDE_PROFESSIONS[id],rank=rank} end
  end
  -- Stable skill IDs keep this independent of localized profession names.
  if C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID then
    for id in pairs(ns.GUIDE_PROFESSIONS) do
      local ok,r=pcall(C_SkillInfo.GetSkillLineInfoByID,id)
      if ok and type(r)=="table" and not r.isHeader then Add(r.skillID or id,r.name,r.rank) end
    end
  end
  if GetProfessions and GetProfessionInfo then
    local ok,indices=pcall(function() return {GetProfessions()} end)
    if ok then for _,index in pairs(indices) do
      local valid,info=pcall(function() return {GetProfessionInfo(index)} end)
      if valid then Add(info[7],info[1],info[3]) end
    end end
  elseif GetNumSkillLines and GetSkillLineInfo then
    local ok,n=pcall(GetNumSkillLines)
    if ok and Number(n,0,500) then for i=1,n do
      local valid,name,header,_,rank=pcall(GetSkillLineInfo,i)
      if valid and not header then Add(nil,name,rank) end
    end end
  end
  return result
end
function ns.GuidePlayer()
  local s=ns.GuideState() or {}
  local class,name
  if UnitClass then local ok,n,c=pcall(UnitClass,"player"); if ok then name,class=n,c end end
  if not class then local r=(ns.roster or {})[ns.me]; class=r and r.classFile; name=r and r.class end
  if not ns.GUIDE_SPECS[class] then class=nil end
  local level
  if UnitLevel then local ok,n=pcall(UnitLevel,"player"); if ok and Number(n,1,100) then level=n end end
  local focus=SpecKnown(class,s.focus) and s.focus or nil
  -- Only use a detected spec when the game supplies a recognized name. Never
  -- guess a Classic tree from a Retail specialization index.
  if not focus then
    local get=(C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
    local info=(C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo) or GetSpecializationInfo
    if get and info then
      local ok,index=pcall(get)
      if ok and index then local valid,_,spec=pcall(info,index); if valid and SpecKnown(class,spec) then focus=spec end end
    end
  end
  local faction
  if UnitFactionGroup then local ok,value=pcall(UnitFactionGroup,"player"); if ok and (value=="Alliance" or value=="Horde") then faction=value end end
  return {class=class,className=name or class,level=level,focus=focus,faction=faction,professions=LiveProfessions()}
end
function ns.SetGuideFocus(spec)
  local s=ns.GuideState(); if not s then return false end
  local player=ns.GuidePlayer()
  if spec~=nil and not SpecKnown(player.class,spec) then return false end
  s.focus=spec; return true
end
function ns.GuideRelevant(r,p)
  if not p.level or not p.class or r.status=="unavailable" or r.status=="needs_review" then return false end
  if r.class and r.class~=p.class then return false end
  if p.level<(r.minLevel or 1) or p.level>(r.maxLevel or 60) then return false end
  if r.spec and r.spec~=p.focus then return false end
  if r.focus and p.focus and r.focus~=p.focus then return false end
  if r.faction and r.faction~=p.faction then return false end
  if r.profession then
    local prof=p.professions[r.profession]
    if not prof or prof.rank<(r.minSkill or 1) or prof.rank>(r.maxSkill or 300) then return false end
  end
  return true
end
function ns.PersonalGuides(topic,savedOnly)
  local p=ns.GuidePlayer(); local s=ns.GuideState() or {}; local candidates,groups={},{}
  for _,r in ipairs(ns.GUIDE_CATALOG or {}) do
    local matches=not topic or topic=="all"
    for _,t in ipairs(r.topics) do if t==topic then matches=true end end
    if matches and ns.GuideRelevant(r,p) and (not r.extra or s.moreSources) then
      candidates[#candidates+1]=r
      local priority=r.priority or 1
      if not groups[r.group] or priority<groups[r.group] then groups[r.group]=priority end
    end
  end
  local result={}
  for _,r in ipairs(candidates) do
    -- Saved never bypasses relevance. A removed profession's bookmark remains
    -- private but is hidden until it becomes relevant again.
    if (s.moreSources or (r.priority or 1)==groups[r.group] or (s.saved or {})[r.id]) and (not savedOnly or (s.saved or {})[r.id]) then result[#result+1]=r end
  end
  table.sort(result,function(a,b)
    if (a.priority or 1)~=(b.priority or 1) then return (a.priority or 1)<(b.priority or 1) end
    if a.title~=b.title then return a.title<b.title end
    return a.id<b.id
  end)
  return result,p
end
function ns.PersonalGuide(id)
  local p=ns.GuidePlayer()
  for _,r in ipairs(ns.GUIDE_CATALOG or {}) do if r.id==id and ns.GuideRelevant(r,p) then return r,p end end
end
local function HasTopic(r,topic)
  for _,value in ipairs(r.topics) do if value==topic then return true end end
end
-- Present player goals rather than exposing the source registry as navigation.
-- Rebuild from live character data so bookmarks and open details cannot bypass
-- level, profession or talent relevance.
function ns.GuideChoices(savedOnly)
  local p=ns.GuidePlayer(); local s=ns.GuideState() or {}; local choices,byKey={},{}
  if not p.class or not p.level then return choices,p end
  local class=p.className or p.class
  local function Add(key,title,hint,r,score)
    if savedOnly and not (s.saved or {})[r.id] then return end
    local choice=byKey[key]
    if not choice then choice={key=key,title=title,hint=hint,sources={}}; byKey[key]=choice; choices[#choices+1]=choice end
    choice.sources[#choice.sources+1]={guide=r,score=score+(r.extra and 1000 or 0)}
  end
  for _,r in ipairs(ns.GUIDE_CATALOG or {}) do
    if ns.GuideRelevant(r,p) then
      if r.profession then
        local prof=p.professions[r.profession]
        local route=r.group:match('%-route$')
        Add('profession:'..r.profession,(prof.rank<300 and 'Level ' or 'Use ')..prof.name,
          'Skill '..prof.rank..' · '..(prof.rank<300 and 'Training and skill-up help' or 'Profession reference'),r,(route and 0 or 100)+(r.priority or 1))
      elseif r.class then
        if HasTopic(r,'leveling') or HasTopic(r,'class') then
          Add('leveling',(p.level<60 and 'Level my ' or 'Understand my ')..class,
            'Level '..p.level..' · '..(p.focus and (p.focus..' playstyle') or 'Abilities, rotation and training'),r,
            (r.spec and 0 or (HasTopic(r,'class') and 100 or 10))+(r.priority or 1))
        end
        if p.level>=5 and HasTopic(r,'talents') then
          Add('talents','Choose my talents',p.focus and (p.focus..' · Build choices for my level') or 'Choose a playstyle or compare class builds',r,
            (r.spec and 0 or (r.id:match('^planner%-') and 100 or 10))+(r.priority or 1))
        end
      end
    end
  end
  for _,choice in ipairs(choices) do
    table.sort(choice.sources,function(a,b) if a.score~=b.score then return a.score<b.score end return a.guide.id<b.guide.id end)
    choice.recommended=choice.sources[1].guide
  end
  table.sort(choices,function(a,b)
    local order={leveling=1,talents=2}
    local x,y=order[a.key] or 3,order[b.key] or 3
    if x~=y then return x<y end
    if a.title~=b.title then return a.title<b.title end
    return a.key<b.key
  end)
  return choices,p
end
function ns.GuideChoice(key)
  for _,choice in ipairs(ns.GuideChoices((ns.GuideState() or {}).savedOnly)) do if choice.key==key then return choice,ns.GuidePlayer() end end
end
function ns.GuideBracket(r,p)
  if r.profession then
    local rank=p.professions[r.profession].rank
    local lo=rank<75 and 1 or (rank<150 and 75 or (rank<225 and 150 or (rank<300 and 225 or 300)))
    return "skill:"..r.profession..":"..lo,"Skill "..rank..(lo<300 and (" · current bracket "..lo.."–"..(lo==1 and 74 or lo+74)) or " · maximum route skill")
  end
  local lo=p.level<10 and 1 or math.floor(p.level/10)*10
  return "level:"..p.class..":"..lo..":"..tostring(p.focus),"Level "..p.level..(p.focus and (" · "..p.focus) or " · class-wide")
end
function ns.GuideReviewLabel(r)
  local age=math.max(0,math.floor((ns.Now()-(r.reviewEpoch or 0))/86400))
  local label=r.status=="beta" and "Beta-derived" or (r.status=="prelaunch" and "Pre-launch source" or "Source checked")
  return label.." · reviewed "..r.reviewed..(age>14 and " · review due" or "")
end
function ns.SetGuideSaved(id,on)
  local s=ns.GuideState(); if not s or not ns.PersonalGuide(id) then return false end
  s.saved[id]=on and true or nil; return true
end
function ns.SaveGuideProgress(id,read,note)
  local r,p=ns.PersonalGuide(id); local s=ns.GuideState()
  if not r or not s then return false end
  local bracket=ns.GuideBracket(r,p)
  s.progress[id]={read=read==true,bracket=bracket,note=tostring(note or ""):sub(1,240),at=ns.Now()}
  return true
end
local function Refresh()
  if ns.UI and ns.UI:IsShown() and ns.UI.view=="activities" and ns.UI.state.activities.kind=="guides" then ns.Debounce("guideView",0.3,function()
    local det=ns.UI.details
    if det and det.kind=="guide" and not ns.PersonalGuide(det.key) then ns.UI:CloseDetails() end
    if det and (det.kind=="guidechoice" or det.kind=="guidesources") and not ns.GuideChoice(det.key) then ns.UI:CloseDetails() end
    ns.UI:Refresh()
  end) end
end
for _,event in ipairs({"PLAYER_LEVEL_UP","SKILL_LINES_CHANGED","SPELLS_CHANGED","PLAYER_SPECIALIZATION_CHANGED","ACTIVE_TALENT_GROUP_CHANGED"}) do ns.On(event,Refresh) end
