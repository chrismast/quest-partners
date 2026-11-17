local _, NS = ...
local C = NS.Core
local UI = {rows={},choices={},regionChoices={}}
NS.UI = UI
local WHITE = "Interface\\Buttons\\WHITE8X8"

local function texture(parent,layer,r,g,b,a)
    local t=parent:CreateTexture(nil,layer or "BACKGROUND")
    t:SetTexture(WHITE); t:SetVertexColor(r,g,b,a)
    return t
end
local function font(parent,size,color)
    local f=parent:CreateFontString(nil,"OVERLAY")
    f:SetFont(STANDARD_TEXT_FONT,size or 12,"OUTLINE")
    f:SetJustifyH("LEFT"); f:SetJustifyV("MIDDLE")
    if f.SetWordWrap then f:SetWordWrap(false) end
    f:SetTextColor(unpack(color or {0.94,0.94,0.90}))
    f:SetShadowColor(0,0,0,0.8); f:SetShadowOffset(1,-1)
    return f
end
local function tooltip(frame,text)
    frame.qpTooltip=text
    if frame.qpTooltipHooked then return end
    frame.qpTooltipHooked=true
    frame:SetScript("OnEnter",function(self)
        GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
        GameTooltip:SetText(self.qpTooltip,nil,nil,nil,nil,true); GameTooltip:Show()
    end)
    frame:SetScript("OnLeave",function(self) if not GameTooltip.IsOwned or GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)
end
local function button(parent,text,width,callback,tip)
    local b=CreateFrame("Button",nil,parent)
    b:SetSize(width,22)
    b.label=font(b,12,{0.89,0.79,0.51}); b.label:SetAllPoints(); b.label:SetJustifyH("CENTER"); b.label:SetText(text)
    local h=b:CreateTexture(nil,"HIGHLIGHT"); h:SetAllPoints(); h:SetColorTexture(1,1,1,0.09)
    b:SetScript("OnClick",callback)
    if tip then tooltip(b,tip) end
    return b
end
local function checkbox(parent,text,x,y,callback)
    local b=CreateFrame("CheckButton",nil,parent,"UICheckButtonTemplate")
    b:SetSize(24,24); b:SetPoint("TOPLEFT",x,y)
    b.label=font(b,12); b.label:SetPoint("LEFT",b,"RIGHT",3,0); b.label:SetText(text)
    b:SetScript("OnClick",function(self) callback(self:GetChecked() and true or false) end)
    return b
end
UI.Helpers={font=font,button=button,checkbox=checkbox,texture=texture,tooltip=tooltip}

function UI:Position(app)
    local f=self.frame
    f:ClearAllPoints()
    if app.db.x and app.db.y then f:SetPoint("TOPLEFT",UIParent,"BOTTOMLEFT",app.db.x,app.db.y)
    else f:SetPoint("TOPLEFT",UIParent,"TOPLEFT",36,-180) end
end

function UI:Build(app)
    local f=CreateFrame("Frame","QuestPartnersFrame",UIParent)
    self.frame=f
    f:SetFrameStrata("MEDIUM"); f:SetClampedToScreen(true)
    f:SetMovable(true); f:SetResizable(true)
    if f.SetResizeBounds then f:SetResizeBounds(280,160,620,800) end
    f:SetSize(app.db.width,app.db.maxHeight)
    self:Position(app)
    f.bg=texture(f,"BACKGROUND",0.025,0.03,0.035,app.db.opacity); f.bg:SetAllPoints()
    self.headerRule=texture(f,"BORDER",0.94,0.81,0.53,0.30)
    self.headerRule:SetPoint("TOPLEFT",7,-29); self.headerRule:SetPoint("TOPRIGHT",-7,-29); self.headerRule:SetHeight(1)
    local header=CreateFrame("Frame",nil,f)
    self.header=header
    header:SetPoint("TOPLEFT"); header:SetPoint("TOPRIGHT"); header:SetHeight(30)
    header:EnableMouse(true); header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart",function() if not app.db.locked then f:StartMoving() end end)
    header:SetScript("OnDragStop",function()
        f:StopMovingOrSizing()
        app.db.x,app.db.y=f:GetLeft(),f:GetTop()
    end)
    self.logo=header:CreateTexture(nil,"ARTWORK")
    self.logo:SetTexture(C.LOGO); self.logo:SetSize(20,20); self.logo:SetPoint("LEFT",7,0)
    self.title=font(header,12,{0.91,0.80,0.53})
    self.title:SetPoint("LEFT",32,0); self.title:SetWidth(116)
    self.title:SetText("Quest Partners")
    self.minimize=button(header,"-",20,function() app.db.minimized=not app.db.minimized; app:Change() end,"Collapse or expand the panel")
    self.minimize:SetPoint("RIGHT",-4,0)
    self.lock=button(header,"L",22,function() app.db.locked=not app.db.locked; app:Change() end,"L = locked; U = unlocked. Drag the title when unlocked.")
    self.lock:SetPoint("RIGHT",self.minimize,"LEFT",0,0)
    self.options=button(header,"Settings",54,function() app.Settings:Open(app) end,"Open Quest Partners in WoW's AddOns settings")
    self.options:SetPoint("RIGHT",self.lock,"LEFT",0,0)
    self.pick=button(header,"Quests",49,function() self:ToggleQuests(app) end,"Choose which quests to display")
    self.pick:SetPoint("RIGHT",self.options,"LEFT",0,0)

    local scroll=CreateFrame("ScrollFrame",nil,f)
    self.scroll=scroll
    scroll:SetPoint("TOPLEFT",7,-34); scroll:SetPoint("BOTTOMRIGHT",-9,22)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel",function(_,delta)
        local maximum=math.max(0,self.content:GetHeight()-scroll:GetHeight())
        scroll:SetVerticalScroll(math.max(0,math.min(maximum,scroll:GetVerticalScroll()-delta*38)))
        if app.Features.actions then app.Features.actions:Hide() end
        app:Render()
    end)
    scroll:SetScript("OnVerticalScroll",function() if not self.painting then app:RequestRender() end end)
    local content=CreateFrame("Frame",nil,scroll)
    content:SetSize(app.db.width-16,1); scroll:SetScrollChild(content); self.content=content
    self.searchBox=CreateFrame("EditBox",nil,f)
    self.searchBox:SetAutoFocus(false);self.searchBox:SetMaxLetters(128)
    self.searchBox:SetFont(STANDARD_TEXT_FONT,11,"OUTLINE");self.searchBox:SetTextInsets(6,5,0,0)
    self.searchBox:SetHeight(20);self.searchBox:SetText("")
    self.searchBG=texture(self.searchBox,"BACKGROUND",0.02,0.03,0.04,0.70);self.searchBG:SetAllPoints()
    self.searchHint=font(self.searchBox,10,{0.65,0.70,0.72});self.searchHint:SetPoint("LEFT",6,0)
    self.searchHint:SetText("Find quest, item or creature...")
    self.searchBox:SetScript("OnTextChanged",function(box)
        if self.syncingSearch then return end
        app.searchText=(box:GetText() or ""):sub(1,128)
        self.searchHint:SetShown(app.searchText=="")
        scroll:SetVerticalScroll(0);app:RequestRender()
    end)
    self.searchBox:SetScript("OnEnterPressed",function(box) box:ClearFocus() end)
    self.searchBox:SetScript("OnEscapePressed",function(box) box:SetText("");box:ClearFocus();app:Change() end)
    tooltip(self.searchBox,"Search quest titles or objective items/creatures within your current filters. Press Enter to finish typing; Escape or x clears. Star a result to add it to Working on.")
    self.searchClear=button(f,"x",20,function() self.searchBox:SetText("");self.searchBox:ClearFocus();app:Change() end,"Clear quest search")
    self.empty=font(content,12,{0.77,0.80,0.82})
    self.empty:SetPoint("TOPLEFT",1,-6); self.empty:SetJustifyV("TOP")
    self.footer=font(f,10,{0.70,0.76,0.78})
    self.footer:SetPoint("BOTTOMLEFT",104,5); self.footer:SetPoint("BOTTOMRIGHT",-25,5); self.footer:SetHeight(14)
    self.scope=button(f,"Shared quests",96,function()
        local cfg=app:ViewConfig()
        app:SetScope(cfg.mode=="manual" and "all" or (cfg.scope=="all" and "shared" or "all"))
    end,"Click to switch All quests / Shared quests. Shared compares your quests with at least one partner; your own quests are shown when solo.")
    self.scope:SetPoint("BOTTOMLEFT",4,1); self.scope:SetHeight(20)
    self.statusHit=CreateFrame("Frame",nil,f); self.statusHit:SetAllPoints(self.footer); self.statusHit:EnableMouse(true)
    self.statusHit:SetScript("OnEnter",function(frame)
        GameTooltip:SetOwner(frame,"ANCHOR_RIGHT"); GameTooltip:SetText(C.SafeText(app:StatusText()),nil,nil,nil,nil,true); GameTooltip:Show()
    end)
    self.statusHit:SetScript("OnLeave",function(self) if not GameTooltip.IsOwned or GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)
    self.scrollHint=font(f,10,{0.83,0.82,0.70}); self.scrollHint:SetPoint("BOTTOMRIGHT",-8,23)
    self.scrollHint:SetText("v")
    self.grip=CreateFrame("Button",nil,f)
    self.grip:SetSize(18,18); self.grip:SetPoint("BOTTOMRIGHT")
    local gripText=font(self.grip,12,{0.70,0.70,0.66}); gripText:SetAllPoints(); gripText:SetText("//")
    self.grip:RegisterForDrag("LeftButton")
    self.grip:SetScript("OnDragStart",function()
        if app.db.locked then return end
        self.resizing=true; f:StartSizing("BOTTOMRIGHT")
    end)
    self.grip:SetScript("OnDragStop",function()
        f:StopMovingOrSizing(); self.resizing=false
        app.db.width,app.db.maxHeight=f:GetWidth(),f:GetHeight()
        app.db.x,app.db.y=f:GetLeft(),f:GetTop()
        app:Change()
    end)
    f:SetScript("OnSizeChanged",function()
        if self.resizing and not self.painting then
            app.db.width,app.db.maxHeight=f:GetWidth(),f:GetHeight()
            app:Change()
        end
    end)
    f:SetScript("OnHide",function()
        if self.questPopup then self.questPopup:Hide() end
        if app.Features and app.Features.actions then app.Features.actions:Hide() end
    end)
end

function UI:UpdateScrollHint()
    local maximum=math.max(0,self.content:GetHeight()-self.scroll:GetHeight())
    self.scrollHint:SetShown(maximum>2 and self.scroll:GetVerticalScroll()<maximum-2)
end

function UI:Row(index,kind)
    local row=self.rows[index]
    if not row then
        row=CreateFrame("Button",nil,self.content)
        row.text=font(row,12); row.name=font(row,11)
        row.band=texture(row,"BACKGROUND",0.94,0.81,0.53,0.05)
        row.rule=texture(row,"BORDER",0.94,0.81,0.53,0.28)
        row.accent=texture(row,"BORDER",0.94,0.81,0.53,0.65)
        row.bar=CreateFrame("StatusBar",nil,row)
        row.bar:SetMinMaxValues(0,1)
        row.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        row.fill=row.bar:GetStatusBarTexture()
        row.track=texture(row.bar,"BACKGROUND",0.05,0.06,0.07,0.75); row.track:SetAllPoints(row.bar)
        row.edges={}
        for i=1,4 do row.edges[i]=texture(row.bar,"OVERLAY",0,0,0,0.6) end
        row.edges[1]:SetPoint("TOPLEFT"); row.edges[1]:SetPoint("TOPRIGHT"); row.edges[1]:SetHeight(1)
        row.edges[2]:SetPoint("BOTTOMLEFT"); row.edges[2]:SetPoint("BOTTOMRIGHT"); row.edges[2]:SetHeight(1)
        row.edges[3]:SetPoint("TOPLEFT"); row.edges[3]:SetPoint("BOTTOMLEFT"); row.edges[3]:SetWidth(1)
        row.edges[4]:SetPoint("TOPRIGHT"); row.edges[4]:SetPoint("BOTTOMRIGHT"); row.edges[4]:SetWidth(1)
        row.glint=texture(row.bar,"OVERLAY",1,1,1,0.15)
        row.glint:SetPoint("TOPLEFT",1,-1); row.glint:SetPoint("TOPRIGHT",-1,-1); row.glint:SetHeight(1)
        row.bar:EnableMouse(false)
        -- Count text belongs to a higher frame layer than the native status bar.
        row.count=font(row.bar,10); row.count:SetJustifyH("RIGHT")
        self.rows[index]=row
        row:RegisterForClicks("LeftButtonUp","RightButtonUp")
        row:SetScript("OnEnter",function(self)
            if self.tip then
                GameTooltip:SetOwner(self,"ANCHOR_RIGHT"); GameTooltip:SetText(self.tip,nil,nil,nil,nil,true); GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave",function(self) if not GameTooltip.IsOwned or GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)
    end
    row:Show(); row.kind=kind
    row.text:Hide(); row.name:Hide(); row.bar:Hide(); row.count:Hide()
    row.band:Hide(); row.rule:Hide(); row.accent:Hide()
    if row.levelFrame then row.levelFrame:Hide();row.fold:Hide();row.star:Hide() end
    row:SetScript("OnClick",nil)
    row.tip,row.zoneKey,row.questID=nil,nil,nil
    return row
end

function UI:QuestHeading(app,r,q,collapsed,width,size,cache,playerLevel)
    if not r.levelFrame then
        r.fold=font(r,12);r.fold:SetWidth(12);r.fold:SetJustifyH("CENTER")
        r.levelFrame=CreateFrame("Frame",nil,r,"BackdropTemplate")
        r.levelFrame:SetBackdrop({bgFile=WHITE,edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=8,insets={left=2,right=2,top=2,bottom=2}})
        r.levelText=font(r.levelFrame,11);r.levelText:SetAllPoints();r.levelText:SetJustifyH("CENTER")
        r.star=button(r,"*",22,function() end)
    end
    local db=app.db
    local indent=db.groupByZone and 14 or 7
    local focused=app:ViewConfig().pinned[q.id]
    r.star:Show();r.star:ClearAllPoints();r.star:SetPoint("RIGHT",-1,0);r.star:SetHeight(size+12)
    r.star.label:SetTextColor(unpack(focused and db.colors.heading or db.colors.grey))
    r.star.label:SetText("*")
    r.star:SetScript("OnClick",function() app:ToggleWorkingQuest(q.id) end)
    tooltip(r.star,focused and "Remove from Working on and collapse this quest" or "Add to Working on: keep this quest expanded at the top")
    r.text:ClearAllPoints();r.text:SetHeight(size+7)
    if db.difficultyStyle=="off" then
        r.text:SetPoint("LEFT",indent,0);r.text:SetWidth(width-indent-27)
        r.text:SetText((collapsed and "+ " or "- ")..(q.level>0 and "["..q.level.."] " or "")..C.SafeText(q.title))
    else
        local value=cache[q.level]
        if not value then value={C.DifficultyColor(q.level)};cache[q.level]=value end
        local color=value[1]
        local label=q.level>0 and tostring(q.level) or "?"
        local badge=db.difficultyStyle=="badge"
        if not badge then label="["..label.."]" end
        local levelWidth=math.max(24,math.ceil(#label*math.max(10,size-1)*0.64)+10)
        r.fold:Show();r.fold:SetFont(STANDARD_TEXT_FONT,size,"OUTLINE");r.fold:SetHeight(size+7)
        r.fold:ClearAllPoints();r.fold:SetPoint("LEFT",indent,0);r.fold:SetText(collapsed and "+" or "-")
        r.fold:SetTextColor(unpack(db.colors.heading))
        r.levelFrame:Show();r.levelFrame:ClearAllPoints();r.levelFrame:SetPoint("LEFT",indent+14,0)
        r.levelFrame:SetSize(levelWidth,size+8)
        r.levelFrame:SetBackdropColor(0.025,0.035,0.045,badge and 0.88 or 0)
        r.levelFrame:SetBackdropBorderColor(color[1],color[2],color[3],badge and 0.85 or 0)
        r.levelText:SetFont(STANDARD_TEXT_FONT,math.max(10,size-1),"OUTLINE")
        r.levelText:SetText(label);r.levelText:SetTextColor(unpack(color))
        r.text:SetPoint("LEFT",indent+levelWidth+20,0);r.text:SetWidth(width-indent-levelWidth-47)
        r.text:SetText(C.SafeText(q.title))
        r.tip=r.tip.."\nQuest level: "..(q.level>0 and q.level or "unknown")
        if playerLevel and q.level>0 then r.tip=r.tip.."\nYour level: "..playerLevel.." (difference "..string.format("%+d",q.level-playerLevel)..")" end
        r.tip=r.tip..(value[2] and "\nDifficulty colour is relative to your character." or "\nDifficulty colour unavailable; neutral badge shown.")
    end
end

function UI:Render(app)
    if self.painting then return end
    self.painting=true
    local f,db=self.frame,app.db
    local size=db.fontSize
    local headerHeight=math.max(30,size+12)
    local footerHeight=math.max(14,size)
    if not db.shown then f:Hide(); self.painting=false; return end
    f:Show()
    local palette=db.colors
    f.bg:SetVertexColor(palette.background[1],palette.background[2],palette.background[3],db.opacity)
    f:SetWidth(db.width)
    self.lock.label:SetText(db.locked and "L" or "U")
    self.minimize.label:SetText(db.minimized and "+" or "-")
    self.title:SetText("Quest Partners")
    self.title:SetFont(STANDARD_TEXT_FONT,size,"OUTLINE")
    self.title:SetTextColor(unpack(palette.heading))
    self.title:SetWidth(math.max(76,db.width-193))
    self.headerRule:SetVertexColor(palette.heading[1],palette.heading[2],palette.heading[3],0.30)
    self.header:SetHeight(headerHeight)
    self.headerRule:ClearAllPoints()
    self.headerRule:SetPoint("TOPLEFT",7,-headerHeight+1); self.headerRule:SetPoint("TOPRIGHT",-7,-headerHeight+1)
    self.footer:SetFont(STANDARD_TEXT_FONT,math.max(10,size-2),"OUTLINE"); self.footer:SetHeight(footerHeight)
    self.searchBox:ClearAllPoints();self.searchBox:SetPoint("TOPLEFT",7,-headerHeight-22);self.searchBox:SetWidth(db.width-38)
    self.searchClear:ClearAllPoints();self.searchClear:SetPoint("LEFT",self.searchBox,"RIGHT",1,0)
    self.scroll.topInset=headerHeight+48; self.scroll.bottomInset=footerHeight+8
    self.scroll:ClearAllPoints()
    self.scroll:SetPoint("TOPLEFT",7,-self.scroll.topInset); self.scroll:SetPoint("BOTTOMRIGHT",-9,self.scroll.bottomInset)
    self.grip:SetShown(not db.locked and not db.minimized)
    if db.minimized then
        f:SetHeight(headerHeight); self.scroll:Hide(); self.footer:Hide(); self.scrollHint:Hide(); self.headerRule:Hide()
        self.scope:Hide(); self.statusHit:Hide()
        self.searchBox:Hide();self.searchClear:Hide()
        self.painting=false; return
    end
    self.scroll:Show(); self.footer:Show(); self.headerRule:Show()
    self.searchBox:Show();self.searchClear:Show()
    self.syncingSearch=true
    if self.searchBox:GetText()~=(app.searchText or "") then self.searchBox:SetText(app.searchText or "") end
    self.syncingSearch=false;self.searchHint:SetShown((app.searchText or "")=="")
    local width=db.width-19
    self.content:SetWidth(width)
    self.empty:SetWidth(width-6)
    local players=app:ViewPlayers()
    local viewDB=app:ViewConfig()
    self.scope:Show(); self.statusHit:Show()
    self.scope.label:SetText(viewDB.mode=="manual" and "Custom quests" or (viewDB.scope=="all" and "All quests" or "Shared quests"))
    local visible=C.Visible(players,viewDB,GetTime(),app.recentProgress)
    local filtered={}
    for _,q in ipairs(visible) do if C.MatchesSearch(q,players,app.searchText) then filtered[#filtered+1]=q end end
    visible=filtered
    local difficultyCache,playerLevel={},C.PlayerLevel()
    local y,n=0,0
    local viewTop=self.scroll:GetVerticalScroll()-40
    local viewBottom=self.scroll:GetVerticalScroll()+db.maxHeight-self.scroll.topInset-self.scroll.bottomInset+40
    local function row(kind,height)
        local at=y;y=y+height
        if at+height<viewTop or at>viewBottom then return nil end
        n=n+1
        local r=self:Row(n,kind)
        r:ClearAllPoints(); r:SetPoint("TOPLEFT",self.content,"TOPLEFT",0,-at)
        r:SetSize(width,height)
        return r
    end
    local function renderQuest(q,qi)
        local questID=q.id
        if qi>1 then y=y+db.questSpacing end
        local collapsed=app:IsQuestCollapsed(questID)
        local function questClick(frame,mouse)
            self.searchBox:ClearFocus()
            if mouse=="RightButton" then app.Features:OpenActions(app,questID,frame) else app:ToggleQuest(questID) end
        end
        local r=row("quest",size+14)
        if r then
        r.questID=q.id
        r.band:Show(); r.band:SetAllPoints(r)
        r.band:SetVertexColor(palette.heading[1],palette.heading[2],palette.heading[3],0.06)
        r.rule:Show(); r.rule:ClearAllPoints(); r.rule:SetPoint("TOPLEFT"); r.rule:SetPoint("TOPRIGHT"); r.rule:SetHeight(1)
        r.rule:SetVertexColor(palette.heading[1],palette.heading[2],palette.heading[3],0.34)
        r.accent:Show(); r.accent:ClearAllPoints(); r.accent:SetPoint("TOPLEFT",0,-1); r.accent:SetPoint("BOTTOMLEFT",0,1); r.accent:SetWidth(2)
        r.accent:SetVertexColor(palette.heading[1],palette.heading[2],palette.heading[3],0.70)
        r.text:Show(); r.text:SetFont(STANDARD_TEXT_FONT,size,"OUTLINE")
        r.text:SetTextColor(unpack(palette.heading))
        r.tip=C.SafeText(q.title).."\nClick to collapse or expand. Right-click for quest actions."
        self:QuestHeading(app,r,q,collapsed,width,size,difficultyCache,playerLevel)
        r:SetScript("OnClick",questClick)
        end
        if collapsed and db.summaries then
            local line=row("summary",size+5)
            if line then
            local summary,tip=app.Features:Summary(app,players,q);line.questID=questID
            line.text:Show(); line.text:SetFont(STANDARD_TEXT_FONT,math.max(10,size-1),"OUTLINE")
            line.text:ClearAllPoints(); line.text:SetPoint("LEFT",14,0); line.text:SetWidth(width-20); line.text:SetHeight(size+4)
            line.text:SetTextColor(unpack(palette.text)); line.text:SetText(summary); line.tip=tip
            line:SetScript("OnClick",questClick)
            end
        end
        if not collapsed then
            local count=math.max(1,#q.objectives)
            for oi=1,count do
                local obj=q.objectives[oi]
                local label=obj and C.SafeText(obj.text) or "Quest status"
                local o=row("objective",size+5)
                if o then
                o.text:Show(); o.text:SetFont(STANDARD_TEXT_FONT,math.max(10,size-1),"OUTLINE")
                o.text:ClearAllPoints(); o.text:SetPoint("LEFT",5,0); o.text:SetWidth(width-8); o.text:SetHeight(size+4)
                o.text:SetTextColor(palette.text[1]*0.91,palette.text[2]*0.91,palette.text[3]*0.91); o.text:SetText(label); o.tip=label
                end
                local behind
                local dense=db.compactParty and #players>=3
                local barHeight=dense and math.min(db.barHeight,math.max(10,size)) or db.barHeight
                for pi,p in ipairs(players) do
                    local line=row("progress",math.max(size+(dense and 2 or 4),barHeight+(dense and 1 or 3)))
                    if line then
                    line.questID=questID
                    behind=behind or (db.highlightBehind and C.Behind(players,questID,oi,GetTime()) or {})
                    local pq=p.quests and p.quests[questID]
                    local ratio,color,text=C.Progress(pq,oi,C.PeerStatus(p,GetTime()))
                    local col=palette[color]
                    local nameWidth=math.floor(math.min(142,width*0.36))
                    local barWidth=width-nameWidth-9
                    line.name:Show(); line.name:SetFont(STANDARD_TEXT_FONT,math.max(10,size-1),"OUTLINE")
                    line.name:ClearAllPoints(); line.name:SetPoint("LEFT",8,0); line.name:SetWidth(nameWidth-9); line.name:SetHeight(size+2)
                    line.name:SetText((behind[pi] and "* " or "")..C.SafeText(p.name))
                    line.name:SetTextColor(unpack(behind[pi] and palette.yellow or palette.text))
                    line.bar:Show(); line.bar:ClearAllPoints(); line.bar:SetPoint("LEFT",nameWidth+3,0)
                    line.bar:SetSize(barWidth,barHeight)
                    line.track:SetVertexColor(palette.track[1],palette.track[2],palette.track[3],db.barOpacity*0.72)
                    line.bar:SetStatusBarColor(col[1],col[2],col[3],db.barOpacity)
                    line.bar:SetValue(ratio)
                    line.fill:SetShown(ratio>0)
                    line.count:Show(); line.count:SetFont(STANDARD_TEXT_FONT,math.max(10,size-1),"OUTLINE")
                    line.count:ClearAllPoints(); line.count:SetPoint("RIGHT",line.bar,"RIGHT",-5,0)
                    line.count:SetWidth(barWidth-10); line.count:SetHeight(size+2)
                    line.count:SetText(C.SafeText(text))
                    line.count:SetTextColor(unpack(color=="grey" and palette.grey or palette.text))
                    line.tip=app.Features:SyncTip(app,p).."\n"..label.."\n"..C.SafeText(text)..(behind[pi] and "\nBehind another confirmed quest holder" or "")
                    end
                end
                y=y+3
            end
        end
        y=y+5
    end
    local working,others={},{}
    for _,q in ipairs(visible) do
        local target=viewDB.pinned[q.id] and working or others;target[#target+1]=q
    end
    local function section(title)
        local r=row("section",size+12)
        if r then
            r.band:Show();r.band:SetAllPoints();r.band:SetVertexColor(palette.heading[1],palette.heading[2],palette.heading[3],0.18)
            r.text:Show();r.text:SetFont(STANDARD_TEXT_FONT,size+1,"OUTLINE");r.text:ClearAllPoints()
            r.text:SetPoint("LEFT",5,0);r.text:SetSize(width-10,size+6);r.text:SetTextColor(unpack(palette.heading));r.text:SetText(title)
            r.tip="Use the star beside a quest to add or remove it. Working on stays expanded and follows your display filters."
        end
        y=y+4
    end
    if #working>0 then
        section("Working on ("..#working..")")
        for qi,q in ipairs(working) do renderQuest(q,qi) end
        if #others>0 then y=y+6;section("Other quests") end
    end
    if db.groupByZone then
        for gi,group in ipairs(C.Regions(others,db.sortMode,app.recentProgress)) do
            if gi>1 then y=y+5 end
            local key=group.key
            local regionCollapsed=viewDB.collapsedZones[key]
            if not app.demo and db.autoExpand then
                for _,q in ipairs(group.quests) do
                    if (app.autoExpanded[q.id] or 0)>GetTime() then regionCollapsed=false; break end
                end
            end
            local r=row("region",size+10)
            if r then
            r.zoneKey=key
            r.band:Show(); r.band:SetAllPoints(r)
            r.band:SetVertexColor(palette.heading[1],palette.heading[2],palette.heading[3],0.14)
            r.rule:Show(); r.rule:ClearAllPoints(); r.rule:SetPoint("BOTTOMLEFT"); r.rule:SetPoint("BOTTOMRIGHT"); r.rule:SetHeight(1)
            r.rule:SetVertexColor(palette.heading[1],palette.heading[2],palette.heading[3],0.55)
            r.text:Show(); r.text:SetFont(STANDARD_TEXT_FONT,size+1,"OUTLINE")
            r.text:ClearAllPoints(); r.text:SetPoint("LEFT",5,0); r.text:SetWidth(width-10); r.text:SetHeight(size+6)
            r.text:SetTextColor(unpack(palette.heading))
            r.text:SetText((regionCollapsed and "+ " or "- ")..C.SafeText(group.name).." ("..#group.quests..")")
            r.tip=C.SafeText(group.name).."\n"..#group.quests.." quests match your filters.\nClick to collapse or expand. Quests > Regions controls visibility."
            r:SetScript("OnClick",function()
                viewDB.collapsedZones[key]=not regionCollapsed
                if not app.demo then for _,q in ipairs(group.quests) do app.autoExpanded[q.id]=nil end end
                app:Change()
            end)
            end
            y=y+4
            if not regionCollapsed then
                for qi,q in ipairs(group.quests) do renderQuest(q,qi) end
            end
        end
    else
        for qi,q in ipairs(others) do renderQuest(q,qi) end
    end
    for i=n+1,#self.rows do self.rows[i]:Hide() end
    if #visible==0 then
        self.empty:Show(); self.empty:SetFont(STANDARD_TEXT_FONT,size,"OUTLINE"); self.empty:SetHeight((size+4)*3+8)
        self.empty:SetText((app.searchText or "")~="" and "No matching quests.\nClear search or check All/Shared\nand region filters." or C.Count(C.Catalogue(players))>0 and "No quests match the current filters.\nUse Quests or Quests > Regions.\nPartner status is shown below." or (#players>1 and "No confirmed shared quests to show.\nUse Quests to choose from either log.\nPartner status is shown below." or
            "No quests selected.\nAccept a quest or use Quests to choose.\nJoin a party to compare progress."))
        y=self.empty:GetHeight()+10
    else self.empty:Hide() end
    self.content:SetHeight(math.max(1,y))
    local overhead=self.scroll.topInset+self.scroll.bottomInset+2
    f:SetHeight(self.resizing and db.maxHeight or math.min(db.maxHeight,math.max(110,y+overhead)))
    local maximum=math.max(0,y-self.scroll:GetHeight())
    local previousScroll=self.scroll:GetVerticalScroll()
    self.scroll:SetVerticalScroll(math.min(maximum,previousScroll))
    self.footer:SetText(C.SafeText(app:StatusText()))
    self:UpdateScrollHint()
    self.painting=false
    if self.scroll:GetVerticalScroll()~=previousScroll then self:Render(app) end
end

function UI:Popup(title,width,height)
    local popup=CreateFrame("Frame",nil,UIParent,"BackdropTemplate")
    popup:SetSize(width,height); popup:SetFrameStrata("DIALOG"); popup:SetClampedToScreen(true)
    popup:SetPoint("TOPLEFT",self.frame,"TOPRIGHT",8,0)
    popup:EnableMouse(true)
    popup:SetBackdrop({bgFile=WHITE,edgeFile=WHITE,edgeSize=1})
    popup:SetBackdropColor(0.045,0.05,0.06,0.96); popup:SetBackdropBorderColor(0.36,0.33,0.24,0.9)
    local t=font(popup,13,{0.91,0.80,0.53}); t:SetPoint("TOPLEFT",12,-13); t:SetText(title)
    local close=button(popup,"x",24,function() popup:Hide() end,"Close")
    close:SetPoint("TOPRIGHT",-5,-5)
    return popup
end

function UI:ToggleOptions(app)
    app.Settings:Open(app)
end

function UI:ToggleQuests(app,tab)
    if self.questPopup and self.questPopup:IsShown() and (not tab or tab==self.manageTab) then
        self.questPopup:Hide(); return
    end
    if not self.questPopup then self:BuildManager(app) end
    self.manageTab=tab or self.manageTab or "quests"
    self:RefreshManager(app,true)
    self.questPopup:Show()
end

function UI:BuildManager(app)
    local p=self:Popup("Manage quests",380,440); self.questPopup=p
    self.questPage=CreateFrame("Frame",nil,p)
    self.questPage:SetPoint("TOPLEFT",0,-68); self.questPage:SetPoint("BOTTOMRIGHT")
    self.regionPage=CreateFrame("Frame",nil,p)
    self.regionPage:SetPoint("TOPLEFT",0,-68); self.regionPage:SetPoint("BOTTOMRIGHT")
    self.questTab=button(p,"Quests",78,function() self.manageTab="quests"; self:RefreshManager(app,true) end)
    self.questTab:SetPoint("TOPLEFT",10,-36)
    self.regionTab=button(p,"Regions",78,function() self.manageTab="regions"; self:RefreshManager(app,true) end)
    self.regionTab:SetPoint("LEFT",self.questTab,"RIGHT",7,0)
    local page=self.questPage
    self.allScope=button(page,"All quests",106,function() app:SetScope("all") end,"All quests in any known party log")
    self.allScope:SetPoint("TOPLEFT",10,-2)
    self.sharedScope=button(page,"Shared quests",120,function() app:SetScope("shared") end,"Your quests also held by at least one partner; solo shows your own log")
    self.sharedScope:SetPoint("LEFT",self.allScope,"RIGHT",8,0)
    self.autoCheck=checkbox(page,"Use automatic quest selection",10,-30,function(v)
        app:ViewConfig().mode=v and "auto" or "manual"; app:Change()
    end)
    local note=font(page,11,{0.71,0.76,0.78}); note:SetPoint("TOPLEFT",15,-60)
    note:SetText("Untick Automatic to choose individual quests.")
    self.collapseQuests=button(page,"Collapse others",120,function() self:SetQuestFolds(app,true) end,"Collapse other quests and keep Working on expanded")
    self.collapseQuests:SetPoint("TOPLEFT",10,-79)
    self.expandQuests=button(page,"Expand quests",120,function() self:SetQuestFolds(app,false) end)
    self.expandQuests:SetPoint("LEFT",self.collapseQuests,"RIGHT",8,0)
    local scroll=CreateFrame("ScrollFrame",nil,page,"UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",10,-110); scroll:SetPoint("BOTTOMRIGHT",-29,39)
    self.choiceContent=CreateFrame("Frame",nil,scroll); self.choiceContent:SetSize(330,1); scroll:SetScrollChild(self.choiceContent)
    local all=button(page,"Select all",84,function()
        local cfg=app:ViewConfig(); cfg.mode="manual"
        for id in pairs(C.Catalogue(app:ViewPlayers())) do cfg.selected[id]=true end
        app:Change()
    end); all:SetPoint("BOTTOMLEFT",10,8)
    local none=button(page,"Clear",64,function()
        local cfg=app:ViewConfig(); cfg.mode="manual"; cfg.selected={}; app:Change()
    end); none:SetPoint("LEFT",all,"RIGHT",5,0)
    self.restoreHidden=button(page,"Restore hidden",125,function()
        app:ViewConfig().hiddenQuests={}; app:Change()
    end,"Restore quests hidden through their right-click menu")
    self.restoreHidden:SetPoint("BOTTOMRIGHT",-10,8)

    page=self.regionPage
    self.groupCheck=checkbox(page,"Group quests by region",10,-4,function(v) app.db.groupByZone=v; app:Change() end)
    local regionNote=font(page,11,{0.71,0.76,0.78}); regionNote:SetPoint("TOPLEFT",15,-39)
    regionNote:SetText("Untick a region to hide it. Its quests keep syncing.")
    self.collapseAll=button(page,"Collapse all",100,function() self:SetAllRegions(app,"collapse") end)
    self.collapseAll:SetPoint("TOPLEFT",10,-60)
    self.expandAll=button(page,"Expand all",100,function() self:SetAllRegions(app,"expand") end)
    self.expandAll:SetPoint("LEFT",self.collapseAll,"RIGHT",6,0)
    local regionScroll=CreateFrame("ScrollFrame",nil,page,"UIPanelScrollFrameTemplate")
    regionScroll:SetPoint("TOPLEFT",10,-92); regionScroll:SetPoint("BOTTOMRIGHT",-29,39)
    self.regionContent=CreateFrame("Frame",nil,regionScroll); self.regionContent:SetSize(330,1)
    regionScroll:SetScrollChild(self.regionContent)
    self.showAll=button(page,"Show all",84,function() self:SetAllRegions(app,"show") end)
    self.showAll:SetPoint("BOTTOMLEFT",10,8)
    self.hideAll=button(page,"Hide all",84,function() self:SetAllRegions(app,"hide") end)
    self.hideAll:SetPoint("LEFT",self.showAll,"RIGHT",5,0)
    local regionHint=font(page,10,{0.65,0.72,0.73}); regionHint:SetPoint("BOTTOMRIGHT",-10,13); regionHint:SetText("Saved per character")
end

function UI:SetQuestFolds(app,collapsed)
    local cfg=app:ViewConfig()
    if collapsed then cfg.collapsed={} else
        for id in pairs(C.Catalogue(app:ViewPlayers())) do cfg.collapsed[id]=false end
    end
    if not app.demo then app.autoExpanded={} end
    app:Change()
end

function UI:RefreshManager(app,force)
    if not self.questPopup or (not force and not self.questPopup:IsShown()) then return end
    self.questPage:SetShown(self.manageTab~="regions")
    self.regionPage:SetShown(self.manageTab=="regions")
    self.questTab.label:SetTextColor(unpack(self.manageTab~="regions" and {1,1,0.94} or {0.74,0.71,0.62}))
    self.regionTab.label:SetTextColor(unpack(self.manageTab=="regions" and {1,1,0.94} or {0.74,0.71,0.62}))
    self:RefreshChoices(app); self:RefreshRegions(app)
end

function UI:SetAllRegions(app,action)
    local cfg=app:ViewConfig()
    if action=="show" then cfg.hiddenZones={}; app:Change(); return end
    if action=="expand" then cfg.collapsedZones={}; app:Change(); return end
    for _,group in ipairs(C.Regions(C.Catalogue(app:ViewPlayers()))) do
        if action=="collapse" then
            cfg.collapsedZones[group.key]=true
            if not app.demo then for _,q in ipairs(group.quests) do app.autoExpanded[q.id]=nil end end
        elseif action=="hide" then cfg.hiddenZones[group.key]=true end
    end
    app:Change()
end

function UI:RefreshRegions(app)
    local cfg=app:ViewConfig()
    self.groupCheck:SetChecked(app.db.groupByZone)
    self.collapseAll:SetEnabled(app.db.groupByZone); self.expandAll:SetEnabled(app.db.groupByZone)
    local groups=C.Regions(C.Catalogue(app:ViewPlayers()))
    for i,group in ipairs(groups) do
        local b=self.regionChoices[i]
        if not b then
            b=checkbox(self.regionContent,"",0,-(i-1)*30,function() end)
            b.label:SetWidth(270); b.label:SetHeight(26)
            b.fold=button(self.regionContent,"-",24,function() end)
            b.fold:SetPoint("TOPLEFT",302,-(i-1)*30-1)
            self.regionChoices[i]=b
        end
        local key=group.key
        b.zoneKey=key
        b.label:SetText(C.SafeText(group.name).." ("..#group.quests..")")
        b:SetChecked(not cfg.hiddenZones[key])
        b:SetScript("OnClick",function(self)
            cfg.hiddenZones[key]=not self:GetChecked() and true or nil; app:Change()
        end)
        b.fold.label:SetText(cfg.collapsedZones[key] and "+" or "-")
        b.fold:SetEnabled(app.db.groupByZone)
        b.fold:SetScript("OnClick",function()
            cfg.collapsedZones[key]=not cfg.collapsedZones[key]
            if not app.demo then for _,q in ipairs(group.quests) do app.autoExpanded[q.id]=nil end end
            app:Change()
        end)
        tooltip(b,C.SafeText(group.name).."\n"..#group.quests.." known quests. Untick to hide; this changes only your display.")
        tooltip(b.fold,"Collapse or expand this region")
        b:Show(); b.fold:Show()
    end
    for i=#groups+1,#self.regionChoices do self.regionChoices[i]:Hide(); self.regionChoices[i].fold:Hide() end
    self.regionContent:SetHeight(math.max(1,#groups*30))
end

function UI:RefreshChoices(app)
    local viewDB=app:ViewConfig()
    self.autoCheck:SetChecked(viewDB.mode~="manual")
    self.allScope.label:SetTextColor(unpack(viewDB.mode~="manual" and viewDB.scope=="all" and {1,1,0.94} or {0.74,0.71,0.62}))
    self.sharedScope.label:SetTextColor(unpack(viewDB.mode~="manual" and viewDB.scope~="all" and {1,1,0.94} or {0.74,0.71,0.62}))
    local catalogue=C.Catalogue(app:ViewPlayers())
    local keys=C.Keys(catalogue)
    for i,id in ipairs(keys) do
        local b=self.choices[i]
        if not b then
            b=checkbox(self.choiceContent,"",0,-(i-1)*27,function() end)
            b.label:SetWidth(300); b.label:SetHeight(24)
            self.choices[i]=b
        end
        local questID=id
        b.label:SetText((viewDB.hiddenQuests[id] and "[Hidden] " or "")..C.SafeText(catalogue[id].title))
        b:SetChecked(viewDB.selected[id] and true or false)
        b:SetEnabled(viewDB.mode=="manual")
        b:SetAlpha(viewDB.mode=="manual" and 1 or 0.45)
        b:SetScript("OnClick",function(self)
            viewDB.selected[questID]=self:GetChecked() and true or nil; app:Change()
        end)
        tooltip(b,C.SafeText(catalogue[id].title).."\nRegion: "..C.SafeText(C.ZoneName(catalogue[id])))
        b:Show()
    end
    for i=#keys+1,#self.choices do self.choices[i]:Hide() end
    self.choiceContent:SetHeight(math.max(1,#keys*27))
end
