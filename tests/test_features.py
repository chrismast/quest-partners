"""Gameplay-facing regressions for Test7, using isolated simulated WoW clients."""
import unittest
from test_addon import client, log, region_log, exchange, route


class SummaryAndSortingTests(unittest.TestCase):
    def test_summaries_use_objective_fractions_and_preserve_unknown_states(self):
        a=client(party=False)
        a.execute('''
local C=NS.Core
local q={state="A",objectives={{fulfilled=1,required=2},{fulfilled=1,required=10}}}
local text,ratio=C.Summary(q,"live"); assert(text=="30%" and ratio==0.3)
assert(C.Summary(q,"stale")=="Stale" and C.Summary(q,"offline")=="Offline")
assert(C.Summary(nil,"waiting")=="Syncing" and C.Summary(nil,"live")=="Not in log")
q.objectives[2]={finished=false}; assert(C.Summary(q,"live")=="0/2 done")
q.objectives[1].finished=true; assert(C.Summary(q,"live")=="1/2 done")
q.state="T"; assert(C.Summary(q,"live")=="Turned in")
q.state="C"; assert(C.Summary(q,"live")=="Ready")
''')

    def test_collapsed_summary_updates_without_opening_and_hover_has_full_names(self):
        a,b=client(),client('Brother');log(a,1);log(b,2);exchange(a,b)
        a.execute('''
NS.db.autoExpand=false
local found=false
for _,r in ipairs(NS.UI.rows) do
 if r:IsShown() and r.kind=="summary" then
  assert(r.text:GetText():find("33%%") and r.text:GetText():find("67%%"))
  assert(r.tip:find("Tester",1,true) and r.tip:find("Brother",1,true))
  assert(r.tip:find("Stringy Vulture Meat: 1/3",1,true)); found=true
 end
end
assert(found and NS:IsQuestCollapsed(38))
''')
        log(b,3);exchange(a,b,8)
        a.execute('''
assert(NS:IsQuestCollapsed(38))
local found=false
for _,r in ipairs(NS.UI.rows) do if r:IsShown() and r.kind=="summary" then assert(r.text:GetText():find("100%%"));found=true end end
assert(found)
NS.Settings.summaryCheck:SetChecked(false);NS.Settings.summaryCheck.scripts.OnClick(NS.Settings.summaryCheck)
for _,r in ipairs(NS.UI.rows) do assert(not r:IsShown() or r.kind~="summary") end
''')

    def test_behind_highlight_excludes_unknown_stale_non_holders_and_ties(self):
        a,b=client(),client('Brother');log(a,1);log(b,2);exchange(a,b)
        a.execute('''
NS:ToggleQuest(38)
local C=NS.Core;local players=NS:Players()
assert(C.Behind(players,38,1,GetTime())[1] and not C.Behind(players,38,1,GetTime())[2])
local highlighted=false
for _,r in ipairs(NS.UI.rows) do if r:IsShown() and r.kind=="progress" and r.name:GetText():find("Tester",1,true) then
 assert(r.name:GetText():sub(1,1)=="*" and r.tip:find("Behind",1,true)); highlighted=true end end
assert(highlighted)
players[2].lastSeen=GetTime()-46;assert(not next(C.Behind(players,38,1,GetTime())))
players[2].lastSeen=GetTime();players[2].quests[38].objectives[1].fulfilled=1
assert(not next(C.Behind(players,38,1,GetTime())))
players[2].quests={};assert(not next(C.Behind(players,38,1,GetTime())))
NS.Settings.behindCheck:SetChecked(false);NS.Settings.behindCheck.scripts.OnClick(NS.Settings.behindCheck)
''')

    def test_four_sort_orders_and_grouped_tie_breaks(self):
        a=client(party=False)
        a.execute('''
local C=NS.Core
local q={{id=3,title="Apple",level=20,state="A",zone="Westfall"},
 {id=2,title="Zebra",level=10,state="C",zone="Westfall"},
 {id=1,title="Apple",level=20,state="A",zone="Westfall"}}
assert(C.SortQuests(q,"level")[1].id==2)
assert(C.SortQuests(q,"title")[1].id==1)
assert(C.SortQuests(q,"recent",{[3]=10,[2]=5})[1].id==3)
assert(C.SortQuests(q,"ready")[1].id==2)
assert(C.Regions(q,"recent",{[3]=10})[1].quests[1].id==3)
local initial=NS.db.sortMode
for i=1,4 do NS.Settings.sortButton.scripts.OnClick(NS.Settings.sortButton) end
assert(NS.db.sortMode==initial)
''')

    def test_recent_sort_reacts_to_progress_not_unchanged_backup_reads(self):
        a=client(party=False);region_log(a);a.globals().MOCK.Tick(2)
        a.execute('''
NS.db.sortMode="recent"; NS.db.groupByZone=false
assert(not next(NS.recentProgress))
MOCK.log[2].objectives[1].numFulfilled=3;MOCK.Fire("QUEST_WATCH_UPDATE");MOCK.Tick(1)
local at=NS.recentProgress[38];assert(at)
assert(NS.Core.Visible(NS:Players(),NS.db,GetTime(),NS.recentProgress)[1].id==38)
MOCK.Tick(4);assert(NS.recentProgress[38]==at)
''')

    def test_five_member_party_is_compact_but_all_individual_bars_remain(self):
        a=client(party=False)
        a.execute('''
for i=1,4 do MOCK.party["party"..i]={name="Friend"..i,online=true} end
NS:UpdateRoster()
''')
        log(a);a.globals().MOCK.Tick(2)
        a.execute('''
for i=1,4 do NS.peers["friend"..i.."-testrealm"]={ready=true,online=true,lastSeen=GetTime(),quests=NS.Core.Copy(NS.localQuests)} end
NS:Change()
local summary,tip=NS.Features:Summary(NS,NS:Players(),NS.localQuests[38])
assert(summary:find("Party:",1,true) and tip:find("Friend4",1,true))
NS:ToggleQuest(38)
local dense=NS.UI.content:GetHeight();local bars=0
for _,r in ipairs(NS.UI.rows) do if r:IsShown() and r.kind=="progress" then bars=bars+1 end end
assert(bars==5)
NS.Settings.compactCheck:SetChecked(false);NS.Settings.compactCheck.scripts.OnClick(NS.Settings.compactCheck)
assert(NS.UI.content:GetHeight()>dense)
local chips=0;for _,c in ipairs(NS.Features.chips) do if c:IsShown() then chips=chips+1 end end;assert(chips==5)
''')


class QuestActionAndStatusTests(unittest.TestCase):
    def test_sync_indicators_and_tooltips_follow_peer_states(self):
        a,b=client(),client('Brother');log(a);log(b);exchange(a,b)
        a.execute('''
local p=NS:Players()[2]
assert(NS.Features:SyncTip(NS,p):find("Live",1,true))
assert(NS.Features:SyncTip(NS,p):find(NS.Core.VERSION,1,true))
p.lastSeen=GetTime()-46;NS:Change()
assert(NS.Features:SyncTip(NS,p):find("Stale",1,true))
p.online=false;assert(NS.Features:SyncTip(NS,p):find("Offline",1,true))
p.online=true;p.ready=false;assert(NS.Features:SyncTip(NS,p):find("Syncing",1,true))
NS.Features.chips[2].scripts.OnClick(NS.Features.chips[2]);assert(NS.pendingFull)
NS.db.minimized=true;NS:Change();assert(not NS.Features.partyStrip:IsShown())
''')

    def test_right_click_pin_hide_and_restore_are_local_display_actions(self):
        a=client(party=False);log(a);a.globals().MOCK.Tick(2)
        a.execute('''
local quest
for _,r in ipairs(NS.UI.rows) do if r:IsShown() and r.kind=="quest" then quest=r end end
quest.scripts.OnClick(quest,"RightButton")
assert(NS.Features.actions:IsShown() and NS.Features.actionID==38 and NS:IsQuestCollapsed(38))
NS.Features.pinAction.scripts.OnClick(NS.Features.pinAction)
assert(NS.db.pinned[38] and not NS:IsQuestCollapsed(38))
NS.Features:OpenActions(NS,38)
NS.Features.hideAction.scripts.OnClick(NS.Features.hideAction)
assert(NS.db.hiddenQuests[38] and #NS.Core.Visible(NS:Players(),NS.db,GetTime())==0)
assert(NS.localQuests[38] and NS.db.pinned[38])
NS:Slash("quests");NS.UI.restoreHidden.scripts.OnClick(NS.UI.restoreHidden)
assert(not NS.db.hiddenQuests[38] and #NS.Core.Visible(NS:Players(),NS.db,GetTime())==1)
NS:ToggleQuest(38);assert(not NS.db.pinned[38] and NS:IsQuestCollapsed(38))
''')

    def test_pins_settings_and_hidden_quests_survive_loading(self):
        a=client(party=False,before='QuestPartnersDB={pinned={[38]=true},hiddenQuests={[38]=true},sortMode="title",compactParty=false,noticeSound=true}')
        log(a);a.globals().MOCK.Tick(2)
        a.execute('''
assert(not NS:IsQuestCollapsed(38) and NS.db.hiddenQuests[38] and NS.db.sortMode=="title")
assert(not NS.db.compactParty and NS.db.noticeSound)
NS:ResetAppearance();assert(NS.db.pinned[38] and NS.db.hiddenQuests[38] and NS.db.noticeSound)
''')

    def test_open_quest_modern_legacy_missing_api_and_combat(self):
        a=client(party=False);log(a);a.globals().MOCK.Tick(2)
        a.execute('''
QuestMapFrame_OpenToQuestDetails=function(id) MOCK.openQuest=id end
NS.Features:OpenQuest(NS,38);assert(MOCK.openQuest==38)
MOCK.openQuest=nil;InCombatLockdown=function() return true end
NS.Features:OpenQuest(NS,38);assert(not MOCK.openQuest)
InCombatLockdown=function() return false end
QuestMapFrame_OpenToQuestDetails=nil
QuestLogPopupDetailFrame_Show=function(index) MOCK.openIndex=index end
NS.Features:OpenQuest(NS,38);assert(MOCK.openIndex==1)
QuestLogPopupDetailFrame_Show=nil;NS.Features:OpenQuest(NS,38)
assert(MOCK.chat[#MOCK.chat]:find("unavailable",1,true))
NS.Features:OpenQuest(NS,999);assert(MOCK.chat[#MOCK.chat]:find("not in your log",1,true))
''')

    def test_share_is_explicit_capability_checked_and_rechecked_at_click(self):
        a=client();log(a);a.globals().MOCK.Tick(2)
        a.execute('''
assert(not NS.Features:CanShare(NS,38))
C_QuestLog.IsPushableQuest=function(id) return id==38 end
QuestMapQuestOptions_ShareQuest=function(id) MOCK.sharedQuest=id end
assert(NS.Features:CanShare(NS,38))
NS.Features:OpenActions(NS,38);assert(NS.Features.shareAction.enabled)
InCombatLockdown=function() return true end
NS.Features.shareAction.scripts.OnClick(NS.Features.shareAction);assert(not MOCK.sharedQuest)
InCombatLockdown=function() return false end
NS.Features:ShareQuest(NS,38);assert(MOCK.sharedQuest==38)
MOCK.sharedQuest=nil;MOCK.party={};NS:UpdateRoster()
NS.Features:ShareQuest(NS,38);assert(not MOCK.sharedQuest)
''')

    def test_demo_actions_do_not_share_open_or_change_real_preferences(self):
        a=client(party=False);a.execute('''
NS:Slash("demo");NS.Features:OpenActions(NS,38)
NS.Features.pinAction.scripts.OnClick(NS.Features.pinAction)
assert(NS.demoDB.pinned[38] and not NS.db.pinned[38])
NS.Features:OpenActions(NS,38);NS.Features.hideAction.scripts.OnClick(NS.Features.hideAction)
assert(NS.demoDB.hiddenQuests[38] and not NS.db.hiddenQuests[38])
NS.Features:OpenQuest(NS,38);assert(MOCK.chat[#MOCK.chat]:find("Demo quest",1,true))
assert(not NS.Features:CanShare(NS,38))
''')


class BubbleNotificationTests(unittest.TestCase):
    def test_forever_bubble_uses_complete_player_and_surname(self):
        a=client(name='Aldren',party=False,before='MOCK.forever=true;MOCK.surname="Oakvale";MOCK.party.party1={name="Brenna",surname="Real",online=true}')
        b=client(name='Brenna',party=False,before='MOCK.forever=true;MOCK.surname="Real";MOCK.party.party1={name="Aldren",surname="Oakvale",online=true}')
        log(a,1);log(b,2);exchange(a,b)
        log(b,3);exchange(a,b,8)
        self.assertEqual(a.eval('NS.Features.notices[1].actor'),'Brenna Real')

    def test_initial_sync_of_completed_objectives_is_quiet(self):
        a,b=client(),client('Brother');log(a,3,complete=True);log(b,3,complete=True);exchange(a,b)
        for lua in (a,b): self.assertEqual(lua.eval('#NS.Features.notices'),0)

    def test_partner_objective_completion_shows_real_name_and_no_chat_message(self):
        a,b=client(),client('Brother');log(a,1);log(b,2);exchange(a,b)
        chat_count=a.eval('#MOCK.chat')
        log(b,3);exchange(a,b,8)
        a.execute('''
local n=NS.Features.notices[1]
assert(n and n.actor=="Brother" and n.title=="Westfall Stew" and n.labels[1]=="Stringy Vulture Meat")
assert(NS.Features.bubbles[1]:IsShown() and NS.Features.bubbles[1].body:GetText():find("Stringy Vulture Meat",1,true))
''')
        self.assertEqual(a.eval('#MOCK.chat'),chat_count)
        exchange(a,b,40)
        self.assertEqual(a.eval('#NS.Features.notices'),0)

    def test_fractions_do_not_notify_and_unchanged_refreshes_do_not_repeat(self):
        a=client(party=False);log(a,0);a.globals().MOCK.Tick(2)
        log(a,1);a.globals().MOCK.Tick(1);self.assertEqual(a.eval('#NS.Features.notices'),0)
        log(a,3);a.globals().MOCK.Tick(1);self.assertEqual(a.eval('#NS.Features.notices'),1)
        a.execute('MOCK.Tick(2); NS:ForceSync(); MOCK.Tick(1); assert(#NS.Features.notices==1)')

    def test_every_completed_objective_in_a_burst_is_coalesced_and_uncounted_works(self):
        a=client(party=False);region_log(a);a.globals().MOCK.Tick(2)
        a.execute('''
MOCK.log[2].objectives[2]={text="Explore camp",finished=false}
MOCK.Fire("QUEST_LOG_UPDATE");MOCK.Tick(1)
MOCK.log[2].objectives[1].numFulfilled=15
MOCK.log[2].objectives[2].finished=true
MOCK.Fire("QUEST_WATCH_UPDATE");MOCK.Tick(1)
assert(#NS.Features.notices==1 and #NS.Features.notices[1].labels==2)
assert(NS.Features.notices[1].labels[2]=="Explore camp")
''')

    def test_notifications_work_with_auto_expand_off_and_hidden_quests(self):
        a=client(party=False);log(a,1);a.globals().MOCK.Tick(2)
        a.execute('NS.db.autoExpand=false;NS.db.hiddenQuests[38]=true')
        log(a,3);a.globals().MOCK.Tick(1)
        a.execute('assert(#NS.Features.notices==1 and NS:IsQuestCollapsed(38));assert(NS.db.hiddenQuests[38])')

    def test_everyone_ready_only_fires_on_confirmed_transition(self):
        a,b=client(),client('Brother');log(a,2);log(b,2);exchange(a,b)
        log(a,3,complete=True);exchange(a,b,8)
        a.execute('for _,n in ipairs(NS.Features.notices) do assert(n.kind~="party") end')
        log(b,3,complete=True);exchange(a,b,8)
        for lua in (a,b):
            lua.execute('''
local count=0
for _,n in ipairs(NS.Features.notices) do if n.kind=="party" then count=count+1 end end
assert(count==1)
NS.Features:CheckPartyReady(NS,true)
local again=0;for _,n in ipairs(NS.Features.notices) do if n.kind=="party" then again=again+1 end end
assert(again==1)
''')

    def test_stale_peer_full_refresh_establishes_notification_baseline(self):
        a,b=client(),client('Brother');log(a,1);log(b,2);exchange(a,b)
        a.execute('NS.peers["brother-testrealm"].lastSeen=GetTime()-46')
        log(b,3,complete=True)
        b.execute('NS:Scan();NS.pendingFull=true')
        # Feed a complete snapshot directly while the receiver still considers peer stale.
        b.execute('freshPackets=NS.Core.Chunks(NS.Core.Serialize(NS.localQuests,nil,true),NS.session,NS.revision+1,0)')
        packets=b.globals().freshPackets
        for i in range(1,len(packets)+1):
            a.globals().NS.Receive(a.globals().NS,a.globals().NS.Core.PREFIX,packets[i],'PARTY','Brother-TestRealm')
        self.assertEqual(a.eval('#NS.Features.notices'),0)

    def test_switches_sound_default_preview_dismissal_and_queue_bound(self):
        a=client(party=False)
        a.execute('''
assert(NS.db.bubbles and NS.db.partyNotices and not NS.db.noticeSound)
PlaySound=function() MOCK.sounds=(MOCK.sounds or 0)+1 end
NS.Settings.testBubble.scripts.OnClick(NS.Settings.testBubble)
assert(NS.Features.bubbles[1]:IsShown() and not MOCK.sounds)
NS.Features.bubbles[1].scripts.OnClick(NS.Features.bubbles[1]);MOCK.Tick(0.25)
assert(#NS.Features.notices==0)
NS.db.noticeSound=true;NS.Settings.testBubble.scripts.OnClick(NS.Settings.testBubble)
assert(MOCK.sounds==1)
for i=1,40 do NS.Features:AddNotice(NS,"test","Tester",{id=i,title="Quest "..i},{"Objective"}) end
assert(#NS.Features.notices==24)
NS.Settings.bubbleCheck:SetChecked(false);NS.Settings.bubbleCheck.scripts.OnClick(NS.Settings.bubbleCheck)
assert(#NS.Features.notices==0 and not NS.Features.bubbles[1]:IsShown())
NS.Features:AddNotice(NS,"test","Tester",{id=1,title="Quest"},{"Objective"});assert(#NS.Features.notices==0)
''')

    def test_disabled_party_notice_does_not_suppress_objective_bubbles(self):
        a,b=client(),client('Brother');log(a,2);log(b,2);exchange(a,b)
        for lua in (a,b): lua.execute('NS.db.partyNotices=false')
        log(a,3,complete=True);log(b,3,complete=True);exchange(a,b,8)
        for lua in (a,b):
            lua.execute('assert(#NS.Features.notices>0);for _,n in ipairs(NS.Features.notices) do assert(n.kind=="objective") end')


if __name__=='__main__':
    unittest.main(verbosity=2)
