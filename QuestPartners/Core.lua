local _, NS = ...
local C = {}
NS.Core = C
C.VERSION = "0.6.0-test9"
C.RX_RATE,C.RX_BURST=16,64
C.BACKUP_SCAN_INTERVAL=2
C.MIN_SCAN_INTERVAL=0.25
C.LOGO = "Interface\\AddOns\\QuestPartners\\Media\\Logo"
C.DEFAULT_COLORS = {
    red={0.88,0.25,0.22},yellow={0.96,0.72,0.20},green={0.22,0.78,0.46},grey={0.48,0.54,0.60},
    background={0.025,0.035,0.045},heading={0.94,0.81,0.53},text={0.94,0.95,0.93},track={0.06,0.075,0.085}
}
C.PREFIX = "QuestPartners1"
C.STALE = 45
C.MAX_QUESTS = 100

function C.UsesSurnames()
    if type(RegionalUniqueNamesEnabled)=="function" then
        local ok,value=pcall(RegionalUniqueNamesEnabled)
        if ok and type(value)=="boolean" then return value end
    end
    if GetBuildInfo then
        local version,_,_,interface=GetBuildInfo()
        return interface==16001 or (type(version)=="string" and version:match("^1%.60%.")) and true or false
    end
    return false
end

function C.NormalizeName(name)
    if type(name)~="string" then return "" end
    return (name:gsub("^%s+",""):gsub("%s+$",""):gsub("%s+"," "):lower())
end

function C.Count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

function C.Keys(t)
    local keys = {}
    for k in pairs(t or {}) do keys[#keys + 1] = k end
    table.sort(keys)
    return keys
end

function C.Copy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do copy[k] = C.Copy(v) end
    return copy
end

function C.ShallowCopy(value)
    local copy={};for k,v in pairs(value or {}) do copy[k]=v end;return copy
end

function C.Finite(value) return type(value)=="number" and value==value and value>-math.huge and value<math.huge end
function C.Clamp(value,low,high,fallback)
    return C.Finite(value) and math.max(low,math.min(high,value)) or fallback
end

C.DIFFICULTY_COLORS={red={1,0.1,0.1},orange={1,0.5,0.25},yellow={1,1,0},green={0.25,0.75,0.25},grey={0.5,0.5,0.5}}
function C.PlayerLevel()
    if type(UnitLevel)=="function" then
        local ok,value=pcall(UnitLevel,"player")
        if ok and C.Finite(value) and value>0 then return value end
    end
end

function C.DifficultyColor(level)
    if not C.Finite(level) or level<=0 then return C.DIFFICULTY_COLORS.grey,false end
    -- Use the client's own quest-log colours, including any native accessibility choices.
    local function native(getter)
        if type(getter)~="function" then return end
        local ok,color=pcall(function()
            local value=getter(level)
            if type(value)=="table" and C.Finite(value.r) and C.Finite(value.g) and C.Finite(value.b)
                and value.r>=0 and value.r<=1 and value.g>=0 and value.g<=1 and value.b>=0 and value.b<=1 then
                return {value.r,value.g,value.b}
            end
        end)
        if ok then return color end
    end
    local color=native(GetQuestDifficultyColor) or native(GetDifficultyColor)
    if color then return color,true end
    local player=C.PlayerLevel()
    if not player then return C.DIFFICULTY_COLORS.grey,false end
    local delta=level-player
    if delta>=5 then return C.DIFFICULTY_COLORS.red,true end
    if delta>=3 then return C.DIFFICULTY_COLORS.orange,true end
    if delta>=-2 then return C.DIFFICULTY_COLORS.yellow,true end
    if type(GetQuestGreenRange)=="function" then
        local ok,range=pcall(GetQuestGreenRange,"player")
        if not ok then ok,range=pcall(GetQuestGreenRange) end
        if ok and C.Finite(range) and range>=0 then
            return -delta<=range and C.DIFFICULTY_COLORS.green or C.DIFFICULTY_COLORS.grey,true
        end
    end
    return C.DIFFICULTY_COLORS.grey,false
end

function C.MatchesSearch(q,players,query)
    query=C.NormalizeName(tostring(query or ""):sub(1,128))
    if query=="" then return true end
    local function matches(value) return tostring(value or ""):lower():find(query,1,true)~=nil end
    if matches(q.title) then return true end
    for _,p in ipairs(players) do
        local quest=(p.quests or {})[q.id]
        for _,o in ipairs(quest and quest.objectives or {}) do if matches(o.text) then return true end end
    end
    return false
end

function C.CleanSet(value,regions)
    local out,count={},0
    for key,flag in pairs(type(value)=="table" and value or {}) do
        local valid=regions and type(key)=="string" and #key<=200 and not key:find("[%c]")
            or (not regions and C.Finite(key) and key==math.floor(key) and key>0 and key<=10000000)
        if valid and type(flag)=="boolean" then out[key]=flag;count=count+1;if count>=512 then break end end
    end
    return out
end

function C.QuestEqual(a,b)
    if a==b then return true end
    if not a or not b or a.id~=b.id or a.title~=b.title or a.level~=b.level or a.state~=b.state or a.zone~=b.zone
        or #(a.objectives or {})~=#(b.objectives or {}) then return false end
    for i,o in ipairs(a.objectives or {}) do
        local p=b.objectives[i]
        if o.text~=p.text or o.type~=p.type or o.fulfilled~=p.fulfilled or o.required~=p.required or o.finished~=p.finished then return false end
    end
    return true
end

function C.TakeToken(owner,key,now,rate,burst)
    local bucket=owner[key]
    if not bucket then bucket={at=now,tokens=burst}; owner[key]=bucket end
    bucket.tokens=math.min(burst,bucket.tokens+math.max(0,now-bucket.at)*rate);bucket.at=now
    if bucket.tokens<1 then return false end
    bucket.tokens=bucket.tokens-1;return true
end

function C.SafeText(text,multiline)
    local value=tostring(text or ""):sub(1,12000)
    value=value:gsub(multiline and "[%z\1-\8\11\12\14-\31\127]" or "[%c]"," ")
    return (value:gsub("|", "||"))
end

function C.ObjectiveLabel(text)
    return (tostring(text or "Objective"):gsub("^%s*%d+%s*/%s*%d+%s*", ""):gsub("%s*:?%s*%d+%s*/%s*%d+%s*$", ""))
end

local function escape(s)
    return (tostring(s or ""):gsub("[%%\t\r\n|]", function(ch)
        return string.format("%%%02X", string.byte(ch))
    end))
end
local function unescape(s)
    return (s:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end
local function split(s, delim, limit)
    local out, start = {}, 1
    while true do
        if limit and #out>=limit then return nil end
        local pos = s:find(delim, start, true)
        if not pos then out[#out + 1] = s:sub(start); break end
        out[#out + 1] = s:sub(start, pos - 1)
        start = pos + #delim
    end
    return out
end
local function integer(s, low, high)
    local n = tonumber(s)
    if n and n == math.floor(n) and n >= low and n <= high then return n end
end

local function questLines(q,includeZones)
    local fields={"Q", q.id, q.level or 0, q.state or "A", escape(q.title)}
    if includeZones then fields[#fields+1]=escape(q.zone or "") end
    local out = { table.concat(fields, "\t") }
    for i, o in ipairs(q.objectives or {}) do
        out[#out + 1] = table.concat({"O", q.id, i, o.fulfilled or -1, o.required or -1,
            o.finished and 1 or 0, escape(o.type), escape(o.text)}, "\t")
    end
    return out
end

function C.Serialize(quests, previous, full, includeZones)
    local out = {full and "F" or "D"}
    for _, id in ipairs(C.Keys(quests)) do
        local old = previous and previous[id]
        if full or quests[id]~=old then
          local lines = questLines(quests[id],includeZones)
          if full or not old or table.concat(lines, "\n") ~= table.concat(questLines(old,includeZones), "\n") then
            for _, line in ipairs(lines) do out[#out + 1] = line end
          end
        end
    end
    if not full then
        for _, id in ipairs(C.Keys(previous)) do
            if not quests[id] then out[#out + 1] = "X\t" .. id end
        end
    end
    if #out == 1 and not full then return nil end
    return table.concat(out, "\n")
end

function C.Decode(payload, previous)
    if type(payload) ~= "string" or #payload > 54000 then return nil, "Invalid payload" end
    local lines = split(payload, "\n",2201)
    if not lines then return nil,"Too many records" end
    if lines[1] ~= "F" and lines[1] ~= "D" then return nil, "Invalid mode" end
    if lines[1] == "D" and not previous then return nil, "Full sync needed" end
    -- Changed quests are always rebuilt below; untouched records are immutable.
    local quests = lines[1] == "F" and {} or C.ShallowCopy(previous)
    local changed = {}
    for i = 2, #lines do
        local f = split(lines[i], "\t",8)
        if not f then return nil,"Too many fields" end
        local id = integer(f[2], 1, 10000000)
        if not id then return nil, "Invalid quest ID" end
        if f[1] == "Q" and (#f == 5 or #f == 6) then
            local level = integer(f[3], -1, 1000)
            if changed[id] or not level or not ({A=true,C=true,F=true,T=true})[f[4]] or #f[5] > 2000 or #(f[6] or "")>600 then
                return nil, "Invalid quest"
            end
            changed[id] = true
            quests[id] = {id=id, level=level, state=f[4], title=unescape(f[5]),zone=unescape(f[6] or ""),objectives={}}
        elseif f[1] == "O" and #f == 8 and changed[id] then
            local q = quests[id]
            local index = integer(f[3], 1, 20)
            local have, need = integer(f[4], -1, 100000000), integer(f[5], -1, 100000000)
            if not q or not index or index ~= #q.objectives + 1 or not have or not need
                or (f[6] ~= "0" and f[6] ~= "1") or #f[7] > 150 or #f[8] > 4000 then
                return nil, "Invalid objective"
            end
            q.objectives[index] = {fulfilled=have >= 0 and have or nil,
                required=need > 0 and need or nil, finished=f[6]=="1", type=unescape(f[7]), text=unescape(f[8])}
        elseif f[1] == "X" and #f == 2 and lines[1] == "D" and not changed[id] then
            quests[id], changed[id] = nil, true
        else
            return nil, "Invalid record"
        end
    end
    if C.Count(quests) > C.MAX_QUESTS then return nil, "Too many quests" end
    return quests, lines[1]
end

function C.Chunks(payload, session, revision, base)
    local chunks, total = {}, math.ceil(#payload / 180)
    if total < 1 or total > 300 then return nil, "Quest log exceeds sync limit" end
    for i = 1, total do
        chunks[i] = table.concat({"1", session, revision, base, i, total}, "|") .. "|" .. payload:sub((i-1)*180+1,i*180)
        if #chunks[i] > 254 then return nil, "Packet too long" end
    end
    return chunks
end

-- One bounded assembly per current party member; never evaluate received Lua.
function C.Receive(peer, message, now)
    if type(message) ~= "string" or #message > 254 then return false, "Invalid packet" end
    local session, rev, base, index, total, body = message:match("^1|([%w%-]+)|(%d+)|(%d+)|(%d+)|(%d+)|(.*)$")
    rev, base, index, total = integer(rev,1,1000000000), integer(base,0,1000000000),
        integer(index,1,300), integer(total,1,300)
    if not session or #session > 32 or not rev or not base or not index or not total or index > total or #body > 180 then
        return false, "Invalid packet"
    end
    if peer.retired and peer.retired[session] then return false, "Old session" end
    if peer.session and peer.session~=session and now<(peer.sessionChangedAt or -1000)+1 then return false,"Session rate limited" end
    if peer.session == session and rev <= (peer.revision or 0) then return false, "Old revision" end
    local a = peer.assembly
    if a and (now - a.started > 120 or a.session ~= session or rev > a.revision) then a = nil end
    if a and rev < a.revision then return false, "Old fragment" end
    if not a then
        a = {session=session,revision=rev,base=base,total=total,parts={},count=0,started=now}
        peer.assembly = a
    end
    if a.total ~= total or a.base ~= base then return false, "Conflicting packet" end
    if a.parts[index] and a.parts[index] ~= body then return false, "Conflicting fragment" end
    if not a.parts[index] then a.parts[index], a.count = body, a.count + 1 end
    if a.count < total then return false, "Partial" end
    peer.assembly = nil
    local payload = table.concat(a.parts)
    local full = payload:sub(1,1) == "F"
    if (full and base~=0) or (not full and base~=rev-1) then return false,"Invalid revision base" end
    if not full and (not peer.ready or peer.session ~= session or peer.revision ~= base) then
        peer.needsFull = true
        return false, "Full sync needed"
    end
    if not C.TakeToken(peer,"decodeBucket",now,4,8) then return false,"Decode rate limited" end
    local quests, err = C.Decode(payload, full and nil or peer.quests)
    if not quests then peer.needsFull = true; return false, err end
    if peer.session and peer.session ~= session then
        peer.retired = peer.retired or {}
        peer.retiredOrder=peer.retiredOrder or {}
        peer.retired[peer.session] = true
        peer.retiredOrder[#peer.retiredOrder+1]=peer.session
        if #peer.retiredOrder>32 then peer.retired[table.remove(peer.retiredOrder,1)]=nil end
        peer.sessionChangedAt=now
    end
    peer.quests, peer.session, peer.revision = quests, session, rev
    peer.ready, peer.needsFull, peer.lastSeen, peer.lastData = true, false, now, now
    return true
end

function C.PeerStatus(peer, now)
    if peer.readError then return "stale" end
    if peer.localPlayer then return "live" end
    if not peer.online then return "offline" end
    if not peer.ready then return "waiting" end
    if peer.needsFull or now - (peer.lastSeen or 0) > C.STALE then return "stale" end
    return "live"
end

function C.Progress(q, index, status)
    if status == "waiting" then return 0, "grey", "Waiting for sync" end
    if status == "offline" then return 0, "grey", "Offline" end
    if status == "stale" then
        local _, _, text = C.Progress(q, index, "live")
        return 0, "grey", "Stale: " .. text
    end
    if not q then return 0, "grey", "Not in log" end
    if q.state == "T" then return 0, "grey", "Turned in" end
    if q.state == "F" then return 0, "red", "Failed" end
    local o = q.objectives[index]
    if not o then
        if q.state == "C" then return 1, "green", "Ready to turn in" end
        return 0, "grey", "No objective data"
    end
    if o.required and o.fulfilled then
        local have = o.finished and o.required or math.min(o.required, o.fulfilled)
        local ratio = math.max(0, have / o.required)
        return ratio, ratio >= 1 and "green" or (ratio >= 0.5 and "yellow" or "red"), have .. "/" .. o.required
    end
    if o.finished then return 1, "green", "Done" end
    return 0, "grey", "Pending"
end

function C.Catalogue(players)
    local quests = {}
    local active = {}
    for _, p in ipairs(players) do
        for id, q in pairs(p.quests or {}) do
            if q.state~="T" then active[id]=true end
            if not quests[id] or (quests[id].state == "T" and q.state ~= "T") then quests[id] = q
            elseif (not quests[id].zone or quests[id].zone=="") and q.zone and q.zone~="" then
                local combined=C.Copy(quests[id]); combined.zone=q.zone; quests[id]=combined
            end
        end
    end
    -- Turn-in records support comparison only while someone still has the quest.
    for id in pairs(quests) do if not active[id] then quests[id]=nil end end
    return quests
end

function C.ProgressChanged(previous,current)
    if not previous or not current or previous.state=="T" or current.state=="T" then return false end
    if previous.state~=current.state then return true end
    for i,o in ipairs(current.objectives or {}) do
        local old=(previous.objectives or {})[i]
        if old and (old.fulfilled~=o.fulfilled or old.finished~=o.finished) then return true end
    end
    return false
end

function C.ZoneName(q)
    local text=type(q.zone)=="string" and q.zone or ""
    text=text:gsub("[%c]"," "):gsub("^%s+",""):gsub("%s+$","")
    return text~="" and text or "Other / unknown"
end
function C.ZoneKey(q) return C.NormalizeName(C.ZoneName(q)) end

function C.SortQuests(quests,mode,recent)
    table.sort(quests,function(a,b)
        if mode=="recent" then
            local at,bt=(recent or {})[a.id] or 0,(recent or {})[b.id] or 0
            if at~=bt then return at>bt end
        elseif mode=="ready" then
            local ar,br=a.state=="C",b.state=="C"
            if ar~=br then return ar end
        end
        if mode~="title" and a.level~=b.level then return a.level<b.level end
        if a.title~=b.title then return a.title<b.title end
        return a.id<b.id
    end)
    return quests
end

function C.Regions(quests,mode,recent)
    local groups,out={},{}
    for _,q in pairs(quests or {}) do
        local key=C.ZoneKey(q)
        if not groups[key] then
            groups[key]={key=key,name=C.ZoneName(q),quests={}}
            out[#out+1]=groups[key]
        end
        local items=groups[key].quests; items[#items+1]=q
    end
    table.sort(out,function(a,b)
        if a.name=="Other / unknown" then return false end
        if b.name=="Other / unknown" then return true end
        return a.key<b.key
    end)
    for _,group in ipairs(out) do
        C.SortQuests(group.quests,mode,recent)
    end
    return out
end

function C.SupportsZones(version)
    if type(version)~="string" then return false end
    local major,minor=version:match("^(%d+)%.(%d+)%.")
    return major and (tonumber(major)>0 or tonumber(minor)>=3) and true or false
end

function C.AutomaticWaiting(players)
    if #players<2 then return false end
    for i=2,#players do if players[i].ready then return false end end
    return true
end

function C.Visible(players, db, now, recent)
    local catalogue, result = C.Catalogue(players), {}
    for id, q in pairs(catalogue) do
        local selected = db.mode == "manual" and db.selected[id]
        if db.mode ~= "manual" then
            local mine = players[1].quests and players[1].quests[id]
            selected = true
            if (db.scope or "shared")=="shared" and #players>1 then
                selected = false
                if mine then
                    for i=2,#players do
                        if players[i].quests and players[i].quests[id] then selected=true; break end
                    end
                end
            end
        end
        local everyoneDone = true
        for _, p in ipairs(players) do
            local pq = p.quests and p.quests[id]
            -- A fresh log without this quest is not an unfinished participant.
            -- Unknown/stale logs still prevent assuming everyone is ready.
            if C.PeerStatus(p, now) ~= "live" or (pq and pq.state ~= "C" and pq.state ~= "T") then everyoneDone = false end
        end
        if selected and not (db.hideFinished and everyoneDone) and not (db.hiddenZones or {})[C.ZoneKey(q)]
            and not (db.hiddenQuests or {})[id] then result[#result+1] = q end
    end
    return C.SortQuests(result,db.sortMode,recent)
end

function C.ObjectiveDone(o)
    return o and (o.finished or (o.required and o.required>0 and o.fulfilled and o.fulfilled>=o.required)) and true or false
end

function C.Summary(q,status)
    if status~="live" then return ({waiting="Syncing",stale="Stale",offline="Offline"})[status] or "Unknown" end
    if not q then return "Not in log" end
    if q.state=="T" then return "Turned in",1 end
    if q.state=="C" then return "Ready",1 end
    if q.state=="F" then return "Failed" end
    local total,done,ratio,known=0,0,0,true
    for i,o in ipairs(q.objectives or {}) do
        total=total+1
        if C.ObjectiveDone(o) then done=done+1; ratio=ratio+1
        elseif o.required and o.fulfilled then ratio=ratio+math.max(0,math.min(1,o.fulfilled/o.required))
        else known=false end
    end
    if total==0 then return "Pending" end
    if not known then return done.."/"..total.." done" end
    return math.floor(ratio/total*100+0.5).."%",ratio/total
end

function C.Behind(players,id,index,now)
    local values,minimum,maximum={},1,0
    for i,p in ipairs(players) do
        local q=(p.quests or {})[id]
        if C.PeerStatus(p,now)=="live" and q and q.state~="F" then
            local value
            if q.state=="T" or q.state=="C" then value=1
            elseif index then
                local o=(q.objectives or {})[index]
                if C.ObjectiveDone(o) then value=1
                elseif o and o.required and o.fulfilled then value=math.max(0,math.min(1,o.fulfilled/o.required)) end
            else local _; _,value=C.Summary(q,"live") end
            if value then values[i]=value; minimum=math.min(minimum,value); maximum=math.max(maximum,value) end
        end
    end
    local behind={}
    if minimum<maximum then for i,v in pairs(values) do if v==minimum then behind[i]=true end end end
    return behind
end

function C.AllReady(players,id,now)
    local holders,ready=0,true
    for _,p in ipairs(players) do
        if C.PeerStatus(p,now)~="live" then return nil,0 end
        local q=(p.quests or {})[id]
        if q then holders=holders+1; if q.state~="C" and q.state~="T" then ready=false end end
    end
    return ready and holders>0,holders
end
