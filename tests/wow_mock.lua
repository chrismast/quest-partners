-- Minimal WoW API simulator. It checks addon behaviour, not client compatibility.
unpack = unpack or table.unpack
MOCK = {time=100,frames={},messages={},chat={},party={},log={},events={},realm="TestRealm",name="Tester"}
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
LE_PARTY_CATEGORY_INSTANCE = 2
UIParent = {width=1920,height=1080}
local methods={}
function methods:SetSize(w,h) assert(type(w)=="number" and type(h)=="number"); self.width=w; self.height=h end
function methods:SetWidth(w) self.width=w end
function methods:SetHeight(h) self.height=h end
function methods:GetWidth() return self.width or 300 end
function methods:GetHeight()
    if self.kind=="ScrollFrame" and self.parent and self.parent==QuestPartnersFrame then
        return self.parent:GetHeight()-(self.topInset or 34)-(self.bottomInset or 22)
    end
    return self.height or 100
end
function methods:SetPoint(...) self.point={...} end
function methods:ClearAllPoints() self.point=nil end
function methods:SetAllPoints(parent) self.allPoints=parent or self.parent end
function methods:SetTexture(s) self.texture=s end
function methods:SetColorTexture(...) self.color={...} end
function methods:SetVertexColor(...) self.color={...} end
function methods:SetTextColor(...) self.textColor={...} end
function methods:SetFont(path,size,flags) assert(path and size>=8); self.fontSize=size end
function methods:SetText(s)
    assert(type(s)=="string" or type(s)=="number");local old=self.text;self.text=tostring(s)
    if self.kind=="EditBox" and old~=self.text and self.scripts and self.scripts.OnTextChanged then self.scripts.OnTextChanged(self,false) end
end
function methods:GetText() return self.text end
function methods:SetScript(event,fn) self.scripts=self.scripts or {}; self.scripts[event]=fn end
function methods:GetScript(event) return self.scripts and self.scripts[event] end
function methods:Show()
    local was=self.shown; self.shown=true
    if not was and self.scripts and self.scripts.OnShow then self.scripts.OnShow(self) end
end
function methods:Hide()
    local was=self.shown; self.shown=false
    if was and self.scripts and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function methods:IsShown() return self.shown~=false end
function methods:SetShown(v) if v then self:Show() else self:Hide() end end
function methods:SetChecked(v) self.checked=v end
function methods:GetChecked() return self.checked end
function methods:SetEnabled(v) self.enabled=v end
function methods:SetValue(v)
    self.value=v
    if self.kind=="StatusBar" and self.statusTexture then
        self.statusTexture:SetSize((self.width or 0)*v,self.height or 1)
    end
    if self.scripts and self.scripts.OnValueChanged then self.scripts.OnValueChanged(self,v) end
end
function methods:GetValue() return self.value end
function methods:SetScrollChild(child) self.child=child end
function methods:SetVerticalScroll(value) self.scroll=value end
function methods:GetVerticalScroll() return self.scroll or 0 end
function methods:GetLeft() return self.left or 36 end
function methods:GetTop() return self.top or 900 end
function methods:RegisterEvent(event) self.events=self.events or {}; self.events[event]=true end
function methods:SetBackdrop(t) self.backdrop=t end
function methods:SetBackdropColor(...) self.color={...} end
function methods:SetBackdropBorderColor(...) self.border={...} end
function methods:SetStatusBarTexture(path)
    self.statusTexture=self:CreateTexture(nil,"ARTWORK"); self.statusTexture:SetTexture(path)
end
function methods:GetStatusBarTexture() return self.statusTexture end
function methods:SetStatusBarColor(...) self.statusColor={...}; self.statusTexture:SetVertexColor(...) end
function methods:SetParent(parent) self.parent=parent end
local noops={"SetJustifyH","SetJustifyV","SetShadowColor","SetShadowOffset","SetFrameStrata","SetClampedToScreen",
 "SetMovable","SetResizable","SetResizeBounds","EnableMouse","RegisterForDrag","EnableMouseWheel",
 "RegisterForClicks","SetMinMaxValues","SetValueStep","SetObeyStepOnDrag","SetOrientation","SetAlpha",
 "StartMoving","StopMovingOrSizing","StartSizing","SetOwner","SetAutoFocus","SetMaxLetters","SetTextInsets","ClearFocus"}
for _,name in ipairs(noops) do methods[name]=function() end end
local function object(kind,name,parent)
    local o=setmetatable({kind=kind,name=name,parent=parent,shown=true}, {__index=methods})
    MOCK.frames[#MOCK.frames+1]=o
    if name then _G[name]=o end
    return o
end
function methods:CreateTexture() return object("Texture",nil,self) end
function methods:CreateFontString() return object("FontString",nil,self) end
function CreateFrame(kind,name,parent,template) return object(kind,name,parent) end
GameTooltip=object("Tooltip")
ColorPickerFrame=object("ColorSelect")
function ColorPickerFrame:SetupColorPickerAndShow(info)
    self.info=info; self.r,self.g,self.b=info.r,info.g,info.b; self:Show()
end
function ColorPickerFrame:GetColorRGB() return self.r,self.g,self.b end
Settings={
 RegisterCanvasLayoutCategory=function(panel,name)
    assert(panel.OnCommit and panel.OnDefault and panel.OnRefresh)
    MOCK.category={panel=panel,name=name,GetID=function() return 7 end}
    return MOCK.category
 end,
 RegisterAddOnCategory=function(category) MOCK.registeredCategory=category end,
 OpenToCategory=function(id)
    assert(id==7); MOCK.openedCategory=id; MOCK.category.panel:Show()
 end
}
function InterfaceOptions_AddCategory(panel) MOCK.legacyPanel=panel end
function InterfaceOptionsFrame_OpenToCategory(panel) MOCK.legacyOpened=panel; panel:Show() end
DEFAULT_CHAT_FRAME={AddMessage=function(_,s) MOCK.chat[#MOCK.chat+1]=s end}
SlashCmdList={}
function GetTime() return MOCK.time end
function UnitLevel(unit) return unit=="player" and (MOCK.level or 17) or 1 end
function GetQuestGreenRange() return MOCK.greenRange or 5 end
function GetServerTime() return 1794700000 end
function GetBuildInfo() return "1.60.1","70938","Nov 12 2026",16001 end
function GetRealmName() return MOCK.realm end
function GetNormalizedRealmName() return MOCK.realm end
function UnitFullName(unit)
    if unit=="player" then return MOCK.name,MOCK.forever and MOCK.surname or MOCK.realm end
    local p=MOCK.party[unit]
    if p then return p.name,MOCK.forever and p.surname or (p.realm or MOCK.realm) end
end
function RegionalUniqueNamesEnabled() return MOCK.forever and true or false end
function GetUnitName(unit,showServerName)
    local first,second=UnitFullName(unit)
    if not first then return nil end
    if MOCK.forever then return first..(second and second~="" and " "..second or "") end
    return first..(showServerName and second and "-"..second or "")
end
function MOCK.Sender()
    return MOCK.forever and GetUnitName("player") or (MOCK.name.."-TestRealm")
end
function UnitExists(unit) return MOCK.party[unit]~=nil end
function UnitIsConnected(unit) return MOCK.party[unit] and MOCK.party[unit].online~=false end
function IsInRaid() return MOCK.raid or false end
function IsInGroup(category)
    if category==LE_PARTY_CATEGORY_INSTANCE then return MOCK.instance or false end
    return next(MOCK.party)~=nil
end
C_QuestLog={
 GetNumQuestLogEntries=function() return #MOCK.log end,
 GetInfo=function(i) return MOCK.log[i] end,
 GetHeaderIndexForQuest=function(id)
    local header
    for i,q in ipairs(MOCK.log) do
        if q.isHeader then header=i elseif q.questID==id then return header end
    end
 end,
 GetQuestObjectives=function(id)
    for _,q in ipairs(MOCK.log) do if q.questID==id then return q.objectives end end
 end,
 IsComplete=function(id)
    for _,q in ipairs(MOCK.log) do if q.questID==id then return q.complete or false end end
    return false
 end,
 IsFailed=function(id) return false end
}
C_ChatInfo={
 RegisterAddonMessagePrefix=function(prefix) MOCK.prefix=prefix; return 0 end,
 SendAddonMessage=function(prefix,message,channel)
    assert(#message<=254,"Oversize message")
    assert(channel=="PARTY" or channel=="INSTANCE_CHAT","Unexpected channel")
    if MOCK.sendResult then return MOCK.sendResult end
    MOCK.messages[#MOCK.messages+1]={prefix=prefix,message=message,channel=channel}
    return 0
 end
}
function MOCK.Fire(event,...)
    for _,frame in ipairs(MOCK.frames) do
        if frame.events and frame.events[event] and frame.scripts.OnEvent then frame.scripts.OnEvent(frame,event,...) end
    end
end
function MOCK.Tick(seconds)
    local ticks=math.ceil(seconds/0.25)
    for i=1,ticks do
        MOCK.time=MOCK.time+0.25
        for _,frame in ipairs(MOCK.frames) do
            if frame.scripts and frame.scripts.OnUpdate then frame.scripts.OnUpdate(frame,0.25) end
        end
    end
end
function MOCK.Load(name,ns,source)
    local fn,err=loadstring(source,"@"..name)
    assert(fn,err); fn("QuestPartners",ns)
end
