local _,NS=...
local C,H=NS.Core,NS.UI.Helpers
local F={notices={},bubbles={},chips={}}
NS.Features=F
F.SORTS={"level","title","recent","ready"}
F.SORT_LABELS={level="Quest level",title="Quest title",recent="Recent progress",ready="Ready to turn in"}
F.STATUS={live={0.22,0.78,0.46},waiting={0.96,0.72,0.20},stale={0.88,0.25,0.22},offline={0.48,0.54,0.60}}
NS.recentProgress,NS.partyReady={},{}

local function inCombat() return InCombatLockdown and InCombatLockdown() end
local function name(p) return p.name or "Player" end
local function shortName(p) return name(p):match("^%S+") or name(p) end

function F:SyncTip(app,p)
    local status=C.PeerStatus(p,GetTime())
    local age=p.localPlayer and app.lastScanSuccess or p.lastSeen
    return C.SafeText(name(p)).."\n"..({live="Live",waiting="Syncing / waiting for addon data",stale="Stale - refresh needed",offline="Offline"})[status]
        .."\nLast confirmed update: "..(age and (math.max(0,math.floor(GetTime()-age)).."s ago") or "not received")
        .."\nAddon: "..C.SafeText(p.localPlayer and C.VERSION or (p.version or "not reported"))
end

function F:Summary(app,players,q)
    local parts,tips={},{}
    local behind=C.Behind(players,q.id,nil,GetTime())
    local ready,holders,unknown=0,0,0
    local slowest
    for i,p in ipairs(players) do
        local pq=(p.quests or {})[q.id]
        local status=C.PeerStatus(p,GetTime())
        local label=C.Summary(pq,status)
        parts[#parts+1]=(app.db.highlightBehind and behind[i] and "*" or "")..C.SafeText(shortName(p))..": "..label
        local detail={self:SyncTip(app,p).."\nQuest progress: "..label}
        for oi,o in ipairs((pq or q).objectives or {}) do
            local _,_,count=C.Progress(pq,oi,status)
            detail[#detail+1]=C.SafeText(o.text)..": "..count
        end
        tips[#tips+1]=table.concat(detail,"\n")
        if pq then holders=holders+1; if status=="live" and (pq.state=="C" or pq.state=="T") then ready=ready+1 end end
        if status~="live" then unknown=unknown+1 end
        if behind[i] and not slowest then slowest=shortName(p) end
    end
    local text=table.concat(parts,"  |  ")
    if #players>=3 and app.db.compactParty then
        text="Party: "..ready.."/"..holders.." ready"
            .."  |  You: "..C.Summary((players[1].quests or {})[q.id],C.PeerStatus(players[1],GetTime()))
        if unknown>0 then text=text.."  |  "..unknown.." unconfirmed"
        elseif slowest and app.db.highlightBehind then text=text.."  |  *"..C.SafeText(slowest) end
    end
    return text,table.concat(tips,"\n\n").."\n\n* = behind another confirmed quest holder.\nPercentages average objective fractions; hover/open for counts."
end

function F:Build(app)
    self.partyStrip=CreateFrame("Frame",nil,app.UI.frame)
    for i=1,5 do
        local chip=CreateFrame("Button",nil,self.partyStrip)
        chip.dot=H.texture(chip,"ARTWORK",1,1,1,1); chip.dot:SetSize(6,6); chip.dot:SetPoint("LEFT",2,0)
        chip.label=H.font(chip,10); chip.label:SetPoint("LEFT",12,0); chip.label:SetHeight(16)
        self.chips[i]=chip
    end
    self.bubbleAnchor=CreateFrame("Frame",nil,UIParent)
    self.bubbleAnchor:SetSize(330,1); self.bubbleAnchor:SetPoint("TOP",UIParent,"TOP",0,-120)
    for i=1,3 do
        local bubble=CreateFrame("Button",nil,self.bubbleAnchor,"BackdropTemplate")
        bubble:SetFrameStrata("HIGH"); bubble:SetClampedToScreen(true); bubble:SetWidth(330)
        bubble:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=14,insets={left=4,right=4,top=4,bottom=4}})
        bubble:SetBackdropColor(0.025,0.035,0.045,0.96); bubble:SetBackdropBorderColor(0.94,0.81,0.53,0.9)
        bubble.tail=H.texture(bubble,"BACKGROUND",0.025,0.035,0.045,0.96)
        bubble.tail:SetSize(11,11); bubble.tail:SetPoint("BOTTOMLEFT",24,-3)
        if bubble.tail.SetRotation then bubble.tail:SetRotation(math.pi/4) end
        bubble.title=H.font(bubble,12,{0.94,0.81,0.53}); bubble.title:SetPoint("TOPLEFT",12,-10); bubble.title:SetSize(306,18)
        bubble.body=H.font(bubble,12); bubble.body:SetPoint("TOPLEFT",12,-32); bubble.body:SetWidth(306)
        if bubble.body.SetWordWrap then bubble.body:SetWordWrap(true) end
        bubble:SetScript("OnClick",function(b) if b.notice then b.notice.dismissed=true end end)
        bubble:Hide(); self.bubbles[i]=bubble
    end
end

function F:RefreshStatus(app,players)
    if not self.partyStrip then return end
    self.partyStrip:ClearAllPoints(); self.partyStrip:SetPoint("TOPLEFT",app.UI.frame,"TOPLEFT",7,-app.UI.header:GetHeight())
    self.partyStrip:SetSize(app.db.width-16,20)
    self.partyStrip:SetShown(app.db.shown and not app.db.minimized)
    local width=(app.db.width-16)/#players
    for i,chip in ipairs(self.chips) do
        local p=players[i]
        chip:SetShown(p~=nil)
        if p then
            chip:ClearAllPoints(); chip:SetPoint("TOPLEFT",(i-1)*width,0); chip:SetSize(width,20)
            local status=C.PeerStatus(p,GetTime())
            chip.dot:SetVertexColor(unpack(self.STATUS[status]))
            chip.label:SetWidth(width-16); chip.label:SetText(C.SafeText(shortName(p)))
            H.tooltip(chip,self:SyncTip(app,p))
            chip:SetScript("OnClick",function() app:ForceSync() end)
        end
    end
end

function F:AddNotice(app,kind,actor,q,labels)
    if not app.db.bubbles or (kind=="party" and not app.db.partyNotices) then return end
    -- Coalesce objectives completed together by the same player/quest.
    for _,n in ipairs(self.notices) do
        if not n.dismissed and n.kind==kind and n.actor==actor and n.id==q.id and GetTime()-n.at<1 then
            for _,label in ipairs(labels or {}) do if #n.labels<20 then n.labels[#n.labels+1]=label end end
            return
        end
    end
    if #self.notices>=24 then table.remove(self.notices,1) end
    self.notices[#self.notices+1]={kind=kind,actor=actor,id=q.id,title=q.title,labels=labels or {},at=GetTime()}
    if app.db.noticeSound and PlaySound and GetTime()>=(self.nextSound or 0) then
        pcall(PlaySound,(SOUNDKIT and SOUNDKIT.IG_QUEST_LOG_UPDATE) or 838,"SFX")
        self.nextSound=GetTime()+1
    end
end

function F:Observe(app,previous,current,actor,allowNotifications)
    for id,q in pairs(current or {}) do
        local old=(previous or {})[id]
        if C.ProgressChanged(old,q) then
            app.recentProgress[id]=GetTime()
            if app.db.autoExpand then app.autoExpanded[id]=GetTime()+15 end
        end
        if allowNotifications and old and old.state~="T" and q.state~="T" and q.state~="F" then
            local completed={}
            for i,o in ipairs(q.objectives or {}) do
                local before=(old.objectives or {})[i]
                if before and not C.ObjectiveDone(before) and C.ObjectiveDone(o) then completed[#completed+1]=o.text or ("Objective "..i) end
            end
            if #completed==0 and #(q.objectives or {})==0 and old.state~="C" and q.state=="C" then completed[1]="Ready to turn in" end
            if #completed>0 then self:AddNotice(app,"objective",actor or "You",q,completed) end
        end
    end
end

function F:CheckPartyReady(app,allowNotifications)
    local players=app:Players()
    local catalogue=C.Catalogue(players)
    for _,cache in ipairs({app.partyReady,app.recentProgress,app.autoExpanded}) do
        for id in pairs(cache) do if not catalogue[id] then cache[id]=nil end end
    end
    for id,q in pairs(catalogue) do
        local ready,holders=C.AllReady(players,id,GetTime())
        if ready~=nil then
            if ready and holders>=2 and app.partyReady[id]==false and allowNotifications then
                self:AddNotice(app,"party","Party",q,{"All quest holders are ready to turn in."})
            end
            app.partyReady[id]=ready
        end
    end
end

function F:Tick(app)
    if not self.bubbleAnchor then return end
    if #self.notices==0 and (self.activeCount or 0)==0 then return end
    if not app.db.bubbles then self.notices={} end
    local now=GetTime()
    for i=#self.notices,1,-1 do
        local n=self.notices[i]
        if n.dismissed or (n.kind=="party" and not app.db.partyNotices) or (n.expires and now>=n.expires) or now-n.at>60 then table.remove(self.notices,i) end
    end
    local key={}
    for i=1,math.min(3,#self.notices) do key[i]=tostring(self.notices[i])..":"..#self.notices[i].labels end
    local paintKey=table.concat(key,"|")
    if paintKey==self.paintKey and not self.styleDirty then return end
    self.paintKey,self.styleDirty,self.activeCount=paintKey,false,math.min(3,#self.notices)
    local y=0
    for i,b in ipairs(self.bubbles) do
        local n=self.notices[i]
        b:SetShown(n~=nil); b.notice=n
        if n then
            n.expires=n.expires or now+7
            b:ClearAllPoints(); b:SetPoint("TOPLEFT",0,-y)
            b.title:SetText(C.SafeText(n.kind=="party" and "Everyone is ready!" or (n.actor.." completed an objective")))
            local palette=app.db.colors
            b:SetBackdropColor(palette.background[1],palette.background[2],palette.background[3],0.96)
            b:SetBackdropBorderColor(palette.heading[1],palette.heading[2],palette.heading[3],0.9)
            b.title:SetTextColor(unpack(palette.heading)); b.body:SetTextColor(unpack(palette.text))
            local lines={C.SafeText(n.title)}
            for j=1,math.min(3,#n.labels) do lines[#lines+1]=C.SafeText(n.labels[j]) end
            if #n.labels>3 then lines[#lines+1]="+"..(#n.labels-3).." more objectives" end
            b.body:SetText(table.concat(lines,"\n"))
            local height=math.min(130,math.max(34,b.body.GetStringHeight and b.body:GetStringHeight() or (#lines*16)))
            b.body:SetHeight(height); b:SetHeight(height+46); y=y+b:GetHeight()+12
            H.tooltip(b,C.SafeText(n.actor).."\n"..C.SafeText(n.title).."\n"..C.SafeText(table.concat(n.labels,"\n"),true).."\nClick to dismiss")
        end
    end
end

function F:QuestIndex(id)
    if C_QuestLog.GetLogIndexForQuestID then return C_QuestLog.GetLogIndexForQuestID(id) end
    for i=1,C_QuestLog.GetNumQuestLogEntries() do
        local info=C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.questID==id then return i end
    end
end

function F:OpenQuest(app,id)
    if app.demo then app:Print("Demo quest - no game quest opened."); return end
    if inCombat() then app:Print("Open quest details after combat."); return end
    local q=app.localQuests[id]
    if not q or q.state=="T" then app:Print("This quest is not in your log."); return end
    local ok
    if QuestMapFrame_OpenToQuestDetails then ok=pcall(QuestMapFrame_OpenToQuestDetails,id)
    elseif QuestLogPopupDetailFrame_Show then
        local index=self:QuestIndex(id)
        if index then ok=pcall(QuestLogPopupDetailFrame_Show,index) end
    end
    if not ok then app:Print("Quest details unavailable on this client. Open your quest log normally.") end
end

function F:CanShare(app,id)
    if app.demo then return false,"Demo quest" end
    if inCombat() then return false,"Available after combat" end
    if not app:Channel() then return false,"Join a party first" end
    local q=app.localQuests[id]
    if not q or q.state=="T" then return false,"Not in your quest log" end
    if not C_QuestLog.IsPushableQuest or not QuestMapQuestOptions_ShareQuest then return false,"Use Share in the game's quest log" end
    local ok,pushable=pcall(C_QuestLog.IsPushableQuest,id)
    return ok and pushable and true or false,ok and "The game does not allow sharing this quest" or "Sharing unavailable"
end

function F:ShareQuest(app,id)
    local enabled,reason=self:CanShare(app,id)
    if not enabled then app:Print(reason); return end
    local ok=pcall(QuestMapQuestOptions_ShareQuest,id)
    if not ok then app:Print("The game could not share this quest. Try its normal quest log.") end
end

function F:OpenActions(app,id,anchor)
    local cfg=app:ViewConfig()
    local q=C.Catalogue(app:ViewPlayers())[id]
    if not q then return end
    if not self.actions then
        local p=app.UI:Popup("Quest actions",270,214); self.actions=p
        self.actionTitle=H.font(p,12); self.actionTitle:SetPoint("TOPLEFT",12,-39); self.actionTitle:SetSize(246,24)
        self.openAction=H.button(p,"Open quest log",240,function() self:OpenQuest(app,self.actionID); p:Hide() end)
        self.openAction:SetPoint("TOPLEFT",12,-70)
        self.pinAction=H.button(p,"Working on",240,function()
            p:Hide();app:ToggleWorkingQuest(self.actionID)
        end); self.pinAction:SetPoint("TOPLEFT",12,-101)
        self.hideAction=H.button(p,"Hide from this tracker",240,function()
            app:ViewConfig().hiddenQuests[self.actionID]=true; p:Hide(); app:Change()
        end); self.hideAction:SetPoint("TOPLEFT",12,-132)
        self.shareAction=H.button(p,"Share quest",240,function() self:ShareQuest(app,self.actionID); p:Hide() end)
        self.shareAction:SetPoint("TOPLEFT",12,-163)
    end
    self.actionID,self.actionConfig=id,cfg; self.actionTitle:SetText(C.SafeText(q.title))
    self.actions:ClearAllPoints(); self.actions:SetPoint("TOPLEFT",anchor or app.UI.frame,"TOPRIGHT",4,0)
    self.pinAction.label:SetText(cfg.pinned[id] and "Remove from Working on" or "Add to Working on")
    local allowed,reason=self:CanShare(app,id)
    self.shareAction:SetEnabled(allowed); self.shareAction:SetAlpha(allowed and 1 or 0.45)
    H.tooltip(self.shareAction,allowed and "Offer this quest through the game's normal party-sharing action" or reason)
    self.actions:Show()
end
