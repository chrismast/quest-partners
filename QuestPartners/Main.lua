local addonName, NS = ...
local C = NS.Core
local eventFrame = CreateFrame("Frame")
NS.peers, NS.roster, NS.localQuests = {}, {}, {}
NS.queue, NS.revision, NS.sent, NS.received = nil, 0, 0, 0
NS.session = tostring(GetServerTime()) .. "-" .. tostring(math.random(100000,999999))
NS.pendingFull, NS.dirty = true, true
NS.rx={raw=0,matched=0,selfEcho=0,unknownSender=0,rejected=0,requests=0,heartbeats=0,fragments=0,rateLimited=0}
NS.scanCount,NS.unsupportedEvents=0,{}
NS.autoExpanded,NS.recentTurnIns={},{}

local defaults = {width=340,maxHeight=360,opacity=0.65,barOpacity=0.92,fontSize=12,barHeight=14,questSpacing=14,
    colors=C.DEFAULT_COLORS,locked=false,hideFinished=true,mode="auto",selected={},collapsed={},shown=true,minimized=false,
    groupByZone=true,hiddenZones={},collapsedZones={},scope="shared",autoExpand=true,
    summaries=true,highlightBehind=true,compactParty=true,sortMode="level",hiddenQuests={},pinned={},
    bubbles=true,partyNotices=true,noticeSound=false,difficultyStyle="badge"}
local function clock() return GetTime() end
local function canonical(name) return C.NormalizeName(name) end
local function fullName(unit)
    local name, realm = UnitFullName(unit)
    if not name then return nil end
    if NS.regionalNames then
        -- Forever's second return is a surname. Never qualify it as a realm.
        local complete=GetUnitName and GetUnitName(unit,false)
        if not complete or complete=="" or (complete==name and realm and realm~="") then
            complete=name..(realm and realm~="" and ((CHARACTERNAME_SURNAME_SEPARATOR or " ")..realm) or "")
        end
        return complete,complete,name
    end
    if not realm or realm == "" then
        realm = GetNormalizedRealmName and GetNormalizedRealmName() or GetRealmName():gsub("%s", "")
    end
    return name .. "-" .. realm:gsub("%s",""), name, name
end
function NS:Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cffdfc37aQuest Partners:|r " .. C.SafeText(message))
end

function NS:RegisterCommands()
    SLASH_QUESTPARTNERS1="/questpartners"
    local conflict=false
    for key,value in pairs(_G) do
        if type(key)=="string" and key:match("^SLASH_.+%d+$") and not key:match("^SLASH_QUESTPARTNERS%d+$")
            and type(value)=="string" and value:lower()=="/qp" then conflict=true;break end
    end
    SLASH_QUESTPARTNERS2=not conflict and "/qp" or nil
    if conflict and not self.aliasConflict then self:Print("The /qp shortcut is in use; use /questpartners instead.") end
    self.aliasConflict=conflict
    SlashCmdList.QUESTPARTNERS=function(msg) self:Slash(msg) end
end
function NS:Channel()
    if IsInRaid() or not IsInGroup() then return nil end
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    return "PARTY"
end

function NS:UpdateRoster()
    local roster = {}
    if not IsInRaid() then
        for i=1,4 do
            local unit = "party" .. i
            if UnitExists(unit) then
                local full, short, first = fullName(unit)
                if full then
                    local key = canonical(full)
                    roster[key] = {key=key,name=short,firstName=first,fullName=full,unit=unit,online=UnitIsConnected(unit) and true or false}
                    local p = self.peers[key]
                    -- A reconnection must prove freshness again.
                    if p and not p.online and roster[key].online then p.ready=false end
                    if p then p.online=roster[key].online; p.unit=unit end
                end
            end
        end
    end
    local changed = false
    for k in pairs(self.roster) do if not roster[k] then self.peers[k]=nil; changed=true end end
    for k in pairs(roster) do if not self.roster[k] then changed=true end end
    self.roster = roster
    if changed then
        self.partyReady={}
        self.queue, self.lastQueued = nil, nil
        self.pendingFull = true
        self.nextRequest = 0
    end
    if not self:Channel() then self.queue, self.lastQueued = nil, nil end
end

function NS:Players()
    local _, short = fullName("player")
    local players = {{name=short or "You",localPlayer=true,online=true,ready=true,quests=self.localQuests,readError=self.readError}}
    for _, key in ipairs(C.Keys(self.roster)) do
        local member = self.roster[key]
        local p = self.peers[key] or {quests={},ready=false}
        p.name, p.online, p.unit = member.name, member.online, member.unit
        players[#players+1] = p
    end
    return players
end

local function number(value)
    if C.Finite(value) and value>=0 then return math.floor(value) end
end
function NS:ScheduleScan(delay,reason)
    local due=math.max(clock()+(delay or 0.20),(self.lastScanAttempt or -1000)+C.MIN_SCAN_INTERVAL)
    -- Keep the earliest deadline: another progress event must not postpone it.
    if not self.scanAt or due<self.scanAt then
        self.scanAt,self.scanReason=due,reason or "quest event"
    end
end
function NS:Scan()
    local api = C_QuestLog
    if not api or not api.GetNumQuestLogEntries or not api.GetInfo or not api.GetQuestObjectives then
        self.readError = "Required quest APIs unavailable on this client"
        return false
    end
    local count = api.GetNumQuestLogEntries()
    if not count then return false end
    if not C.Finite(count) or count<0 or count>300 or count~=math.floor(count) then self.readError="Quest log entry count outside supported limits";return false end
    local quests,currentHeader,seen = {},"",{}
    for i=1,count do
        local info = api.GetInfo(i)
        if not info then self:ScheduleScan(1,"quest data retry"); return false end
        if info.isHeader then currentHeader=info.title or "" end
        if not info.isHeader and not info.isHidden and not info.isTask and info.questID and info.questID>0 then
            local id = info.questID
            if not info.title or info.title=="" then self:ScheduleScan(1,"quest title retry"); return false end
            local zone=currentHeader
            if zone=="" and api.GetHeaderIndexForQuest then
                local ok,headerIndex=pcall(api.GetHeaderIndexForQuest,id)
                if ok and type(headerIndex)=="number" and headerIndex>0 then
                    local header=api.GetInfo(headerIndex)
                    if header and header.isHeader and header.title then zone=header.title end
                end
            end
            local q = {id=id,title=info.title,level=info.level or 0,state="A",zone=zone,objectives={}}
            if api.IsComplete and api.IsComplete(id) then q.state="C" end
            if api.IsFailed and api.IsFailed(id) then q.state="F" end
            for j, obj in ipairs(api.GetQuestObjectives(id) or {}) do
                if j>20 then self.readError="Quest has more than 20 objectives"; return false end
                local have, need = number(obj.numFulfilled), number(obj.numRequired)
                if not need or need<=0 then have,need=nil,nil end
                q.objectives[j] = {text=C.ObjectiveLabel(obj.text or ("Objective "..j)),type=obj.type or "",
                    fulfilled=have,required=need,finished=obj.finished and true or false}
            end
            quests[id]=q
            seen[id]=true
        end
    end
    -- Keep authoritative turn-in events through a temporarily lingering API row.
    -- A later acceptance event, or absence followed by reappearance, starts a new run.
    local recent = {}
    for id,q in pairs(self.localQuests) do
        if q.state=="T" and not self.recentTurnIns[id] then
            self.recentTurnIns[id]={quest=C.Copy(q),at=q.turnedAt or clock(),absent=not seen[id]}
        end
    end
    for id,record in pairs(self.recentTurnIns) do
        if (seen[id] and record.absent) or clock()-record.at>=1800 then
            self.recentTurnIns[id]=nil
        else
            if not seen[id] then record.absent=true end
            quests[id]=nil
            recent[#recent+1]=record.quest
        end
    end
    table.sort(recent,function(a,b) return (a.turnedAt or 0)>(b.turnedAt or 0) end)
    local slots=math.max(0,C.MAX_QUESTS-C.Count(quests))
    for i=1,math.min(30,#recent,slots) do quests[recent[i].id]=recent[i] end
    for i=31,#recent do self.recentTurnIns[recent[i].id]=nil end
    if C.Count(quests)>C.MAX_QUESTS then self.readError="Quest log exceeds 100-quest test limit"; return false end
    local changed=false
    for id,q in pairs(quests) do
        if C.QuestEqual(q,self.localQuests[id]) then quests[id]=self.localQuests[id] else changed=true end
    end
    for id in pairs(self.localQuests) do if not quests[id] then changed=true end end
    local notify=not self.readError
    if changed then self:ObserveProgress(self.localQuests,quests,self:Players()[1].name,notify);self.localQuests=quests end
    self.readError=nil;self.dirty=self.dirty or changed
    if changed then self.Features:CheckPartyReady(self,notify) end
    return true,changed
end

function NS:MarkTurnedIn(id)
    local old=self.localQuests[id] or (self.lastQueued or {})[id]
    if not old then return end
    local q=C.Copy(old); q.state,q.turnedAt="T",clock()
    self.recentTurnIns[id]={quest=q,at=clock(),absent=false}
    self.localQuests[id]=q; self.dirty=true
    self.autoExpanded[id]=nil
end

function NS:ObserveProgress(previous,current,actor,allowNotifications)
    self.Features:Observe(self,previous,current,actor,allowNotifications)
end

function NS:IsQuestCollapsed(id)
    local cfg=self:ViewConfig()
    if (cfg.pinned or {})[id] then return false end
    return cfg.collapsed[id]~=false and not (not self.demo and self.db.autoExpand and (self.autoExpanded[id] or 0)>clock())
end

function NS:ToggleQuest(id)
    local collapsed=self:IsQuestCollapsed(id)
    local cfg=self:ViewConfig()
    cfg.collapsed[id]=not collapsed
    if not collapsed then cfg.pinned[id]=nil end
    if collapsed then
        local quest=C.Catalogue(self:ViewPlayers())[id]
        if quest then cfg.collapsedZones[C.ZoneKey(quest)]=false end
    end
    if not self.demo then self.autoExpanded[id]=nil end
    self:Change()
end

function NS:ToggleWorkingQuest(id)
    local cfg=self:ViewConfig()
    if cfg.pinned[id] then cfg.pinned[id]=nil;cfg.collapsed[id]=true
    else
        cfg.pinned[id]=true;cfg.collapsed[id]=false
        local q=C.Catalogue(self:ViewPlayers())[id]
        if q then cfg.collapsedZones[C.ZoneKey(q)]=false end
        self.searchText=""
    end
    self.UI.scroll:SetVerticalScroll(0)
    if self.UI.searchBox then self.UI.searchBox:ClearFocus() end
    self:Change()
end

function NS:SetScope(scope)
    local cfg=self:ViewConfig()
    cfg.scope,cfg.mode=scope=="all" and "all" or "shared","auto"
    self:Change()
end

function NS:Render()
    self.renderAt=nil
    if self.db and self.UI then
        self.UI:Render(self)
        if self.UI.RefreshManager then self.UI:RefreshManager(self) end
        if self.Features then self.Features:RefreshStatus(self,self:ViewPlayers()) end
    end
end

function NS:RequestRender()
    self.renderAt=self.renderAt or (clock()+0.10)
end

function NS:CanSendZones()
    local any=false
    for key,member in pairs(self.roster) do
        if member.online then
            any=true
            local peer=self.peers[key]
            if not peer or not C.SupportsZones(peer.version) then return false end
        end
    end
    return any
end
function NS:Change()
    if self.Features and self.Features.actions and self.Features.actionConfig~=self:ViewConfig() then self.Features.actions:Hide() end
    self:Render()
    if self.Settings then self.Settings:Refresh(self) end
    self.Features.styleDirty=true;self.Features:Tick(self)
end

function NS:ResetAppearance()
    for _,key in ipairs({"opacity","barOpacity","fontSize","barHeight","questSpacing","colors","difficultyStyle"}) do
        self.db[key]=C.Copy(defaults[key])
    end
    self:Change()
end
function NS:ForceSync()
    self.pendingFull, self.nextRequest = true, 0
    self:ScheduleScan(0,"manual recovery")
    self:Render()
end

local function resultSuccess(result)
    return result == true or result == 0
end
local sendResults={[0]="Success",[1]="InvalidPrefix",[2]="InvalidMessage",[3]="AddonMessageThrottle",
    [4]="InvalidChatType",[5]="NotInGroup",[6]="TargetRequired",[7]="InvalidChannel",[8]="ChannelThrottle",
    [9]="GeneralError",[10]="NotInGuild",[11]="AddOnMessageLockdown",[12]="TargetOffline"}
function NS:Send(message)
    local channel = self:Channel()
    if not channel then return false end
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, C.PREFIX, message, channel)
    self.lastSendResult=ok and (sendResults[result] or tostring(result)) or ("Lua error: "..tostring(result))
    if ok and resultSuccess(result) then
        self.sent = self.sent+1
        self.sendError = nil
        return true
    end
    self.sendError = "Sync blocked (" .. tostring(result) .. ": "..self.lastSendResult..")"
    self.retryAt = clock() + ((result==3 or result==8) and 1 or 5)
    return false
end

function NS:Pump(now)
    if not self:Channel() or now < (self.retryAt or 0) or not self.prefixOK then return end
    if not self.queue then
        if now>=(self.nextHello or 0) then
            self:Send("V|1|"..C.VERSION)
            self.nextHello=now+60
            return
        end
        if now >= (self.nextRequest or 0) then
            local needed = false
            for _, p in ipairs(self:Players()) do
                if not p.localPlayer and p.online and (not p.ready or p.needsFull or C.PeerStatus(p,now)=="stale") then needed=true end
            end
            self.nextRequest = now + 15
            if needed then self:Send("R|1"); return end
        end
        local zones=self:CanSendZones()
        if self.pendingFull or self.dirty or now >= (self.nextFull or 0) or self.lastZoneFormat~=zones then
            local full = self.pendingFull or not self.lastQueued or now >= (self.nextFull or 0) or self.lastZoneFormat~=zones
            local payload = C.Serialize(self.localQuests, self.lastQueued, full,zones)
            self.pendingFull, self.dirty = false, false
            if payload then
                local base = full and 0 or self.revision
                self.revision = self.revision+1
                local packets, err = C.Chunks(payload,self.session,self.revision,base)
                if not packets then self.sendError=err; self.retryAt=now+10; self.pendingFull=true; return end
                self.queue = {packets=packets,index=1,full=full}
                self.lastQueued = C.ShallowCopy(self.localQuests)
                self.lastZoneFormat=zones
                if full then self.nextFull=now+90 end
            end
        end
        if not self.queue and now >= (self.nextHeartbeat or 0) then
            self:Send("H|1|"..self.session.."|"..self.revision)
            self.nextHeartbeat=now+12
            return
        end
    end
    if self.queue then
        local q = self.queue
        if self:Send(q.packets[q.index]) then
            q.index=q.index+1
            if q.index>#q.packets then self.queue=nil end
        end
    end
end

function NS:ResolveSender(sender)
    if type(sender)~="string" then return nil,"Invalid sender" end
    local key = canonical(sender)
    if self.roster[key] then return key end
    local found
    -- Accept an optional realm suffix on a complete regional name, but never
    -- shorten a supplied surname or guess between duplicate first names.
    local unqualified=self.regionalNames and sender:match("^(.*)%-[^%-]+$")
    local bare=not sender:find("-",1,true) and not sender:find("%s")
    for k,m in pairs(self.roster) do
        local matches=(unqualified and canonical(m.name)==canonical(unqualified))
            or (bare and canonical(m.firstName or m.name)==key)
            or (not self.regionalNames and not sender:find("-",1,true) and canonical(m.name)==key)
        if matches then
            if found then return nil,"Ambiguous sender" end
            found=k
        end
    end
    if found then return found end
    return nil,"Name not matched to current party"
end
function NS:Receive(prefix,message,channel,sender)
    if prefix~=C.PREFIX or not self:Channel() or channel~=self:Channel() then return end
    if type(message)~="string" or #message>254 or type(sender)~="string" or #sender>200 then return end
    self.rx.raw=self.rx.raw+1
    local me=fullName("player")
    if canonical(sender)==canonical(me) then self.rx.selfEcho=self.rx.selfEcho+1; return end
    local key,why = self:ResolveSender(sender)
    if not key then
        self.rx.unknownSender=self.rx.unknownSender+1
        self.lastUnknownSender=tostring(sender); self.lastUnknownReason=why
        return
    end
    self.rx.matched=self.rx.matched+1
    local peer = self.peers[key]
    if not peer then peer={quests={},online=true}; self.peers[key]=peer end
    if not C.TakeToken(peer,"packetBucket",clock(),C.RX_RATE,C.RX_BURST) then self.rx.rateLimited=self.rx.rateLimited+1; return end
    peer.lastPacket=clock()
    local version=message:match("^V|1|([%w%.%-]+)$")
    if version and #version<=32 then
        if peer.version and peer.version~=version and clock()<(peer.nextVersionChange or 0) then return end
        local before=self:CanSendZones()
        peer.version=version
        peer.nextVersionChange=clock()+5
        if before~=self:CanSendZones() then self.pendingFull=true end
        return
    end
    if message=="R|1" then
        self.rx.requests=self.rx.requests+1
        if clock() >= (peer.nextReply or 0) then
            -- The current full log already answers this request. Avoid queuing
            -- duplicate full logs ahead of new item/objective changes.
            if not self.queue or not self.queue.full then self.pendingFull=true end
            peer.nextReply=clock()+15
        end
        return
    end
    local session, revision = message:match("^H|1|([%w%-]+)|(%d+)$")
    if session and #session<=32 then
        local rev=tonumber(revision)
        if not rev or rev<0 or rev>1000000000 then return end
        local before=C.PeerStatus(peer,clock())
        self.rx.heartbeats=self.rx.heartbeats+1
        if peer.session==session and peer.revision==tonumber(revision) then
            peer.lastSeen=clock()
        elseif not peer.assembly then
            peer.needsFull=true
        end
        if before~=C.PeerStatus(peer,clock()) then self:RequestRender() end
        return
    end
    local previous=peer.ready and peer.quests or nil
    local wasFresh=C.PeerStatus(peer,clock())=="live"
    local applied, reason = C.Receive(peer,message,clock())
    if applied then
        if previous then self:ObserveProgress(previous,peer.quests,self.roster[key].name,wasFresh) end
        self.Features:CheckPartyReady(self,previous~=nil and wasFresh)
        self.received=self.received+1; self.receiveError=nil; peer.lastReject=nil; self:RequestRender()
    elseif reason=="Partial" then self.rx.fragments=self.rx.fragments+1
    elseif reason=="Decode rate limited" or reason=="Session rate limited" then self.rx.rateLimited=self.rx.rateLimited+1
    elseif reason~="Old revision" and reason~="Old fragment" and reason~="Old session" then
        self.rx.rejected=self.rx.rejected+1; peer.lastReject=reason
        self.receiveError="Sync update rejected: "..tostring(reason)
        if reason=="Full sync needed" then self.nextRequest=0 end
        self:RequestRender()
    end
end

function NS:StatusText()
    if self.demo then return "DEMO - example progress" end
    if self.readError then return self.readError end
    if self.sendError then return self.sendError end
    if self.receiveError then return self.receiveError end
    if IsInRaid() then return "Party mode only - leave raid to sync" end
    local players = self:Players()
    if #players==1 then return "Solo - showing your quests" end
    local live,waiting = 0,0
    for i=2,#players do
        if C.PeerStatus(players[i],clock())=="live" then live=live+1 else waiting=waiting+1 end
    end
    if C.AutomaticWaiting(players) and self.db.mode~="manual" then
        return self.db.scope=="all" and "Waiting for partner data - showing known quests" or "Waiting for partner data - choose All quests to see yours"
    end
    if waiting>0 then return "Waiting for fresh partner data: "..waiting end
    if self.queue then return "Syncing your quest log..." end
    return "Party synced - "..live.." partner"..(live==1 and "" or "s")
end

function NS:Diagnostics()
    local version, build, _, interface = GetBuildInfo()
    self:Print(C.VERSION.."; client "..version.." / "..build.." / interface "..interface)
    self:Print("Prefix: "..tostring(self.prefixOK).."; channel: "..tostring(self:Channel())..
        "; quests: "..C.Count(self.localQuests).."; sent packets: "..self.sent.."; received updates: "..self.received)
    self:Print("Incoming packets: "..self.rx.raw.."; party matched: "..self.rx.matched.."; self echoes: "..self.rx.selfEcho..
        "; unmatched names: "..self.rx.unknownSender.."; rejected updates: "..self.rx.rejected)
    self:Print("Fragments: "..self.rx.fragments.."; requests: "..self.rx.requests.."; heartbeats: "..self.rx.heartbeats..
        "; last send: "..tostring(self.lastSendResult).."; surname names: "..tostring(self.regionalNames))
    self:Print("Local reads: "..self.scanCount.."; last trigger: "..tostring(self.lastScanReason)..
        "; last success: "..(self.lastScanSuccess and (math.floor(clock()-self.lastScanSuccess).."s ago") or "not yet")..
        "; backup: "..C.BACKUP_SCAN_INTERVAL.."s")
    self:Print("Regions: "..#C.Regions(C.Catalogue(self:Players())).."; zone metadata format: "..tostring(self:CanSendZones()))
    for event in pairs(self.unsupportedEvents) do self:Print("Optional event unavailable: "..event) end
    if self.lastUnknownSender then
        self:Print("Last unmatched sender: "..C.SafeText(self.lastUnknownSender).." ("..tostring(self.lastUnknownReason)..")")
    end
    self:Print("Settings: "..(self.Settings.category and "native" or (self.Settings.legacy and "classic Options" or "standalone fallback")))
    if self.Settings.registrationError then self:Print("Settings registration: "..self.Settings.registrationError) end
    for _,p in ipairs(self:Players()) do
        self:Print(C.SafeText(p.name)..": "..C.PeerStatus(p,clock()).."; quests "..C.Count(p.quests)..
            "; addon "..(p.localPlayer and C.VERSION or (p.version or "not reported")))
        if p.lastReject then self:Print("Last rejected update: "..p.lastReject) end
    end
    for _,key in ipairs(C.Keys(self.roster)) do self:Print("Party name key: "..C.SafeText(key)) end
    if self.readError or self.sendError or self.receiveError then self:Print(self.readError or self.sendError or self.receiveError) end
end

function NS:ViewPlayers()
    if not self.demo then return self:Players() end
    local function q(a,b,c,d)
        local objs = {}
        for i,v in ipairs({a,b,c,d}) do
            objs[i]={text=({"Stringy Vulture Meat","Murloc Eye","Goretusk Snout","Okra"})[i],fulfilled=v,required=3,finished=v==3}
        end
        return {[38]={id=38,title="Westfall Stew",zone="Westfall",level=13,state="A",objectives=objs},
            [102]={id=102,title="Patrolling Westfall",zone="Westfall",level=14,state="A",objectives={{text="Gnoll paws",fulfilled=a,required=8,finished=false}}},
            [900001]={id=900001,title="Elwynn Patrol (sample)",zone="Elwynn Forest",level=10,state="A",objectives={{text="Patrol checkpoints",fulfilled=b,required=3,finished=b==3}}}}
    end
    local actual, demoPlayers = self:Players(), {}
    for i,p in ipairs(actual) do
        demoPlayers[i]={name=p.name,localPlayer=true,online=true,quests=i==1 and q(2,0,2,0) or q(3,1,2,1)}
    end
    if #demoPlayers==1 then
        demoPlayers[2]={name="Partner (sample)",localPlayer=true,online=true,quests=q(3,1,2,1)}
    end
    return demoPlayers
end

function NS:ViewConfig()
    if not self.demo then return self.db end
    self.demoDB=self.demoDB or {mode="auto",scope="shared",selected={},collapsed={},hiddenZones={},collapsedZones={},hiddenQuests={},pinned={}}
    self.demoDB.hideFinished=self.db.hideFinished
    self.demoDB.sortMode=self.db.sortMode
    return self.demoDB
end

function NS:Slash(text)
    local cmd,arg = (text or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd=cmd:lower()
    if cmd=="" then self.db.shown=not self.db.shown
    elseif cmd=="show" then self.db.shown=true
    elseif cmd=="hide" then self.db.shown=false
    elseif cmd=="lock" then self.db.locked=not self.db.locked
    elseif cmd=="sync" then self:ForceSync()
    elseif cmd=="status" then self:Diagnostics()
    elseif cmd=="demo" then self.demo=not self.demo; self.db.shown=true
    elseif cmd=="quests" then self.UI:ToggleQuests(self)
    elseif cmd=="regions" then self.UI:ToggleQuests(self,"regions")
    elseif cmd=="options" or cmd=="settings" then self.Settings:Open(self)
    elseif cmd=="opacity" then
        local n=tonumber(arg)
        if n and n>=0 and n<=100 then self.db.opacity=n/100 else self:Print("Use /qp opacity 0 to 100") end
    elseif cmd=="reset" then
        self.db.width,self.db.maxHeight,self.db.x,self.db.y=340,360,nil,nil
        self.db.shown,self.db.locked=true,false
        self.UI:Position(self)
    else self:Print("/qp show, hide, quests, regions, settings, lock, sync, status, demo, opacity 0-100, reset") end
    self:Change()
end

local function initialize()
    QuestPartnersDB = type(QuestPartnersDB)=="table" and QuestPartnersDB or {}
    NS.db = QuestPartnersDB
    -- Each login/reload starts compact; manual opens last for this session.
    NS.db.collapsed={}
    if NS.db.scope==nil and NS.db.mode=="manual" then NS.db.scope="all" end
    NS.regionalNames=C.UsesSurnames()
    if not NS.db.styleVersion then
        if C.Finite(NS.db.opacity) and math.abs(NS.db.opacity-0.18)<0.00001 then NS.db.opacity=defaults.opacity end
        if C.Finite(NS.db.barOpacity) and math.abs(NS.db.barOpacity-0.66)<0.00001 then NS.db.barOpacity=defaults.barOpacity end
        NS.db.styleVersion=2
    end
    for k,v in pairs(defaults) do
        if NS.db[k]==nil or type(NS.db[k])~=type(v) then NS.db[k]=C.Copy(v) end
    end
    NS.db.width=C.Clamp(NS.db.width,280,620,defaults.width)
    NS.db.maxHeight=C.Clamp(NS.db.maxHeight,160,800,defaults.maxHeight)
    NS.db.fontSize=C.Clamp(NS.db.fontSize,10,20,defaults.fontSize)
    NS.db.opacity=C.Clamp(NS.db.opacity,0,1,defaults.opacity)
    NS.db.barOpacity=C.Clamp(NS.db.barOpacity,0.3,1,defaults.barOpacity)
    NS.db.barHeight=C.Clamp(NS.db.barHeight,10,22,defaults.barHeight)
    NS.db.questSpacing=C.Clamp(NS.db.questSpacing,4,30,defaults.questSpacing)
    if not C.Finite(NS.db.x) or not C.Finite(NS.db.y) then NS.db.x,NS.db.y=nil,nil end
    if NS.db.x then NS.db.x=C.Clamp(NS.db.x,-100000,100000,0);NS.db.y=C.Clamp(NS.db.y,-100000,100000,0) end
    if NS.db.mode~="manual" then NS.db.mode="auto" end
    for _,key in ipairs({"selected","hiddenQuests","pinned"}) do NS.db[key]=C.CleanSet(NS.db[key]) end
    for _,key in ipairs({"hiddenZones","collapsedZones"}) do NS.db[key]=C.CleanSet(NS.db[key],true) end
    if NS.db.scope~="all" then NS.db.scope="shared" end
    if not ({badge=true,level=true,off=true})[NS.db.difficultyStyle] then NS.db.difficultyStyle="badge" end
    if not NS.Features.SORT_LABELS[NS.db.sortMode] then NS.db.sortMode="level" end
    for key,color in pairs(C.DEFAULT_COLORS) do
        if type(NS.db.colors[key])~="table" then NS.db.colors[key]=C.Copy(color) end
        for i=1,3 do
            local value=NS.db.colors[key][i]
            NS.db.colors[key][i]=C.Clamp(value,0,1,color[i])
        end
    end
    local ok,result=pcall(C_ChatInfo.RegisterAddonMessagePrefix,C.PREFIX)
    NS.prefixOK=ok and (result==true or result==0 or result==1)
    if not NS.prefixOK then NS.sendError="Cannot register sync prefix: "..tostring(result) end
    NS.UI:Build(NS)
    NS.Features:Build(NS)
    NS.Settings:Build(NS)
    NS:UpdateRoster()
    NS:RegisterCommands()
    NS:ScheduleScan(1,"login")
    NS.nextBackup=clock()+C.BACKUP_SCAN_INTERVAL
    NS:Print("Test build "..C.VERSION.." loaded. /qp settings for appearance and colours; /qp quests to choose quests.")
    NS:Render()
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event=="ADDON_LOADED" then
        if (...)==addonName then initialize()
        elseif NS.db and NS.Settings then NS.Settings:Register(NS) end
        return
    end
    if not NS.db then return end
    if event=="CHAT_MSG_ADDON" then NS:Receive(...); return end
    if event=="PLAYER_LEVEL_UP" then NS:RequestRender(); return end
    if event=="PLAYER_LOGIN" then NS:RegisterCommands(); return end
    if event=="GROUP_ROSTER_UPDATE" or event=="PLAYER_ENTERING_WORLD" then
        NS:UpdateRoster(); NS.pendingFull=true; NS:ScheduleScan(1,event); NS:Render()
    elseif event=="QUEST_TURNED_IN" then
        local id=(...)
        NS:MarkTurnedIn(id)
        NS:ScheduleScan(0.4,event)
    elseif event=="QUEST_ACCEPTED" then
        local first,second=...
        local id=type(second)=="number" and second or first
        if type(id)=="number" and id>0 then
            NS.recentTurnIns[id]=nil
            if NS.localQuests[id] and NS.localQuests[id].state=="T" then NS.localQuests[id]=nil end
            NS.db.collapsed[id]=nil; NS.autoExpanded[id]=nil
            NS.partyReady[id]=nil; NS.recentProgress[id]=nil
        end
        NS:ScheduleScan(0.20,event)
    elseif event=="UNIT_QUEST_LOG_CHANGED" then
        local unit=(...)
        if not unit or unit=="player" then NS:ScheduleScan(0.20,event) end
    elseif event=="UNIT_CONNECTION" then
        NS:UpdateRoster(); NS.pendingFull=true; NS:ScheduleScan(0.20,event)
    else
        NS:ScheduleScan(0.20,event)
    end
end)
for _,event in ipairs({"ADDON_LOADED","CHAT_MSG_ADDON","PLAYER_LOGIN","PLAYER_LEVEL_UP","PLAYER_ENTERING_WORLD","GROUP_ROSTER_UPDATE","QUEST_LOG_UPDATE",
    "QUEST_WATCH_UPDATE","QUEST_ACCEPTED","QUEST_REMOVED","QUEST_TURNED_IN","UNIT_CONNECTION",
    "BAG_UPDATE_DELAYED","UNIT_QUEST_LOG_CHANGED"}) do
    local ok=pcall(eventFrame.RegisterEvent,eventFrame,event)
    if not ok then NS.unsupportedEvents[event]=true end
end
local elapsedPump,elapsedUI=0,0
eventFrame:SetScript("OnUpdate", function(_,elapsed)
    if not NS.db then return end
    local now=clock()
    if now>=(NS.nextBackup or 0) then
        NS:ScheduleScan(0,"periodic backup")
        NS.nextBackup=now+C.BACKUP_SCAN_INTERVAL
    end
    if NS.scanAt and now>=NS.scanAt then
        local reason=NS.scanReason
        NS.scanAt=nil
        NS.lastScanAttempt=now; NS.scanCount=NS.scanCount+1
        local priorError=NS.readError
        local ok,result,changed=pcall(NS.Scan,NS)
        if not ok then NS.readError="Quest scan error: "..tostring(result)
        elseif result then
            NS.lastScanSuccess,NS.lastScanReason=now,reason
            NS.nextBackup=now+C.BACKUP_SCAN_INTERVAL
        end
        if changed or priorError~=NS.readError then NS:Render() end
    end
    elapsedPump,elapsedUI=elapsedPump+elapsed,elapsedUI+elapsed
    if elapsedPump>=0.25 then elapsedPump=0; NS:Pump(now);NS.Features:Tick(NS) end
    if NS.renderAt and now>=NS.renderAt then NS:Render() end
    if elapsedUI>=2 then
        elapsedUI=0
        NS:UpdateRoster()
        NS:Render()
    end
end)
