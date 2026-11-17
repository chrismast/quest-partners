"""Run using Python + lupa (Lua 5.1). No WoW client or accounts needed."""
from pathlib import Path
import sys
import unittest

try:
    from lupa.lua51 import LuaRuntime
except ImportError:
    sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'scratch' / 'questpartners-deps'))
    from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
ADDON = ROOT/'QuestPartners' if (ROOT/'QuestPartners/QuestPartners.toc').exists() else ROOT

def client(name='Tester', party=True, before=None):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute((Path(__file__).parent/'wow_mock.lua').read_text(encoding='utf-8'))
    lua.execute('NS = {}')
    lua.globals().MOCK.name = name
    if before:
        lua.execute(before)
    if party:
        partner = 'Brother' if name == 'Tester' else 'Tester'
        lua.execute(f'MOCK.party.party1={{name="{partner}",online=true}}')
    for filename in ('Core.lua', 'UI.lua', 'Settings.lua', 'Features.lua', 'Main.lua'):
        lua.globals().MOCK.Load(filename, lua.globals().NS,
            (ADDON/filename).read_text(encoding='utf-8'))
    lua.execute('MOCK.Fire("ADDON_LOADED", "QuestPartners")')
    return lua

def route(source, dest):
    messages = source.globals().MOCK.messages
    for i in range(1, len(messages)+1):
        m = messages[i]
        dest.globals().MOCK.Fire('CHAT_MSG_ADDON', m.prefix, m.message, m.channel,
            source.globals().MOCK.Sender())
    source.execute('MOCK.messages = {}')

def exchange(a, b, steps=160):
    for _ in range(steps):
        a.globals().MOCK.Tick(.25)
        route(a, b)
        b.globals().MOCK.Tick(.25)
        route(b, a)

def log(lua, have=2, need=3, complete=False):
    lua.execute('MOCK.log={{questID=38,title="Westfall Stew",level=13,complete=%s,objectives={'
        '{text="Stringy Vulture Meat: %d/%d",type="item",numFulfilled=%d,numRequired=%d,finished=%s}}}}'
        % ('true' if complete else 'false',have,need,have,need,'true' if have==need else 'false'))
    lua.execute('MOCK.Fire("QUEST_LOG_UPDATE")')

def region_log(lua,have=2):
    lua.execute('''MOCK.log={
 {isHeader=true,title="Westfall",questID=0},
 {questID=38,title="Westfall test quest",level=13,objectives={{text="Supplies",type="item",numFulfilled=%d,numRequired=15}}},
 {isHeader=true,title="Elwynn Forest",questID=0},
 {questID=900001,title="Forest test quest",level=10,objectives={{text="Patrol checkpoints",type="event",numFulfilled=1,numRequired=3}}}
}; MOCK.Fire("QUEST_LOG_UPDATE")''' % have)

class CoreTests(unittest.TestCase):
    def setUp(self):
        self.lua=client()

    def runlua(self, text):
        self.lua.execute(text)

    def test_thresholds_and_unknown_states(self):
        self.runlua('''
local C=NS.Core
local q={state="A",objectives={{fulfilled=5,required=15}}}
local r,c,t=C.Progress(q,1,"live"); assert(c=="red" and t=="5/15")
q.objectives[1].fulfilled=8
r,c,t=C.Progress(q,1,"live"); assert(c=="yellow" and t=="8/15")
q.objectives[1].fulfilled=15
r,c,t=C.Progress(q,1,"live"); assert(c=="green" and r==1)
r,c,t=C.Progress(q,1,"stale"); assert(c=="grey" and t=="Stale: 15/15")
r,c,t=C.Progress(nil,1,"waiting"); assert(t=="Waiting for sync")
r,c,t=C.Progress(nil,1,"live"); assert(t=="Not in log")
q.state="T"; r,c,t=C.Progress(q,1,"live"); assert(t=="Turned in")
q.state="F"; r,c,t=C.Progress(q,1,"live"); assert(t=="Failed")
q={state="A",objectives={{}}}; r,c,t=C.Progress(q,1,"live"); assert(t=="Pending")
''')

    def test_roundtrip_escaping_and_utf8(self):
        self.runlua('''
local C=NS.Core
local text="ä Thai ไทย % \\t \\n |cffff0000Test|r"
local q={[38]={id=38,title=text,level=13,state="A",objectives={{text=text,type="item",fulfilled=0,required=3,finished=false}}}}
local copy=C.Decode(C.Serialize(q,nil,true))
assert(copy[38].title==text and copy[38].objectives[1].text==text)
assert(copy[38].objectives[1].fulfilled==0)
assert(C.SafeText("|Tbad:2000|t")=="||Tbad:2000||t")
assert(C.ObjectiveLabel("Meat: 2/3")=="Meat")
''')

    def test_fragment_reordering_duplicates_and_atomicity(self):
        self.runlua('''
local C=NS.Core
local q={[38]={id=38,title=string.rep("x",700),level=13,state="A",objectives={}}}
local packets=C.Chunks(C.Serialize(q,nil,true),"s1",1,0)
local p={}; assert(#packets>3)
for i=#packets,2,-1 do assert(not C.Receive(p,packets[i],100)) end
assert(not p.quests)
assert(not C.Receive(p,packets[2],100))
assert(C.Receive(p,packets[1],101)); assert(p.quests[38].title==q[38].title)
assert(not C.Receive(p,packets[1],102))
''')

    def test_delta_deletion_and_revision_gap(self):
        self.runlua('''
local C=NS.Core
local q={[38]={id=38,title="Quest",level=13,state="A",objectives={{fulfilled=2,required=3,text="Meat"}}}}
local p={}
for _,m in ipairs(C.Chunks(C.Serialize(q,nil,true),"s1",1,0)) do C.Receive(p,m,100) end
local nextq=C.Copy(q); nextq[38].objectives[1].fulfilled=3
for _,m in ipairs(C.Chunks(C.Serialize(nextq,q,false),"s1",2,1)) do C.Receive(p,m,101) end
assert(p.quests[38].objectives[1].fulfilled==3)
for _,m in ipairs(C.Chunks(C.Serialize({},nextq,false),"s1",4,3)) do C.Receive(p,m,102) end
assert(p.needsFull and p.quests[38])
for _,m in ipairs(C.Chunks(C.Serialize({},nil,true),"s1",5,0)) do C.Receive(p,m,103) end
assert(not p.needsFull and not next(p.quests))
assert(C.Serialize({}, {}, false)==nil)
''')

    def test_invalid_payload_does_not_mutate_previous(self):
        self.runlua('''
local C=NS.Core
local q={[38]={id=38,title="Good",level=13,state="A",objectives={}}}
assert(not C.Decode("D\\nX\\t38\\nQ\\t0\\t0\\tA\\tBad",q))
assert(q[38].title=="Good")
assert(not C.Decode("F\\nQ\\t38\\t13\\tA\\tTitle\\nO\\t38\\t21\\t0\\t3\\t0\\titem\\tMeat"))
assert(not C.Receive({},"1|s|1|0|301|301|bad",100))
assert(not C.Decode("F\\nQ\\t38\\t13\\tZ\\tTitle"))
''')

    def test_retired_session_and_staleness(self):
        self.runlua('''
local C=NS.Core; local p={online=true}
for _,m in ipairs(C.Chunks("F","old",1,0)) do C.Receive(p,m,100) end
for _,m in ipairs(C.Chunks("F","new",1,0)) do C.Receive(p,m,101) end
for _,m in ipairs(C.Chunks("F","old",2,0)) do assert(not C.Receive(p,m,102)) end
assert(p.session=="new")
assert(C.PeerStatus(p,145)=="live")
assert(C.PeerStatus(p,147)=="stale")
p.online=false; assert(C.PeerStatus(p,147)=="offline")
''')

    def test_hide_finished_requires_everyone_and_fresh_data(self):
        self.runlua('''
local C=NS.Core
local q={id=38,title="Quest",level=13,state="C",objectives={}}
local a={localPlayer=true,quests={[38]=q}}
local b={ready=true,online=true,lastSeen=100,quests={[38]=C.Copy(q)}}
local db={mode="auto",hideFinished=true,selected={}}
assert(#C.Visible({a,b},db,100)==0)
b.quests[38].state="A"; assert(#C.Visible({a,b},db,100)==1)
b.quests[38].state="T"; assert(#C.Visible({a,b},db,100)==0)
assert(#C.Visible({a,b},db,150)==1)
db.mode="manual"; db.selected[38]=true; b.quests={}
assert(#C.Visible({a,b},db,100)==0) -- a fresh non-holder does not block hiding
b.ready=false; assert(#C.Visible({a,b},db,100)==1)
''')

class IntegrationTests(unittest.TestCase):
    def test_two_clients_initial_sync_then_live_progress(self):
        a,b=client(),client('Brother')
        log(a,2); log(b,1)
        exchange(a,b)
        self.assertEqual(a.eval('NS.peers["brother-testrealm"].quests[38].objectives[1].fulfilled'),1)
        self.assertEqual(b.eval('NS.peers["tester-testrealm"].quests[38].objectives[1].fulfilled'),2)
        log(b,3)
        exchange(a,b,12)
        self.assertEqual(a.eval('NS.peers["brother-testrealm"].quests[38].objectives[1].fulfilled'),3)
        self.assertEqual(a.eval('#NS.Core.Visible(NS:Players(),NS.db,GetTime())'),1)

    def test_large_log_and_multiple_objectives(self):
        a,b=client(),client('Brother')
        for lua in (a,b):
            lua.execute('''MOCK.log={}
for i=1,40 do
 MOCK.log[i]={questID=i,title="Example quest "..i,level=i,objectives={}}
 for j=1,4 do MOCK.log[i].objectives[j]={text="Objective "..j,type="item",numFulfilled=j,numRequired=15} end
end
MOCK.Fire("QUEST_LOG_UPDATE")''')
        exchange(a,b,240)
        self.assertEqual(a.eval('NS.Core.Count(NS.peers["brother-testrealm"].quests)'),40)
        self.assertEqual(a.eval('NS.peers["brother-testrealm"].quests[40].objectives[4].fulfilled'),4)
        self.assertEqual(a.eval('NS.UI.frame:GetHeight()'),360)
        self.assertTrue(a.eval('NS.UI.scrollHint:IsShown()'))

    def test_turn_in_versus_abandonment(self):
        a,b=client(),client('Brother')
        log(a);log(b);exchange(a,b)
        b.execute('MOCK.Fire("QUEST_TURNED_IN",38); MOCK.log={}; MOCK.Fire("QUEST_LOG_UPDATE")')
        exchange(a,b,16)
        self.assertEqual(a.eval('NS.peers["brother-testrealm"].quests[38].state'),'T')
        log(b)
        b.execute('MOCK.Fire("QUEST_ACCEPTED",38)')
        exchange(a,b,8)
        b.execute('MOCK.log={}; MOCK.Fire("QUEST_REMOVED",38)')
        exchange(a,b,16)
        self.assertIsNone(a.eval('NS.peers["brother-testrealm"].quests[38]'))

    def test_sender_and_channel_validation(self):
        a=client()
        a.execute('''
local m=NS.Core.Chunks("F","remote",1,0)[1]
NS:Receive(NS.Core.PREFIX,m,"GUILD","Brother-TestRealm")
NS:Receive(NS.Core.PREFIX,m,"PARTY","Stranger-TestRealm")
assert(not next(NS.peers))
NS:Receive(NS.Core.PREFIX,m,"PARTY","Brother-TestRealm")
assert(NS.peers["brother-testrealm"].ready)
MOCK.party.party1=nil; NS:UpdateRoster(); assert(not next(NS.peers))
''')

    def test_message_throttle_retry(self):
        a,b=client(),client('Brother')
        log(a);log(b)
        a.execute('MOCK.sendResult=3')
        exchange(a,b,12)
        self.assertIn('Sync blocked',a.eval('NS.sendError'))
        a.execute('MOCK.sendResult=nil')
        exchange(a,b,100)
        self.assertTrue(b.eval('NS.peers["tester-testrealm"].ready'))

    def test_popup_controls_and_transparency_do_not_fade_text(self):
        a=client(party=False);log(a);a.globals().MOCK.Tick(2)
        a.execute('''
assert(NS.UI.frame.bg.color[4]==0.65)
assert(NS.UI.frame:GetHeight()<360)
NS:Slash("options"); assert(MOCK.openedCategory==7)
NS.Settings.sliders.opacity.slider:SetValue(0)
assert(NS.db.opacity==0 and NS.UI.frame.bg.color[4]==0)
assert(NS.UI.title.textColor[4]==nil)
NS:Slash("quests"); assert(NS.UI.questPopup:IsShown())
NS.UI.autoCheck:SetChecked(false); NS.UI.autoCheck.scripts.OnClick(NS.UI.autoCheck)
assert(NS.db.mode=="manual")
NS.UI.choices[1]:SetChecked(true); NS.UI.choices[1].scripts.OnClick(NS.UI.choices[1])
assert(NS.db.selected[38])
NS:Slash("lock"); assert(NS.db.locked)
NS:Slash("demo"); assert(NS.demo)
NS:Slash("demo"); assert(not NS.demo)
NS.db.minimized=true; NS:Change(); assert(NS.UI.frame:GetHeight()==30)
NS.db.minimized=false; NS:Change()
NS:Slash("opacity 35"); assert(NS.db.opacity==0.35)
NS:Slash("hide"); assert(not NS.UI.frame:IsShown())
NS:Slash("show"); assert(NS.UI.frame:IsShown())
NS:Slash("reset"); assert(NS.db.opacity==0.35)
NS:Slash("status")
''')

    def test_offline_and_reconnect_require_new_data(self):
        a,b=client(),client('Brother');log(a);log(b);exchange(a,b)
        a.execute('MOCK.party.party1.online=false; NS:UpdateRoster()')
        self.assertEqual(a.eval('NS.Core.PeerStatus(NS:Players()[2],GetTime())'),'offline')
        a.execute('MOCK.party.party1.online=true; NS:UpdateRoster()')
        self.assertEqual(a.eval('NS.Core.PeerStatus(NS:Players()[2],GetTime())'),'waiting')
        exchange(a,b,100)
        self.assertEqual(a.eval('NS.Core.PeerStatus(NS:Players()[2],GetTime())'),'live')

    def test_instance_group_and_raid_guard(self):
        a=client()
        a.execute('MOCK.instance=true; assert(NS:Channel()=="INSTANCE_CHAT"); MOCK.raid=true; NS:UpdateRoster(); assert(NS:Channel()==nil)')

    def test_lost_delta_recovers_from_revision_gap(self):
        a,b=client(),client('Brother');log(a);log(b);exchange(a,b)
        log(b,3)
        b.globals().MOCK.Tick(3)
        b.execute('MOCK.messages={}')  # Drop one whole revision.
        log(b,1)
        exchange(a,b,160)
        self.assertEqual(a.eval('NS.peers["brother-testrealm"].quests[38].objectives[1].fulfilled'),1)
        self.assertFalse(a.eval('NS.peers["brother-testrealm"].needsFull'))

    def test_reload_with_a_new_session(self):
        a,b=client(),client('Brother');log(a);log(b);exchange(a,b)
        b=client('Brother')
        b.execute('NS.session="reload-session"')
        log(b,3)
        exchange(a,b)
        self.assertEqual(a.eval('NS.peers["brother-testrealm"].session'),'reload-session')
        self.assertEqual(a.eval('NS.peers["brother-testrealm"].quests[38].objectives[1].fulfilled'),3)

    def test_turn_in_history_is_bounded_and_expires(self):
        a=client(party=False)
        a.execute('''
for i=1,50 do
 NS.localQuests[i]={id=i,title="Old quest",level=10,state="T",turnedAt=GetTime()-i,objectives={}}
end
NS:Scan(); assert(NS.Core.Count(NS.localQuests)==30)
MOCK.time=MOCK.time+1801; NS:Scan(); assert(NS.Core.Count(NS.localQuests)==0)
''')

    def test_api_failure_does_not_erase_known_progress(self):
        a=client(party=False);log(a);a.globals().MOCK.Tick(2)
        a.execute('''
C_QuestLog.GetInfo=function() error("Simulated restricted API") end
MOCK.Fire("QUEST_LOG_UPDATE"); MOCK.Tick(1)
assert(NS.localQuests[38].objectives[1].fulfilled==2)
assert(NS.readError and NS.Core.PeerStatus(NS:Players()[1],GetTime())=="stale")
''')

class AutomaticProgressTests(unittest.TestCase):
    def setUp(self):
        self.a,self.b=client(),client('Brother')
        log(self.a,2,15);log(self.b,1,15);exchange(self.a,self.b)

    def change_progress(self,lua,have):
        obj=lua.globals().MOCK.log[1].objectives[1]
        obj.numFulfilled=have; obj.finished=have==15
        obj.text=f'Stringy Vulture Meat: {have}/15'

    def test_bag_only_pickup_updates_partner_without_manual_sync(self):
        self.change_progress(self.b,3)
        self.b.execute('MOCK.Fire("BAG_UPDATE_DELAYED")')
        exchange(self.a,self.b,8)
        self.assertEqual(self.a.eval('NS:Players()[2].quests[38].objectives[1].fulfilled'),3)

    def test_backup_read_catches_missed_events_within_three_seconds(self):
        self.change_progress(self.b,4)
        exchange(self.a,self.b,12)
        self.assertEqual(self.a.eval('NS:Players()[2].quests[38].objectives[1].fulfilled'),4)

    def test_continuous_quest_events_cannot_postpone_updates(self):
        self.change_progress(self.b,5)
        for _ in range(8):
            self.b.execute('MOCK.Fire("QUEST_LOG_UPDATE")')
            exchange(self.a,self.b,1)
        self.assertEqual(self.a.eval('NS:Players()[2].quests[38].objectives[1].fulfilled'),5)

    def test_unit_quest_progress_updates_in_both_selection_modes(self):
        for mode,value in [('manual',6),('auto',7)]:
            with self.subTest(mode=mode):
                self.b.execute(f'NS.db.mode="{mode}"; NS.db.selected={{}}; NS:Slash("hide")')
                self.change_progress(self.b,value)
                self.b.execute('MOCK.Fire("UNIT_QUEST_LOG_CHANGED","player")')
                exchange(self.a,self.b,8)
                self.assertEqual(self.a.eval('NS:Players()[2].quests[38].objectives[1].fulfilled'),value)
        self.change_progress(self.a,8)
        self.a.execute('MOCK.Fire("QUEST_WATCH_UPDATE",38)')
        exchange(self.a,self.b,8)
        self.assertEqual(self.b.eval('NS:Players()[2].quests[38].objectives[1].fulfilled'),8)

    def test_rapid_pickups_and_delayed_api_refresh_converge_to_latest_count(self):
        # An event may precede the actual quest API update. No second event follows.
        self.b.execute('MOCK.Fire("BAG_UPDATE_DELAYED")')
        exchange(self.a,self.b,2)
        self.change_progress(self.b,9)
        exchange(self.a,self.b,12)
        self.assertEqual(self.a.eval('NS:Players()[2].quests[38].objectives[1].fulfilled'),9)
        for value in range(10,16):
            self.change_progress(self.b,value)
            self.b.execute('MOCK.Fire("BAG_UPDATE_DELAYED")')
            exchange(self.a,self.b,1)
        exchange(self.a,self.b,8)
        self.assertEqual(self.a.eval('NS:Players()[2].quests[38].objectives[1].fulfilled'),15)

    def test_unchanged_backup_reads_do_not_send_quest_log_deltas(self):
        revision=self.b.eval('NS.revision')
        reads=self.b.eval('NS.scanCount')
        exchange(self.a,self.b,32)
        self.assertGreater(self.b.eval('NS.scanCount'),reads)
        self.assertEqual(self.b.eval('NS.revision'),revision)

    def test_changes_during_initial_full_log_arrive_without_duplicate_full_queue(self):
        a,b=client(),client('Brother')
        for lua in (a,b):
            lua.execute('''MOCK.log={}
for i=1,35 do
 MOCK.log[i]={questID=i,title="Long initial quest "..i,level=13,objectives={}}
 for j=1,4 do MOCK.log[i].objectives[j]={text="A long objective description "..j,type="item",numFulfilled=0,numRequired=15} end
end
MOCK.Fire("QUEST_LOG_UPDATE")''')
        exchange(a,b,16)
        b.execute('''
assert(NS.queue and NS.queue.full)
local p=NS.peers["tester-testrealm"]; p.nextReply=0
NS:Receive(NS.Core.PREFIX,"R|1","PARTY","Tester-TestRealm")
assert(not NS.pendingFull)
MOCK.log[1].objectives[1].numFulfilled=11
MOCK.Fire("BAG_UPDATE_DELAYED")
''')
        exchange(a,b,160)
        self.assertEqual(a.eval('NS:Players()[2].quests[1].objectives[1].fulfilled'),11)

class ForeverSyncTests(unittest.TestCase):
    def test_forever_first_and_surname_names_sync_both_directions(self):
        a=client(name='Aldren',party=False,before='MOCK.forever=true; MOCK.surname="Oakvale"')
        b=client(name='Brenna',party=False,before='MOCK.forever=true; MOCK.surname="Real"')
        a.execute('MOCK.party.party1={name="Brenna",surname="Real",online=true}; MOCK.Fire("GROUP_ROSTER_UPDATE")')
        b.execute('MOCK.party.party1={name="Aldren",surname="Oakvale",online=true}; MOCK.Fire("GROUP_ROSTER_UPDATE")')
        log(a,2); log(b,1); exchange(a,b)
        self.assertGreater(a.eval('NS.received'),0)
        self.assertGreater(b.eval('NS.received'),0)
        self.assertEqual(a.eval('NS:Players()[1].name'),'Aldren Oakvale')
        self.assertEqual(a.eval('NS:Players()[2].name'),'Brenna Real')
        self.assertEqual(a.eval('NS:Players()[2].quests[38].objectives[1].fulfilled'),1)

    def test_explicit_shared_waits_for_overlap_all_shows_known_quests(self):
        a=client();log(a);a.globals().MOCK.Tick(2)
        a.execute('''
assert(NS.Core.AutomaticWaiting(NS:Players()))
assert(#NS.Core.Visible(NS:Players(),NS.db,GetTime())==0)
assert(NS:StatusText():find("choose All quests",1,true))
NS:SetScope("all")
assert(#NS.Core.Visible(NS:Players(),NS.db,GetTime())==1)
NS:SetScope("shared")
local p=NS:Players()[2]
local _,_,text=NS.Core.Progress(nil,1,NS.Core.PeerStatus(p,GetTime()))
assert(text=="Waiting for sync")
NS.peers["brother-testrealm"]={ready=true,online=true,lastSeen=GetTime(),quests={}}
assert(not NS.Core.AutomaticWaiting(NS:Players()))
assert(#NS.Core.Visible(NS:Players(),NS.db,GetTime())==0)
NS.peers["brother-testrealm"].quests=NS.Core.Copy(NS.localQuests)
assert(#NS.Core.Visible(NS:Players(),NS.db,GetTime())==1)
''')

    def test_surname_matching_is_unique_and_stays_party_only(self):
        a=client(name='Aldren',party=False,before='MOCK.forever=true; MOCK.surname="Oakvale"')
        a.execute('''
MOCK.party.party1={name="Brenna",surname="Real",online=true}
MOCK.party.party2={name="Brenna",surname="Other",online=true}
NS:UpdateRoster()
assert(NS:ResolveSender("Brenna Real")=="brenna real")
assert(NS:ResolveSender("Brenna Other")=="brenna other")
assert(NS:ResolveSender("Brenna Real-InternalRealm")=="brenna real")
assert(not NS:ResolveSender("Brenna"))
assert(not NS:ResolveSender("Brenna Pretender"))
NS:Receive(NS.Core.PREFIX,"R|1","GUILD","Brenna Real")
assert(NS.rx.raw==0)
NS:Receive(NS.Core.PREFIX,"R|1","PARTY","Brenna Pretender")
assert(NS.rx.unknownSender==1 and NS.lastUnknownSender=="Brenna Pretender")
assert(not next(NS.peers))
''')

    def test_forever_name_fallback_and_objective_labels(self):
        a=client(name='Aldren',party=False,before='MOCK.forever=true; MOCK.surname="Oakvale"; GetUnitName=nil; RegionalUniqueNamesEnabled=nil')
        a.execute('''
assert(NS.regionalNames and NS:Players()[1].name=="Aldren Oakvale")
assert(NS.Core.ObjectiveLabel("0/7 Longshore Murloc Gill")=="Longshore Murloc Gill")
assert(NS.Core.ObjectiveLabel("Stringy Vulture Meat: 2/3")=="Stringy Vulture Meat")
''')

    def test_diagnostics_distinguish_packets_from_accepted_updates(self):
        a,b=client(),client('Brother');log(a);log(b);exchange(a,b)
        a.execute('''
assert(NS.rx.raw>0 and NS.rx.matched>0 and NS.received>0)
assert(NS.peers["brother-testrealm"].version==NS.Core.VERSION)
local before=NS.received
NS:Receive(NS.Core.PREFIX,"1|s|1|0|1|1|Invalid","PARTY","Brother-TestRealm")
assert(NS.rx.rejected==1 and NS.received==before)
assert(NS.peers["brother-testrealm"].lastReject=="Full sync needed")
NS:Receive(NS.Core.PREFIX,"R|1","PARTY","Tester-TestRealm")
assert(NS.rx.selfEcho==1)
NS:Slash("status")
''')

    def test_numeric_send_failures_are_named(self):
        a=client()
        a.execute('''
MOCK.sendResult=11
NS:Send("R|1")
assert(NS.sendError:find("11: AddOnMessageLockdown",1,true))
MOCK.sendResult=nil
NS:Send("R|1")
assert(NS.lastSendResult=="Success" and not NS.sendError)
''')

class RegionTests(unittest.TestCase):
    def test_regions_come_from_headers_with_a_sequential_fallback(self):
        for header_api in (True,False):
            with self.subTest(header_api=header_api):
                a=client(party=False)
                if not header_api: a.execute('C_QuestLog.GetHeaderIndexForQuest=nil')
                region_log(a);a.globals().MOCK.Tick(1)
                self.assertEqual(a.eval('NS.localQuests[38].zone'),'Westfall')
                self.assertEqual(a.eval('NS.localQuests[900001].zone'),'Elwynn Forest')
                self.assertEqual(a.eval('NS.Core.Count(NS.localQuests)'),2)

    def test_region_collapse_hiding_and_restoration_preserve_quests(self):
        a=client(party=False);region_log(a);a.globals().MOCK.Tick(1)
        a.execute('''
local original=NS.UI.content:GetHeight()
local westfall
for _,r in ipairs(NS.UI.rows) do if r:IsShown() and r.zoneKey=="westfall" then westfall=r end end
assert(westfall); westfall.scripts.OnClick(westfall)
assert(NS.db.collapsedZones.westfall and NS.UI.content:GetHeight()<original)
NS:Slash("regions"); assert(NS.UI.manageTab=="regions" and NS.UI.regionPage:IsShown())
local choice
for _,b in ipairs(NS.UI.regionChoices) do if b.zoneKey=="westfall" then choice=b end end
choice:SetChecked(false); choice.scripts.OnClick(choice)
assert(NS.db.hiddenZones.westfall)
assert(#NS.Core.Visible(NS:Players(),NS.db,GetTime())==1)
assert(NS.Core.Count(NS.localQuests)==2)
NS.db.hiddenZones["old region"]=true
NS.UI.showAll.scripts.OnClick(NS.UI.showAll)
assert(not NS.db.hiddenZones.westfall and not NS.db.hiddenZones["old region"] and NS.db.collapsedZones.westfall)
NS.db.collapsedZones["old region"]=true
NS.UI.expandAll.scripts.OnClick(NS.UI.expandAll)
assert(not NS.db.collapsedZones.westfall and not NS.db.collapsedZones["old region"])
NS.UI.hideAll.scripts.OnClick(NS.UI.hideAll)
assert(#NS.Core.Visible(NS:Players(),NS.db,GetTime())==0 and NS.UI.empty:IsShown())
assert(#NS.UI.regionChoices==2)
NS.UI.showAll.scripts.OnClick(NS.UI.showAll)
assert(#NS.Core.Visible(NS:Players(),NS.db,GetTime())==2)
''')

    def test_collapse_all_compacts_a_long_list_to_region_headings(self):
        a=client(party=False)
        a.execute('''
MOCK.log={}
for zone=1,8 do
 MOCK.log[#MOCK.log+1]={isHeader=true,title="Region "..zone,questID=0}
 for q=1,5 do MOCK.log[#MOCK.log+1]={questID=zone*100+q,title="Quest "..q,level=10,objectives={{text="Item",numFulfilled=1,numRequired=10}}} end
end
MOCK.Fire("QUEST_LOG_UPDATE"); MOCK.Tick(1)
local expanded=NS.UI.content:GetHeight()
NS:Slash("regions"); NS.UI.collapseAll.scripts.OnClick(NS.UI.collapseAll)
local regions,quests=0,0
for _,r in ipairs(NS.UI.rows) do
 if r:IsShown() then if r.kind=="region" then regions=regions+1 elseif r.kind=="quest" then quests=quests+1 end end
end
assert(regions==8 and quests==0 and NS.Core.Count(NS.localQuests)==40)
assert(NS.UI.content:GetHeight()<expanded/3)
assert(NS.UI.frame:GetHeight()<360)
NS.UI.expandAll.scripts.OnClick(NS.UI.expandAll)
assert(NS.UI.content:GetHeight()==expanded)
''')

    def test_hidden_and_collapsed_regions_keep_receiving_live_updates(self):
        a,b=client(),client('Brother');region_log(a);region_log(b);exchange(a,b)
        self.assertEqual(a.eval('NS:Players()[2].quests[38].zone'),'Westfall')
        a.execute('NS.db.hiddenZones.westfall=true; NS.db.collapsedZones["elwynn forest"]=true; NS:Change()')
        b.execute('MOCK.log[2].objectives[1].numFulfilled=7; MOCK.Fire("BAG_UPDATE_DELAYED")')
        exchange(a,b,12)
        self.assertEqual(a.eval('NS:Players()[2].quests[38].objectives[1].fulfilled'),7)
        self.assertTrue(a.eval('NS.db.hiddenZones.westfall'))
        self.assertIsNone(b.eval('NS.db.hiddenZones.westfall'))
        a.execute('NS.db.hiddenZones.westfall=nil; NS:Change()')
        self.assertEqual(a.eval('NS:Players()[2].quests[38].objectives[1].fulfilled'),7)

    def test_zone_codec_negotiates_optional_metadata_without_breaking_legacy_rows(self):
        a=client(party=False)
        a.execute('''
local C=NS.Core
local q={[38]={id=38,title="Quest",level=13,state="A",zone="Forest\\t100%|r",objectives={}}}
local extended=C.Serialize(q,nil,true,true)
local old=C.Serialize(q,nil,true,false)
assert(C.Decode(extended)[38].zone==q[38].zone)
assert(C.Decode(old)[38].zone=="")
local tabs=0; for _ in old:gmatch("\\t") do tabs=tabs+1 end
assert(tabs==4)
assert(not C.SupportsZones("0.2.2-test4") and C.SupportsZones("0.3.0-test5"))
assert(not C.SupportsZones(nil) and not C.SupportsZones("garbage"))
''')
        a,b=client(),client('Brother')
        b.execute('NS._testZoneCheck=NS.CanSendZones; NS.Core.VERSION="0.2.2-test4"; NS.CanSendZones=function() return false end')
        region_log(a);region_log(b);exchange(a,b)
        self.assertFalse(a.eval('NS.lastZoneFormat'))
        self.assertGreater(a.eval('NS.received'),0)
        self.assertGreater(b.eval('NS.received'),0)
        b.execute('NS.Core.VERSION="0.3.0-test5"; NS.CanSendZones=NS._testZoneCheck; NS.nextHello=0')
        exchange(a,b,80)
        self.assertTrue(a.eval('NS.lastZoneFormat'))
        self.assertEqual(a.eval('NS:Players()[2].quests[38].zone'),'Westfall')

    def test_region_preferences_and_font_size_survive_saved_variable_loading(self):
        a=client(party=False,before='QuestPartnersDB={fontSize=20,groupByZone=true,hiddenZones={westfall=true},collapsedZones={["elwynn forest"]=true},selected={[38]=true}}')
        region_log(a);a.globals().MOCK.Tick(1)
        a.execute('''
assert(NS.db.fontSize==20 and NS.db.hiddenZones.westfall and NS.db.collapsedZones["elwynn forest"])
assert(NS.db.selected[38])
NS:ResetAppearance()
assert(NS.db.hiddenZones.westfall and NS.db.collapsedZones["elwynn forest"] and NS.db.selected[38])
''')

    def test_full_font_range_resizes_tracker_rows_and_status(self):
        a=client(party=False);region_log(a);a.globals().MOCK.Tick(1)
        a.execute('NS.UI:SetQuestFolds(NS,false)')
        for size in (10,20):
            a.execute(f'NS.Settings.sliders.fontSize.slider:SetValue({size})')
            a.execute('''
local size=NS.db.fontSize
assert(NS.UI.title.fontSize==size and NS.UI.footer.fontSize==math.max(10,size-2))
for _,r in ipairs(NS.UI.rows) do
 if r:IsShown() then
  if r.kind=="region" then assert(r.text.fontSize==size+1 and r:GetHeight()>=r.text:GetHeight())
  elseif r.kind=="quest" then assert(r.text.fontSize==size)
  elseif r.kind=="progress" then assert(r.count.fontSize==math.max(10,size-1) and r:GetHeight()>=r.count:GetHeight()) end
 end
end
assert(NS.UI.scroll.topInset+NS.UI.scroll.bottomInset<NS.UI.frame:GetHeight())
''')

    def test_flat_view_keeps_region_filters_and_quest_collapse_independent(self):
        a=client(party=False);region_log(a);a.globals().MOCK.Tick(1)
        a.execute('''
NS.db.collapsed[38]=true; NS.db.collapsedZones.westfall=true
NS.Settings.groupCheck:SetChecked(false); NS.Settings.groupCheck.scripts.OnClick(NS.Settings.groupCheck)
assert(not NS.db.groupByZone)
for _,r in ipairs(NS.UI.rows) do if r:IsShown() then assert(r.kind~="region") end end
NS.db.hiddenZones.westfall=true; NS:Change()
assert(#NS.Core.Visible(NS:Players(),NS.db,GetTime())==1)
NS.db.hiddenZones.westfall=nil
NS.Settings.groupCheck:SetChecked(true); NS.Settings.groupCheck.scripts.OnClick(NS.Settings.groupCheck)
assert(NS.db.collapsed[38] and NS.db.collapsedZones.westfall)
''')

    def test_demo_region_filters_do_not_hide_actual_regions(self):
        a=client(party=False);region_log(a);a.globals().MOCK.Tick(1)
        a.execute('''
NS:Slash("demo"); NS:Slash("regions")
NS.UI.hideAll.scripts.OnClick(NS.UI.hideAll)
assert(NS:ViewConfig().hiddenZones.westfall and not NS.db.hiddenZones.westfall)
NS:Slash("demo")
assert(#NS.Core.Visible(NS:Players(),NS.db,GetTime())==2)
''')

    def test_missing_region_is_labelled_unknown_and_remains_manageable(self):
        a=client(party=False);log(a);a.globals().MOCK.Tick(1)
        a.execute('''
local regions=NS.Core.Regions(NS.localQuests)
assert(#regions==1 and regions[1].name=="Other / unknown")
NS:Slash("regions"); NS.UI.hideAll.scripts.OnClick(NS.UI.hideAll)
assert(#NS.Core.Visible(NS:Players(),NS.db,GetTime())==0)
NS.UI.showAll.scripts.OnClick(NS.UI.showAll)
assert(#NS.Core.Visible(NS:Players(),NS.db,GetTime())==1)
''')

class CompactQuestTests(unittest.TestCase):
    def test_all_union_shared_overlap_and_custom_selection(self):
        a,b=client(),client('Brother')
        region_log(a);log(b);exchange(a,b)
        a.execute('''
assert(#NS.Core.Visible(NS:Players(),NS.db,GetTime())==1)
NS:SetScope("all"); assert(#NS.Core.Visible(NS:Players(),NS.db,GetTime())==2)
NS.db.mode="manual"; NS.db.selected={[900001]=true}
assert(#NS.Core.Visible(NS:Players(),NS.db,GetTime())==1)
NS.UI.scope.scripts.OnClick(NS.UI.scope)
assert(NS.db.scope=="all" and NS.db.mode=="auto" and NS.db.selected[900001])
NS.UI.scope.scripts.OnClick(NS.UI.scope)
assert(NS.db.scope=="shared" and #NS.Core.Visible(NS:Players(),NS.db,GetTime())==1)
''')
        b.execute('MOCK.log[2]={questID=99,title="Partner only",level=10,objectives={}}; MOCK.Fire("QUEST_LOG_UPDATE")')
        exchange(a,b,12)
        a.execute('NS:SetScope("all"); assert(#NS.Core.Visible(NS:Players(),NS.db,GetTime())==3)')

    def test_initial_sync_and_backup_reads_start_collapsed(self):
        a,b=client(),client('Brother');region_log(a);region_log(b);exchange(a,b)
        a.execute('''
assert(NS:IsQuestCollapsed(38) and NS:IsQuestCollapsed(900001))
for _,r in ipairs(NS.UI.rows) do assert(not r:IsShown() or r.kind~="progress") end
NS:ToggleQuest(38); assert(not NS:IsQuestCollapsed(38) and NS:IsQuestCollapsed(900001))
MOCK.Tick(4); assert(not NS:IsQuestCollapsed(38))
NS:ToggleQuest(38); assert(NS:IsQuestCollapsed(38))
''')

    def test_new_quests_and_reload_start_collapsed(self):
        a=client(party=False,before='QuestPartnersDB={collapsed={[38]=false},autoExpand=false}')
        log(a);a.globals().MOCK.Tick(2)
        self.assertTrue(a.eval('NS:IsQuestCollapsed(38)'))
        a.execute('NS:ToggleQuest(38)')
        region_log(a);a.globals().MOCK.Tick(2)
        a.execute('assert(not NS:IsQuestCollapsed(38) and NS:IsQuestCollapsed(900001))')

    def test_local_pickup_temporarily_opens_matching_quest_and_region(self):
        a=client(party=False);region_log(a);a.globals().MOCK.Tick(2)
        a.execute('''
NS.db.collapsedZones.westfall=true
MOCK.log[2].objectives[1].numFulfilled=3; MOCK.Fire("BAG_UPDATE_DELAYED"); MOCK.Tick(1)
assert(not NS:IsQuestCollapsed(38) and NS:IsQuestCollapsed(900001))
local found=false
for _,r in ipairs(NS.UI.rows) do if r:IsShown() and r.kind=="progress" then found=true end end
assert(found and NS.db.collapsedZones.westfall)
MOCK.Tick(16); assert(NS:IsQuestCollapsed(38))
for _,r in ipairs(NS.UI.rows) do assert(not r:IsShown() or r.kind~="progress") end
''')

    def test_partner_kill_progress_expands_after_initial_sync(self):
        a,b=client(),client('Brother');log(a);log(b);exchange(a,b)
        self.assertTrue(a.eval('NS:IsQuestCollapsed(38)'))
        b.execute('MOCK.log[1].objectives[1].numFulfilled=3; MOCK.log[1].objectives[1].finished=true; MOCK.Fire("QUEST_WATCH_UPDATE",38)')
        exchange(a,b,8)
        self.assertFalse(a.eval('NS:IsQuestCollapsed(38)'))
        a.execute('NS:ToggleQuest(38); assert(NS:IsQuestCollapsed(38)); MOCK.Tick(3); assert(NS:IsQuestCollapsed(38))')

    def test_auto_expansion_off_and_manual_open_outlasts_timer(self):
        a=client(party=False);log(a);a.globals().MOCK.Tick(2)
        a.execute('''
NS.Settings.autoExpandCheck:SetChecked(false); NS.Settings.autoExpandCheck.scripts.OnClick(NS.Settings.autoExpandCheck)
MOCK.log[1].objectives[1].numFulfilled=1; MOCK.Fire("QUEST_WATCH_UPDATE",38); MOCK.Tick(1)
assert(NS:IsQuestCollapsed(38))
NS:ToggleQuest(38); MOCK.Tick(20); assert(not NS:IsQuestCollapsed(38))
NS.Settings.autoExpandCheck:SetChecked(true); NS.Settings.autoExpandCheck.scripts.OnClick(NS.Settings.autoExpandCheck)
MOCK.log[1].objectives[1].numFulfilled=2; MOCK.Fire("BAG_UPDATE_DELAYED"); MOCK.Tick(20)
assert(not NS:IsQuestCollapsed(38))
''')

    def test_auto_expansion_preserves_hidden_regions_and_scope(self):
        a,b=client(),client('Brother');region_log(a);log(b);exchange(a,b)
        a.execute('''
NS.db.hiddenZones.westfall=true
MOCK.log[2].objectives[1].numFulfilled=3; MOCK.log[4].objectives[1].numFulfilled=2
MOCK.Fire("QUEST_WATCH_UPDATE"); MOCK.Tick(1)
assert(#NS.Core.Visible(NS:Players(),NS.db,GetTime())==0)
assert(NS.db.hiddenZones.westfall and NS.db.scope=="shared")
for _,r in ipairs(NS.UI.rows) do assert(not r:IsShown() or r.kind~="progress") end
''')

    def test_bulk_collapse_closes_auto_opens_without_changing_selection(self):
        a=client(party=False);region_log(a);a.globals().MOCK.Tick(2)
        a.execute('''
NS:Slash("quests"); NS.UI.expandQuests.scripts.OnClick(NS.UI.expandQuests)
assert(not NS:IsQuestCollapsed(38) and not NS:IsQuestCollapsed(900001))
MOCK.log[2].objectives[1].numFulfilled=3; MOCK.Fire("BAG_UPDATE_DELAYED"); MOCK.Tick(1)
NS.UI.collapseQuests.scripts.OnClick(NS.UI.collapseQuests)
assert(NS:IsQuestCollapsed(38) and NS:IsQuestCollapsed(900001))
assert(NS.Core.Count(NS.localQuests)==2 and NS.db.scope=="shared")
NS.UI.allScope.scripts.OnClick(NS.UI.allScope); assert(NS.db.scope=="all")
NS.UI.sharedScope.scripts.OnClick(NS.UI.sharedScope); assert(NS.db.scope=="shared")
''')

    def test_no_turned_in_only_ghosts_in_all_shared_or_manual(self):
        a=client(party=False)
        a.execute('''
local C=NS.Core
local q={id=38,title="Old quest",level=13,state="T",objectives={}}
local mine={localPlayer=true,quests={[38]=q}}
local other={online=true,ready=true,lastSeen=GetTime(),quests={[38]=C.Copy(q)}}
local third={online=true,ready=true,lastSeen=GetTime(),quests={}}
local cfg={scope="all",mode="auto",hideFinished=false,selected={[38]=true}}
for _,mode in ipairs({"auto","manual"}) do
 cfg.mode=mode
 for _,scope in ipairs({"all","shared"}) do
  cfg.scope=scope; assert(#C.Visible({mine,other,third},cfg,GetTime())==0)
 end
end
assert(C.Count(C.Catalogue({mine,other,third}))==0)
other.quests[38].state="A";cfg.mode="auto";cfg.scope="shared"
assert(#C.Visible({mine,other,third},cfg,GetTime())==1)
other.quests[38]=nil; assert(#C.Visible({mine,other,third},cfg,GetTime())==0)
''')

    def test_turn_in_survives_lingering_log_then_both_clients_clear(self):
        a,b=client(),client('Brother');log(a);log(b);exchange(a,b)
        b.execute('MOCK.Fire("QUEST_TURNED_IN",38)')
        exchange(a,b,12)
        self.assertEqual(b.eval('NS.localQuests[38].state'),'T')
        self.assertEqual(a.eval('NS.peers["brother-testrealm"].quests[38].state'),'T')
        self.assertEqual(a.eval('#NS.Core.Visible(NS:Players(),NS.db,GetTime())'),1)
        a.execute('MOCK.Fire("QUEST_TURNED_IN",38); MOCK.log={}')
        b.execute('MOCK.log={}; MOCK.Fire("QUEST_LOG_UPDATE")')
        exchange(a,b,16)
        for lua in (a,b):
            lua.execute('''
NS.db.hideFinished=false
for _,scope in ipairs({"all","shared"}) do
 NS:SetScope(scope); assert(#NS.Core.Visible(NS:Players(),NS.db,GetTime())==0)
 NS:Slash("quests"); assert(NS.UI.choiceContent:GetHeight()==1)
end
''')

    def test_repeatable_acceptance_clears_completion_for_both_event_shapes(self):
        for event_args in ('38','1,38'):
            with self.subTest(event_args=event_args):
                a=client(party=False);log(a);a.globals().MOCK.Tick(2)
                a.execute('MOCK.Fire("QUEST_TURNED_IN",38); MOCK.Tick(1); assert(NS.localQuests[38].state=="T")')
                log(a,0)
                a.execute(f'MOCK.Fire("QUEST_ACCEPTED",{event_args}); MOCK.Tick(1); assert(NS.localQuests[38].state=="A"); assert(NS:IsQuestCollapsed(38))')

    def test_repeatable_absence_then_reappearance_catches_missed_accept(self):
        a=client(party=False);log(a);a.globals().MOCK.Tick(2)
        a.execute('MOCK.Fire("QUEST_TURNED_IN",38); MOCK.log={}; MOCK.Tick(2)')
        log(a,0);a.globals().MOCK.Tick(2)
        a.execute('assert(NS.localQuests[38].state=="A" and not NS.recentTurnIns[38])')

    def test_fresh_non_holders_do_not_keep_ready_quests_visible(self):
        a,b=client(),client('Brother');log(a,3,complete=True);exchange(a,b)
        a.execute('NS:SetScope("all"); assert(#NS.Core.Visible(NS:Players(),NS.db,GetTime())==0)')
        a.execute('NS.db.hideFinished=false; NS:Change(); assert(#NS.Core.Visible(NS:Players(),NS.db,GetTime())==1)')

    def test_manual_scope_migration_and_demo_isolation(self):
        a=client(party=False,before='QuestPartnersDB={mode="manual",selected={[38]=true},collapsed={[38]=false},autoExpand=false}')
        log(a);a.globals().MOCK.Tick(2)
        a.execute('''
assert(NS.db.scope=="all" and NS.db.selected[38] and NS:IsQuestCollapsed(38))
NS:Slash("demo"); NS:SetScope("shared"); NS:ToggleQuest(38)
assert(not NS:IsQuestCollapsed(38))
NS:Slash("demo"); assert(NS.db.scope=="all" and NS.db.mode=="manual" and NS:IsQuestCollapsed(38))
''')

class AppearanceTests(unittest.TestCase):
    def test_appearance_migration_preserves_layout_and_selection(self):
        a=client(before='QuestPartnersDB={opacity=0.18,barOpacity=0.66,width=412,x=145,y=830,mode="manual",selected={[38]=true}}')
        a.execute('''
assert(NS.db.opacity==0.65 and NS.db.barOpacity==0.92)
assert(NS.db.width==412 and NS.db.x==145 and NS.db.y==830)
assert(NS.db.mode=="manual" and NS.db.selected[38])
assert(NS.db.colors.red[1]>0 and NS.db.styleVersion==2)
''')
        b=client(before='QuestPartnersDB={opacity=0.41,barOpacity=0.75,colors={red={0.1,0.2,0.3}}}')
        b.execute('assert(NS.db.opacity==0.41 and NS.db.barOpacity==0.75 and NS.db.colors.red[1]==0.1)')

    def test_demo_uses_actual_names_and_marks_solo_sample(self):
        a=client(name='Aldren Oakvale')
        a.execute('''
NS:Slash("demo")
local p=NS:ViewPlayers()
assert(p[1].name=="Aldren Oakvale" and p[2].name=="Tester")
for _,r in ipairs(NS.UI.rows) do
 if r:IsShown() and r.kind=="progress" then
  assert(r.name:GetText()~="You" and r.name:GetText()~="Brother")
 end
end
''')
        b=client(name='Aldren Oakvale',party=False)
        b.execute('NS:Slash("demo"); assert(NS:ViewPlayers()[2].name=="Partner (sample)")')

    def test_demo_selection_does_not_change_actual_quest_preferences(self):
        a=client(before='QuestPartnersDB={mode="manual",selected={[999]=true},collapsed={[999]=true}}')
        a.execute('''
NS:Slash("demo")
assert(#NS.Core.Visible(NS:ViewPlayers(),NS:ViewConfig(),GetTime())==3)
NS:Slash("quests"); NS.UI.autoCheck:SetChecked(false); NS.UI.autoCheck.scripts.OnClick(NS.UI.autoCheck)
NS.UI.choices[1]:SetChecked(true); NS.UI.choices[1].scripts.OnClick(NS.UI.choices[1])
assert(NS.db.mode=="manual" and NS.db.selected[999] and not NS.db.selected[38])
NS:Slash("demo"); assert(NS:ViewConfig()==NS.db)
''')

    def test_color_picker_updates_bars_and_cancel_restores(self):
        a=client(party=False);log(a,1);a.globals().MOCK.Tick(2)
        a.execute('''
NS:ToggleQuest(38)
local before=NS.Core.Copy(NS.db.colors.red)
NS.Settings:PickColor(NS,"red")
ColorPickerFrame.r,ColorPickerFrame.g,ColorPickerFrame.b=0.12,0.55,0.88
ColorPickerFrame.info.swatchFunc()
assert(NS.db.colors.red[1]==0.12)
local found=false
for _,r in ipairs(NS.UI.rows) do
 if r:IsShown() and r.kind=="progress" then
  assert(r.bar.statusColor[1]==0.12 and r.bar.statusColor[3]==0.88)
  found=true
 end
end
assert(found)
ColorPickerFrame.info.cancelFunc()
assert(NS.db.colors.red[1]==before[1] and NS.db.colors.red[3]==before[3])
''')

    def test_settings_registration_modern_legacy_and_fallback(self):
        a=client()
        a.execute('NS:Slash("settings"); assert(MOCK.registeredCategory.name=="Quest Partners" and MOCK.openedCategory==7)')
        b=client(before='Settings=nil')
        b.execute('NS:Slash("settings"); assert(MOCK.legacyPanel and MOCK.legacyOpened==NS.Settings.panel)')
        c=client(before='Settings=nil; InterfaceOptions_AddCategory=nil; InterfaceOptionsFrame_OpenToCategory=nil')
        c.execute('NS:Slash("settings"); assert(NS.Settings.fallback:IsShown() and NS.Settings.panel:IsShown())')

    def test_settings_can_register_when_loaded_after_the_addon(self):
        a=client(before='savedSettings=Settings; Settings=nil; InterfaceOptions_AddCategory=nil')
        a.execute('''
assert(not NS.Settings.category)
Settings=savedSettings; MOCK.Fire("ADDON_LOADED","Blizzard_Settings")
assert(NS.Settings.category and MOCK.registeredCategory)
''')

    def test_appearance_controls_dividers_and_reset(self):
        a=client(party=False);a.execute('NS:Slash("demo")')
        a.execute('''
NS.UI:SetQuestFolds(NS,false)
NS.Settings.sliders.opacity.slider:SetValue(80)
assert(NS.UI.frame.bg.color[4]==0.80)
assert(NS.Settings.sliders.opacity.hint:GetText()=="20% transparent")
NS.Settings.sliders.barOpacity.slider:SetValue(75)
NS.Settings.sliders.barHeight.slider:SetValue(20)
NS.Settings.sliders.questSpacing.slider:SetValue(24)
NS.Settings.sliders.fontSize.slider:SetValue(16)
for _,r in ipairs(NS.UI.rows) do
 if r:IsShown() and r.kind=="progress" then
  assert(r.bar.height==20 and r:GetHeight()>=23 and r.bar.statusColor[4]==0.75)
  assert(r.count.textColor[4]==nil)
 elseif r:IsShown() and r.kind=="quest" then
  assert(r.rule:IsShown() and r.accent:IsShown() and r.band:IsShown())
 end
end
assert(NS.UI.logo.texture==NS.Core.LOGO)
NS.db.selected[999]=true; NS.db.x=125; NS.db.y=800
NS.Settings:PickColor(NS,"red"); local staleCancel=ColorPickerFrame.info.cancelFunc
NS.Settings.resetAppearance.scripts.OnClick(NS.Settings.resetAppearance)
staleCancel()
assert(NS.db.opacity==0.65 and NS.db.barHeight==14 and NS.db.questSpacing==14)
assert(NS.db.selected[999] and NS.db.x==125 and NS.db.y==800)
''')

if __name__=='__main__':
    unittest.main(verbosity=2)
