"""Level colouring and the search -> Working on gameplay workflow."""
import unittest
from test_addon import client,log,region_log,exchange


class DifficultyTests(unittest.TestCase):
    def test_five_standard_colours_and_boundary_levels(self):
        a=client(party=False)
        a.execute('''
local C=NS.Core
for _,pair in ipairs({{22,"red"},{20,"orange"},{19,"yellow"},{15,"yellow"},{14,"green"},{12,"green"},{11,"grey"}}) do
 local color,known=C.DifficultyColor(pair[1]);assert(known and color==C.DIFFICULTY_COLORS[pair[2]])
end
local color,known=C.DifficultyColor(0);assert(not known and color==C.DIFFICULTY_COLORS.grey)
''')

    def test_native_colour_wins_and_native_globals_are_not_modified(self):
        a=client(party=False,before='GetQuestDifficultyColor=function(level) return {r=0.12,g=0.34,b=0.56} end; nativeDifficulty=GetQuestDifficultyColor')
        a.execute('''
local color,known=NS.Core.DifficultyColor(13)
assert(known and color[1]==0.12 and color[3]==0.56 and GetQuestDifficultyColor==nativeDifficulty)
''')

    def test_legacy_native_and_failure_fallbacks_are_guarded(self):
        a=client(party=False)
        a.execute('''
GetQuestDifficultyColor=function() error("Unavailable") end
GetDifficultyColor=function() return {r=0.2,g=0.4,b=0.6} end
assert(NS.Core.DifficultyColor(13)[3]==0.6)
GetDifficultyColor=function() return {r=0/0,g=9,b="invalid"} end
assert(NS.Core.DifficultyColor(22)==NS.Core.DIFFICULTY_COLORS.red)
GetQuestGreenRange=function(unit) if unit then error("Legacy no arguments") end;return 5 end
assert(NS.Core.DifficultyColor(12)==NS.Core.DIFFICULTY_COLORS.green)
GetQuestGreenRange=nil;local _,known=NS.Core.DifficultyColor(12);assert(not known)
UnitLevel=nil;local _,known=NS.Core.DifficultyColor(13);assert(not known)
''')

    def test_badge_number_and_off_preserve_title_colour_and_bar_palette(self):
        a=client(party=False);log(a);a.globals().MOCK.Tick(2)
        a.execute('''
local r
for _,line in ipairs(NS.UI.rows) do if line:IsShown() and line.kind=="quest" then r=line end end
assert(r and r.levelFrame:IsShown() and r.levelText:GetText()=="13")
assert(r.levelText.textColor[1]==0.25 and r.text:GetText()=="Westfall Stew")
assert(r.text.textColor[1]==NS.db.colors.heading[1])
NS.Settings.difficultyButton.scripts.OnClick(NS.Settings.difficultyButton)
assert(NS.db.difficultyStyle=="level" and r.levelText:GetText()=="[13]" and r.levelFrame.color[4]==0)
NS.Settings.difficultyButton.scripts.OnClick(NS.Settings.difficultyButton)
assert(NS.db.difficultyStyle=="off" and not r.levelFrame:IsShown() and r.text:GetText():find("[13]",1,true))
NS.Settings.difficultyButton.scripts.OnClick(NS.Settings.difficultyButton)
assert(NS.db.difficultyStyle=="badge")
assert(NS.db.colors.red[1]==NS.Core.DEFAULT_COLORS.red[1])
''')

    def test_level_up_recolours_and_unknown_levels_stay_neutral(self):
        a=client(party=False);log(a);a.globals().MOCK.Tick(2)
        a.execute('''
MOCK.level=13;MOCK.Fire("PLAYER_LEVEL_UP",13);MOCK.Tick(0.25)
local r;for _,line in ipairs(NS.UI.rows) do if line:IsShown() and line.kind=="quest" then r=line end end
assert(r.levelText.textColor[1]==1 and r.levelText.textColor[2]==1)
MOCK.level=22;MOCK.Fire("PLAYER_LEVEL_UP",22);MOCK.Tick(0.25)
assert(r.levelText.textColor[1]==0.5)
MOCK.log[1].level=0;MOCK.Fire("QUEST_LOG_UPDATE");MOCK.Tick(1)
for _,line in ipairs(NS.UI.rows) do if line:IsShown() and line.kind=="quest" then
 assert(line.levelText:GetText()=="?" and line.tip:find("unavailable",1,true)) end end
''')

    def test_badges_fit_font_range_and_recycled_rows_hide_decorations(self):
        a=client(party=False);region_log(a);a.globals().MOCK.Tick(2)
        a.execute('''
NS.db.width=280
for _,size in ipairs({10,20}) do
 NS.Settings.sliders.fontSize.slider:SetValue(size)
 for _,r in ipairs(NS.UI.rows) do if r:IsShown() and r.kind=="quest" then
  assert(r.text:GetWidth()>100 and r.levelFrame:GetHeight()<=r:GetHeight())
 elseif r:IsShown() and r.levelFrame then assert(not r.levelFrame:IsShown() and not r.star:IsShown()) end end
end
NS:ToggleQuest(38)
for _,r in ipairs(NS.UI.rows) do if r:IsShown() and r.kind~="quest" and r.levelFrame then assert(not r.levelFrame:IsShown()) end end
''')


class SearchAndWorkingOnTests(unittest.TestCase):
    def test_search_matches_title_or_any_players_objective_as_plain_text(self):
        a=client(party=False);region_log(a);a.globals().MOCK.Tick(2)
        a.execute('''
local C=NS.Core;local players=NS:Players()
assert(C.MatchesSearch(NS.localQuests[38],players,"WESTFALL"))
assert(C.MatchesSearch(NS.localQuests[38],players,"supplies"))
assert(not C.MatchesSearch(NS.localQuests[38],players,"checkpoint"))
assert(not C.MatchesSearch(NS.localQuests[38],players,".*"))
players[2]={quests={[38]={objectives={{text="Creature 100%"}}}}}
assert(C.MatchesSearch(NS.localQuests[38],players,"100%"))
''')

    def test_typing_search_filters_and_clear_restores_without_stopping_sync(self):
        a,b=client(),client('Brother');region_log(a);region_log(b);exchange(a,b)
        a.execute('''
NS.UI.searchBox:SetText("checkpoints");MOCK.Tick(0.25)
local ids={}
for _,r in ipairs(NS.UI.rows) do if r:IsShown() and r.kind=="quest" then ids[r.questID]=true end end
assert(ids[900001] and not ids[38] and NS.Core.Count(NS.localQuests)==2)
''')
        region_log(b,7);exchange(a,b,8)
        a.execute('''
assert(NS:Players()[2].quests[38].objectives[1].fulfilled==7)
NS.UI.searchClear.scripts.OnClick(NS.UI.searchClear)
assert(NS.searchText=="")
local count=0;for _,r in ipairs(NS.UI.rows) do if r:IsShown() and r.kind=="quest" then count=count+1 end end
assert(count==2)
NS.UI.searchBox:SetText(string.rep("x",200));MOCK.Tick(0.25);assert(#NS.searchText==128 and NS.UI.empty:IsShown())
NS.UI.searchBox.scripts.OnEscapePressed(NS.UI.searchBox);assert(NS.searchText=="")
''')

    def test_one_click_star_adds_to_top_clears_search_and_opens_objectives(self):
        a=client(party=False);region_log(a);a.globals().MOCK.Tick(2)
        a.execute('''
NS.UI.searchBox:SetText("supplies");MOCK.Tick(0.25)
local r;for _,line in ipairs(NS.UI.rows) do if line:IsShown() and line.kind=="quest" then r=line end end
assert(r.questID==38);r.star.scripts.OnClick(r.star)
assert(NS.db.pinned[38] and not NS:IsQuestCollapsed(38) and NS.searchText=="")
assert(NS.UI.rows[1].kind=="section" and NS.UI.rows[1].text:GetText()=="Working on (1)")
local order={};for _,line in ipairs(NS.UI.rows) do if line:IsShown() and line.kind=="quest" then order[#order+1]=line.questID end end
assert(order[1]==38 and NS:IsQuestCollapsed(900001))
NS:ToggleWorkingQuest(38);assert(not NS.db.pinned[38] and NS:IsQuestCollapsed(38))
''')

    def test_working_on_persists_uses_local_filters_and_finished_cleanup(self):
        a=client(party=False,before='QuestPartnersDB={pinned={[38]=true},difficultyStyle="level"}')
        region_log(a);a.globals().MOCK.Tick(2)
        a.execute('''
assert(NS.db.difficultyStyle=="level" and not NS:IsQuestCollapsed(38))
assert(NS.UI.rows[1].kind=="section")
NS.db.hiddenZones.westfall=true;NS:Change()
for _,r in ipairs(NS.UI.rows) do assert(not r:IsShown() or r.kind~="quest" or r.questID~=38) end
NS.db.hiddenZones.westfall=nil;NS:Change()
NS:MarkTurnedIn(38);MOCK.log={MOCK.log[3],MOCK.log[4]};NS:Scan();NS:Change()
for _,r in ipairs(NS.UI.rows) do assert(not r:IsShown() or r.kind~="quest" or r.questID~=38) end
''')

    def test_collapse_others_keeps_shortlist_and_demo_preferences_are_separate(self):
        a=client(party=False);region_log(a);a.globals().MOCK.Tick(2)
        a.execute('''
NS:ToggleWorkingQuest(38);NS:ToggleQuest(900001)
NS.UI:SetQuestFolds(NS,true)
assert(NS.db.pinned[38] and not NS:IsQuestCollapsed(38) and NS:IsQuestCollapsed(900001))
NS:Slash("demo");NS:ToggleWorkingQuest(102)
assert(NS.demoDB.pinned[102] and not NS.db.pinned[102])
NS:Slash("demo");assert(NS.db.pinned[38])
''')

    def test_working_on_and_search_keep_virtual_scroll_pool_bounded(self):
        a=client(party=False)
        a.execute('''
for id=1,100 do
 MOCK.log[id]={questID=id,title=string.format("Quest %03d",id),level=10,objectives={{text="Task "..id,numFulfilled=0,numRequired=3}}}
end
NS:Scan();NS:Change()
NS.UI.scroll:SetVerticalScroll(NS.UI.content:GetHeight()-NS.UI.scroll:GetHeight());NS:Render()
NS:ToggleWorkingQuest(99)
assert(NS.UI.scroll:GetVerticalScroll()==0 and NS.UI.rows[1].kind=="section" and #NS.UI.rows<80)
NS.UI.searchBox:SetText("Task 100");MOCK.Tick(0.25)
assert(#NS.UI.rows<80)
local found=false;for _,r in ipairs(NS.UI.rows) do if r:IsShown() and r.kind=="quest" then assert(r.questID==100);found=true end end
assert(found and NS.db.pinned[99])
''')


if __name__=='__main__':
    unittest.main(verbosity=2)
