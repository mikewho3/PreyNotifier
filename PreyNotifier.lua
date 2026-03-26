local PreyAddon = CreateFrame("Frame")
local isEnabled = true
local lastAlertTime = 0 
local lastEchoAlertTime = 0
local isHuntComplete = false
local isFlashSuppressed = false
local defaultScreenFlash = "1"
local isHuntActiveCached = false

-- Forward Declarations
local UpdateTargetList
local UpdateDebuffs
local UpdateProgressBar
local CustomTracker
local ApplyAmbushWarningStyle
local UIFrame

local AmbushGraphicOptions = {
    { key = "sharp_blood", text = "Sharp Weapons w/Blood", texture = "ambushed_test.tga", glow = "ambushed_test_glow.tga", selectable = true },
    { key = "ambushed_shield", text = "Bloody Words on Shield", texture = "ambushed2.tga", glow = "ambushed2_glow.tga", selectable = true },
    { key = "placeholder2", text = "Placeholder2", texture = "placeholder2.tga", glow = "placeholder2_glow.tga", selectable = false },
    { key = "placeholder3", text = "Placeholder3", texture = "placeholder3.tga", glow = "placeholder3_glow.tga", selectable = false },
}

local function GetAmbushGraphicOption(styleKey)
    for _, option in ipairs(AmbushGraphicOptions) do
        if option.key == styleKey then
            return option
        end
    end
    return AmbushGraphicOptions[1]
end

local ValidHuntZones = {

    [2395] = true, -- Eversong Woods
    [2437] = true, -- Zul'Aman
	[2536] = true, -- Atal'aman
    [2405] = true, -- Voidstorm
	[2444] = true, -- Slayer's Rise
    [2576] = true, -- The Den - Harandar
    [2413] = true, -- Harandar
}

local function IsInHuntZone()
    local mapID = C_Map.GetBestMapForUnit("player")
    if mapID and ValidHuntZones[mapID] then
        return true
    end
    return false
end

local function FindPlayerDebuff(spellName)
    if not C_UnitAuras then return nil end
    local i = 1
    while true do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HARMFUL")
        if not aura then break end
        
        -- Use pcall to safely compare the name, avoiding crashes from Blizzard's "Secret/Private" auras
        local success, isMatch = pcall(function() return aura.name == spellName end)
        if success and isMatch then
            return aura
        end
        i = i + 1
    end
    
    -- Also check HELPFUL auras, as Blizzard sometimes categorizes zone mechanics as buffs internally
    i = 1
    while true do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not aura then break end
        
        local success, isMatch = pcall(function() return aura.name == spellName end)
        if success and isMatch then
            return aura
        end
        i = i + 1
    end
    return nil
end

local function IsHuntActive()
    local inZone = IsInHuntZone()
    if not inZone then 
        isHuntActiveCached = false
        return false 
    end
    
    local hasQuest = PreyNotifierDB and PreyNotifierDB["_PrimaryTarget"]
    if not hasQuest then
        isHuntActiveCached = false
        return false
    end
    
    local hasDebuff = FindPlayerDebuff("Bloodsworn")
    if hasDebuff then
        isHuntActiveCached = true
        return true
    end
    
    -- Edge case: Auras can drop on death or become restricted to read when entering combat.
    -- If we are in the zone with the quest, and were previously active, assume we still are!
    if isHuntActiveCached and (InCombatLockdown() or UnitIsDeadOrGhost("player")) then
        return true
    end
    
    isHuntActiveCached = false
    return false
end

local function UpdateTargetButton()
    if InCombatLockdown() then return end
    if not PreyNotifierDB then return end
    
    local btn = _G["PreyNotifierTargetBtn"]
    if not btn then return end

    local prim = PreyNotifierDB["_PrimaryTarget"]
    
    -- Dynamically construct Trap Macro depending on primary target
    local trapMacro = ""
    if prim then
        trapMacro = "/targetexact " .. prim .. "\n/use Disarmed Trap\n/run if GetItemCount(\"Disarmed Trap\") == 0 then print(\"|cffFF0000PreyNotifier: ERROR> No Traps are available in Bags.|r\") end"
    else
        trapMacro = "/use Disarmed Trap\n/run if GetItemCount(\"Disarmed Trap\") == 0 then print(\"|cffFF0000PreyNotifier: ERROR> No Traps are available in Bags.|r\") end"
    end
    btn:SetAttribute("macrotext3", trapMacro)

    btn:Show() -- Ensure the frame is active so Alpha can control its visual state

    -- Visually "hide" the button without functionally breaking the keybinds via Hide()
    if not IsHuntActive() or PreyNotifierDB["_ShowTargetBtn"] == false then
        btn:SetAlpha(0)
        btn:EnableMouse(false)
    else
        btn:SetAlpha(1)
        btn:EnableMouse(true)
    end
end

-- HELPER COMMAND: Type /pnzone to get your current Map ID
SLASH_PREYZONE1 = "/pnzone"
SlashCmdList["PREYZONE"] = function()
    local mapID = C_Map.GetBestMapForUnit("player")
    if mapID then
        local mapInfo = C_Map.GetMapInfo(mapID)
        local mapName = mapInfo and mapInfo.name or "Unknown Zone"
        print("|cff00FF00PreyNotifier:|r You are in |cffFFFF00" .. mapName .. "|r (Map ID: |cff00FFFF" .. mapID .. "|r)")
    else
        print("|cffFF0000PreyNotifier:|r Could not determine Map ID.")
    end
end

-- ==========================================
-- GLOBAL KEYBINDINGS
-- ==========================================
_G["BINDING_CATEGORY_PREYNOTIFIER"] = "PreyNotifier"
_G["BINDING_HEADER_PREYNOTIFIER"] = "PreyNotifier Macros"
_G["BINDING_NAME_CLICK PreyNotifierTargetBtn:LeftButton"] = "Target Primary Prey"
_G["BINDING_NAME_CLICK PreyNotifierTargetBtn:MiddleButton"] = "Use Disarmed Trap"
_G["BINDING_NAME_CLICK PreyNotifierEchoBtn:LeftButton"] = "Target Echo of Predation"

-- ==========================================
-- BLIZZARD OPTIONS MENU INTEGRATION
-- ==========================================
-- 1. Create a blank frame for the Blizzard menu
local OptionsPanel = CreateFrame("Frame")
OptionsPanel.name = "PreyNotifier"

-- 2. Add a Title
local Title = OptionsPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
Title:SetPoint("TOPLEFT", 16, -16)
Title:SetText("PreyNotifier")

local SubTitle = OptionsPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
SubTitle:SetPoint("TOPLEFT", Title, "BOTTOMLEFT", 0, -8)
SubTitle:SetText("Custom Hunt Tracker & Nightmare Difficulty Tools.")

-- 3. Create the "Open Settings" Button
local OpenMenuBtn = CreateFrame("Button", nil, OptionsPanel, "UIPanelButtonTemplate")
OpenMenuBtn:SetSize(200, 30)
OpenMenuBtn:SetPoint("TOPLEFT", SubTitle, "BOTTOMLEFT", 0, -20)
OpenMenuBtn:SetText("Open PreyNotifier Settings")

OpenMenuBtn:SetScript("OnClick", function()
    -- Close the Blizzard settings window so ours doesn't get buried
    HideUIPanel(SettingsPanel) 
    
    -- Open your custom UI window
    if InCombatLockdown() then
        print("|cffFF0000PreyNotifier:|r Cannot open menu while in combat!")
    else
        UIFrame:Show()
    end
end)

-- 4. Register it with the modern WoW Settings API
local category = Settings.RegisterCanvasLayoutCategory(OptionsPanel, OptionsPanel.name)
Settings.RegisterAddOnCategory(category)


-- ==========================================
-- 1. VISUAL INTERFACE (GUI) SETUP
-- ==========================================
UIFrame = CreateFrame("Frame", "PreyNotifierUI", UIParent, "BasicFrameTemplateWithInset")
UIFrame:SetFrameStrata("DIALOG")
UIFrame:SetSize(480, 500) 
UIFrame:SetPoint("CENTER")
UIFrame:SetMovable(true)
UIFrame:EnableMouse(true)
UIFrame:RegisterForDrag("LeftButton")
UIFrame:SetScript("OnDragStart", UIFrame.StartMoving)
UIFrame:SetScript("OnDragStop", UIFrame.StopMovingOrSizing)
UIFrame:Hide()

-- Window Title
UIFrame.title = UIFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
UIFrame.title:SetPoint("CENTER", UIFrame.TitleBg, "CENTER", 0, 0)
UIFrame.title:SetText("PreyNotifier")

-- ==========================================
-- TABS SETUP
-- ==========================================
local Tab1Btn = CreateFrame("Button", nil, UIFrame, "UIPanelButtonTemplate")
Tab1Btn:SetSize(80, 22)
Tab1Btn:SetPoint("TOPLEFT", UIFrame, "TOPLEFT", 12, -30)
Tab1Btn:SetText("Prey List")

local Tab2Btn = CreateFrame("Button", nil, UIFrame, "UIPanelButtonTemplate")
Tab2Btn:SetSize(80, 22)
Tab2Btn:SetPoint("LEFT", Tab1Btn, "RIGHT", 5, 0)
Tab2Btn:SetText("Options")

local Tab3Btn = CreateFrame("Button", nil, UIFrame, "UIPanelButtonTemplate")
Tab3Btn:SetSize(80, 22)
Tab3Btn:SetPoint("LEFT", Tab2Btn, "RIGHT", 5, 0)
Tab3Btn:SetText("Sound")

local Tab4Btn = CreateFrame("Button", nil, UIFrame, "UIPanelButtonTemplate")
Tab4Btn:SetSize(80, 22)
Tab4Btn:SetPoint("LEFT", Tab3Btn, "RIGHT", 5, 0)
Tab4Btn:SetText("Keybinds")

local PreyListTab = CreateFrame("Frame", nil, UIFrame)
PreyListTab:SetPoint("TOPLEFT", UIFrame, "TOPLEFT", 0, -60)
PreyListTab:SetPoint("BOTTOMRIGHT", UIFrame, "BOTTOMRIGHT", 0, 0)

local OptionsTab = CreateFrame("Frame", nil, UIFrame)
OptionsTab:SetPoint("TOPLEFT", UIFrame, "TOPLEFT", 0, -60)
OptionsTab:SetPoint("BOTTOMRIGHT", UIFrame, "BOTTOMRIGHT", 0, 0)
OptionsTab:Hide()

local OptionsScrollFrame = CreateFrame("ScrollFrame", "PreyNotifierOptionsScrollFrame", OptionsTab, "UIPanelScrollFrameTemplate")
OptionsScrollFrame:SetPoint("TOPLEFT", OptionsTab, "TOPLEFT", 8, -8)
OptionsScrollFrame:SetPoint("BOTTOMRIGHT", OptionsTab, "BOTTOMRIGHT", -36, 8)

local OptionsContent = CreateFrame("Frame", nil, OptionsScrollFrame)
OptionsContent:SetSize(420, 800)
OptionsScrollFrame:SetScrollChild(OptionsContent)

local SoundTab = CreateFrame("Frame", nil, UIFrame)
SoundTab:SetPoint("TOPLEFT", UIFrame, "TOPLEFT", 0, -60)
SoundTab:SetPoint("BOTTOMRIGHT", UIFrame, "BOTTOMRIGHT", 0, 0)
SoundTab:Hide()

local KeybindsTab = CreateFrame("Frame", nil, UIFrame)
KeybindsTab:SetPoint("TOPLEFT", UIFrame, "TOPLEFT", 0, -60)
KeybindsTab:SetPoint("BOTTOMRIGHT", UIFrame, "BOTTOMRIGHT", 0, 0)
KeybindsTab:Hide()

Tab1Btn:SetScript("OnClick", function()
    PreyListTab:Show()
    OptionsTab:Hide()
    SoundTab:Hide()
    KeybindsTab:Hide()
    Tab1Btn:LockHighlight()
    Tab2Btn:UnlockHighlight()
    Tab3Btn:UnlockHighlight()
    Tab4Btn:UnlockHighlight()
end)

Tab2Btn:SetScript("OnClick", function()
    PreyListTab:Hide()
    OptionsTab:Show()
    OptionsScrollFrame:SetVerticalScroll(0)
    SoundTab:Hide()
    KeybindsTab:Hide()
    Tab1Btn:UnlockHighlight()
    Tab2Btn:LockHighlight()
    Tab3Btn:UnlockHighlight()
    Tab4Btn:UnlockHighlight()
end)

Tab3Btn:SetScript("OnClick", function()
    PreyListTab:Hide()
    OptionsTab:Hide()
    SoundTab:Show()
    KeybindsTab:Hide()
    Tab1Btn:UnlockHighlight()
    Tab2Btn:UnlockHighlight()
    Tab3Btn:LockHighlight()
    Tab4Btn:UnlockHighlight()
end)

Tab4Btn:SetScript("OnClick", function()
    PreyListTab:Hide()
    OptionsTab:Hide()
    SoundTab:Hide()
    KeybindsTab:Show()
    Tab1Btn:UnlockHighlight()
    Tab2Btn:UnlockHighlight()
    Tab3Btn:UnlockHighlight()
    Tab4Btn:LockHighlight()
end)
Tab1Btn:LockHighlight() -- Default to tab 1

-- ==========================================
-- TAB 1: PREY LIST CONTENT
-- ==========================================

-- Text Input Box
local InputBox = CreateFrame("EditBox", nil, PreyListTab, "InputBoxTemplate")
InputBox:SetPoint("TOPLEFT", 25, -10)
InputBox:SetSize(190, 25)
InputBox:SetAutoFocus(false)

-- Add Target Button
local AddButton = CreateFrame("Button", nil, PreyListTab, "UIPanelButtonTemplate")
AddButton:SetPoint("LEFT", InputBox, "RIGHT", 10, 0)
AddButton:SetSize(50, 22)
AddButton:SetText("Add")

-- ==========================================
-- TAB 2: OPTIONS CONTENT
-- ==========================================
local OptionsHeader = OptionsContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
OptionsHeader:SetPoint("TOPLEFT", 20, -15)
OptionsHeader:SetText("Bar/Button only displays in the Prey Zone")

-- Timer Slider Label
local SliderLabel = OptionsContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
SliderLabel:SetPoint("TOPLEFT", OptionsHeader, "BOTTOMLEFT", 0, -15) 
SliderLabel:SetText("Alert Cooldown (Seconds):")

-- The Cooldown Slider
local CooldownSlider = CreateFrame("Slider", "PreyNotifierCooldownSlider", OptionsContent, "OptionsSliderTemplate")
CooldownSlider:SetPoint("TOPLEFT", SliderLabel, "BOTTOMLEFT", 0, -5) 
CooldownSlider:SetSize(160, 16)
CooldownSlider:SetMinMaxValues(30, 120)
CooldownSlider:SetValueStep(1)
CooldownSlider:SetObeyStepOnDrag(true)

local SliderValueText = CooldownSlider:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
SliderValueText:SetPoint("LEFT", CooldownSlider, "RIGHT", 10, 0)

-- Progress Bar Toggle Checkbox
local ShowBarChk = CreateFrame("CheckButton", "PreyNotifierShowBarChk", OptionsContent, "UICheckButtonTemplate")
ShowBarChk:SetSize(24, 24)
ShowBarChk:SetPoint("TOPLEFT", CooldownSlider, "BOTTOMLEFT", -5, -15) 
ShowBarChk.text = ShowBarChk:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
ShowBarChk.text:SetPoint("LEFT", ShowBarChk, "RIGHT", 5, 0)
ShowBarChk.text:SetText("Show On-Screen Progress Bar")

-- Explanatory Subtext
local ShowBarSubtext = ShowBarChk:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
ShowBarSubtext:SetPoint("TOPLEFT", ShowBarChk, "BOTTOMLEFT", 5, -2) 
ShowBarSubtext:SetText("Displays ONLY when an active hunt is detected in the current zone.")
ShowBarSubtext:SetTextColor(0.65, 0.55, 0.15) -- A dimmed, muted gold/yellow

local SubText2 = ShowBarChk:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
SubText2:SetPoint("TOPLEFT", ShowBarSubtext, "BOTTOMLEFT", 0, -2) 
SubText2:SetText("Blizzard only updates Prey status every 2-5 Hunt Progress Points")
SubText2:SetTextColor(0.65, 0.55, 0.15)


ShowBarChk:SetScript("OnClick", function(self)
    if PreyNotifierDB then
        PreyNotifierDB["_ShowProgressBar"] = self:GetChecked()
    end
    UpdateProgressBar()
end)

-- ------------------------------------------
-- TARGET BUTTON TOGGLE CHECKBOX
-- ------------------------------------------
local ShowTargetBtnChk = CreateFrame("CheckButton", "PreyNotifierShowTargetBtnChk", OptionsContent, "UICheckButtonTemplate")
ShowTargetBtnChk:SetSize(24, 24)
ShowTargetBtnChk:SetPoint("TOPLEFT", SubText2, "BOTTOMLEFT", -5, -15) 
ShowTargetBtnChk.text = ShowTargetBtnChk:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
ShowTargetBtnChk.text:SetPoint("LEFT", ShowTargetBtnChk, "RIGHT", 5, 0)
ShowTargetBtnChk.text:SetText("Show On-Screen Targeting Button")

local ShowTargetBtnSubtext = ShowTargetBtnChk:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
ShowTargetBtnSubtext:SetPoint("TOPLEFT", ShowTargetBtnChk, "BOTTOMLEFT", 5, -2) 
ShowTargetBtnSubtext:SetText("Left Click to Target - Middle Click to Throw a Trap")
ShowTargetBtnSubtext:SetTextColor(0.65, 0.55, 0.15) 

ShowTargetBtnChk:SetScript("OnClick", function(self)
    if PreyNotifierDB then
        PreyNotifierDB["_ShowTargetBtn"] = self:GetChecked()
    end
    UpdateTargetButton()
end)

-- ------------------------------------------
-- HIDE BLIZZARD UI CHECKBOX
-- ------------------------------------------
local HideBlizzChk = CreateFrame("CheckButton", "PreyNotifierHideBlizzChk", OptionsContent, "UICheckButtonTemplate")
HideBlizzChk:SetSize(24, 24)
HideBlizzChk:SetPoint("TOPLEFT", ShowTargetBtnSubtext, "BOTTOMLEFT", -5, -10) 
HideBlizzChk.text = HideBlizzChk:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
HideBlizzChk.text:SetPoint("LEFT", HideBlizzChk, "RIGHT", 5, 0)
HideBlizzChk.text:SetText("Hide Default Blizzard Tracker")

local HideBlizzSubtext = HideBlizzChk:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
HideBlizzSubtext:SetPoint("TOPLEFT", HideBlizzChk, "BOTTOMLEFT", 5, -2) 
HideBlizzSubtext:SetText("Makes the default Blizzard Prey crystal invisible.")
HideBlizzSubtext:SetTextColor(0.65, 0.55, 0.15) 

HideBlizzChk:SetScript("OnClick", function(self)
    if PreyNotifierDB then
        PreyNotifierDB["_HideBlizzUI"] = self:GetChecked()
    end
    UpdateProgressBar()
end)

local RaidWarnChk = CreateFrame("CheckButton", "PreyNotifierRaidWarnChk", OptionsContent, "UICheckButtonTemplate")
RaidWarnChk:SetSize(24, 24)
RaidWarnChk:SetPoint("TOPLEFT", HideBlizzSubtext, "BOTTOMLEFT", -5, -10)
RaidWarnChk.text = RaidWarnChk:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
RaidWarnChk.text:SetPoint("LEFT", RaidWarnChk, "RIGHT", 5, 0)
RaidWarnChk.text:SetText("Enable Raid Warnings for Alerts")

RaidWarnChk:SetScript("OnClick", function(self)
    if PreyNotifierDB then
        PreyNotifierDB["_RaidWarnings"] = self:GetChecked()
    end
end)

local TrackDebuffsChk = CreateFrame("CheckButton", "PreyNotifierTrackDebuffsChk", OptionsContent, "UICheckButtonTemplate")
TrackDebuffsChk:SetSize(24, 24)
TrackDebuffsChk:SetPoint("TOPLEFT", RaidWarnChk, "BOTTOMLEFT", 0, -10)
TrackDebuffsChk.text = TrackDebuffsChk:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
TrackDebuffsChk.text:SetPoint("LEFT", TrackDebuffsChk, "RIGHT", 5, 0)
TrackDebuffsChk.text:SetText("Show Torment & Bloody Command Trackers")

TrackDebuffsChk:SetScript("OnClick", function(self)
    if PreyNotifierDB then
        PreyNotifierDB["_TrackDebuffs"] = self:GetChecked()
    end
    UpdateDebuffs()
end)

local DisableBCFlashChk = CreateFrame("CheckButton", "PreyNotifierDisableBCFlashChk", OptionsContent, "UICheckButtonTemplate")
DisableBCFlashChk:SetSize(24, 24)
DisableBCFlashChk:SetPoint("TOPLEFT", TrackDebuffsChk, "BOTTOMLEFT", 0, -10)
DisableBCFlashChk.text = DisableBCFlashChk:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
DisableBCFlashChk.text:SetPoint("LEFT", DisableBCFlashChk, "RIGHT", 5, 0)
DisableBCFlashChk.text:SetText("WIP-Disable Bloody Command Screen Flash")

local DisableBCFlashSubtext = DisableBCFlashChk:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
DisableBCFlashSubtext:SetPoint("TOPLEFT", DisableBCFlashChk, "BOTTOMLEFT", 5, -2) 
DisableBCFlashSubtext:SetText("Disables the pulsing red screen border when debuffed.")
DisableBCFlashSubtext:SetTextColor(0.65, 0.55, 0.15) 

DisableBCFlashChk:SetScript("OnClick", function(self)
    if PreyNotifierDB then
        PreyNotifierDB["_DisableBCFlash"] = self:GetChecked()
    end
    UpdateDebuffs()
end)

local ShowAmbushWarnChk = CreateFrame("CheckButton", "PreyNotifierShowAmbushWarnChk", OptionsContent, "UICheckButtonTemplate")
ShowAmbushWarnChk:SetSize(24, 24)
ShowAmbushWarnChk:SetPoint("TOPLEFT", DisableBCFlashSubtext, "BOTTOMLEFT", -5, -10)
ShowAmbushWarnChk.text = ShowAmbushWarnChk:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
ShowAmbushWarnChk.text:SetPoint("LEFT", ShowAmbushWarnChk, "RIGHT", 5, 0)
ShowAmbushWarnChk.text:SetText("Show Ambushed! Warning Graphic")

local ShowAmbushWarnSubtext = ShowAmbushWarnChk:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
ShowAmbushWarnSubtext:SetPoint("TOPLEFT", ShowAmbushWarnChk, "BOTTOMLEFT", 5, -2)
ShowAmbushWarnSubtext:SetText("Enable/disable the ambush warning graphic.")
ShowAmbushWarnSubtext:SetTextColor(0.65, 0.55, 0.15)

ShowAmbushWarnChk:SetScript("OnClick", function(self)
    local enabled = self:GetChecked() and true or false
    if PreyNotifierDB then
        PreyNotifierDB["_ShowAmbushWarning"] = enabled
    end
    if CustomTracker and CustomTracker.AmbushWarning and not enabled then
        CustomTracker.AmbushWarning:Hide()
    end
end)

local ShowEchoWarnChk = CreateFrame("CheckButton", "PreyNotifierShowEchoWarnChk", OptionsContent, "UICheckButtonTemplate")
ShowEchoWarnChk:SetSize(24, 24)
ShowEchoWarnChk:SetPoint("TOPLEFT", ShowAmbushWarnSubtext, "BOTTOMLEFT", -5, -10)
ShowEchoWarnChk.text = ShowEchoWarnChk:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
ShowEchoWarnChk.text:SetPoint("LEFT", ShowEchoWarnChk, "RIGHT", 5, 0)
ShowEchoWarnChk.text:SetText("Show Echo of Predation Warning Graphic")

local ShowEchoWarnSubtext = ShowEchoWarnChk:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
ShowEchoWarnSubtext:SetPoint("TOPLEFT", ShowEchoWarnChk, "BOTTOMLEFT", 5, -2)
ShowEchoWarnSubtext:SetText("Enable/disable the Echo of Predation warning graphic.")
ShowEchoWarnSubtext:SetTextColor(0.65, 0.55, 0.15)

ShowEchoWarnChk:SetScript("OnClick", function(self)
    local enabled = self:GetChecked() and true or false
    if PreyNotifierDB then
        PreyNotifierDB["_ShowEchoWarning"] = enabled
    end
    if currentWarningType == "echo" and CustomTracker and CustomTracker.AmbushWarning and not enabled then
        CustomTracker.AmbushWarning:Hide()
    end
end)

local MinimapIconChk = CreateFrame("CheckButton", "PreyNotifierMinimapIconChk", OptionsContent, "UICheckButtonTemplate")
MinimapIconChk:SetSize(24, 24)
MinimapIconChk:SetPoint("TOPLEFT", ShowEchoWarnSubtext, "BOTTOMLEFT", -5, -10)
MinimapIconChk.text = MinimapIconChk:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
MinimapIconChk.text:SetPoint("LEFT", MinimapIconChk, "RIGHT", 5, 0)
MinimapIconChk.text:SetText("Show Minimap Button")

local MinimapIconSubtext = MinimapIconChk:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
MinimapIconSubtext:SetPoint("TOPLEFT", MinimapIconChk, "BOTTOMLEFT", 5, -2)
MinimapIconSubtext:SetText("Enable/disable the minimap icon (Menu still accessible via /pn).")
MinimapIconSubtext:SetTextColor(0.65, 0.55, 0.15)

MinimapIconChk:SetScript("OnClick", function(self)
    local enabled = self:GetChecked() and true or false
    if PreyNotifierDB then
        PreyNotifierDB["_ShowMinimapIcon"] = enabled
    end
    if enabled then PreyNotifierMinimapButton:Show() else PreyNotifierMinimapButton:Hide() end
end)

local AmbushStyleLabel = OptionsContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
AmbushStyleLabel:SetPoint("TOPLEFT", MinimapIconSubtext, "BOTTOMLEFT", 0, -10)
AmbushStyleLabel:SetText("Ambush Graphic Style:")

local AmbushStyleDropDown = CreateFrame("Frame", "PreyNotifierAmbushStyleDropDown", OptionsContent, "UIDropDownMenuTemplate")
AmbushStyleDropDown:SetPoint("TOPLEFT", AmbushStyleLabel, "BOTTOMLEFT", -15, -5)
UIDropDownMenu_SetWidth(AmbushStyleDropDown, 230)
UIDropDownMenu_JustifyText(AmbushStyleDropDown, "LEFT")
UIDropDownMenu_Initialize(AmbushStyleDropDown, function(self, level)
    if level ~= 1 then return end

    local currentStyle = "sharp_blood"
    if PreyNotifierDB and PreyNotifierDB["_AmbushGraphicStyle"] then
        currentStyle = PreyNotifierDB["_AmbushGraphicStyle"]
    end

    for _, option in ipairs(AmbushGraphicOptions) do
        if option.selectable == false then
            -- Keep option definitions for future use, but hide for now.
        else
        local info = UIDropDownMenu_CreateInfo()
        info.text = option.text
        info.value = option.key
        info.arg1 = option.key
        info.checked = (currentStyle == option.key)
        info.func = function(_, selectedKey)
            local selected = GetAmbushGraphicOption(selectedKey)
            if PreyNotifierDB then
                PreyNotifierDB["_AmbushGraphicStyle"] = selected.key
            end
            UIDropDownMenu_SetSelectedValue(AmbushStyleDropDown, selected.key)
            UIDropDownMenu_SetText(AmbushStyleDropDown, selected.text)
            if ApplyAmbushWarningStyle then
                ApplyAmbushWarningStyle(selected.key)
            end
        end
        UIDropDownMenu_AddButton(info, level)
        end
    end
end)

-- ------------------------------------------
-- TORMENT THRESHOLD SETTINGS
-- ------------------------------------------
local TormentHeader = OptionsContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
TormentHeader:SetPoint("TOPLEFT", AmbushStyleDropDown, "BOTTOMLEFT", 5, -10)
TormentHeader:SetText("Torment Warning Thresholds")

local YellowWarnLabel = OptionsContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
YellowWarnLabel:SetPoint("TOPLEFT", TormentHeader, "BOTTOMLEFT", 0, -10)
YellowWarnLabel:SetText("Warning Stacks:")

local YellowWarnBox = CreateFrame("EditBox", "PreyNotifierYellowWarnBox", OptionsContent, "InputBoxTemplate")
YellowWarnBox:SetPoint("LEFT", YellowWarnLabel, "RIGHT", 5, 0)
YellowWarnBox:SetSize(30, 20)
YellowWarnBox:SetNumeric(true)
YellowWarnBox:SetAutoFocus(false)
YellowWarnBox:SetMaxLetters(2)

local RedWarnLabel = OptionsContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
RedWarnLabel:SetPoint("LEFT", YellowWarnBox, "RIGHT", 15, 0)
RedWarnLabel:SetText("Critical Stacks:")

local RedWarnBox = CreateFrame("EditBox", "PreyNotifierRedWarnBox", OptionsContent, "InputBoxTemplate")
RedWarnBox:SetPoint("LEFT", RedWarnLabel, "RIGHT", 5, 0)
RedWarnBox:SetSize(30, 20)
RedWarnBox:SetNumeric(true)
RedWarnBox:SetAutoFocus(false)
RedWarnBox:SetMaxLetters(2)

local TormentSaveBtn = CreateFrame("Button", nil, OptionsContent, "UIPanelButtonTemplate")
TormentSaveBtn:SetPoint("LEFT", RedWarnBox, "RIGHT", 10, 0)
TormentSaveBtn:SetSize(55, 22)
TormentSaveBtn:SetText("Save")

local TormentResetBtn = CreateFrame("Button", nil, OptionsContent, "UIPanelButtonTemplate")
TormentResetBtn:SetPoint("LEFT", TormentSaveBtn, "RIGHT", 5, 0)
TormentResetBtn:SetSize(55, 22)
TormentResetBtn:SetText("Reset")

TormentResetBtn:SetScript("OnClick", function()
    if PreyNotifierDB then
        PreyNotifierDB["_TormentYellow"] = 5
        PreyNotifierDB["_TormentRed"] = 8
    end
    YellowWarnBox:SetText("5")
    RedWarnBox:SetText("8")
    print("|cff00FF00PreyNotifier:|r Torment warnings reset to defaults (Warning: 5, Critical: 8).")
    UpdateDebuffs()
end)

local function SaveTormentSettings()
    local yVal = tonumber(YellowWarnBox:GetText())
    local rVal = tonumber(RedWarnBox:GetText())
    if yVal and rVal then
        if yVal < 1 or yVal > 20 or rVal < 1 or rVal > 20 then
            print("|cffFF0000PreyNotifier Error:|r Torment warning stacks must be between 1 and 20.")
            YellowWarnBox:SetText(tostring(PreyNotifierDB and PreyNotifierDB["_TormentYellow"] or 5))
            RedWarnBox:SetText(tostring(PreyNotifierDB and PreyNotifierDB["_TormentRed"] or 8))
            return
        end
        
        if yVal >= rVal then
            print("|cffFF0000PreyNotifier Error:|r Critical warning stacks must be greater than Warning stacks.")
            YellowWarnBox:SetText(tostring(PreyNotifierDB and PreyNotifierDB["_TormentYellow"] or 5))
            RedWarnBox:SetText(tostring(PreyNotifierDB and PreyNotifierDB["_TormentRed"] or 8))
            return
        end

        if PreyNotifierDB then
            PreyNotifierDB["_TormentYellow"] = yVal
            PreyNotifierDB["_TormentRed"] = rVal
            YellowWarnBox:ClearFocus()
            RedWarnBox:ClearFocus()
            print("|cff00FF00PreyNotifier:|r Torment warnings saved - Warning: " .. yVal .. ", Critical: " .. rVal)
            UpdateDebuffs()
        end
    end
end

TormentSaveBtn:SetScript("OnClick", SaveTormentSettings)
YellowWarnBox:SetScript("OnEnterPressed", SaveTormentSettings)
RedWarnBox:SetScript("OnEnterPressed", SaveTormentSettings)

OptionsContent:SetHeight(760)


-- ==========================================
-- TAB 3: SOUND CONTENT
-- ==========================================
local EnableSoundChk = CreateFrame("CheckButton", "PreyNotifierEnableSoundChk", SoundTab, "UICheckButtonTemplate")
EnableSoundChk:SetSize(24, 24)
EnableSoundChk:SetPoint("TOPLEFT", 20, -15)
EnableSoundChk.text = EnableSoundChk:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
EnableSoundChk.text:SetPoint("LEFT", EnableSoundChk, "RIGHT", 5, 0)
EnableSoundChk.text:SetText("Enable Ambush Alert Sounds")

EnableSoundChk:SetScript("OnClick", function(self)
    if PreyNotifierDB then
        PreyNotifierDB["_PlaySound"] = self:GetChecked()
    end
end)

local SoundInputLabel = SoundTab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
SoundInputLabel:SetPoint("TOPLEFT", EnableSoundChk, "BOTTOMLEFT", 5, -10)
SoundInputLabel:SetText("Ambush Alert Sound ID:")

local SoundInputBox = CreateFrame("EditBox", nil, SoundTab, "InputBoxTemplate")
SoundInputBox:SetPoint("TOPLEFT", SoundInputLabel, "BOTTOMLEFT", 0, -5)
SoundInputBox:SetSize(70, 25)
SoundInputBox:SetNumeric(true)
SoundInputBox:SetMaxLetters(8)
SoundInputBox:SetAutoFocus(false)

local SoundSaveBtn = CreateFrame("Button", nil, SoundTab, "UIPanelButtonTemplate")
SoundSaveBtn:SetPoint("LEFT", SoundInputBox, "RIGHT", 10, 0)
SoundSaveBtn:SetSize(55, 22)
SoundSaveBtn:SetText("Save")

local SoundTestBtn = CreateFrame("Button", nil, SoundTab, "UIPanelButtonTemplate")
SoundTestBtn:SetPoint("LEFT", SoundSaveBtn, "RIGHT", 5, 0)
SoundTestBtn:SetSize(55, 22)
SoundTestBtn:SetText("Test")

local SoundDefaultBtn = CreateFrame("Button", nil, SoundTab, "UIPanelButtonTemplate")
SoundDefaultBtn:SetPoint("LEFT", SoundTestBtn, "RIGHT", 5, 0)
SoundDefaultBtn:SetSize(55, 22)
SoundDefaultBtn:SetText("Reset")

local function SaveSoundID()
    local text = SoundInputBox:GetText()
    local num = tonumber(text)
    if num then
        if PreyNotifierDB then PreyNotifierDB["_SoundFile"] = num end
        SoundInputBox:ClearFocus()
        print("|cff00FF00PreyNotifier:|r Sound ID saved as " .. num)
    else
        print("|cffFF0000PreyNotifier:|r Invalid Sound ID.")
    end
end

SoundSaveBtn:SetScript("OnClick", SaveSoundID)
SoundInputBox:SetScript("OnEnterPressed", SaveSoundID)

SoundTestBtn:SetScript("OnClick", function()
    local soundID = PreyNotifierDB and PreyNotifierDB["_SoundFile"] or 552035
    local success = pcall(PlaySoundFile, soundID, "Dialog")
    if not success then
        print("|cffFF0000PreyNotifier Error:|r Could not play sound. Invalid or restricted Sound ID.")
    else
        print("|cff00FF00PreyNotifier:|r Playing test sound: " .. soundID)
    end
end)

SoundDefaultBtn:SetScript("OnClick", function()
    if PreyNotifierDB then PreyNotifierDB["_SoundFile"] = 552035 end
    SoundInputBox:SetText("552035")
    print("|cff00FF00PreyNotifier:|r Sound ID reset to default (552035).")
end)

-- ------------------------------------------
-- ECHO OF PREDATION ALERT SOUND SETTINGS
-- ------------------------------------------
local EnableEchoSoundChk = CreateFrame("CheckButton", "PreyNotifierEnableEchoSoundChk", SoundTab, "UICheckButtonTemplate")
EnableEchoSoundChk:SetSize(24, 24)
EnableEchoSoundChk:SetPoint("TOPLEFT", EnableSoundChk, "BOTTOMLEFT", 0, -60)
EnableEchoSoundChk.text = EnableEchoSoundChk:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
EnableEchoSoundChk.text:SetPoint("LEFT", EnableEchoSoundChk, "RIGHT", 5, 0)
EnableEchoSoundChk.text:SetText("Enable Echo of Predation Alert Sounds")

EnableEchoSoundChk:SetScript("OnClick", function(self)
    if PreyNotifierDB then
        PreyNotifierDB["_PlayEchoSound"] = self:GetChecked()
    end
end)

local EchoSoundInputLabel = SoundTab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
EchoSoundInputLabel:SetPoint("TOPLEFT", EnableEchoSoundChk, "BOTTOMLEFT", 5, -10)
EchoSoundInputLabel:SetText("Echo Alert Sound ID:")

local EchoSoundInputBox = CreateFrame("EditBox", nil, SoundTab, "InputBoxTemplate")
EchoSoundInputBox:SetPoint("TOPLEFT", EchoSoundInputLabel, "BOTTOMLEFT", 0, -5)
EchoSoundInputBox:SetSize(70, 25)
EchoSoundInputBox:SetNumeric(true)
EchoSoundInputBox:SetMaxLetters(8)
EchoSoundInputBox:SetAutoFocus(false)

local EchoSoundSaveBtn = CreateFrame("Button", nil, SoundTab, "UIPanelButtonTemplate")
EchoSoundSaveBtn:SetPoint("LEFT", EchoSoundInputBox, "RIGHT", 10, 0)
EchoSoundSaveBtn:SetSize(55, 22)
EchoSoundSaveBtn:SetText("Save")

local EchoSoundTestBtn = CreateFrame("Button", nil, SoundTab, "UIPanelButtonTemplate")
EchoSoundTestBtn:SetPoint("LEFT", EchoSoundSaveBtn, "RIGHT", 5, 0)
EchoSoundTestBtn:SetSize(55, 22)
EchoSoundTestBtn:SetText("Test")

local EchoSoundDefaultBtn = CreateFrame("Button", nil, SoundTab, "UIPanelButtonTemplate")
EchoSoundDefaultBtn:SetPoint("LEFT", EchoSoundTestBtn, "RIGHT", 5, 0)
EchoSoundDefaultBtn:SetSize(55, 22)
EchoSoundDefaultBtn:SetText("Reset")

local function SaveEchoSoundID()
    local text = EchoSoundInputBox:GetText()
    local num = tonumber(text)
    if num then
        if PreyNotifierDB then PreyNotifierDB["_EchoSoundFile"] = num end
        EchoSoundInputBox:ClearFocus()
        print("|cff00FF00PreyNotifier:|r Echo Sound ID saved as " .. num)
    else
        print("|cffFF0000PreyNotifier:|r Invalid Echo Sound ID.")
    end
end

EchoSoundSaveBtn:SetScript("OnClick", SaveEchoSoundID)
EchoSoundInputBox:SetScript("OnEnterPressed", SaveEchoSoundID)

EchoSoundTestBtn:SetScript("OnClick", function()
    local soundID = PreyNotifierDB and PreyNotifierDB["_EchoSoundFile"] or 554099
    local success = pcall(PlaySoundFile, soundID, "Dialog")
    if not success then
        print("|cffFF0000PreyNotifier Error:|r Could not play sound. Invalid or restricted Sound ID.")
    else
        print("|cff00FF00PreyNotifier:|r Playing Echo test sound: " .. soundID)
    end
end)

EchoSoundDefaultBtn:SetScript("OnClick", function()
    if PreyNotifierDB then PreyNotifierDB["_EchoSoundFile"] = 554099 end
    EchoSoundInputBox:SetText("554099")
    print("|cff00FF00PreyNotifier:|r Echo Sound ID reset to default (554099).")
end)





-- ==========================================
-- TAB 4: KEYBINDS CONTENT
-- ==========================================
local BindCatcher = CreateFrame("Button", nil, UIFrame)
BindCatcher:SetAllPoints(UIFrame)
BindCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
BindCatcher:EnableKeyboard(true)
BindCatcher:EnableMouseWheel(true)
BindCatcher.bg = BindCatcher:CreateTexture(nil, "BACKGROUND")
BindCatcher.bg:SetAllPoints()
BindCatcher.bg:SetColorTexture(0, 0, 0, 0.9)
BindCatcher.text = BindCatcher:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
BindCatcher.text:SetPoint("CENTER")
BindCatcher.text:SetText("Press a key to bind...\n\nPress ESC to cancel.")
BindCatcher:Hide()

local function BindCatcher_HandleKey(self, key)
    if InCombatLockdown() then
        print("|cffFF0000PreyNotifier:|r Cannot set bindings in combat.")
        self:Hide()
        return
    end
    if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL" or key == "LALT" or key == "RALT" or key == "UNKNOWN" then return end
    
    if key == "ESCAPE" then
        self:Hide()
        if self.updateFunc then self.updateFunc() end
        return
    end
    
    local prefix = ""
    if IsAltKeyDown() then prefix = prefix .. "ALT-" end
    if IsControlKeyDown() then prefix = prefix .. "CTRL-" end
    if IsShiftKeyDown() then prefix = prefix .. "SHIFT-" end
    
    local finalKey = prefix .. key
    
    -- Unbind old instances of this command
    local keys = {GetBindingKey(self.command)}
    for _, k in ipairs(keys) do SetBinding(k, nil) end
    
    SetBinding(finalKey, self.command)
    SaveBindings(GetCurrentBindingSet() or 1)
    
    self:Hide()
    if self.updateFunc then self.updateFunc() end
end

BindCatcher:SetScript("OnKeyDown", BindCatcher_HandleKey)
BindCatcher:SetScript("OnMouseDown", function(self, button)
    if button == "LeftButton" or button == "RightButton" then return end
    local mappedBtn
    if button == "MiddleButton" then mappedBtn = "BUTTON3"
    elseif button:match("^Button(%d)$") then mappedBtn = "BUTTON" .. button:match("^Button(%d)$")
    else mappedBtn = button:upper() end
    BindCatcher_HandleKey(self, mappedBtn)
end)
BindCatcher:SetScript("OnMouseWheel", function(self, delta)
    local mappedBtn = delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN"
    BindCatcher_HandleKey(self, mappedBtn)
end)

local KeybindHelperText = KeybindsTab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
KeybindHelperText:SetPoint("TOPLEFT", 20, -15)
KeybindHelperText:SetText("Click to Set Keybind | ESC to ABORT")
KeybindHelperText:SetTextColor(0.65, 0.55, 0.15)

local TargetBindLabel = KeybindsTab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
TargetBindLabel:SetPoint("TOPLEFT", KeybindHelperText, "BOTTOMLEFT", 0, -15)
TargetBindLabel:SetText("Target Primary Prey:")

local TargetBindBtn = CreateFrame("Button", nil, KeybindsTab, "UIPanelButtonTemplate")
TargetBindBtn:SetSize(130, 22)
TargetBindBtn:SetPoint("TOPLEFT", TargetBindLabel, "BOTTOMLEFT", 0, -5)

local TargetClearBtn = CreateFrame("Button", nil, KeybindsTab, "UIPanelButtonTemplate")
TargetClearBtn:SetSize(55, 22)
TargetClearBtn:SetPoint("LEFT", TargetBindBtn, "RIGHT", 5, 0)
TargetClearBtn:SetText("Clear")

local TrapBindLabel = KeybindsTab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
TrapBindLabel:SetPoint("TOPLEFT", TargetBindBtn, "BOTTOMLEFT", 0, -15)
TrapBindLabel:SetText("Use Disarmed Trap:")

local TrapBindBtn = CreateFrame("Button", nil, KeybindsTab, "UIPanelButtonTemplate")
TrapBindBtn:SetSize(130, 22)
TrapBindBtn:SetPoint("TOPLEFT", TrapBindLabel, "BOTTOMLEFT", 0, -5)

local TrapClearBtn = CreateFrame("Button", nil, KeybindsTab, "UIPanelButtonTemplate")
TrapClearBtn:SetSize(55, 22)
TrapClearBtn:SetPoint("LEFT", TrapBindBtn, "RIGHT", 5, 0)
TrapClearBtn:SetText("Clear")

local EchoBindLabel = KeybindsTab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
EchoBindLabel:SetPoint("TOPLEFT", TrapBindBtn, "BOTTOMLEFT", 0, -15)
EchoBindLabel:SetText("Target Echo of Predation:")

local EchoBindBtn = CreateFrame("Button", nil, KeybindsTab, "UIPanelButtonTemplate")
EchoBindBtn:SetSize(130, 22)
EchoBindBtn:SetPoint("TOPLEFT", EchoBindLabel, "BOTTOMLEFT", 0, -5)

local EchoClearBtn = CreateFrame("Button", nil, KeybindsTab, "UIPanelButtonTemplate")
EchoClearBtn:SetSize(55, 22)
EchoClearBtn:SetPoint("LEFT", EchoBindBtn, "RIGHT", 5, 0)
EchoClearBtn:SetText("Clear")

TargetBindBtn.Glow = TargetBindBtn:CreateTexture(nil, "BACKGROUND")
TargetBindBtn.Glow:SetPoint("TOPLEFT", -3, 3)
TargetBindBtn.Glow:SetPoint("BOTTOMRIGHT", 3, -3)
TargetBindBtn.Glow:SetColorTexture(1, 0, 0, 0.7)
TargetBindBtn.Glow:SetBlendMode("ADD")
TargetBindBtn.Glow:Hide()

TargetBindBtn.GlowAnim = TargetBindBtn.Glow:CreateAnimationGroup()
TargetBindBtn.GlowAnim:SetLooping("BOUNCE")
local tAlpha = TargetBindBtn.GlowAnim:CreateAnimation("Alpha")
tAlpha:SetFromAlpha(0.2)
tAlpha:SetToAlpha(1.0)
tAlpha:SetDuration(0.6)

local function UpdateBindButtons()
    local tKey = GetBindingKey("CLICK PreyNotifierTargetBtn:LeftButton")
    if tKey then
        TargetBindBtn:SetText(tKey)
        TargetBindBtn:GetFontString():SetTextColor(1, 1, 1)
        TargetBindBtn.Glow:Hide()
        TargetBindBtn.GlowAnim:Stop()
    else
        TargetBindBtn:SetText("Not Bound")
        TargetBindBtn:GetFontString():SetTextColor(1, 0.2, 0.2)
        TargetBindBtn.Glow:Show()
        TargetBindBtn.GlowAnim:Play()
    end
    
    local mKey = GetBindingKey("CLICK PreyNotifierTargetBtn:MiddleButton")
    if mKey then
        TrapBindBtn:SetText(mKey)
        TrapBindBtn:GetFontString():SetTextColor(1, 1, 1)
    else
        TrapBindBtn:SetText("Not Bound")
        TrapBindBtn:GetFontString():SetTextColor(1, 0.2, 0.2)
    end
    
    local eKey = GetBindingKey("CLICK PreyNotifierEchoBtn:LeftButton")
    if eKey then
        EchoBindBtn:SetText(eKey)
        EchoBindBtn:GetFontString():SetTextColor(1, 1, 1)
    else
        EchoBindBtn:SetText("Not Bound")
        EchoBindBtn:GetFontString():SetTextColor(1, 0.2, 0.2)
    end
end

TargetBindBtn:SetScript("OnClick", function()
    BindCatcher.command = "CLICK PreyNotifierTargetBtn:LeftButton"
    BindCatcher.updateFunc = UpdateBindButtons
    BindCatcher:Show()
end)

TargetClearBtn:SetScript("OnClick", function()
    if InCombatLockdown() then return end
    local keys = {GetBindingKey("CLICK PreyNotifierTargetBtn:LeftButton")}
    for _, k in ipairs(keys) do SetBinding(k, nil) end
    SaveBindings(GetCurrentBindingSet() or 1)
    UpdateBindButtons()
end)

TrapBindBtn:SetScript("OnClick", function()
    BindCatcher.command = "CLICK PreyNotifierTargetBtn:MiddleButton"
    BindCatcher.updateFunc = UpdateBindButtons
    BindCatcher:Show()
end)

TrapClearBtn:SetScript("OnClick", function()
    if InCombatLockdown() then return end
    local keys = {GetBindingKey("CLICK PreyNotifierTargetBtn:MiddleButton")}
    for _, k in ipairs(keys) do SetBinding(k, nil) end
    SaveBindings(GetCurrentBindingSet() or 1)
    UpdateBindButtons()
end)

EchoBindBtn:SetScript("OnClick", function()
    BindCatcher.command = "CLICK PreyNotifierEchoBtn:LeftButton"
    BindCatcher.updateFunc = UpdateBindButtons
    BindCatcher:Show()
end)

EchoClearBtn:SetScript("OnClick", function()
    if InCombatLockdown() then return end
    local keys = {GetBindingKey("CLICK PreyNotifierEchoBtn:LeftButton")}
    for _, k in ipairs(keys) do SetBinding(k, nil) end
    SaveBindings(GetCurrentBindingSet() or 1)
    UpdateBindButtons()
end)

-- ==========================================
-- 1.5 SECURE TARGETING BUTTON
-- ==========================================
local TargetBtn = CreateFrame("Button", "PreyNotifierTargetBtn", UIParent, "SecureActionButtonTemplate")
TargetBtn:SetSize(36, 36)
TargetBtn:SetPoint("CENTER", 0, -150)
TargetBtn:SetFrameStrata("HIGH") 

TargetBtn:RegisterForClicks("AnyDown", "AnyUp") 

-- LEFT CLICK: Target the Prey
TargetBtn:SetAttribute("type1", "macro")

-- MIDDLE CLICK: Dynamic Trap Assignment
TargetBtn:SetAttribute("type3", "macro")

-- ECHO OF PREDATION INVISIBLE SECURE BUTTON
local EchoBtn = CreateFrame("Button", "PreyNotifierEchoBtn", UIParent, "SecureActionButtonTemplate")
EchoBtn:SetSize(1, 1)
EchoBtn:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -100, 100) 
EchoBtn:RegisterForClicks("AnyDown", "AnyUp")
EchoBtn:SetAttribute("type1", "macro")
EchoBtn:SetAttribute("macrotext1", "/cleartarget\n/targetexact Echo of Predation")


local BtnTexture = TargetBtn:CreateTexture(nil, "BACKGROUND")
BtnTexture:SetAllPoints()
BtnTexture:SetTexture("Interface\\Icons\\Ability_Hunter_SniperShot") 

-- Make the button movable using RIGHT-CLICK
TargetBtn:SetMovable(true)
TargetBtn:RegisterForDrag("RightButton")
TargetBtn:SetScript("OnDragStart", TargetBtn.StartMoving)
TargetBtn:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    
    local point, _, relativePoint, xOfs, yOfs = self:GetPoint()
    if PreyNotifierDB then
        PreyNotifierDB["_BtnPoint"] = point
        PreyNotifierDB["_BtnRel"] = relativePoint
        PreyNotifierDB["_BtnX"] = xOfs
        PreyNotifierDB["_BtnY"] = yOfs
    end
end)

-- Tooltip Logic for the Secure Action Button
TargetBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("|cffCC0000PreyNotifier")
	GameTooltip:SetText("|cffCC0000Primary Target:|r " .. PreyNotifierDB["_PrimaryTarget"])
    GameTooltip:AddLine("Left-Click or Keybind to target", 1, 1, 1)
    GameTooltip:AddLine("Middle-Click or Keybind to use Disarmed Trap", 1, 1, 1)
	GameTooltip:AddLine("Bind keys in the /pn Keybinds Tab", 1, 0.82, 0)
    GameTooltip:AddLine("Right-Click and drag to move", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)

TargetBtn:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)


-- ==========================================
-- SCROLL FRAME SETUP
-- ==========================================
local ScrollFrame = CreateFrame("ScrollFrame", "PreyNotifierScrollFrame", PreyListTab, "UIPanelScrollFrameTemplate")
ScrollFrame:SetPoint("TOPLEFT", InputBox, "BOTTOMLEFT", 0, -20)
ScrollFrame:SetPoint("BOTTOMRIGHT", PreyListTab, "BOTTOMRIGHT", -36, 50)

local ScrollChild = CreateFrame("Frame")
ScrollChild:SetSize(ScrollFrame:GetWidth(), 1) 
ScrollFrame:SetScrollChild(ScrollChild)

local listFrames = {}
UpdateTargetList = function()
    for _, row in ipairs(listFrames) do row:Hide() end
    if not PreyNotifierDB then return end
    
    local yOffset = 0 
    local rowIndex = 1
    
    for mobName, _ in pairs(PreyNotifierDB) do
        if not mobName:match("^_") then
            if not listFrames[rowIndex] then
                local row = CreateFrame("Frame", nil, ScrollChild)
                row:SetSize(415, 22) 
                
                local txt = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                txt:SetPoint("LEFT", 5, 0)
                txt:SetWidth(305) 
                txt:SetWordWrap(false) 
                txt:SetJustifyH("LEFT") 
                row.text = txt
                
                local delBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                delBtn:SetSize(22, 22)
                delBtn:SetPoint("RIGHT", -6, 0)
                delBtn:SetText("X")
                row.delBtn = delBtn

                local priBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                priBtn:SetSize(75, 22)
                priBtn:SetPoint("RIGHT", delBtn, "LEFT", -5, 0)
                row.priBtn = priBtn
                
                listFrames[rowIndex] = row
            end
            
            local currentRow = listFrames[rowIndex]
            currentRow:SetPoint("TOPLEFT", ScrollChild, "TOPLEFT", 0, yOffset)
            currentRow.text:SetText(mobName)
            
            if PreyNotifierDB["_PrimaryTarget"] == mobName then
                currentRow.priBtn:SetText("Primary")
                currentRow.priBtn:Disable()
                currentRow.text:SetTextColor(0, 1, 0)
            else
                currentRow.priBtn:SetText("Set Primary")
                currentRow.priBtn:Enable()
                currentRow.text:SetTextColor(1, 0.82, 0)
            end

            currentRow.priBtn:SetScript("OnClick", function()
                if InCombatLockdown() then
                    print("|cffFF0000PreyNotifier:|r Cannot change Primary Target while in combat!")
                    return
                end
                
                PreyNotifierDB["_PrimaryTarget"] = mobName
                PreyNotifierTargetBtn:SetAttribute("macrotext1", "/cleartarget\n/targetexact " .. mobName)
                UpdateTargetButton()
                print("|cff00FF00PreyNotifier:|r Primary Target set to |cffFFFF00" .. mobName .. "|r.")
                UpdateTargetList() 
            end)
            
            currentRow.delBtn:SetScript("OnClick", function()
                PreyNotifierDB[mobName] = nil
                if PreyNotifierDB["_PrimaryTarget"] == mobName then
                    PreyNotifierDB["_PrimaryTarget"] = nil
                    if not InCombatLockdown() then
                        PreyNotifierTargetBtn:SetAttribute("macrotext1", "")
                        UpdateTargetButton()
                    else
                        print("|cffFF9900PreyNotifier:|r Primary Target deleted, but button cannot be hidden while in combat.")
                    end
                    -- NEW: Hide the progress bar
                    if CustomTracker then CustomTracker:Hide() end 
                    isHuntComplete = false
                end
                UpdateTargetList()
            end)
            
            currentRow:Show()
            yOffset = yOffset - 25
            rowIndex = rowIndex + 1
        end
    end
    
    ScrollChild:SetHeight(math.abs(yOffset))
end

local ClearPriBtn = CreateFrame("Button", nil, PreyListTab, "UIPanelButtonTemplate")
ClearPriBtn:SetSize(100, 22)
ClearPriBtn:SetPoint("TOPRIGHT", ScrollFrame, "BOTTOMRIGHT", -6, -10)
ClearPriBtn:SetText("Clear Primary")

ClearPriBtn:SetScript("OnClick", function()
    if InCombatLockdown() then
        print("|cffFF0000PreyNotifier:|r Cannot clear Primary Target while in combat!")
        return
    end
    
    if PreyNotifierDB["_PrimaryTarget"] then
        PreyNotifierDB["_PrimaryTarget"] = nil
        PreyNotifierTargetBtn:SetAttribute("macrotext1", "")
        UpdateTargetButton()
        -- NEW: Hide the progress bar
        if CustomTracker then CustomTracker:Hide() end 
        print("|cff00FF00PreyNotifier:|r Primary Target cleared. Button hidden.")
        isHuntComplete = false
        UpdateTargetList() 
    end
end)

UIFrame:SetScript("OnShow", function()
    UpdateTargetList()
    if UpdateBindButtons then UpdateBindButtons() end
    if PreyNotifierDB and PreyNotifierDB["_Cooldown"] then
        CooldownSlider:SetValue(PreyNotifierDB["_Cooldown"])
        SliderValueText:SetText(PreyNotifierDB["_Cooldown"] .. "s")
    end
    if PreyNotifierDB and PreyNotifierDB["_ShowProgressBar"] ~= nil then
        ShowBarChk:SetChecked(PreyNotifierDB["_ShowProgressBar"])
    end
    if PreyNotifierDB and PreyNotifierDB["_ShowTargetBtn"] ~= nil then
        ShowTargetBtnChk:SetChecked(PreyNotifierDB["_ShowTargetBtn"])
    end
	if PreyNotifierDB and PreyNotifierDB["_HideBlizzUI"] ~= nil then
        HideBlizzChk:SetChecked(PreyNotifierDB["_HideBlizzUI"])
    end
    if PreyNotifierDB and PreyNotifierDB["_RaidWarnings"] ~= nil then
        RaidWarnChk:SetChecked(PreyNotifierDB["_RaidWarnings"])
    end
    if PreyNotifierDB and PreyNotifierDB["_TrackDebuffs"] ~= nil then
        TrackDebuffsChk:SetChecked(PreyNotifierDB["_TrackDebuffs"])
    end
    if PreyNotifierDB and PreyNotifierDB["_DisableBCFlash"] ~= nil then
        DisableBCFlashChk:SetChecked(PreyNotifierDB["_DisableBCFlash"])
    end
    if PreyNotifierDB and PreyNotifierDB["_ShowAmbushWarning"] ~= nil then
        ShowAmbushWarnChk:SetChecked(PreyNotifierDB["_ShowAmbushWarning"])
    end
    if PreyNotifierDB and PreyNotifierDB["_ShowEchoWarning"] ~= nil then
        ShowEchoWarnChk:SetChecked(PreyNotifierDB["_ShowEchoWarning"])
    end
    if PreyNotifierDB and PreyNotifierDB["_ShowMinimapIcon"] ~= nil then
        MinimapIconChk:SetChecked(PreyNotifierDB["_ShowMinimapIcon"])
    end
    if PreyNotifierDB then
        local selected = GetAmbushGraphicOption(PreyNotifierDB["_AmbushGraphicStyle"])
        UIDropDownMenu_SetSelectedValue(AmbushStyleDropDown, selected.key)
        UIDropDownMenu_SetText(AmbushStyleDropDown, selected.text)
        if ApplyAmbushWarningStyle then
            ApplyAmbushWarningStyle(selected.key)
        end
    end
    if PreyNotifierDB and PreyNotifierDB["_PlaySound"] ~= nil then
        EnableSoundChk:SetChecked(PreyNotifierDB["_PlaySound"])
    end
    if PreyNotifierDB and PreyNotifierDB["_SoundFile"] then
        SoundInputBox:SetText(tostring(PreyNotifierDB["_SoundFile"]))
    end
    if PreyNotifierDB and PreyNotifierDB["_PlayEchoSound"] ~= nil then
        EnableEchoSoundChk:SetChecked(PreyNotifierDB["_PlayEchoSound"])
    end
    if PreyNotifierDB and PreyNotifierDB["_EchoSoundFile"] then
        EchoSoundInputBox:SetText(tostring(PreyNotifierDB["_EchoSoundFile"]))
    end
    if PreyNotifierDB and PreyNotifierDB["_TormentYellow"] then
        YellowWarnBox:SetText(tostring(PreyNotifierDB["_TormentYellow"]))
    end
    if PreyNotifierDB and PreyNotifierDB["_TormentRed"] then
        RedWarnBox:SetText(tostring(PreyNotifierDB["_TormentRed"]))
    end
end)

CooldownSlider:SetScript("OnValueChanged", function(self, value)
    local val = math.floor(value)
    SliderValueText:SetText(val .. "s")
    if PreyNotifierDB then PreyNotifierDB["_Cooldown"] = val end
end)

AddButton:SetScript("OnClick", function()
    local text = InputBox:GetText()
    if text and text ~= "" then
        if not text:match("^[%a%s'-]+$") or string.len(text) > 40 then
            print("|cffFF0000PreyNotifier Error:|r Invalid name.")
        elseif PreyNotifierDB and PreyNotifierDB[text] then
            print("|cffFF0000PreyNotifier Error:|r |cffFFFF00" .. text .. "|r is already in the hunt list.")
        else
            PreyNotifierDB[text] = true
            InputBox:SetText("")
            InputBox:ClearFocus()
            UpdateTargetList()
            print("|cff00FF00PreyNotifier:|r Added \"" .. text .. "\" to the hunt list.")
        end
    end
end)

InputBox:SetScript("OnEnterPressed", function(self) AddButton:Click() end)

-- ==========================================
-- ADDON COMPARTMENT FRAME LOGIN (Minimap Dropdown)
-- ==========================================
_G.PreyNotifier_OnCompartmentClick = function(addonName, buttonName)
    if InCombatLockdown() then
        print("|cffFF0000PreyNotifier:|r Cannot open menu while in combat!")
        return
    end

    if UIFrame:IsShown() then
        UIFrame:Hide()
    else
        UIFrame:Show()
    end
end

-- ==========================================
-- 2. SLASH COMMANDS
-- ==========================================


SLASH_PREY1 = "/prey"
SLASH_PREY2 = "/pn"
SLASH_PREY3 = "/preynotifier"
SlashCmdList["PREY"] = function(msg)
local command, rest = msg:match("^(%S*)%s*(.-)$")
	if command == "" then
        if UIFrame:IsShown() then
            UIFrame:Hide()
        else
            if InCombatLockdown() then
                print("|cffFF0000PreyNotifier:|r Cannot open menu while in combat!")
            else
                UIFrame:Show()
            end
        end
    elseif command == "toggle" then
        isEnabled = not isEnabled
        if PreyNotifierDB then PreyNotifierDB["_IsEnabled"] = isEnabled end
        if isEnabled then print("|cff00FF00PreyNotifier:|r Tracking Enabled.")
        else print("|cffFF0000PreyNotifier:|r Tracking Disabled.") end
	elseif command == "timer" then
        if rest and rest:match("^%d+$") then
            local newTime = tonumber(rest)
            if newTime >= 30 and newTime <= 120 then
                PreyNotifierDB["_Cooldown"] = newTime
                print("|cff00FF00PreyNotifier:|r Alert cooldown set to " .. newTime .. " seconds.")
                if UIFrame and UIFrame:IsShown() then
                    CooldownSlider:SetValue(newTime)
                end
            else
                print("|cffFF0000PreyNotifier Error:|r Timer value must be between 30 and 120.")
            end
        else
            print("|cffFF0000PreyNotifier Error:|r Invalid input. Please enter a whole number (e.g., /pn timer 45).")
        end
	elseif command == "version" then
        local version = C_AddOns.GetAddOnMetadata("PreyNotifier", "Version") 
        if not version then version = "Unknown" end 
        print("|cffCC0000--- PreyNotifier By|r |cffF48CBAMikeWho|r-Dark Iron ---")
        print("|cffCC0000--- PreyNotifier Version " .. version .. " ---|r")
    elseif command == "help" then
        print("|cffCC0000--- PreyNotifier by|r |cffF48CBAMikeWho|r-Dark Iron ---|r")
		print("  --- Sounds are played on the Dialog Channel ---")
		print("  --- Set your Keybinds directly in the /pn Keybinds Tab ---")
		print("|cffCC0000--- PreyNotifier Commands ---|r") 
		print("|cffCC0000--- All Commands can be Used With |cffFFFF00/prey|r, |cffFFFF00/pn|r, or |cffFFFF00/PreyNotifier|r  ---")
        print("  |cffFFFF00/prey|r - Opens the Tracking Interface.")
        print("  |cffFFFF00/prey toggle|r - Toggles tracking alerts on and off.")
        print("  |cffFFFF00/prey timer <seconds>|r - Sets alert cooldown (30s-120s).")
		print("  |cffFFFF00/prey version|r - Displays the current addon version.")
		print("  |cffFFFF00/prey help|r - Displays this helpful information.")
	else
        print("|cffFF0000PreyNotifier:|r Unknown command. Type |cffFFFF00/prey help|r or |cffFFFF00/pn help|r for a list of commands.")
    end
end

-- ==========================================
-- 3. MINIMAP BUTTON (Icon & Position)
-- ==========================================
local radiusOffset = 10 
local MinimapButton = CreateFrame("Button", "PreyNotifierMinimapButton", Minimap)
MinimapButton:SetSize(32, 32)
MinimapButton:SetFrameStrata("MEDIUM")
MinimapButton:SetFrameLevel(8)

local iconBg = MinimapButton:CreateTexture(nil, "BACKGROUND")
iconBg:SetTexture("Interface\\AddOns\\PreyNotifier\\Art\\preynotifier_minibutton.png") 
iconBg:SetSize(32, 32) 
iconBg:SetPoint("CENTER", 1, -2)

local border = MinimapButton:CreateTexture(nil, "OVERLAY")
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetSize(56, 56)
border:SetPoint("TOPLEFT")

local function UpdatePosition(angle)
    local radius = (Minimap:GetWidth() / 2) + radiusOffset
    local x = math.cos(angle) * radius
    local y = math.sin(angle) * radius
    MinimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

MinimapButton:RegisterForDrag("LeftButton")
MinimapButton:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
        local scale = Minimap:GetEffectiveScale()
        local cx, cy = Minimap:GetCenter()
        local xpos, ypos = GetCursorPosition()
        local angle = math.atan2((ypos / scale) - cy, (xpos / scale) - cx)
        UpdatePosition(angle)
    end)
end)

MinimapButton:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = Minimap:GetCenter()
    local xpos, ypos = GetCursorPosition()
    if PreyNotifierDB then
        PreyNotifierDB["_MinimapAngle"] = math.atan2((ypos / scale) - cy, (xpos / scale) - cx)
    end
end)

MinimapButton:SetScript("OnEnter", function(self)
    local version = C_AddOns.GetAddOnMetadata("PreyNotifier", "Version") or "Unknown"
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("|cffCC0000PreyNotifier|r by |cffF48CBAMikeWho|r-Dark Iron")
    GameTooltip:AddLine("Version: |cffFFFF00" .. version .. "|r", 1, 1, 1)
    GameTooltip:AddLine("Left-Click to open menu.", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Drag to move.", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)

MinimapButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

MinimapButton:SetScript("OnClick", function(self, button)
    if button == "LeftButton" then
        if UIFrame:IsShown() then 
            UIFrame:Hide() 
        else 
            if InCombatLockdown() then
                print("|cffFF0000PreyNotifier:|r Cannot open menu while in combat!")
            else
                UIFrame:Show() 
            end
        end
    end
end)

-- ==========================================
-- 4. CORE EVENTS & TRACKING LOGIC
-- ==========================================

-- ------------------------------------------
-- GUILD LOGO TRACKER UI SETUP (Standalone & Movable)
-- ------------------------------------------
-- Reusing the name "PreyNotifierProgBar" so your saved position still works!
CustomTracker = CreateFrame("Frame", "PreyNotifierProgBar", UIParent)
CustomTracker:SetSize(128, 128)
CustomTracker:SetPoint("TOP", UIParent, "TOP", 0, -100) 

-- Make it movable via Right-Click
CustomTracker:SetMovable(true)
CustomTracker:EnableMouse(true)
CustomTracker:RegisterForDrag("RightButton")
CustomTracker:SetScript("OnDragStart", function(self) self:StartMoving() end)
CustomTracker:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relativePoint, xOfs, yOfs = self:GetPoint()
    if PreyNotifierDB then
        PreyNotifierDB["_ProgPoint"] = point
        PreyNotifierDB["_ProgRel"] = relativePoint
        PreyNotifierDB["_ProgX"] = xOfs
        PreyNotifierDB["_ProgY"] = yOfs
    end
end)

-- Tooltip Logic
CustomTracker:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText("|cffCC0000PreyNotifier Tracker|r")
    GameTooltip:AddLine("Right-Click and drag to move", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)
CustomTracker:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Base empty background
local Background = CustomTracker:CreateTexture(nil, "BACKGROUND")
Background:SetAllPoints()
Background:SetTexture("Interface\\AddOns\\PreyNotifier\\Art\\guild_base.tga")

-- Piece 1 (33%)
local Stage1 = CustomTracker:CreateTexture(nil, "ARTWORK")
Stage1:SetAllPoints()
Stage1:SetTexture("Interface\\AddOns\\PreyNotifier\\Art\\guild_level_one.tga")

-- Piece 2 (66%)
local Stage2 = CustomTracker:CreateTexture(nil, "ARTWORK")
Stage2:SetAllPoints()
Stage2:SetTexture("Interface\\AddOns\\PreyNotifier\\Art\\guild_level_two.tga")

-- Piece 3 (100%)
local Stage3 = CustomTracker:CreateTexture(nil, "ARTWORK")
Stage3:SetAllPoints()
Stage3:SetTexture("Interface\\AddOns\\PreyNotifier\\Art\\guild_full.tga")

-- Load the Glow Art
local GlowArt = CustomTracker:CreateTexture(nil, "BORDER")
GlowArt:SetAllPoints()
GlowArt:SetTexture("Interface\\AddOns\\PreyNotifier\\Art\\guild_glow.tga")
GlowArt:SetBlendMode("ADD")
GlowArt:SetVertexColor(1, 1, 0)
GlowArt:SetAlpha(0) 

-- Create the Pulse Animation
local GlowPulse = GlowArt:CreateAnimationGroup()
GlowPulse:SetLooping("BOUNCE")
local AlphaAnim = GlowPulse:CreateAnimation("Alpha")
AlphaAnim:SetFromAlpha(0.2) 
AlphaAnim:SetToAlpha(1.0)   
AlphaAnim:SetDuration(1.2)  
GlowPulse:Play()

-- Keep the text below the guildlogo
CustomTracker.textBg = CustomTracker:CreateTexture(nil, "BACKGROUND")
CustomTracker.textBg:SetColorTexture(0, 0, 0, 0.6) -- Semi-transparent black background

CustomTracker.text = CustomTracker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
CustomTracker.text:SetPoint("TOP", CustomTracker, "BOTTOM", 0, -5)
CustomTracker.text:SetText("Searching for Prey...")

CustomTracker.textBg:SetPoint("TOPLEFT", CustomTracker.text, "TOPLEFT", -5, 2)
CustomTracker.textBg:SetPoint("BOTTOMRIGHT", CustomTracker.text, "BOTTOMRIGHT", 5, -2)

CustomTracker:Hide()

-- ------------------------------------------
-- AMBUSH WARNING GRAPHIC
-- ------------------------------------------
local AmbushWarningFrame = CreateFrame("Frame", nil, CustomTracker)
AmbushWarningFrame:SetSize(150, 70)
AmbushWarningFrame:SetPoint("BOTTOM", CustomTracker, "TOP", 0, -20)
AmbushWarningFrame:EnableMouse(false)

local AmbushTexture = AmbushWarningFrame:CreateTexture(nil, "ARTWORK")
AmbushTexture:SetAllPoints()
AmbushTexture:SetTexture("Interface\\AddOns\\PreyNotifier\\Art\\ambushed_test.tga")

-- Draw glow above the base art so additive blending is actually visible.
local AmbushGlow = AmbushWarningFrame:CreateTexture(nil, "OVERLAY", nil, 1)
AmbushGlow:SetPoint("TOPLEFT", -6, 6)
AmbushGlow:SetPoint("BOTTOMRIGHT", 6, -6)
AmbushGlow:SetTexture("Interface\\AddOns\\PreyNotifier\\Art\\ambushed_test_glow.tga")
AmbushGlow:SetBlendMode("ADD")
AmbushGlow:SetVertexColor(1, 1, 1)
AmbushGlow:SetAlpha(0)

local AmbushGlowPulse = AmbushGlow:CreateAnimationGroup()
AmbushGlowPulse:SetLooping("BOUNCE")
local AmbushAlphaAnim = AmbushGlowPulse:CreateAnimation("Alpha")
AmbushAlphaAnim:SetFromAlpha(0.3)
AmbushAlphaAnim:SetToAlpha(1.0)
AmbushAlphaAnim:SetDuration(0.5) -- Urgent pulse

AmbushWarningFrame:SetScript("OnShow", function()
    AmbushGlowPulse:Stop()
    AmbushGlow:SetAlpha(0.3)
    AmbushGlowPulse:Play()
end)
AmbushWarningFrame:SetScript("OnHide", function()
    AmbushGlowPulse:Stop()
    AmbushGlow:SetAlpha(0)
end)

local warningHideTimer
local currentWarningType = nil

local function ShowWarningGraphic(warningType)
    if not (CustomTracker and CustomTracker.AmbushWarning) then return end

    if warningType == "ambush" and PreyNotifierDB and PreyNotifierDB["_ShowAmbushWarning"] == false then
        CustomTracker.AmbushWarning:Hide()
        currentWarningType = nil
        if warningHideTimer and not warningHideTimer:IsCancelled() then
            warningHideTimer:Cancel()
        end
        warningHideTimer = nil
        return
    end

    if warningType == "echo" and PreyNotifierDB and PreyNotifierDB["_ShowEchoWarning"] == false then
        CustomTracker.AmbushWarning:Hide()
        currentWarningType = nil
        if warningHideTimer and not warningHideTimer:IsCancelled() then
            warningHideTimer:Cancel()
        end
        warningHideTimer = nil
        return
    end

    local root = "Interface\\AddOns\\PreyNotifier\\Art\\"
    if warningType == "echo" then
        AmbushTexture:SetTexture(root .. "echo.tga")
        AmbushGlow:Hide()
    else
        local selected = GetAmbushGraphicOption(PreyNotifierDB and PreyNotifierDB["_AmbushGraphicStyle"])
        AmbushTexture:SetTexture(root .. selected.texture)
        if selected.key == "ambushed_shield" then
            AmbushGlow:Hide()
        else
            -- Use the custom glow texture for other styles
            AmbushGlow:Show()
            AmbushGlow:SetTexture(root .. selected.glow)
            AmbushGlow:SetVertexColor(1, 1, 1) -- Reset to white for custom glow textures
        end
    end

    currentWarningType = warningType
    CustomTracker.AmbushWarning:Show()

    if warningHideTimer and not warningHideTimer:IsCancelled() then
        warningHideTimer:Cancel()
    end
    warningHideTimer = C_Timer.NewTimer(5, function()
        if CustomTracker and CustomTracker.AmbushWarning then
            CustomTracker.AmbushWarning:Hide()
        end
        currentWarningType = nil
        warningHideTimer = nil
    end)
end

ApplyAmbushWarningStyle = function(styleKey)
    local selected = GetAmbushGraphicOption(styleKey or (PreyNotifierDB and PreyNotifierDB["_AmbushGraphicStyle"]))
    local root = "Interface\\AddOns\\PreyNotifier\\Art\\"
    if currentWarningType ~= "echo" then
        AmbushTexture:SetTexture(root .. selected.texture)
        if selected.key == "ambushed_shield" then
            AmbushGlow:Hide()
        else
            -- Use the custom glow texture for other styles
            AmbushGlow:Show()
            AmbushGlow:SetTexture(root .. selected.glow)
            AmbushGlow:SetVertexColor(1, 1, 1) -- Reset to white for custom glow textures
        end
    end
end

ApplyAmbushWarningStyle()
AmbushWarningFrame:Hide()
CustomTracker.AmbushWarning = AmbushWarningFrame -- Attach it for easy access

-- ------------------------------------------
-- DEBUFF TRACKING FRAMES
-- ------------------------------------------
local BCFrame = CreateFrame("Frame", nil, CustomTracker)
BCFrame:SetHeight(20)
BCFrame.bg = BCFrame:CreateTexture(nil, "BACKGROUND")
BCFrame.bg:SetColorTexture(0, 0, 0, 0.6)
BCFrame.bg:SetAllPoints()

BCFrame.glow = BCFrame:CreateTexture(nil, "BACKGROUND", nil, -1)
BCFrame.glow:SetPoint("TOPLEFT", -2, 2)
BCFrame.glow:SetPoint("BOTTOMRIGHT", 2, -2)
BCFrame.glow:SetColorTexture(1, 0, 0, 1)
BCFrame.glow:SetBlendMode("ADD")
BCFrame.glowAnim = BCFrame.glow:CreateAnimationGroup()
BCFrame.glowAnim:SetLooping("BOUNCE")
local bcAlphaAnim = BCFrame.glowAnim:CreateAnimation("Alpha")
bcAlphaAnim:SetFromAlpha(0.2)
bcAlphaAnim:SetToAlpha(1.0)
bcAlphaAnim:SetDuration(0.5)

BCFrame:SetScript("OnShow", function(self) self.glowAnim:Play() end)
BCFrame:SetScript("OnHide", function(self) self.glowAnim:Stop() end)

BCFrame.icon = BCFrame:CreateTexture(nil, "ARTWORK")
BCFrame.icon:SetSize(14, 14) -- Roughly 50% of a standard debuff icon
BCFrame.icon:SetPoint("LEFT", 4, 0)
BCFrame.icon:SetTexture("Interface\\Icons\\ability_blackhand_marked4death")

BCFrame.text = BCFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
BCFrame.text:SetPoint("LEFT", BCFrame.icon, "RIGHT", 4, 0)
BCFrame:Hide()
BCFrame.isActive = false

BCFrame:SetScript("OnUpdate", function(self)
    if self.expirationTime and self.expirationTime > 0 then
        local timeLeft = self.expirationTime - GetTime()
        if timeLeft > 0 then
            self.text:SetText(string.format("Bloody Command: %.1fs", timeLeft))
        else
            self.text:SetText("Bloody Command: 0.0s")
            -- Allow the frame to hide itself if it naturally expires mid-combat
            if self.isActive and InCombatLockdown() then
                self.isActive = false
                self:Hide()
                UpdateDebuffs()
            end
        end
        self:SetWidth(self.icon:GetWidth() + self.text:GetStringWidth() + 12)
    end
end)

local TormentFrame = CreateFrame("Frame", nil, CustomTracker)
TormentFrame:SetHeight(20)
TormentFrame.bg = TormentFrame:CreateTexture(nil, "BACKGROUND")
TormentFrame.bg:SetColorTexture(0, 0, 0, 0.6)
TormentFrame.bg:SetAllPoints()

TormentFrame.glow = TormentFrame:CreateTexture(nil, "BACKGROUND", nil, -1)
TormentFrame.glow:SetPoint("TOPLEFT", -2, 2)
TormentFrame.glow:SetPoint("BOTTOMRIGHT", 2, -2)
TormentFrame.glow:SetColorTexture(1, 0, 0, 1)
TormentFrame.glow:SetBlendMode("ADD")
TormentFrame.glow:Hide()
TormentFrame.glowAnim = TormentFrame.glow:CreateAnimationGroup()
TormentFrame.glowAnim:SetLooping("BOUNCE")
local torAlphaAnim = TormentFrame.glowAnim:CreateAnimation("Alpha")
torAlphaAnim:SetFromAlpha(0.2)
torAlphaAnim:SetToAlpha(1.0)
torAlphaAnim:SetDuration(0.5)

TormentFrame:SetScript("OnShow", function(self) self.glowAnim:Play() end)
TormentFrame:SetScript("OnHide", function(self) self.glowAnim:Stop() end)

TormentFrame.icon = TormentFrame:CreateTexture(nil, "ARTWORK")
TormentFrame.icon:SetSize(14, 14)
TormentFrame.icon:SetPoint("LEFT", 4, 0)

TormentFrame.text = TormentFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
TormentFrame.text:SetPoint("LEFT", TormentFrame.icon, "RIGHT", 4, 0)
TormentFrame:Hide()

TormentFrame.lastTickTime = 0
TormentFrame.predictedStacks = 0

TormentFrame.glowState = 0
TormentFrame.lastWarnedStack = nil

function TormentFrame:UpdateDisplay(stacks)
    local isNightmare = PreyNotifierDB and PreyNotifierDB["_IsNightmare"]
    local multiplier = isNightmare and 4 or 2
    local showDebuffs = PreyNotifierDB and PreyNotifierDB["_TrackDebuffs"] ~= false

    local tYellow = PreyNotifierDB and PreyNotifierDB["_TormentYellow"] or 5
    local tRed = PreyNotifierDB and PreyNotifierDB["_TormentRed"] or 8

    local percent = stacks * multiplier
    self.text:SetText("Torment: " .. stacks .. "x | " .. percent .. "%")
    
    -- Colorize Text
    if stacks >= tRed then
        self.text:SetTextColor(1, 0, 0) -- Red
    elseif stacks >= tYellow then
        self.text:SetTextColor(1, 1, 0) -- Yellow
    else
        self.text:SetTextColor(1, 1, 1) -- Default White
    end

    local newGlowState = 0
    if isNightmare then
        if stacks >= tRed then newGlowState = 2
        elseif stacks >= tYellow then newGlowState = 1 end
    else
        if stacks >= tYellow then newGlowState = 1 end
    end
    
    if self.glowState ~= newGlowState then
        self.glowState = newGlowState
        if newGlowState == 2 then
            self.glow:Show()
            torAlphaAnim:SetDuration(0.15) -- Very fast pulse for intense warning
        elseif newGlowState == 1 then
            self.glow:Show()
            torAlphaAnim:SetDuration(0.5) -- Normal pulse
        else
            self.glow:Hide()
        end
    end
    
    if not showDebuffs then
        self.glow:Hide()
    elseif self.glowState > 0 then
        self.glow:Show()
    end

    if isNightmare and stacks >= tRed then
        if self.lastWarnedStack ~= stacks then
            self.lastWarnedStack = stacks
            if showDebuffs then
                local iconTex = self.icon:GetTexture()
                local iconStr = iconTex and ("|T" .. tostring(iconTex) .. ":16|t") or ""
                print("|cffFF0000PreyNotifier: Warning:|r " .. iconStr .. "Torment at |cffFFFF00" .. stacks .. " stacks|r. Taking |cffFF0000" .. percent .. "%|r increased damage from all sources.")
            end
        end
    else
        if stacks < tRed then self.lastWarnedStack = nil end
    end

    self:SetWidth(self.icon:GetWidth() + self.text:GetStringWidth() + 12)
end

TormentFrame:SetScript("OnUpdate", function(self)
    if InCombatLockdown() and self.lastTickTime > 0 then
        if GetTime() - self.lastTickTime >= 60 then
            self.lastTickTime = self.lastTickTime + 60
            self.predictedStacks = self.predictedStacks + 1
            self:UpdateDisplay(self.predictedStacks)
        end 
    end
end)

UpdateDebuffs = function()
    if not IsHuntActive() then
        if isFlashSuppressed then
            SetCVar("screenEdgeFlash", defaultScreenFlash)
            if FullScreenStatus then 
                FullScreenStatus:SetAlpha(1) 
                FullScreenStatus:Show()
            end
            isFlashSuppressed = false
        end
        BCFrame:Hide()
        BCFrame.isActive = false
        TormentFrame:Hide()
        TormentFrame.glow:Hide()
        TormentFrame.lastTickTime = 0
        TormentFrame.predictedStacks = 0
        TormentFrame.glowState = 0
        TormentFrame.lastWarnedStack = nil
        return
    end

    local showDebuffs = PreyNotifierDB and PreyNotifierDB["_TrackDebuffs"] ~= false

    -- Bloody Command Check
    local bcAura = FindPlayerDebuff("Bloody Command")

    -- Explicitly clear the active state if the aura is gone and we are not in combat.
    -- This prevents the timer from continuing to run after a fight ends.
    if not bcAura and not InCombatLockdown() then
        BCFrame.isActive = false
    end

    local isBCActive = bcAura or BCFrame.isActive

    if isBCActive then
        if bcAura then
            BCFrame.expirationTime = bcAura.expirationTime
            BCFrame.isActive = true
        end
        
        if showDebuffs then
            BCFrame:Show()
        else
            BCFrame:Hide()
        end
        
        if PreyNotifierDB and PreyNotifierDB["_DisableBCFlash"] then
            if not isFlashSuppressed then
                defaultScreenFlash = GetCVar("screenEdgeFlash")
                SetCVar("screenEdgeFlash", "0")
                if FullScreenStatus then 
                    FullScreenStatus:SetAlpha(0) 
                    FullScreenStatus:Hide()
                end
                isFlashSuppressed = true
            end
        end
    else
        if isFlashSuppressed then
            SetCVar("screenEdgeFlash", defaultScreenFlash)
            if FullScreenStatus then 
                FullScreenStatus:SetAlpha(1) 
                FullScreenStatus:Show()
            end
            isFlashSuppressed = false
        end
        BCFrame:Hide()
    end

    -- Torment Check
    local tormentAura = FindPlayerDebuff("Torment")
    if tormentAura then
        TormentFrame.icon:SetTexture(tormentAura.icon)
        local stacks = (tormentAura.applications and tormentAura.applications > 0) and tormentAura.applications or 1
        
        -- Sync base time if stacks change unpredictably or first application
        if TormentFrame.lastTickTime == 0 or stacks ~= TormentFrame.predictedStacks then
            TormentFrame.lastTickTime = GetTime()
            TormentFrame.predictedStacks = stacks
        end
        
        TormentFrame:UpdateDisplay(stacks)
        TormentFrame:Show()
    else
        if not InCombatLockdown() then
            TormentFrame:Hide()
            TormentFrame.glow:Hide()
            TormentFrame.lastTickTime = 0
            TormentFrame.predictedStacks = 0
            TormentFrame.glowState = 0
            TormentFrame.lastWarnedStack = nil
        end
    end
    
    if TormentFrame.predictedStacks > 0 and showDebuffs then
        TormentFrame:Show()
    else
        TormentFrame:Hide()
        TormentFrame.glow:Hide()
    end

    -- Dynamic Stacking Layout
    BCFrame:ClearAllPoints()
    TormentFrame:ClearAllPoints()

    if BCFrame:IsShown() then
        BCFrame:SetPoint("TOP", CustomTracker.text, "BOTTOM", 0, -5)
        if TormentFrame:IsShown() then
            TormentFrame:SetPoint("TOP", BCFrame, "BOTTOM", 0, -2)
        end
    elseif TormentFrame:IsShown() then
        TormentFrame:SetPoint("TOP", CustomTracker.text, "BOTTOM", 0, -5)
    end
    
    if TormentFrame:IsShown() then
        TormentFrame:SetWidth(TormentFrame.icon:GetWidth() + TormentFrame.text:GetStringWidth() + 12)
    end
end
-- ------------------------------------------
-- DYNAMIC WIDGET SCANNER
-- ------------------------------------------
UpdateProgressBar = function() 
    -- MASTER KILL SWITCH: Only show if the hunt is fully active.
    if not IsHuntActive() then
        if CustomTracker then CustomTracker:Hide() end
        UpdateDebuffs() -- Ensure debuff trackers are also hidden.
        return
    end

    if PreyNotifierDB and PreyNotifierDB["_ShowProgressBar"] == false then
        CustomTracker:Hide()
        return
    end

    local foundWidget = false
    if not C_UIWidgetManager then return end

    local candidateSets = {
        C_UIWidgetManager.GetTopCenterWidgetSetID(),
        C_UIWidgetManager.GetObjectiveTrackerWidgetSetID(),
        C_UIWidgetManager.GetBelowMinimapWidgetSetID(),
        C_UIWidgetManager.GetPowerBarWidgetSetID()
    }

    for _, setID in ipairs(candidateSets) do
        if setID then
            local widgets = C_UIWidgetManager.GetAllWidgetsBySetID(setID)
            if widgets then
                for _, widget in ipairs(widgets) do
                    if widget.widgetType == 31 then
                        local info = C_UIWidgetManager.GetPreyHuntProgressWidgetVisualizationInfo(widget.widgetID)
                        
						-- ==========================================
                        -- GHOST THE DEFAULT BLIZZARD UI
                        -- ==========================================
                        local blizzContainers = {
                            UIWidgetTopCenterContainerFrame,
                            UIWidgetBelowMinimapContainerFrame,
                            UIWidgetPowerBarContainerFrame,
                            ObjectiveTrackerUIWidgetContainer
                        }
                        
                        for _, container in ipairs(blizzContainers) do
                            if container and container.widgetFrames and container.widgetFrames[widget.widgetID] then
                                if PreyNotifierDB and PreyNotifierDB["_HideBlizzUI"] then
                                    -- Ghost the crystal widget and kill its tooltip hitbox
                                    container.widgetFrames[widget.widgetID]:SetAlpha(0) 
                                    container.widgetFrames[widget.widgetID]:EnableMouse(false)
                                    
                                    -- Ghost the entire Encounter Bar parent (kills the blood background)
                                    if container == UIWidgetPowerBarContainerFrame then
                                        container:SetAlpha(0)
                                        container:EnableMouse(false)
                                    end
                                else
                                    -- Restore the crystal widget and its tooltip
                                    container.widgetFrames[widget.widgetID]:SetAlpha(1)
                                    container.widgetFrames[widget.widgetID]:EnableMouse(true)
                                    
                                    -- Restore the Encounter Bar parent
                                    if container == UIWidgetPowerBarContainerFrame then
                                        container:SetAlpha(1)
                                        container:EnableMouse(true)
                                    end
                                end
                            end
                        end
                        -- ==========================================
						
						
                        if info and info.shownState == 1 then
                            local pct = 0
                            local stageName = nil 
                            
                            if info.progressPercentage and info.progressPercentage > 0 then
                                pct = info.progressPercentage
                            elseif info.barValue and info.barMax and info.barMax > 0 then
                                pct = math.floor((info.barValue / info.barMax) * 100)
                            elseif info.value and info.max and info.max > 0 then
                                pct = math.floor((info.value / info.max) * 100)
                            elseif info.progressState then
                                if info.progressState == 1 then pct = 33; stageName = "Searching for Prey"
                                elseif info.progressState == 2 then pct = 66; stageName = "Tracking your Prey"
                                elseif info.progressState == 3 then pct = 100; stageName = "Found your Prey"
                                else pct = 0; stageName = "Begin the Hunt" end
                            end
                            
                            -- GRAPHICAL PROGRESS LOGIC
                            if pct >= 33 then Stage1:Show() else Stage1:Hide() end
                            if pct >= 66 then Stage2:Show() else Stage2:Hide() end
                            if pct >= 100 then Stage3:Show() else Stage3:Hide() end


							-- GLOW LOGIC (Only active at 100%)
                            if pct >= 100 then
                                GlowArt:Show()
                                if not GlowPulse:IsPlaying() then
                                    GlowPulse:Play()
                                end
                            else
                                GlowArt:Hide()
                                GlowPulse:Stop()
                            end
                            
                            -- TEXT LOGIC
                            if stageName then
                                CustomTracker.text:SetText("Hunt Stage: " .. stageName .. " (" .. pct .. "%)")
                            else
                                CustomTracker.text:SetText("Hunt Progress: " .. pct .. "%")
                            end
                            
                            if pct >= 100 then
                                CustomTracker.text:SetTextColor(0, 0.8, 0) -- Green text when done
                                isHuntComplete = true
                            else
                                CustomTracker.text:SetTextColor(1, 1, 1) -- White text normally
                                isHuntComplete = false
                            end
                            
                            CustomTracker:Show()
                            foundWidget = true
                            break
                        end
                    end
                end
            end
        end
        if foundWidget then break end
    end

    if not foundWidget then
        CustomTracker:Hide()
    end
    
    UpdateDebuffs()
end




-- ------------------------------------------
-- EVENT REGISTRATIONS
-- ------------------------------------------
PreyAddon:RegisterEvent("ADDON_LOADED")
PreyAddon:RegisterEvent("NAME_PLATE_UNIT_ADDED")
PreyAddon:RegisterEvent("PLAYER_TARGET_CHANGED")
PreyAddon:RegisterEvent("QUEST_ACCEPTED")
PreyAddon:RegisterEvent("UPDATE_UI_WIDGET") 
PreyAddon:RegisterEvent("QUEST_REMOVED")
PreyAddon:RegisterEvent("PLAYER_ENTERING_WORLD")
PreyAddon:RegisterEvent("PLAYER_REGEN_DISABLED")
PreyAddon:RegisterEvent("PLAYER_REGEN_ENABLED")
PreyAddon:RegisterEvent("ZONE_CHANGED_NEW_AREA")
PreyAddon:RegisterEvent("UNIT_AURA")
PreyAddon:RegisterEvent("CHAT_MSG_MONSTER_YELL")
PreyAddon:RegisterEvent("CHAT_MSG_MONSTER_SAY")
PreyAddon:RegisterEvent("PLAYER_LOGOUT")
PreyAddon:RegisterEvent("PLAYER_ALIVE")
PreyAddon:RegisterEvent("PLAYER_UNGHOST")

local function ScanQuestLogForPrey()
    if not PreyNotifierDB then return end
    
    local currentPrimary = PreyNotifierDB["_PrimaryTarget"]
    local foundCurrentPrimary = false
    local firstFoundPrey = nil
    local isNightmare = false
    local isHard = false
    
    local numEntries = C_QuestLog.GetNumQuestLogEntries()
    for i = 1, numEntries do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.questID then
            if info.title and info.title:match("^Prey:") then
                if info.title:match("%(Nightmare%)") then
                    isNightmare = true
                elseif info.title:match("%(Hard%)") then
                    isHard = true
                end
                local mobName = info.title:match("^Prey:%s+(.-)%s+%([^)]+%)$")
                
                if mobName then
                    if not firstFoundPrey then firstFoundPrey = mobName end
                    if mobName == currentPrimary then
                        foundCurrentPrimary = true
                        break
                    end
                end
            end
        end
    end

    -- Cleanup if our primary target is no longer in the quest log
    if currentPrimary and not foundCurrentPrimary then
        PreyNotifierDB["_PrimaryTarget"] = nil
        currentPrimary = nil
        if not InCombatLockdown() then
            PreyNotifierTargetBtn:SetAttribute("macrotext1", "")
            UpdateTargetButton()
        end
        if CustomTracker then CustomTracker:Hide() end
        print("|cffFF9900PreyNotifier:|r Offline completion detected. Cleared missing Primary Target.")
        if UIFrame and UIFrame:IsShown() then UpdateTargetList() end
        isHuntComplete = false
    end

    PreyNotifierDB["_IsNightmare"] = isNightmare
    PreyNotifierDB["_IsHard"] = isHard

    -- Setup target if we found one
    local targetToSet = currentPrimary or firstFoundPrey
    if targetToSet then
        if not PreyNotifierDB[targetToSet] then
            PreyNotifierDB[targetToSet] = true
            print("|cff00FF00PreyNotifier:|r Auto-added |cffFFFF00" .. targetToSet .. "|r to the hunt list.")
        end
        
        if PreyNotifierDB["_PrimaryTarget"] ~= targetToSet then
            if not InCombatLockdown() then
                PreyNotifierDB["_PrimaryTarget"] = targetToSet
                PreyNotifierTargetBtn:SetAttribute("macrotext1", "/cleartarget\n/target " .. targetToSet)
                UpdateTargetButton()
                print("|cff00FF00PreyNotifier:|r Auto-detected hunt! Primary Target set to |cffFFFF00" .. targetToSet .. "|r.")
            else
                print("|cffFF9900PreyNotifier:|r Hunt picked up, but cannot auto-set Primary Target while in combat.")
            end
        else
            if not InCombatLockdown() then
                PreyNotifierTargetBtn:SetAttribute("macrotext1", "/cleartarget\n/target " .. targetToSet)
                UpdateTargetButton()
            end
        end
        
        if UIFrame and UIFrame:IsShown() then UpdateTargetList() end
    end
end

-- ------------------------------------------
-- MAIN EVENT HANDLER
-- ------------------------------------------
PreyAddon:SetScript("OnEvent", function(self, event, arg1, arg2)

	-- KICKSTART THE UI ON LOGIN/RELOAD
    if event == "PLAYER_ENTERING_WORLD" then
        ScanQuestLogForPrey()
        UpdateProgressBar()
        UpdateTargetButton()
        return
    end
	-- WAKE UP / SLEEP WHEN CHANGING ZONES
    if event == "ZONE_CHANGED_NEW_AREA" then
        UpdateProgressBar()
        UpdateTargetButton()
        return
    end
	-- DEBUFF TRACKER & HUNT STATE CHANGE
    if event == "UNIT_AURA" and arg1 == "player" then
        -- The "Bloodsworn" debuff is our key for IsHuntActive(), so we need to update everything when any aura changes.
        UpdateProgressBar()
        UpdateTargetButton()
        return
    end
    -- BLOODY COMMAND CHAT TRACKER
    if event == "CHAT_MSG_MONSTER_YELL" or event == "CHAT_MSG_MONSTER_SAY" then
        if not IsInHuntZone() or not CustomTracker:IsShown() then return end
        
        local msg = arg1
        local sender = arg2
        if sender and sender:match("Astalor Bloodsworn") then
            if msg and (msg:match("Kill for me. Now!") or msg:match("Drain their anguish!")) then
                BCFrame.expirationTime = GetTime() + 20
                if not BCFrame.isActive then
                    BCFrame.isActive = true
                    if PreyNotifierDB and PreyNotifierDB["_TrackDebuffs"] ~= false then
                        print("|cffFF0000PreyNotifier: WARNING: Bloody Command applied!|r")
                    end
                end
                UpdateDebuffs()
            end
        end
        return
    end
	-- AUTO-HIDE MENU IN COMBAT
    if event == "PLAYER_REGEN_DISABLED" then
        if UIFrame and UIFrame:IsShown() then
            UIFrame:Hide()
            if BindCatcher and BindCatcher:IsShown() then
                BindCatcher:Hide()
            end
            print("|cffFF9900PreyNotifier:|r Entering combat! Hiding menu.")
        end
        
        -- Prevent the predictive timer from fast-forwarding if you paused in a rested area
        if TormentFrame:IsShown() then
            TormentFrame.lastTickTime = GetTime()
        end
        return
    end

    if event == "PLAYER_LOGOUT" then
        if isFlashSuppressed then
            SetCVar("screenEdgeFlash", defaultScreenFlash)
            if FullScreenStatus then 
                FullScreenStatus:SetAlpha(1)
                FullScreenStatus:Show() 
            end
        end
        return
    end

    if event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
        UpdateProgressBar()
        UpdateTargetButton()
        UpdateDebuffs()
        return
    end

	-- CLEANUP WHEN COMBAT ENDS
    if event == "PLAYER_REGEN_ENABLED" then
        UpdateProgressBar()
        UpdateTargetButton()
        UpdateDebuffs()
        return
    end

	-- ADDON LOADED LOGIC
    if event == "ADDON_LOADED" and arg1 == "PreyNotifier" then
        if type(PreyNotifierDB) ~= "table" then
            PreyNotifierDB = { ["_Cooldown"] = 45, ["_MinimapAngle"] = math.rad(225) }
        end
        
        if PreyNotifierDB["_IsEnabled"] ~= nil then
            isEnabled = PreyNotifierDB["_IsEnabled"]
        end
        
        -- Initialize checkbox state
        if PreyNotifierDB["_ShowProgressBar"] == nil then 
            PreyNotifierDB["_ShowProgressBar"] = true 
        end
        if PreyNotifierDB["_ShowTargetBtn"] == nil then
            PreyNotifierDB["_ShowTargetBtn"] = true
        end
        if PreyNotifierDB["_PlaySound"] == nil then
            PreyNotifierDB["_PlaySound"] = true
        end
        if PreyNotifierDB["_SoundFile"] == nil then
            PreyNotifierDB["_SoundFile"] = 552035
        end
        if PreyNotifierDB["_PlayEchoSound"] == nil then
            PreyNotifierDB["_PlayEchoSound"] = true
        end
        if PreyNotifierDB["_RaidWarnings"] == nil then
            PreyNotifierDB["_RaidWarnings"] = true
        end
        if PreyNotifierDB["_TrackDebuffs"] == nil then
            PreyNotifierDB["_TrackDebuffs"] = true
        end
        if PreyNotifierDB["_DisableBCFlash"] == nil then
            PreyNotifierDB["_DisableBCFlash"] = false
        end
        if PreyNotifierDB["_ShowAmbushWarning"] == nil then
            PreyNotifierDB["_ShowAmbushWarning"] = true
        end
        if PreyNotifierDB["_ShowEchoWarning"] == nil then
            PreyNotifierDB["_ShowEchoWarning"] = true
        end
        if PreyNotifierDB["_ShowMinimapIcon"] == nil then
            PreyNotifierDB["_ShowMinimapIcon"] = true
        end
        if PreyNotifierDB["_AmbushGraphicStyle"] == nil then
            PreyNotifierDB["_AmbushGraphicStyle"] = "sharp_blood"
        end
        PreyNotifierDB["_AmbushGraphicStyle"] = GetAmbushGraphicOption(PreyNotifierDB["_AmbushGraphicStyle"]).key
        if PreyNotifierDB["_EchoSoundFile"] == nil then
            PreyNotifierDB["_EchoSoundFile"] = 554099
        end
        if PreyNotifierDB["_TormentYellow"] == nil then
            PreyNotifierDB["_TormentYellow"] = 5
        end
        if PreyNotifierDB["_TormentRed"] == nil then
            PreyNotifierDB["_TormentRed"] = 8
        end
        
        UpdatePosition(PreyNotifierDB["_MinimapAngle"] or math.rad(225))
        if ApplyAmbushWarningStyle then
            ApplyAmbushWarningStyle(PreyNotifierDB["_AmbushGraphicStyle"])
        end
        if CustomTracker and CustomTracker.AmbushWarning and PreyNotifierDB["_ShowAmbushWarning"] == false then
            CustomTracker.AmbushWarning:Hide()
        end
        if PreyNotifierDB["_ShowMinimapIcon"] == false then
            PreyNotifierMinimapButton:Hide()
        end
        
        -- Load Progress Bar saved position
        if PreyNotifierDB["_ProgPoint"] then
            CustomTracker:ClearAllPoints()
            CustomTracker:SetPoint(PreyNotifierDB["_ProgPoint"], UIParent, PreyNotifierDB["_ProgRel"], PreyNotifierDB["_ProgX"], PreyNotifierDB["_ProgY"])
        end
        
        -- Delayed Startup Message
        C_Timer.After(2, function()
            local version = C_AddOns.GetAddOnMetadata("PreyNotifier", "Version") or "Unknown"
            print("|cffCC0000PreyNotifier:|r Version |cffFFFF00" .. version .. "|r Loaded")
            print("|cffCC0000PreyNotifier:|r type |cffFFFF00/pn|r to begin or |cffFFFF00/pn help|r for options")
            
            if PreyNotifierDB["_PrimaryTarget"] then
                PreyNotifierTargetBtn:SetAttribute("macrotext1", "/cleartarget\n/target " .. PreyNotifierDB["_PrimaryTarget"])
                UpdateTargetButton()
            end
            if PreyNotifierDB["_BtnPoint"] then
                PreyNotifierTargetBtn:ClearAllPoints()
                PreyNotifierTargetBtn:SetPoint(PreyNotifierDB["_BtnPoint"], UIParent, PreyNotifierDB["_BtnRel"], PreyNotifierDB["_BtnX"], PreyNotifierDB["_BtnY"])
            end
        end)
        return 
    end

    -- PROGRESS BAR UPDATE LOGIC
    if event == "UPDATE_UI_WIDGET" then
        UpdateProgressBar()
        return
    end
    
    -- AUTO-DETECT QUEST ACCEPTANCE
    if event == "QUEST_ACCEPTED" then
        local questId = arg2 and arg2 or arg1 
        local questName = C_QuestLog.GetTitleForQuestID(questId)
        
        if questName then
            if questName:match("^Prey:") then
                if questName:match("%(Nightmare%)") then
                    if PreyNotifierDB then 
                        PreyNotifierDB["_IsNightmare"] = true
                        PreyNotifierDB["_IsHard"] = false
                    end
                elseif questName:match("%(Hard%)") then
                    if PreyNotifierDB then 
                        PreyNotifierDB["_IsNightmare"] = false
                        PreyNotifierDB["_IsHard"] = true 
                    end
                end
            end
            local mobName = questName:match("^Prey:%s+(.-)%s+%([^)]+%)$")
            
            if mobName then
                if not PreyNotifierDB[mobName] then
                    PreyNotifierDB[mobName] = true
                    print("|cff00FF00PreyNotifier:|r Auto-added |cffFFFF00" .. mobName .. "|r to the hunt list.")
                end
                
                if PreyNotifierDB["_PrimaryTarget"] ~= mobName then
                    if not InCombatLockdown() then
                        PreyNotifierDB["_PrimaryTarget"] = mobName
                        PreyNotifierTargetBtn:SetAttribute("macrotext1", "/cleartarget\n/target " .. mobName)
                        UpdateTargetButton()
                        print("|cff00FF00PreyNotifier:|r Auto-detected hunt! Primary Target set to |cffFFFF00" .. mobName .. "|r.")
                    else
                        print("|cffFF9900PreyNotifier:|r Hunt picked up, but cannot auto-set Primary Target while in combat.")
                    end
                else
                    if not InCombatLockdown() then
                        PreyNotifierTargetBtn:SetAttribute("macrotext1", "/cleartarget\n/target " .. mobName)
                        UpdateTargetButton()
                    end
                end
                
                if UIFrame and UIFrame:IsShown() then
                    UpdateTargetList()
                end
                isHuntComplete = false
            end
        end
        return
    end
    
	-- AUTO-DETECT ABANDONED/COMPLETED QUESTS
    if event == "QUEST_REMOVED" then
        if PreyNotifierDB and PreyNotifierDB["_PrimaryTarget"] then
            local targetName = PreyNotifierDB["_PrimaryTarget"]
            local numEntries = C_QuestLog.GetNumQuestLogEntries()
            local found = false
            local foundNightmare = false
            local foundHard = false
            
            for i = 1, numEntries do
                local info = C_QuestLog.GetInfo(i)
                if info and not info.isHeader and info.questID then
                    if info.title and info.title:match("^Prey:") then
                        if info.title:match("%(Nightmare%)") then foundNightmare = true end
                        if info.title:match("%(Hard%)") then foundHard = true end
                        local mobName = info.title:match("^Prey:%s+(.-)%s+%([^)]+%)$")
                        
                        if mobName == targetName then
                            found = true
                        end
                    end
                end
            end
            if PreyNotifierDB then 
                PreyNotifierDB["_IsNightmare"] = foundNightmare 
                PreyNotifierDB["_IsHard"] = foundHard 
            end
            
            -- If the tracked prey is no longer in the quest log, clear the tracker!
            if not found then
                PreyNotifierDB["_PrimaryTarget"] = nil
                if not InCombatLockdown() then
                    PreyNotifierTargetBtn:SetAttribute("macrotext1", "")
                    UpdateTargetButton()
                end
                if CustomTracker then CustomTracker:Hide() end
                print("|cffFF9900PreyNotifier:|r Quest removed. Primary Target tracking cleared.")
                if UIFrame and UIFrame:IsShown() then
                    UpdateTargetList()
                end
            end
        end
        return
    end
	
	
    -- AMBUSH TRACKING LOGIC
    if not isEnabled then return end
    
    -- MASTER KILL SWITCH: Only scan for ambushes if the hunt is fully active.
    if not IsHuntActive() then return end
    
    local inInstance, instanceType = IsInInstance()
    if inInstance then return end
    
    local currentUnit = (event == "PLAYER_TARGET_CHANGED") and "target" or arg1
    if not currentUnit or not UnitExists(currentUnit) then return end
    if UnitIsDead(currentUnit) then return end
    
    local mobName = UnitName(currentUnit)
    if type(mobName) ~= "string" then return end    
    if not mobName then return end 
    
    -- SAFETY CHECK: Prevent errors from Blizzard's restricted "secret" nameplate strings in protected areas
    local isSafeString = pcall(function() return mobName == "" end)
    if not isSafeString then return end
    
    -- ECHO OF PREDATION TRACKING
    if mobName == "Echo of Predation" and PreyNotifierDB and PreyNotifierDB["_IsNightmare"] then
        local currentTime = GetTime()
        if (currentTime - lastEchoAlertTime) >= 15 then
            lastEchoAlertTime = currentTime 

            ShowWarningGraphic("echo")
            
            if PreyNotifierDB["_PlayEchoSound"] ~= false then
                local soundID = PreyNotifierDB["_EchoSoundFile"] or 554099
                local success = pcall(PlaySoundFile, soundID, "Dialog")
                if not success then
                    print("|cffFF0000PreyNotifier Error:|r Failed to play Echo alert sound. Check sound ID.")
                end
            end

            if PreyNotifierDB["_RaidWarnings"] ~= false then
                RaidNotice_AddMessage(RaidWarningFrame, "ECHO OF PREDATION DETECTED! INTERRUPT ITS CAST!", ChatTypeInfo["RAID_WARNING"])
            end
            print("|cffFF0000PreyNotifier: WARNING: Echo of Predation Detected! Interrupt its cast!|r")
        end
    end
    
    if not isHuntComplete and PreyNotifierDB and PreyNotifierDB[mobName] then
        -- Ignore non-attackable units (e.g., inspectable prey targets that are part of the tracking mini-game).
        if not UnitCanAttack("player", currentUnit) then
            return
        end

        local currentTime = GetTime()
        if (currentTime - lastAlertTime) >= (PreyNotifierDB["_Cooldown"] or 45) then
            lastAlertTime = currentTime 

            ShowWarningGraphic("ambush")
            
            if PreyNotifierDB["_PlaySound"] ~= false then
                local soundID = PreyNotifierDB["_SoundFile"] or 552035
                local success = pcall(PlaySoundFile, soundID, "Dialog")
                if not success then
                    print("|cffFF0000PreyNotifier Error:|r Failed to play ambush alert sound. Check sound ID.")
                end
            end

            if PreyNotifierDB["_RaidWarnings"] ~= false then
                RaidNotice_AddMessage(RaidWarningFrame, "PREY AMBUSH: " .. string.upper(mobName) .. "!", ChatTypeInfo["RAID_WARNING"])
            end
            print("|cffFF0000PreyNotifier: WARNING: Ambush Detected!|r")
        end
    end
end)



-- ==========================================
-- WIDGET DEBUGGER (/pnwidget)
-- ==========================================
SLASH_PREYWIDGET1 = "/pnwidget"
SLASH_PREYWIDGET2 = "/pnw"
SlashCmdList["PREYWIDGET"] = function()
    local c = C_UIWidgetManager
    if not c then return end
    
    local found = false
    for _, s in pairs({c.GetTopCenterWidgetSetID(), c.GetObjectiveTrackerWidgetSetID(), c.GetBelowMinimapWidgetSetID(), c.GetPowerBarWidgetSetID()}) do
        local w = s and c.GetAllWidgetsBySetID(s)
        if w then
            for _, v in pairs(w) do
                if v.widgetType == 31 then
                    local i = c.GetPreyHuntProgressWidgetVisualizationInfo(v.widgetID)
                    if i then
                        print("|cff00FFFF[PreyNotifier Widget]|r Raw Progress -> Pct: " .. tostring(i.progressPercentage) .. " | State: " .. tostring(i.progressState))
                        found = true
                    end
                end
            end
        end
    end
    if not found then
        print("|cffFF0000[PreyNotifier Widget]|r Could not find active Widget ID 31.")
    end
end