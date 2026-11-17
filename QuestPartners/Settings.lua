local _,NS = ...
local C=NS.Core
local S={sliders={},swatches={}}
NS.Settings=S
local H=NS.UI.Helpers

local function percent(v) return math.floor(v*100+0.5).."%" end
local function label(parent,text,x,y,size)
    local t=H.font(parent,size or 12)
    t:SetPoint("TOPLEFT",x,y); t:SetText(text)
    return t
end

function S:CancelColorEdit()
    -- Another addon may currently own the shared picker. Invalidate only ours.
    self.activeColor=nil
end

function S:PickColor(app,key)
    if not ColorPickerFrame and C_AddOns and C_AddOns.LoadAddOn then
        pcall(C_AddOns.LoadAddOn,"Blizzard_ColorPicker")
    end
    if not ColorPickerFrame or not ColorPickerFrame.SetupColorPickerAndShow then
        app:Print("This client's colour picker is unavailable. Your current colours are preserved.")
        return
    end
    self:CancelColorEdit()
    local before=C.Copy(app.db.colors[key])
    local token={key=key}; self.activeColor=token
    local function apply(r,g,b)
        if self.activeColor~=token then return end
        app.db.colors[key]={r,g,b}
        app:Change()
    end
    local info={r=before[1],g=before[2],b=before[3],hasOpacity=false,
        swatchFunc=function() apply(ColorPickerFrame:GetColorRGB()) end,
        cancelFunc=function() apply(before[1],before[2],before[3]) end}
    ColorPickerFrame:SetupColorPickerAndShow(info)
end

function S:Build(app)
    local panel=CreateFrame("Frame","QuestPartnersSettingsPanel",UIParent)
    self.panel=panel; panel.name="Quest Partners"; panel:SetSize(580,660); panel:Hide()
    local scroll=CreateFrame("ScrollFrame",nil,panel,"UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",4,-4); scroll:SetPoint("BOTTOMRIGHT",-28,8)
    local body=CreateFrame("Frame",nil,scroll); body:SetSize(530,910); scroll:SetScrollChild(body)
    self.body=body
    local logo=body:CreateTexture(nil,"ARTWORK"); logo:SetTexture(C.LOGO)
    logo:SetSize(38,38); logo:SetPoint("TOPLEFT",12,-13); self.logo=logo
    label(body,"Quest Partners",62,-15,18)
    label(body,"Compact party quest progress  |  "..C.VERSION,62,-41,11)
    label(body,"Changes apply immediately and are saved for this character.",14,-73,11)
    label(body,"Readability",14,-102,14)
    label(body,"Colours",290,-102,14)
    local specs={
        {key="opacity",title="Background opacity",low=0,high=100,unit="percent",y=-132,
            hint="0% is invisible; 100% is solid. Text stays opaque."},
        {key="barOpacity",title="Bar opacity",low=30,high=100,unit="percent",y=-198,
            hint="Controls only the progress bars and their tracks."},
        {key="fontSize",title="Tracker font size",low=10,high=20,unit="px",y=-264,
            hint="Adjust region and quest titles, objectives, player names, counts and tracker status."},
        {key="barHeight",title="Bar height",low=10,high=22,unit="px",y=-330},
        {key="questSpacing",title="Space between quests",low=4,high=30,unit="px",y=-396}
    }
    for _,spec in ipairs(specs) do
        local entry=spec
        local t=label(body,"",14,entry.y,12)
        local hint=label(body,"",14,entry.y-19,10)
        hint:SetTextColor(0.69,0.74,0.76)
        local slider=CreateFrame("Slider",nil,body,"OptionsSliderTemplate")
        slider:SetPoint("TOPLEFT",18,entry.y-37); slider:SetSize(235,16); slider:SetOrientation("HORIZONTAL")
        slider:SetMinMaxValues(entry.low,entry.high); slider:SetValueStep(1); slider:SetObeyStepOnDrag(true)
        if slider.Low then slider.Low:SetText("") end
        if slider.High then slider.High:SetText("") end
        if slider.Text then slider.Text:SetText("") end
        slider:SetScript("OnValueChanged",function(_,value)
            if self.refreshing then return end
            value=math.floor(value+0.5)
            app.db[entry.key]=entry.unit=="percent" and value/100 or value
            app:Change()
        end)
        if entry.hint then H.tooltip(slider,entry.hint) end
        self.sliders[entry.key]={slider=slider,label=t,hint=hint,spec=entry}
    end
    local colorSpecs={{"red","Below 50%"},{"yellow","50% to incomplete"},{"green","Completed objective"},
        {"grey","Unknown / stale"},{"background","Panel background"},{"heading","Quest headings / dividers"},
        {"text","Names and counts"},{"track","Unfilled bar track"}}
    for i,spec in ipairs(colorSpecs) do
        local key=spec[1]
        local b=CreateFrame("Button",nil,body); b:SetSize(232,29); b:SetPoint("TOPLEFT",290,-128-(i-1)*37)
        local border=H.texture(b,"BACKGROUND",0.80,0.81,0.77,0.6); border:SetPoint("LEFT",0,0); border:SetSize(23,21)
        b.swatch=H.texture(b,"ARTWORK",1,1,1,1); b.swatch:SetPoint("LEFT",2,0); b.swatch:SetSize(19,17)
        local title=H.font(b,11); title:SetPoint("LEFT",31,0); title:SetWidth(197); title:SetHeight(24); title:SetText(spec[2])
        b:SetScript("OnClick",function() self:PickColor(app,key) end)
        H.tooltip(b,"Click to choose "..spec[2]:lower().." colour. Cancel restores the previous colour.")
        self.swatches[key]=b
    end
    label(body,"Display",14,-464,14)
    self.hideCheck=H.checkbox(body,"Hide when all holders are ready",10,-487,function(v) app.db.hideFinished=v; app:Change() end)
    H.tooltip(self.hideCheck,"Hide ready-to-turn-in quests when all relevant logs are fresh and every holder is ready. Turned-in-only history always disappears.")
    self.lockCheck=H.checkbox(body,"Lock panel position",286,-487,function(v) app.db.locked=v; app:Change() end)
    self.shownCheck=H.checkbox(body,"Show quest panel",10,-518,function(v) app.db.shown=v; app:Change() end)
    self.demoCheck=H.checkbox(body,"Demo example progress",286,-518,function(v) app.demo=v; app.db.shown=true; app:Change() end)
    self.groupCheck=H.checkbox(body,"Group quests by region",10,-549,function(v) app.db.groupByZone=v; app:Change() end)
    label(body,"Manage visibility via Quests > Regions",290,-555,10)
    self.autoExpandCheck=H.checkbox(body,"Expand on progress (15 seconds)",10,-580,function(v)
        app.db.autoExpand=v; app.autoExpanded={}; app:Change()
    end)
    H.tooltip(self.autoExpandCheck,"Starts collapsed each login. Item/kill/objective progress from you or a synced partner briefly opens the matching visible quest and region. Manually opening a collapsed quest keeps it open. Initial sync does not expand quests.")
    self.difficultyButton=H.button(body,"",232,function()
        local nextStyle={badge="level",level="off",off="badge"}
        app.db.difficultyStyle=nextStyle[app.db.difficultyStyle] or "badge";app:Change()
    end,"Click to cycle a coloured level badge, coloured level number only, or no difficulty colour. Uses your own character's quest difficulty colours.")
    self.difficultyButton:SetPoint("TOPLEFT",286,-581)
    label(body,"Party progress and notifications",14,-621,14)
    self.summaryCheck=H.checkbox(body,"Collapsed progress summaries",10,-648,function(v) app.db.summaries=v; app:Change() end)
    self.behindCheck=H.checkbox(body,"Highlight players behind",286,-648,function(v) app.db.highlightBehind=v; app:Change() end)
    H.tooltip(self.behindCheck,"An amber name and * mark the lowest confirmed progress when another quest holder is ahead. Stale/offline/unknown data is excluded.")
    self.compactCheck=H.checkbox(body,"Compact parties of 3-5",10,-679,function(v) app.db.compactParty=v; app:Change() end)
    H.tooltip(self.compactCheck,"Summarise larger parties on collapsed quests and use denser individual bars when expanded. Hover for every player's status.")
    self.sortButton=H.button(body,"",232,function()
        local modes=app.Features.SORTS
        for i,mode in ipairs(modes) do if app.db.sortMode==mode then app.db.sortMode=modes[i%#modes+1]; break end end
        app:Change()
    end,"Click to cycle Quest level, Quest title, Recent progress and Ready to turn in. Sorting applies inside each region; level/title/ID break ties consistently.")
    self.sortButton:SetPoint("TOPLEFT",286,-680)
    self.bubbleCheck=H.checkbox(body,"Objective speech bubbles",10,-710,function(v)
        app.db.bubbles=v; app.Features:Tick(app); app:Change()
    end)
    self.partyNoticeCheck=H.checkbox(body,"Everyone-ready notification",286,-710,function(v)
        app.db.partyNotices=v; app.Features:Tick(app); app:Change()
    end)
    self.soundCheck=H.checkbox(body,"Notification sound",10,-741,function(v) app.db.noticeSound=v; app:Change() end)
    self.testBubble=H.button(body,"Test speech bubble",190,function()
        app.Features:AddNotice(app,"test",app:Players()[1].name,{id=0,title="Example quest"},{"Example objective completed - preview only"})
        app.Features:Tick(app)
    end,"Preview locally using your character name; no chat message is sent")
    self.testBubble:SetPoint("TOPLEFT",286,-742)
    label(body,"Bubbles appear on your screen for 7 seconds; click to dismiss.",14,-783,11)
    label(body,"Initial sync and reconnection establish a baseline without old notifications.",14,-803,10)
    self.resetAppearance=H.button(body,"Restore appearance",155,function()
        self:CancelColorEdit(); app:ResetAppearance()
    end,"Restore default colours, opacity, font, bar height and spacing. Keep quest selection and position.")
    self.resetAppearance:SetPoint("TOPLEFT",12,-842)
    local position=H.button(body,"Reset position",124,function() app:Slash("reset") end,"Reset the window position and size; preserve colours and opacity")
    position:SetPoint("LEFT",self.resetAppearance,"RIGHT",8,0)
    local sync=H.button(body,"Sync now",90,function() app:ForceSync() end,"Request fresh party quest progress")
    sync:SetPoint("LEFT",position,"RIGHT",8,0)
    label(body,"Demo data is fictional. Actual character names are used when available.",14,-882,10)

    panel.OnCommit=function() end -- Controls already commit their values immediately.
    panel.OnDefault=function() self:CancelColorEdit(); app:ResetAppearance() end
    panel.OnRefresh=function() self:Refresh(app) end
    panel.refresh=panel.OnRefresh
    panel.default=panel.OnDefault
    panel:SetScript("OnShow",function() self:Refresh(app) end)
    self:Register(app)
    self:Refresh(app)
end

function S:Register(app)
    if self.category or self.legacy or not self.panel then return end
    local panel=self.panel
    -- Retry on later ADDON_LOADED events if the client loads Settings on demand.
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local ok,category=pcall(function()
            local c=Settings.RegisterCanvasLayoutCategory(panel,"Quest Partners")
            Settings.RegisterAddOnCategory(c)
            return c
        end)
        if ok then self.category=category else self.registrationError=tostring(category) end
    elseif InterfaceOptions_AddCategory then
        local ok,err=pcall(InterfaceOptions_AddCategory,panel)
        if ok then self.legacy=true else self.registrationError=tostring(err) end
    end
end

function S:Refresh(app)
    if not self.panel or self.refreshing then return end
    self.refreshing=true
    for key,s in pairs(self.sliders) do
        local value=app.db[key]
        local display=s.spec.unit=="percent" and math.floor(value*100+0.5) or value
        s.slider:SetValue(display)
        s.label:SetText(s.spec.title..": "..display..(s.spec.unit=="percent" and "%" or " px"))
        if key=="opacity" then s.hint:SetText(percent(1-value).." transparent")
        elseif key=="barOpacity" then s.hint:SetText("Names and counts remain fully opaque")
        elseif key=="fontSize" then s.hint:SetText("Quest, region and progress text")
        else s.hint:SetText("") end
    end
    for key,b in pairs(self.swatches) do b.swatch:SetVertexColor(unpack(app.db.colors[key])) end
    self.hideCheck:SetChecked(app.db.hideFinished); self.lockCheck:SetChecked(app.db.locked)
    self.shownCheck:SetChecked(app.db.shown); self.demoCheck:SetChecked(app.demo and true or false)
    self.groupCheck:SetChecked(app.db.groupByZone)
    self.autoExpandCheck:SetChecked(app.db.autoExpand)
    self.difficultyButton.label:SetText("Level colour: "..({badge="Badge",level="Number only",off="Off"})[app.db.difficultyStyle])
    self.summaryCheck:SetChecked(app.db.summaries); self.behindCheck:SetChecked(app.db.highlightBehind)
    self.compactCheck:SetChecked(app.db.compactParty); self.bubbleCheck:SetChecked(app.db.bubbles)
    self.partyNoticeCheck:SetChecked(app.db.partyNotices); self.soundCheck:SetChecked(app.db.noticeSound)
    self.sortButton.label:SetText("Sort: "..app.Features.SORT_LABELS[app.db.sortMode])
    self.testBubble:SetEnabled(app.db.bubbles)
    self.refreshing=false
end

function S:Open(app)
    if app.UI.questPopup then app.UI.questPopup:Hide() end
    if app.Features.actions then app.Features.actions:Hide() end
    if self.category and Settings and Settings.OpenToCategory then
        local ok=pcall(Settings.OpenToCategory,self.category:GetID())
        if ok then self:Refresh(app); return end
    elseif self.legacy and InterfaceOptionsFrame_OpenToCategory then
        local ok=pcall(InterfaceOptionsFrame_OpenToCategory,self.panel)
        if ok then self:Refresh(app); return end
    end
    -- Appearance remains accessible even when a client omits native registration.
    if not self.fallback then
        self.fallback=app.UI:Popup("Quest Partners settings",580,690)
        self.panel:SetParent(self.fallback); self.panel:ClearAllPoints()
        self.panel:SetPoint("TOPLEFT",0,-25); self.panel:SetPoint("BOTTOMRIGHT",0,0)
    end
    self.fallback:Show(); self.panel:Show(); self:Refresh(app)
end
