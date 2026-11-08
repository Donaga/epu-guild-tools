"""Character relevance, private guide state, source maintenance and actual UI."""
from simcore import *
from pathlib import Path
import copy,json,sys,urllib.error
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import build_guide_catalog as build
import check_guide_sources as health

data=json.loads(build.SOURCE.read_text(encoding='utf-8'))
check('all curated sources validate and generated Lua is current',build.build(data)==build.TARGET.read_text(encoding='utf-8'))
for label,edit in [
    ('insecure URL',lambda r:r.update(url='http://www.method.gg/wow-forever/guide')),
    ('untrusted host',lambda r:r.update(url='https://evil.example/wow-forever/guide')),
    ('wrong edition',lambda r:r.update(url='https://www.method.gg/retail/mage')),
    ('missing relevance',lambda r:r.pop('class')),
    ('invalid level',lambda r:r.update(maxLevel=70)),
    ('invalid profession',lambda r:r.update(profession=999)),
    ('bad priority',lambda r:r.update(priority=0)),
]:
    bad=copy.deepcopy(data);edit(bad['guides'][0])
    try:build.validate(bad);rejected=False
    except ValueError:rejected=True
    check('registry rejects '+label,rejected)
check('page hash ignores executable markup and spacing',health.content_hash('<p>Forever  guide</p><script>abc</script>')==health.content_hash('<p>Forever guide</p>'))
for code,status in [(403,'blocked'),(429,'blocked'),(404,'missing'),(500,'error')]:
    with patch.object(health.urllib.request.OpenerDirector,'open',side_effect=urllib.error.HTTPError('https://example.com',code,'mock',{},None)):
        check('HTTP '+str(code)+' is classified without mutating source',health.check(data['guides'][0])['status']==status)

A=Client('Chris Baker');clients[A.name]=A;tick(120)
A.ex("""UnitClass=function() return 'Mage','MAGE' end; UnitLevel=function() return __level or 20 end
UnitFactionGroup=function() return 'Alliance' end
GetProfessions=nil; GetProfessionInfo=nil; GetNumSkillLines=function() return 0 end
__skill=100; C_SkillInfo={GetSkillLineInfoByID=function(id) if id==171 and __skill then return {skillID=id,name='Alchimie',rank=__skill,isHeader=false} end end}
function __ids(topic,saved) local out={} for _,r in ipairs(__ns.PersonalGuides(topic,saved)) do out[r.id]=true end return out end
function __count(t) local n=0 for _ in pairs(t) do n=n+1 end return n end
""")
check('stable profession IDs support localized names',A.ev('__ns.GuidePlayer().professions[171].name')=='Alchimie')
check('preferred live class guide is selected',A.ev('__ids()["moba-mage"]') is True and not A.ev('__ids()["method-mage"]'))
check('only own class and learned professions appear',A.ev("(function() for _,r in ipairs(__ns.PersonalGuides()) do if r.class and r.class~='MAGE' or r.profession and r.profession~=171 then return false end end return true end)()"))
check('beta alternatives start hidden',not A.ev('__ids()["beta-alchemy"]'))
check('early crafting guide is preferred',A.ev('__ids()["method-prof-alchemy"]') is True and not A.ev('__ids()["route-alchemy"]'))
A.ex('__skill=225')
check('skill 225 moves beyond partial early route',A.ev('__ids()["route-alchemy"]') is True and not A.ev('__ids()["method-prof-alchemy"]'))
A.ex('__skill=300')
check('max skill hides leveling routes but retains references',not A.ev('__ids()["route-alchemy"]') and A.ev('__ids()["reference-alchemy"]') is True)
A.ex('__skill=100; GetProfessions=function() return 1 end; GetProfessionInfo=function() return "Alchemy",nil,310,nil,nil,nil,171 end')
check('legacy/modern fallback does not overwrite stable skill rank',A.ev('__ns.GuidePlayer().professions[171].rank')==100)
A.ex('C_SkillInfo=nil')
check('modern profession fallback works',A.ev('__ns.GuidePlayer().professions[171].rank')==310)
A.ex("GetProfessions=nil; GetProfessionInfo=nil; GetNumSkillLines=function() return 1 end; GetSkillLineInfo=function() return 'Alchemy',false,false,100 end")
check('legacy skill line fallback works',A.ev('__ns.GuidePlayer().professions[171].rank')==100)
check('no specialization is guessed from class',A.ev('__ns.GuidePlayer().focus') is None)
check('other class talent focus is rejected',A.ev("__ns.SetGuideFocus('Arms')") is False)
check('own class talent focus can be selected',A.ev("__ns.SetGuideFocus('Frost')") is True)
check('only matching focused sources appear',A.ev("(function() local found=false for _,r in ipairs(__ns.PersonalGuides()) do if r.spec then if r.spec~='Frost' then return false end found=true end end return found end)()"))
A.ex("__ns.SetGuideSaved('moba-mage',true); __ns.SaveGuideProgress('moba-mage',true,'Private guide note')")
check('saved filter keeps only saved relevant guides',A.ev('__count(__ids(nil,true))')==1)
A.ex('__level=30')
check('progress expires when level bracket changes',A.ev('__ns.GuideState().progress["moba-mage"].bracket~=__ns.GuideBracket(__ns.PersonalGuide("moba-mage"))'))
A.ex('__level=60')
check('level cap hides leveling guides even when saved',not A.ev('__ids()["moba-mage"]') and A.ev('__ns.PersonalGuide("moba-mage")') is None)
check('class reference and planner remain at level cap',A.ev('__ids()["overview-mage"]') is True and A.ev('__ids()["planner-mage"]') is True)
A.ex("__level=20; __ns.SetGuideSaved('method-prof-alchemy',true); GetNumSkillLines=function() return 0 end")
check('unlearning profession hides saved guide and direct details',not A.ev('__ids()["method-prof-alchemy"]') and A.ev('__ns.PersonalGuide("method-prof-alchemy")') is None)
A.ex("__ns.GuideState().moreSources=true")
check('alternative sources remain restricted to own class',A.ev('__ids()["method-mage"]') is True and not A.ev('__ids()["method-warrior"]'))
A.ex("UnitLevel=function() return -1 end")
check('unavailable level fails closed',A.ev('#__ns.PersonalGuides()')==0)
A.ex("UnitLevel=function() return 20 end; UnitClass=function() return 'Unknown','UNKNOWN' end")
check('unknown class fails closed',A.ev('#__ns.PersonalGuides()')==0)
A.ex("UnitClass=function() return 'Mage','MAGE' end; __ns.SetGuideFocus(nil); GetSpecialization=function() return 2 end; GetSpecializationInfo=function() return 63,'Fire' end")
check('recognized live specialization is used',A.ev('__ns.GuidePlayer().focus')=='Fire')
A.ex("GetSpecializationInfo=function() return 123,'Not a known tree' end")
check('unknown live tree is not mapped by numeric index',A.ev('__ns.GuidePlayer().focus') is None)
check('review labels disclose prelaunch status', 'Pre-launch' in A.ev('__ns.GuideReviewLabel(__ns.PersonalGuide("overview-mage"))'))
check('private guide state is absent from shared guild data','Private guide note' not in A.ev('__ns.Serialize(__ns.G())'))

# Render the real activity board, options, details and source-copy dialog.
A.ex("""__ns.UI:Show(); __ns.UI.state.activities.kind='guides'; __ns.UI:SetView('activities')
function __click(label) for _,b in ipairs(__ns.UI.details.pools.btn) do if b:IsShown() and b.text:GetText()==label then b:GetScript('OnClick')(b); return end end error('Missing button '..label) end
__ns.UI:OpenDetails('guideoptions','options'); __click('Frost'); __ns.UI:OpenDetails('guide','moba-mage')
""")
check('options select only this class focus',A.ev('__ns.GuidePlayer().focus')=='Frost')
A.ex("__ns.UI.details.pools.box[1]:SetText('A note from the real form'); __ns.UI:Refresh()")
check('background refresh preserves guide note draft',A.ev('__ns.UI.details.pools.box[1]:GetText()')=='A note from the real form')
A.ex("__click('Save note')")
check('actual note form saves privately',A.ev('__ns.GuideState().progress["moba-mage"].note')=='A note from the real form')
A.ex("__click('Read full guide')")
check('full source link is copyable',A.ev('EPUGuildGuideLink:IsShown()') and A.ev('EPUGuildGuideLink.url:GetText()')=='https://mobalytics.gg/wow-forever/classes/mage-leveling-guide')
A.ex("local b=__ns.UI.bars.activities; b.casualMine:GetScript('OnClick')(b.casualMine)")
check('guide toolbar changes private saved filter',A.ev('__ns.GuideState().savedOnly') is True)
check('guide toolbar hides unrelated availability action',not A.ev('__ns.UI.bars.activities.casualAvailability:IsShown()'))
check('guide toolbar fits minimum supported window',A.ev('__ns.UI.bars.activities.leftX+__ns.UI.bars.activities.rightX<=480'))
A.ex("__ns.UI.state.activities.kind='events'; __ns.UI:Refresh(); __ns.UI.state.activities.kind='help'; __ns.UI:Refresh(); local b=__ns.UI.bars.activities; b.casualMine:GetScript('OnClick')(b.casualMine)")
check('switching boards restores original Mine handler',A.ev('__ns.UI.state.activities.mine') is True)
check('switching boards restores availability action',A.ev('__ns.UI.bars.activities.casualAvailability:IsShown()'))
A.ex("__ns.UI.state.activities.kind='guides'; __ns.UI:Refresh()")
A.ex("__ns.UI:OpenDetails('guide','moba-mage'); UnitLevel=function() return 60 end; __fire('PLAYER_LEVEL_UP',60); __advance(1)")
check('now-irrelevant guide details close after a level change',not A.ev('__ns.UI.details:IsShown()'))
check('actual guide UI produces no runtime errors',(A.ev('__errors') or 0)==0)
for class_name in sorted(build.CLASSES):
    A.rt.globals()['testClass']=class_name
    A.ex("UnitClass=function() return testClass,testClass end; UnitLevel=function() return 20 end; __ns.GuideState().savedOnly=false")
    check(class_name+' has only its own class guides',A.ev("(function() local count=0 for _,r in ipairs(__ns.PersonalGuides()) do if r.class then if r.class~=testClass then return false end count=count+1 end end return count>=3 end)()"))
print('Guide checks:',check.failed,'failed')
sys.exit(bool(check.failed))
