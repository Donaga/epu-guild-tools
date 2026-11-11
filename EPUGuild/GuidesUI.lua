local ADDON,ns=...
local E,UI,C,copy
local function Open(kind,key) UI:OpenDetails(kind,key) end
function ns.ShowGuideLink(id)
  local r=ns.PersonalGuide(id); if not r then return end
  if not copy then
    copy=CreateFrame("Frame","EPUGuildGuideLink",UIParent,"BasicFrameTemplateWithInset")
    copy:SetSize(590,140); copy:SetPoint("CENTER"); copy:SetFrameStrata("DIALOG")
    copy.TitleText:SetText("Read the full guide")
    copy.url=CreateFrame("EditBox",nil,copy,"InputBoxTemplate")
    copy.url:SetSize(540,24); copy.url:SetPoint("TOPLEFT",24,-46); copy.url:SetAutoFocus(false)
    copy.url:SetScript("OnEscapePressed",function() copy:Hide() end)
    copy.help=copy:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    copy.help:SetPoint("TOPLEFT",24,-82); copy.help:SetWidth(540)
    copy.help:SetText("Press Ctrl+C to copy this source link, then paste it into your browser. The addon does not open websites or download guide pages in game.")
    tinsert(UISpecialFrames,"EPUGuildGuideLink")
  end
  copy.guideID=id; copy.url:SetText(r.url); copy:Show(); copy.url:SetFocus(); copy.url:HighlightText()
end
ns.On("PLAYER_LEVEL_UP",function() if copy then copy:Hide() end end)
ns.On("SKILL_LINES_CHANGED",function() if copy and not ns.PersonalGuide(copy.guideID) then copy:Hide() end end)
local install=ns.InstallCommunityViews
ns.InstallCommunityViews=function(views,env)
  install(views,env)
  E=env; UI=env.UI; C=E.C
end
local action=ns.CommunityNewAction
ns.CommunityNewAction=function(kind)
  if kind=="guides" then Open("guideoptions","options"); return true end
  return action(kind)
end
local form=ns.CommunityFormKind
ns.CommunityFormKind=function(kind) return kind=="guideoptions" or form(kind) end
local rows=ns.CommunityRows
ns.CommunityRows=function(g,q,state,bar)
  if state.kind~="guides" then return rows(g,q,state,bar) end
  local s=ns.GuideState(); local list,p=ns.GuideChoices(s.savedOnly)
  local out={{key="guide:profile",title=p.class and ('Guides for your '..(p.className or p.class)) or "Waiting for your character information",
    sub="What would you like help with? Choose a topic below."}}
  for _,choice in ipairs(list) do
    local matches=E.Match(q,choice.title,choice.hint)
    for _,source in ipairs(choice.sources) do if E.Match(q,source.guide.title,source.guide.publisher,source.guide.summary) then matches=true end end
    if matches then
      local key=choice.key
      out[#out+1]={key="guidechoice:"..key,title=choice.title,sub=choice.hint,right="Open",onClick=function() Open("guidechoice",key) end}
    end
  end
  if #out==1 then out[#out+1]={key="guide:none",title=s.savedOnly and "No saved guides match" or "No matching guides",sub="Clear the search or turn off Saved to see your topics."} end
  return out
end
local footer=ns.CommunityFooter
ns.CommunityFooter=function(kind)
  if kind=="guides" then return "Choose a topic, then copy its recommended guide link to your browser." end
  return footer(kind)
end
local details=ns.FillCommunityDetails
ns.FillCommunityDetails=function(kind,key,det)
  if kind=="guidechoice" or kind=="guidesources" then
    local choice,p=ns.GuideChoice(key)
    if not choice then UI:CloseDetails(); UI:Refresh(); return true end
    local r=choice.recommended; local s=ns.GuideState()
    det:Reset(nil,nil,choice.title,choice.hint)
    if kind=="guidesources" then
      det:Buttons({{"Back",function() Open("guidechoice",key) end}})
      for i,source in ipairs(choice.sources) do
        local guide=source.guide
        det:Text(guide.publisher..(i==1 and " · Recommended" or ""),C.gold)
        det:Text(guide.title)
        det:Text(ns.GuideReviewLabel(guide),C.muted)
        det:Buttons({{"Copy link",function() ns.ShowGuideLink(guide.id) end},{"Source details",function() Open("guide",guide.id) end}})
      end
    else
      if key=="talents" and not p.focus then
        det:Text("Pick your playstyle to see a matching talent guide, or use the class guide below.")
        det:Buttons({{"Choose playstyle",function() Open("guideoptions","options") end}})
      end
      det:Text("Start here",C.gold)
      if r.notice then det:Text(r.notice,C.gold) end
      det:Text(r.summary)
      det:Buttons({{"Copy guide link",function() ns.ShowGuideLink(r.id) end,accent=true}})
      det:Text("Paste the link into your browser to read the full guide.",C.muted)
      if r.status=="beta" or r.status=="prelaunch" then det:Text("This source includes pre-launch advice. Check current in-game tooltips for exact values.",C.gold) end
      det:Buttons({{s.saved[r.id] and "Unsave" or "Save guide",function() ns.SetGuideSaved(r.id,not s.saved[r.id]); UI:FillDetails(); UI:Refresh() end}})
      det:Buttons({{"Other sources",function() Open("guidesources",key) end},{"Source details / notes",function() Open("guide",r.id) end}})
    end
  elseif kind=="guideoptions" then
    local p=ns.GuidePlayer(); local s=ns.GuideState()
    det:Reset(nil,nil,"Your guide preferences","Private to this character")
    det:Text("Class: "..(p.className or "Loading").." · level "..tostring(p.level or "?"))
    det:Text("My playstyle: "..(p.focus or "Not chosen"),C.gold)
    det:Buttons({{"Automatic / class-wide",function() ns.SetGuideFocus(nil); UI:FillDetails(); UI:Refresh() end}})
    local buttons={}
    for _,spec in ipairs(ns.GUIDE_SPECS[p.class] or {}) do
      local value=spec
      buttons[#buttons+1]={spec,function() ns.SetGuideFocus(value); UI:FillDetails(); UI:Refresh() end}
    end
    det:Buttons(buttons)
    det:Text("The game supplies your class, level and learned professions. A recognized active specialization is used when available; otherwise choose your own class's talent focus to see a matching build guide.",C.muted)
    det:Text("Each topic has one starting recommendation. Find alternatives under Other sources inside that topic.",C.muted)
    det:Buttons({{"Refresh my information",function() UI:FillDetails(); UI:Refresh() end}})
  elseif kind=="guide" then
    local r,p=ns.PersonalGuide(key)
    if not r then UI:CloseDetails(); UI:Refresh(); return true end
    local s=ns.GuideState(); local bracket,label=ns.GuideBracket(r,p); local progress=s.progress[key] or {}
    det:Reset(nil,nil,r.title,r.publisher.." · "..r.author)
    det:Text(label,C.gold); det:Text(r.summary)
    if r.notice then det:Text(r.notice,C.gold) end
    if r.profession then
      det:Text("Start at your current skill section in the full guide. Check recipes you actually know, the trainer's current requirements and material prices before crafting. Ask a guild crafter or helper when a route does not fit your supplies.")
      det:Text("Reviewed coverage: skill "..(r.minSkill or 1).."–"..(r.maxSkill or 300)..". Quantities in a route are estimates; no shopping list is generated automatically.",C.muted)
    else
      det:Text(p.level<10 and "Focus on your starting rotation, training and safe pulls. Use the source's sections for your level; only spend talent points actually available in game."
        or (p.level<60 and "Use the leveling section around your current level, then review your next talent choices and training priorities. Pick a playstyle you enjoy and compare it with your current in-game abilities."
        or "Use class and talent references for your current playstyle. Leveling-only routes are hidden at the level cap."))
      if not p.focus then det:Text("Choose a talent focus in Options for specialization-specific sources. Class-wide guides can contain several alternative paths.",C.muted) end
    end
    det:Text(ns.GuideReviewLabel(r),C.gold)
    det:Text("Publisher update: "..(r.updated or "not stated").."\nEdition: WoW Forever"..(r.dataBuild and ("\nSource data snapshot: "..r.dataBuild) or ""),C.muted)
    if r.status=="beta" or r.status=="prelaunch" then det:Text("This source retains pre-launch assumptions. Compare live tooltips and current patch notes before following exact talent or material numbers.",C.gold) end
    det:Buttons({{"Read full guide",function() ns.ShowGuideLink(key) end,accent=true},
      {s.saved[key] and "Unsave" or "Save guide",function() ns.SetGuideSaved(key,not s.saved[key]); UI:FillDetails(); UI:Refresh() end}})
    local note=det:Field("My note",progress.note or "",160); note.onChange=function() det.casualDraft=true end
    local reviewed=progress.read and progress.bracket==bracket
    det:Buttons({{reviewed and "Review again" or "Reviewed this bracket",function()
      ns.SaveGuideProgress(key,not reviewed,note:GetText()); UI:FillDetails(); UI:Refresh()
    end},{"Save note",function() ns.SaveGuideProgress(key,reviewed,note:GetText()); UI:FillDetails() end}})
    if progress.read and progress.bracket~=bracket then det:Text("Your level, skill bracket or talent focus changed since the last review.",C.gold) end
    det:Buttons({{"Find a guild helper",function() UI.state.activities.kind="helpers"; UI:CloseDetails(); UI:SetView("activities") end}})
    det:Text("Summaries and notes are local. The addon does not apply talents, copy full articles or send your guide-reading history to the guild.",C.muted)
  else return details(kind,key,det) end
  return true
end
