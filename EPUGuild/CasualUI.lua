local ADDON, ns = ...
local E, UI, C
local categories={{label="Activities",value="events"},{label="Quick quest help",value="help"},{label="Quick dungeon",value="dungeon"},{label="Available helpers",value="helpers"},{label="Starter kits",value="kits"}}
local drafts={}
local function State() return UI.state.activities end
local function Whisper(name) if ChatFrame_SendTell then ChatFrame_SendTell(name) end end
local function Remaining(r) return math.max(0,math.ceil((r.expires-ns.Now())/60)).."m left" end
local function MemberText(name)
  local r=ns.roster[name] or {}
  return name.." · "..(r.online and "Online" or "Offline").." · level "..tostring(r.level or "?")
end
local function Open(kind,key) UI:OpenDetails(kind,key) end
local function SetCategory(kind) State().kind=kind; UI:CloseDetails(); UI.search:SetText(""); UI:SetView("activities") end
function ns.CasualFormKind(kind)
  return (ns.CommunityFormKind and ns.CommunityFormKind(kind)) or kind=="activityform" or kind=="helperform" or kind=="kitedit" or kind=="kitlaunch"
end
function ns.InstallCasualViews(views,env)
  E=env; UI=E.UI; C=E.C
  UI.state.activities={kind="events",mine=false,near=false}
  views.activities={label="Guild activities",icon="Interface\\Icons\\INV_Misc_GroupLooking",tools=function(bar)
    local choose=bar:Add(E.Btn(bar,"Quest / elite help",126,22),"left")
    choose:SetScript("OnClick",function() E.OpenMenu(choose,categories,State().kind,function(kind) SetCategory(kind) end) end)
    local mine=bar:Add(E.Btn(bar,"Mine",46,22),"left",function(self) State().mine=not State().mine; self:SetOn(State().mine); UI:Refresh() end)
    local near=bar:Add(E.Btn(bar,"My level",70,22),"left",function(self) State().near=not State().near; self:SetOn(State().near); UI:Refresh() end)
    bar.casualNew=bar:Add(E.Btn(bar,"New / edit",80,22),"right",function()
      local kind=State().kind
      if ns.CommunityNewAction and ns.CommunityNewAction(kind) then return end
      if kind=="helpers" then Open("helperform",ns.me)
      elseif kind=="kits" then
        if not ns.IsTrusted(ns.me) then return ns.Print("Officers create and apply starter-kit templates.") end
        drafts.new={title="",note="",lines={}}; Open("kitedit","new")
      else Open("activityform",kind) end
    end)
    bar.casualAvailability=bar:Add(E.Btn(bar,"My availability",90,22),"right",function() Open("helperform",ns.me) end)
    bar.casualMine=mine; bar.casualNear=near; bar.casualChoose=choose
    bar.levelFilterClick=near:GetScript("OnClick")
  end,rows=function(g,q)
    ns.CasualStore(); local st=State(); local rows={}
    local bar=views.activities.bar
    if bar then
      for _,v in ipairs(categories) do if v.value==st.kind then bar.casualChoose:SetLabel(v.label) end end
      bar.casualMine:SetOn(st.mine); bar.casualNear:SetOn(st.near)
      bar.casualMine:SetShown(st.kind~="kits"); bar.casualNear:SetShown(st.kind~="kits")
      bar.casualNear:SetLabel("My level")
      bar.casualNear:SetScript("OnClick",bar.levelFilterClick)
      bar.casualNear.tip=nil
    end
    if ns.CommunityRows then local extra=ns.CommunityRows(g,q,st,bar); if extra then return extra end end
    if st.kind=="kits" then
      for id,r in pairs(ns.KitTemplates()) do
        if E.Match(q,r.title,r.note) then
          local total=0 for _,line in ipairs(r.lines) do total=total+line.qty end
          rows[#rows+1]={key="kit:"..id,title=r.title,sub=(id:sub(1,8)=="example:" and "Example · " or "Guild template · ")..r.note,
            right=total.." items",onClick=function() Open("kit",id) end}
        end
      end
    elseif st.kind=="helpers" then
      local lvl=(ns.roster[ns.me] or {}).level or 1
      for name,r in pairs(g.helpers) do
        local mr=ns.roster[name] or {}
        if ns.ActiveHelper(r) and (not st.mine or name==ns.me) and (not st.near or math.abs((mr.level or 1)-lvl)<=5)
          and E.Match(q,name,ns.HelperRoleText(r.roles),r.note,mr.zone) then
          rows[#rows+1]={key="helper:"..name,title=name.." · "..ns.HelperRoleText(r.roles),sub=MemberText(name).." · "..r.note,
            right=Remaining(r),onClick=function() Open("helper",name) end}
        end
      end
    else
      local lvl=(ns.roster[ns.me] or {}).level or 1
      for id,r in pairs(g.activityPosts) do
        local mine=g.activityReplies[id.."\030"..ns.me]
        if r.kind==st.kind and ns.ActiveActivity(r) and (not st.mine or r.who==ns.me or (mine and mine.state~="withdrawn"))
          and (not st.near or (lvl>=r.minLevel and lvl<=r.maxLevel)) and E.Match(q,r.title,r.note,r.zone,r.who) then
          local n=ns.ActivityCounts(id)
          rows[#rows+1]={key="activity:"..id,title=r.title,sub=r.who.." · "..r.zone.." · levels "..r.minLevel.."–"..r.maxLevel.." · "..r.note,
            right=n.ready.." / "..r.slots.." ready · "..Remaining(r),onClick=function() Open("activity",id) end}
        end
      end
    end
    table.sort(rows,function(a,b) if a.title==b.title then return a.key<b.key end return a.title<b.title end)
    return rows
  end,empty="Nothing matches this board. Choose another board, clear the search or turn off Mine / My level.",footer=function()
    local kind=State().kind
    if ns.CommunityFooter then local extra=ns.CommunityFooter(kind); if extra then return extra end end
    if kind=="kits" then return "Reusable templates become tracked Projects. Officers review the recipient and crafters before creating requests." end
    if kind=="helpers" then return "Helpers opt in for 15–240 minutes and appear only while online. No automatic renewal or guild-chat announcements." end
    return "Voluntary interest, with no automatic invites. Levels are suggestions; posts close automatically at their expiry time."
  end}
  if ns.InstallCommunityViews then ns.InstallCommunityViews(views,env) end
end
local function RoleButtons(det,roles,changed,multiple)
  local specs={}
  for _,role in ipairs(multiple and {"t","h","d","c","m"} or {"t","h","d"}) do
    local r=role
    specs[#specs+1]={(multiple and (roles:find(r,1,true) and "[x] " or "[ ] ") or "")..ns.HELPER_ROLES[r],function(self)
      changed(r,self)
    end}
  end
  det:Buttons(specs)
end
function ns.FillCasualDetails(kind,key,det)
  if not UI then return false end
  local g=ns.CasualStore(); if not g then return false end
  local officer=ns.IsTrusted(ns.me)
  if ns.FillCommunityDetails and ns.FillCommunityDetails(kind,key,det) then return true end
  if kind=="activityform" then
    local r=g.activityPosts[key]
    local activity=r and r.kind or key
    det:Reset(nil,nil,r and "Edit activity" or (activity=="dungeon" and "Find dungeon company" or "Ask for a hand"),"No guild-chat broadcast or automatic invitations")
    local title=det:Field(activity=="dungeon" and "Dungeon" or "Need help",r and r.title or "",160)
    local zone=det:Field("Zone",r and r.zone or (ns.roster[ns.me] or {}).zone or "",160)
    local note=det:Field("Details",r and r.note or "",160)
    local low=det:Field("Min level",tostring(r and r.minLevel or math.max(1,((ns.roster[ns.me] or {}).level or 1)-5)),60,true)
    local high=det:Field("Max level",tostring(r and r.maxLevel or math.min(100,((ns.roster[ns.me] or {}).level or 1)+5)),60,true)
    local slots=det:Field("Players",tostring(r and r.slots or 5),60,true)
    local expiry=not r and det:Field("Minutes","60",60,true)
    det:Text("Levels are a guide. Anyone can offer help. Ready and tentative responses are shown separately; the organiser decides the final group.",C.muted)
    if r then det:Text("Editing keeps the original expiry: "..Remaining(r),C.gold) end
    det:Buttons({{r and "Save changes" or "Post activity",function()
      local id=ns.SaveActivity(activity,{title=title:GetText(),zone=zone:GetText(),note=note:GetText(),minLevel=tonumber(low:GetText()),maxLevel=tonumber(high:GetText()),slots=tonumber(slots:GetText()),minutes=expiry and tonumber(expiry:GetText()) or 60},r and key)
      if id then Open("activity",id) end
    end,accent=true}})
  elseif kind=="activity" then
    local r=g.activityPosts[key]; if not r then UI:CloseDetails(); return true end
    det:Reset(nil,nil,r.title,ns.ActiveActivity(r) and Remaining(r) or "Closed / expired")
    det:Text(MemberText(r.who)); det:Text(r.zone.." · suggested levels "..r.minLevel.."–"..r.maxLevel)
    det:Text(r.note)
    local n=ns.ActivityCounts(key)
    det:Text(n.ready.." ready / "..r.slots.." planned; "..n.tentative.." tentative",C.gold)
    det:Text(n.t.." tank · "..n.h.." healer · "..n.d.." DPS",C.muted)
    if n.ready>r.slots then det:Text("More people are interested than planned slots. Check with the organiser before travelling.",C.gold) end
    det:Buttons({{"Whisper organiser",function() Whisper(r.who) end}})
    for _,reply in ipairs(ns.ActivityReplies(key)) do
      local name=reply.who
      det:Text(MemberText(name).." · "..ns.HELPER_ROLES[reply.role].." · "..reply.state)
      if reply.note~="" then det:Text(reply.note,C.muted) end
      local buttons={{"Whisper",function() Whisper(name) end}}
      if r.who==ns.me and name~=ns.me and (ns.roster[name] or {}).online then
        buttons[#buttons+1]={"Invite",function() local invite=(C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit; if invite then invite(name) end end}
      end
      det:Buttons(buttons)
    end
    if ns.ActiveActivity(r) then
      local mine=g.activityReplies[key.."\030"..ns.me]
      local role=mine and mine.role or ((ns.ProfileOf(ns.me) or {}).roles or "d"):match("[thd]") or "d"
      local note=det:Field("My note",mine and mine.note or "",160)
      note.onChange=function() det.casualDraft=true end
      local roleText=det:Text("My role: "..ns.HELPER_ROLES[role],C.gold)
      RoleButtons(det,"",function(new) det.casualDraft=true; role=new; roleText:SetText("My role: "..ns.HELPER_ROLES[role]) end)
      det:Buttons({{"I'm ready",function() ns.RespondActivity(key,role,"ready",note:GetText()); UI:FillDetails() end,accent=true},
        {"Tentative",function() ns.RespondActivity(key,role,"tentative",note:GetText()); UI:FillDetails() end},
        {"Withdraw",function() ns.RespondActivity(key,role,"withdrawn",""); UI:FillDetails() end}})
      if r.who==ns.me then det:Buttons({{"Edit post",function() Open("activityform",key) end}}) end
      if r.who==ns.me or officer then det:Buttons({{"Close post",function() ns.CloseActivity(key); UI:FillDetails() end}}) end
    end
  elseif kind=="helperform" then
    local cur=g.helpers[ns.me]; local roles=cur and cur.roles or ""
    det:Reset(nil,nil,"Happy to help","Voluntary, time-limited availability")
    local info=det:Text(ns.HelperRoleText(roles),C.gold)
    RoleButtons(det,roles,function(r,self)
      if roles:find(r,1,true) then roles=roles:gsub(r,"") else roles=roles..r end
      self:SetLabel((roles:find(r,1,true) and "[x] " or "[ ] ")..ns.HELPER_ROLES[r]); info:SetText(ns.HelperRoleText(roles))
    end,true)
    local note=det:Field("Can help",cur and cur.note or "",160)
    local minutes=det:Field("Minutes","60",60,true)
    det:Text("Only online guildmates see you as available. Availability expires after 15–240 minutes and does not restart at login. This does not enable map location sharing.",C.muted)
    det:Buttons({{"Available",function() if ns.SetHelperAvailability(roles,note:GetText(),tonumber(minutes:GetText())) then Open("helper",ns.me) end end,accent=true},
      {"Stop helping",function() ns.SetHelperAvailability(roles,note:GetText(),60,true); SetCategory("helpers") end}})
  elseif kind=="helper" then
    local r=g.helpers[key]; if not r then UI:CloseDetails(); return true end
    det:Reset(nil,nil,key,ns.ActiveHelper(r) and Remaining(r) or "Unavailable")
    det:Text(MemberText(key)); det:Text(ns.HelperRoleText(r.roles),C.gold); det:Text(r.note)
    det:Buttons({{"Whisper",function() Whisper(key) end}})
    if key==ns.me then det:Buttons({{"Update availability",function() Open("helperform",ns.me) end},
      {"Stop helping",function() ns.SetHelperAvailability(r.roles,r.note,60,true); UI:FillDetails() end}}) end
  elseif kind=="kit" then
    local r=ns.KitTemplates()[key]; if not r then UI:CloseDetails(); return true end
    det:Reset(nil,nil,r.title,key:sub(1,8)=="example:" and "Editable example" or "Reusable guild template")
    det:Text(r.note)
    for _,l in ipairs(r.lines) do det:Text(ns.ItemName(l.item,true).." x"..l.qty.." · "..l.mode) end
    det:Text("An officer applies this kit to a member. Bank supplies and craft tasks become normal requests in one tracked project.",C.muted)
    if officer then det:Buttons({{"Prepare kit",function() Open("kitlaunch",key) end,accent=true},
      {key:sub(1,8)=="example:" and "Copy and customise" or "Edit template",function()
        drafts[key]={title=r.title,note=r.note,lines={}}
        for _,l in ipairs(r.lines) do drafts[key].lines[#drafts[key].lines+1]={item=l.item,qty=l.qty,mode=l.mode} end
        Open("kitedit",key)
      end}}) end
  elseif kind=="kitedit" then
    if not officer then UI:CloseDetails(); return true end
    local d=drafts[key] or {title="",note="",lines={}}; drafts[key]=d
    det:Reset(nil,nil,"Starter-kit template","Save once; reuse for different guild members")
    local title=det:Field("Title",d.title,160); local note=det:Field("Details",d.note,160)
    local function Remember() d.title=title:GetText(); d.note=note:GetText() end
    for i,l in ipairs(d.lines) do
      local index=i
      det:Text(ns.ItemName(l.item,true).." x"..l.qty.." · "..l.mode)
      det:Buttons({{l.mode=="bank" and "Use craft" or "Use bank",function() Remember(); l.mode=l.mode=="bank" and "craft" or "bank"; UI:FillDetails() end},
        {"Remove",function() Remember(); table.remove(d.lines,index); UI:FillDetails() end}})
    end
    local item=det:Field("Add item","",160); local qty=det:Field("Quantity","1",60,true)
    det:Text("Shift-click or drag an item into Add item, or enter its ID. Add up to 12 lines. Craft lines require a shared recipe when preparing a kit.",C.muted)
    det:Buttons({{"Add item",function()
      local id=ns.ItemID(item:GetText()); local n=tonumber(qty:GetText())
      if not id or not ns.PositiveInt(n,1000) or #d.lines>=12 then return ns.Print("Enter an item and a whole quantity from 1 to 1000; maximum 12 lines.") end
      Remember(); d.lines[#d.lines+1]={item=id,qty=n,mode="bank"}; UI:FillDetails()
    end}})
    det:Buttons({{"Save template",function()
      Remember(); local id=ns.SaveKitTemplate(key,d.title,d.note,d.lines)
      if id then drafts[key]=nil; Open("kit",id) end
    end,accent=true}})
    if g.kitTemplates[key] then det:Buttons({{"Retire template",function()
      local r=g.kitTemplates[key]; ns.SaveKitTemplate(key,r.title,r.note,r.lines,true); SetCategory("kits")
    end}}) end
  elseif kind=="kitlaunch" then
    local r=ns.KitTemplates()[key]; if not officer or not r then UI:CloseDetails(); return true end
    local revision=ns.Fingerprint(r)
    det:Reset(nil,nil,"Prepare: "..r.title,"Review before creating requests")
    local to=det:Field("Recipient",ns.me,160)
    local choices={}
    for i,l in ipairs(r.lines) do
      det:Text(ns.ItemName(l.item,true).." x"..l.qty.." · "..l.mode)
      if l.mode=="craft" then
        choices[i]=det:Field("Crafter","",160)
        local e=ns.RecipeFor("item:"..l.item); local names={}
        for _,c in ipairs(e and e.crafters or {}) do names[#names+1]=c.who end
        table.sort(names); det:Text(#names>0 and ("Shared recipe: "..table.concat(names,", ")) or "No shared recipe yet; ask a crafter to open their profession window.",C.muted)
      end
    end
    det:Text("Creates one project and the exact bank/craft requests shown above. Nothing is mailed automatically. An active kit of this type for the same member blocks duplicates.",C.muted)
    det:Buttons({{"Create kit project",function()
      local assignments={} for i,box in pairs(choices) do assignments[i]=box:GetText() end
      local id=ns.LaunchStarterKit(key,to:GetText(),assignments,revision)
      if id then UI:SetView("projects"); Open("project",id) end
    end,accent=true}})
  else return false end
  return true
end
