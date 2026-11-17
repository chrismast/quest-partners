"""Performance, hostile-input and shared-addon-boundary regressions."""
import unittest
from test_addon import client,log,region_log,exchange


class PerformanceAuditTests(unittest.TestCase):
    def test_disjoint_five_player_union_stays_bounded_at_500_quests(self):
        a=client(party=False)
        a.execute('''
MOCK.log={}
for id=1,100 do
 local q={questID=id,title="Quest "..id,level=10,objectives={}}
 for j=1,20 do q.objectives[j]={text="x",numFulfilled=1,numRequired=15} end
 MOCK.log[id]=q
end
NS:Scan()
for i=1,4 do MOCK.party["party"..i]={name="Friend"..i,online=true} end
NS:UpdateRoster()
for i=1,4 do
 local quests={}
 for id,q in pairs(NS.localQuests) do local copy=NS.Core.Copy(q);copy.id=id+i*100;copy.title="Quest "..copy.id;quests[copy.id]=copy end
 local wire=NS.Core.Serialize(quests,nil,true)
 assert(#wire<=54000)
 NS.peers["friend"..i.."-testrealm"]={ready=true,online=true,lastSeen=GetTime(),quests=NS.Core.Decode(wire)}
end
NS.db.scope="all";NS.db.hideFinished=false
for id in pairs(NS.Core.Catalogue(NS:Players())) do NS.db.collapsed[id]=false end
NS:Change()
assert(#NS.Core.Visible(NS:Players(),NS.db,GetTime())==500)
assert(#NS.UI.rows<80 and NS.UI.content:GetHeight()>500000)
''')

    def test_unchanged_scans_reuse_records_and_do_not_serialize(self):
        a,b=client(),client('Brother');log(a);log(b);exchange(a,b)
        a.execute('''
local original=NS.localQuests[38];local calls=0;local serialize=NS.Core.Serialize
NS.Core.Serialize=function(...) calls=calls+1;return serialize(...) end
local before=NS.scanCount
MOCK.Tick(5)
assert(NS.scanCount>before and calls==0 and NS.localQuests[38]==original)
MOCK.log[1].objectives[1].numFulfilled=1;MOCK.Fire("QUEST_WATCH_UPDATE");MOCK.Tick(1)
assert(NS.localQuests[38]~=original and original.objectives[1].fulfilled==2)
assert(calls>=1)
''')

    def test_immutable_delta_snapshot_keeps_unchanged_records_and_atomic_rejection(self):
        a=client(party=False)
        a.execute('''
local C=NS.Core
local previous={[1]={id=1,title="One",level=10,state="A",objectives={}},[2]={id=2,title="Two",level=10,state="A",objectives={}}}
local updated=C.Decode("D\\nQ\\t1\\t10\\tC\\tOne",previous)
assert(updated[2]==previous[2] and updated[1]~=previous[1] and previous[1].state=="A")
assert(not C.Decode("D\\nQ\\t1\\t10\\tC\\tOne\\nO\\t1\\t99\\t0\\t1\\t0\\titem\\tx",previous))
assert(previous[1].state=="A" and previous[2].title=="Two")
''')

    def test_bubble_paint_is_not_repeated_each_frame(self):
        a=client(party=False)
        a.execute('''
NS.Settings.testBubble.scripts.OnClick(NS.Settings.testBubble)
local calls=0;local body=NS.Features.bubbles[1].body;local setText=body.SetText
body.SetText=function(...) calls=calls+1;return setText(...) end
for i=1,600 do NS.Features:Tick(NS) end
assert(calls==0)
MOCK.Tick(1);assert(calls==0)
NS.db.colors.heading={0.4,0.5,0.6};NS:Change();assert(calls==1)
MOCK.Tick(8);assert(not NS.Features.bubbles[1]:IsShown())
''')

    def test_ten_thousand_progress_rows_use_a_small_scroll_pool(self):
        a=client(party=False)
        a.execute('''
MOCK.log={}
for id=1,100 do
 local q={questID=id,title="Quest "..id,level=10,objectives={}}
 for j=1,20 do q.objectives[j]={text="Objective "..j,numFulfilled=id+j,numRequired=1000} end
 MOCK.log[id]=q
end
NS:Scan()
for i=1,4 do MOCK.party["party"..i]={name="Friend"..i,online=true} end
NS:UpdateRoster()
for i=1,4 do NS.peers["friend"..i.."-testrealm"]={ready=true,online=true,lastSeen=GetTime(),quests=NS.Core.Copy(NS.localQuests)} end
for id in pairs(NS.localQuests) do NS.db.collapsed[id]=false end
NS.db.hideFinished=false;NS:Change()
assert(#NS.UI.rows<80 and NS.UI.content:GetHeight()>100000)
local maximum=NS.UI.content:GetHeight()-NS.UI.scroll:GetHeight()
NS.UI.scroll:SetVerticalScroll(maximum);NS:Render()
assert(#NS.UI.rows<80)
local found=false
-- Level/title order finishes with Quest 99, not numeric ID 100.
for _,r in ipairs(NS.UI.rows) do if r:IsShown() and r.kind=="progress" and r.questID==99 then found=true end end
assert(found)
NS.db.mode="manual";NS.db.selected={[1]=true};NS.db.collapsed[1]=true;NS:Change()
assert(NS.UI.scroll:GetVerticalScroll()==0)
local first=false
for _,r in ipairs(NS.UI.rows) do if r:IsShown() and r.kind=="quest" and r.questID==1 then first=true end end
assert(first)
''')

    def test_mouse_scrolling_paints_new_rows_without_allocating_whole_list(self):
        a=client(party=False)
        a.execute('''
MOCK.log={}
for id=1,100 do MOCK.log[id]={questID=id,title=string.format("Quest %03d",id),level=10,objectives={}} end
NS:Scan();NS.db.hideFinished=false;NS:Change()
local top=NS.UI.rows[1].questID
for i=1,12 do NS.UI.scroll.scripts.OnMouseWheel(NS.UI.scroll,-1) end
assert(NS.UI.scroll:GetVerticalScroll()>0 and #NS.UI.rows<80)
assert(NS.UI.rows[1].questID~=top)
''')

    def test_progress_caches_prune_quests_no_longer_held(self):
        a=client(party=False);log(a);a.globals().MOCK.Tick(2)
        a.execute('''
NS.recentProgress[38]=GetTime();NS.partyReady[38]=false;NS.autoExpanded[38]=GetTime()+15
MOCK.log={};NS:Scan()
assert(not NS.recentProgress[38] and NS.partyReady[38]==nil and not NS.autoExpanded[38])
''')


class SecurityAuditTests(unittest.TestCase):
    def test_unreasonable_api_count_fails_without_looping_or_losing_progress(self):
        a=client(party=False);log(a);a.globals().MOCK.Tick(2)
        a.execute('''
C_QuestLog.GetNumQuestLogEntries=function() return 1000000000 end
local ok=NS:Scan();assert(not ok and NS.readError and NS.localQuests[38])
''')

    def test_full_active_log_takes_priority_over_turn_in_history(self):
        a=client(party=False)
        a.execute('''
for id=1,100 do MOCK.log[id]={questID=id,title="Active",level=10,objectives={}} end
for id=101,150 do NS.localQuests[id]={id=id,title="Turned in",state="T",level=10,turnedAt=GetTime()-id,objectives={}} end
assert(NS:Scan() and not NS.readError and NS.Core.Count(NS.localQuests)==100)
assert(NS.Core.Count(NS.recentTurnIns)<=30)
''')

    def test_malformed_packets_and_records_never_execute_or_mutate_known_data(self):
        a=client()
        a.execute('''
local C=NS.Core
local original={[38]={id=38,title="Safe",level=10,state="A",objectives={}}}
local bad={"", "F\\nQ\\t0\\t10\\tA\\tBad", "D\\nX\\t38\\nO\\t38\\t1\\t0\\t3\\t0\\titem\\tx",
 "F\\nQ\\t38\\t10\\tA\\tGood\\nQ\\t38\\t10\\tA\\tDuplicate", "F\\nQ\\t38\\t10\\tA\\tx\\nO\\t38\\t1\\t0\\t3\\t9\\titem\\tx"}
for _,payload in ipairs(bad) do
 local ok,result=pcall(C.Decode,payload,original);assert(ok and not result and original[38].title=="Safe")
end
assert(not C.Decode("F\\n"..string.rep("X\\t38\\n",2202)))
assert(not C.Decode("F\\nQ\\t38\\t10\\tA\\tx\\tregion\\textra\\tmore\\tbad"))
local peer={quests=original,ready=true,session="safe",revision=1,online=true}
local packets=C.Chunks("F","other",2,1)
local ok,reason=C.Receive(peer,packets[1],GetTime());assert(not ok and reason=="Invalid revision base")
assert(peer.quests==original)
''')

    def test_randomized_decoder_and_packet_fuzzing_does_not_raise(self):
        a=client(party=False)
        a.execute('''
math.randomseed(4517)
local alphabet="FDOQXabc123%|\\t\\n"
local peer={};local previous={}
for n=1,10000 do
 local out={}
 for j=1,math.random(0,254) do local i=math.random(1,#alphabet);out[j]=alphabet:sub(i,i) end
 local input=table.concat(out)
 assert(pcall(NS.Core.Decode,input,previous))
 assert(pcall(NS.Core.Receive,peer,input,GetTime()))
end
''')

    def test_peer_flood_is_bounded_and_redraws_are_coalesced(self):
        a=client()
        a.execute('''
local renders=0;local render=NS.UI.Render
NS.UI.Render=function(...) renders=renders+1;return render(...) end
for rev=1,10000 do
 local message="1|attack|"..rev.."|0|1|1|F"
 NS:Receive(NS.Core.PREFIX,message,"PARTY","Brother-TestRealm")
end
assert(NS.received<=8 and NS.rx.rateLimited>9900 and renders==0)
MOCK.Tick(0.25);assert(renders<=1)
local peer=NS.peers["brother-testrealm"]
assert(peer and NS.Core.Count(peer.quests)==0 and NS.Core.Count(NS.peers)==1)
''')

    def test_session_history_and_partial_assemblies_stay_bounded(self):
        a=client(party=False)
        a.execute('''
local C=NS.Core;local peer={}
for i=1,150 do assert(C.Receive(peer,"1|s"..i.."|1|0|1|1|F",100+i*2)) end
assert(#peer.retiredOrder==32 and C.Count(peer.retired)==32)
assert(not C.Receive(peer,"1|s149|2|0|1|1|F",500))
local original=peer.quests
for i=1,300 do
 local packet="1|pending|2|0|"..i.."|300|"..string.rep("x",180)
 C.Receive(peer,packet,600)
 if i<300 then assert(peer.quests==original) end
end
assert(peer.quests==original and not peer.assembly)
''')

    def test_untrusted_display_text_escapes_markup_and_control_characters(self):
        a=client(party=False)
        a.execute('''
local C=NS.Core
assert(C.SafeText("|Ttexture:9000|t|Hlink|hClick|h")=="||Ttexture:9000||t||Hlink||hClick||h")
assert(C.SafeText("Quest\\nFake system message\\000")=="Quest Fake system message ")
assert(C.SafeText("One\\nTwo",true)=="One\\nTwo")
assert(#C.SafeText(string.rep("a",20000))==12000)
local quests=C.Decode("F\\nQ\\t38\\t10\\tA\\tloadstring('NOT_EXECUTED')|Hfake|h")
assert(quests[38] and not _G.NOT_EXECUTED)
''')

    def test_corrupt_saved_values_fall_back_without_loading_errors(self):
        a=client(party=False,before='''QuestPartnersDB={opacity="invalid",barOpacity="invalid",fontSize=0/0,width=math.huge,
 x="invalid",y=math.huge,mode="bad",colors={red={0/0,math.huge,"red"}},
 selected={[38]=true,[0]=true,["bad"]=true,[42]={}},hiddenZones={["bad\\nregion"]=true,westfall=true},pinned={[38]=true}}''')
        a.execute('''
assert(NS.db.opacity==0.65 and NS.db.barOpacity==0.92 and NS.db.fontSize==12 and NS.db.width==340)
assert(NS.db.x==nil and NS.db.y==nil and NS.db.mode=="auto")
assert(NS.db.selected[38] and not NS.db.selected[0] and not NS.db.selected.bad and not NS.db.selected[42])
assert(NS.db.hiddenZones.westfall and not NS.db.hiddenZones["bad\\nregion"])
assert(NS.db.colors.red[1]==NS.Core.DEFAULT_COLORS.red[1] and NS.db.pinned[38])
local large={};for id=1,10000 do large[id]=true end;assert(NS.Core.Count(NS.Core.CleanSet(large))==512)
''')


class AddonCompatibilityAuditTests(unittest.TestCase):
    def test_other_prefixes_and_channels_do_not_touch_our_peer_state(self):
        a=client()
        a.execute('''
local other=CreateFrame("Frame");other:RegisterEvent("CHAT_MSG_ADDON")
other:SetScript("OnEvent",function() MOCK.otherEvents=(MOCK.otherEvents or 0)+1 end)
MOCK.Fire("CHAT_MSG_ADDON","QuestTogether","payload","PARTY","Brother-TestRealm")
MOCK.Fire("CHAT_MSG_ADDON","Questie","payload","GUILD","Brother-TestRealm")
MOCK.Fire("CHAT_MSG_ADDON",NS.Core.PREFIX,"1|s|1|0|1|1|F","INSTANCE_CHAT","Brother-TestRealm")
assert(MOCK.otherEvents==3 and NS.rx.raw==0 and not next(NS.peers))
''')

    def test_slash_alias_yields_and_preserves_another_addons_command(self):
        a=client(party=False,before='SLASH_QUESTPOP1="/qp";SlashCmdList.QUESTPOP=function() MOCK.otherCommand=true end')
        a.execute('''
assert(SLASH_QUESTPARTNERS1=="/questpartners" and SLASH_QUESTPARTNERS2==nil)
assert(SLASH_QUESTPOP1=="/qp");SlashCmdList.QUESTPOP();assert(MOCK.otherCommand)
SlashCmdList.QUESTPARTNERS("show");assert(NS.db.shown)
''')
        b=client(party=False)
        b.execute('''
assert(SLASH_QUESTPARTNERS2=="/qp")
SLASH_ANOTHER1="/qp";MOCK.Fire("PLAYER_LOGIN")
assert(SLASH_QUESTPARTNERS2==nil and SLASH_ANOTHER1=="/qp")
''')

    def test_reset_does_not_hide_or_restyle_another_addons_colour_picker(self):
        a=client(party=False)
        a.execute('''
local changedStrata=0
ColorPickerFrame.SetFrameStrata=function() changedStrata=changedStrata+1 end
NS.Settings:PickColor(NS,"red")
local oldCancel=ColorPickerFrame.info.cancelFunc
ColorPickerFrame:SetupColorPickerAndShow({r=0.2,g=0.3,b=0.4})
NS:ResetAppearance();oldCancel()
assert(ColorPickerFrame:IsShown() and changedStrata==0 and ColorPickerFrame.info.r==0.2)
assert(NS.db.colors.red[1]==NS.Core.DEFAULT_COLORS.red[1])
''')

    def test_leaving_our_widgets_does_not_hide_another_owners_tooltip(self):
        a=client(party=False);log(a);a.globals().MOCK.Tick(2)
        a.execute('''
GameTooltip.IsOwned=function(self,frame) return self.owner==frame end
GameTooltip.SetOwner=function(self,frame) self.owner=frame end
local other=CreateFrame("Frame")
local widget=NS.UI.scope
widget.scripts.OnEnter(widget);assert(GameTooltip.owner==widget)
GameTooltip:SetOwner(other);GameTooltip:Show();widget.scripts.OnLeave(widget)
assert(GameTooltip:IsShown())
GameTooltip:SetOwner(widget);widget.scripts.OnLeave(widget);assert(not GameTooltip:IsShown())
''')

    def test_runtime_does_not_replace_native_apis_or_another_addons_settings(self):
        a=client(party=False,before='''OtherAddonDB={enabled=true};nativeGetInfo=C_QuestLog.GetInfo;
nativeSend=C_ChatInfo.SendAddonMessage;nativeCreateFrame=CreateFrame;
SetCVar=function() error("Unexpected CVar change") end;
SendChatMessage=function() error("Unexpected public chat") end;
C_QuestLog.SetSelectedQuest=function() error("Unexpected protected selection mutation") end''')
        log(a);a.globals().MOCK.Tick(4)
        a.execute('''
NS:Slash("demo");NS:Slash("settings");NS.Settings.testBubble.scripts.OnClick(NS.Settings.testBubble)
assert(C_QuestLog.GetInfo==nativeGetInfo and C_ChatInfo.SendAddonMessage==nativeSend and CreateFrame==nativeCreateFrame)
assert(OtherAddonDB.enabled)
''')


if __name__=='__main__':
    unittest.main(verbosity=2)
