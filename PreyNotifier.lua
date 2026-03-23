local PreyAddon = CreateFrame("Frame")
local isEnabled = true
local lastAlertTime = 0 
local ValidHuntZones = {

    [2395] = true, -- Eversong Woods
    [2437] = true, -- Zul'Aman
	[2536] = true, -- Atal'aman
    [2405] = true, -- Voidstorm
	[2444] = true, -- Slayer's Rise
    [0004] = true, -- PlaceHolder until I find the value
}

local function IsInHuntZone()
    local mapID = C_Map.GetBestMapForUnit("player")
    if mapID and ValidHuntZones[mapID] then
        return true
    end
    return false
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
_G["BINDING_NAME_CLICK PreyNotifierTargetBtn:LeftButton"] = "Target Primary Prey"
_G["BINDING_NAME_CLICK PreyNotifierTargetBtn:MiddleButton"] = "Use Disarmed Trap"

-- ==========================================
-- 1. VISUAL INTERFACE (GUI) SETUP
-- ==========================================
local UIFrame = CreateFrame("Frame", "PreyNotifierUI", UIParent, "BasicFrameTemplateWithInset")
UIFrame:SetFrameStrata("DIALOG")
UIFrame:SetSize(375, 600) 
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
Tab1Btn:SetSize(100, 25)
Tab1Btn:SetPoint("TOPLEFT", UIFrame, "TOPLEFT", 15, -30)
Tab1Btn:SetText("Prey List")

local Tab2Btn = CreateFrame("Button", nil, UIFrame, "UIPanelButtonTemplate")
Tab2Btn:SetSize(100, 25)
Tab2Btn:SetPoint("LEFT", Tab1Btn, "RIGHT", 5, 0)
Tab2Btn:SetText("Options")

local PreyListTab = CreateFrame("Frame", nil, UIFrame)
PreyListTab:SetPoint("TOPLEFT", UIFrame, "TOPLEFT", 0, -60)
PreyListTab:SetPoint("BOTTOMRIGHT", UIFrame, "BOTTOMRIGHT", 0, 0)

local OptionsTab = CreateFrame("Frame", nil, UIFrame)
OptionsTab:SetPoint("TOPLEFT", UIFrame, "TOPLEFT", 0, -60)
OptionsTab:SetPoint("BOTTOMRIGHT", UIFrame, "BOTTOMRIGHT", 0, 0)
OptionsTab:Hide()

Tab1Btn:SetScript("OnClick", function()
    PreyListTab:Show()
    OptionsTab:Hide()
    Tab1Btn:LockHighlight()
    Tab2Btn:UnlockHighlight()
end)

Tab2Btn:SetScript("OnClick", function()
    PreyListTab:Hide()
    OptionsTab:Show()
    Tab1Btn:UnlockHighlight()
    Tab2Btn:LockHighlight()
end)
Tab1Btn:LockHighlight() -- Default to tab 1

-- ==========================================
-- TAB 1: PREY LIST CONTENT
-- ==========================================

-- Text Input Box
local InputBox = CreateFrame("EditBox", nil, PreyListTab, "InputBoxTemplate")
InputBox:SetPoint("TOPLEFT", 25, -10)
InputBox:SetSize(180, 30)
InputBox:SetAutoFocus(false)

-- Add Target Button
local AddButton = CreateFrame("Button", nil, PreyListTab, "UIPanelButtonTemplate")
AddButton:SetPoint("LEFT", InputBox, "RIGHT", 10, 0)
AddButton:SetSize(60, 25)
AddButton:SetText("Add")

-- ==========================================
-- TAB 2: OPTIONS CONTENT
-- ==========================================
-- Timer Slider Label
local SliderLabel = OptionsTab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
SliderLabel:SetPoint("TOPLEFT", 20, -20) 
SliderLabel:SetText("Alert Cooldown (Seconds):")

-- The Cooldown Slider
local CooldownSlider = CreateFrame("Slider", "PreyNotifierCooldownSlider", OptionsTab, "OptionsSliderTemplate")
CooldownSlider:SetPoint("TOPLEFT", SliderLabel, "BOTTOMLEFT", 0, -10) 
CooldownSlider:SetSize(180, 20)
CooldownSlider:SetMinMaxValues(30, 120)
CooldownSlider:SetValueStep(1)
CooldownSlider:SetObeyStepOnDrag(true)

local SliderValueText = CooldownSlider:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
SliderValueText:SetPoint("LEFT", CooldownSlider, "RIGHT", 10, 0)

-- Progress Bar Toggle Checkbox
local ShowBarChk = CreateFrame("CheckButton", "PreyNotifierShowBarChk", OptionsTab, "UICheckButtonTemplate")
ShowBarChk:SetPoint("TOPLEFT", CooldownSlider, "BOTTOMLEFT", -5, -20) 
ShowBarChk.text = ShowBarChk:CreateFontString(nil, "OVERLAY", "GameFontNormal")
ShowBarChk.text:SetPoint("LEFT", ShowBarChk, "RIGHT", 5, 0)
ShowBarChk.text:SetText("Show On-Screen Progress Bar")

-- Explanatory Subtext
local ShowBarSubtext = ShowBarChk:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
ShowBarSubtext:SetPoint("TOPLEFT", ShowBarChk, "BOTTOMLEFT", 5, -2) 
ShowBarSubtext:SetText("Displays ONLY when an active hunt is detected in the current zone.")
ShowBarSubtext:SetTextColor(0.65, 0.55, 0.15) -- A dimmed, muted gold/yellow


ShowBarChk:SetScript("OnClick", function(self)
    if PreyNotifierDB then
        PreyNotifierDB["_ShowProgressBar"] = self:GetChecked()
    end
    -- Call the global function if it exists
    if UpdateProgressBar then UpdateProgressBar() end
end)

-- ------------------------------------------
-- HIDE BLIZZARD UI CHECKBOX
-- ------------------------------------------
local HideBlizzChk = CreateFrame("CheckButton", "PreyNotifierHideBlizzChk", OptionsTab, "UICheckButtonTemplate")
HideBlizzChk:SetPoint("TOPLEFT", ShowBarSubtext, "BOTTOMLEFT", -5, -10) 
HideBlizzChk.text = HideBlizzChk:CreateFontString(nil, "OVERLAY", "GameFontNormal")
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
    if UpdateProgressBar then UpdateProgressBar() end
end)



local TestButton = CreateFrame("Button", nil, OptionsTab, "UIPanelButtonTemplate")
TestButton:SetPoint("TOPLEFT", HideBlizzSubtext, "BOTTOMLEFT", -5, -20)
TestButton:SetSize(100, 25)
TestButton:SetText("Test Sound")
TestButton:SetScript("OnClick", function()
    pcall(PlaySoundFile, 552035, "Dialog")
    print("|cff00FF00PreyNotifier:|r Playing test sound on Dialog channel.")
end)






-- ==========================================
-- 1.5 SECURE TARGETING BUTTON
-- ==========================================
local TargetBtn = CreateFrame("Button", "PreyNotifierTargetBtn", UIParent, "SecureActionButtonTemplate")
TargetBtn:SetSize(42, 42)
TargetBtn:SetPoint("CENTER", 0, -150)
TargetBtn:SetFrameStrata("HIGH") 

TargetBtn:RegisterForClicks("AnyDown", "AnyUp") 
TargetBtn:Hide()

-- LEFT CLICK: Target the Prey
TargetBtn:SetAttribute("type1", "macro")

-- MIDDLE CLICK: Use Disarmed Trap
TargetBtn:SetAttribute("type3", "macro")
TargetBtn:SetAttribute("macrotext3", "/run if GetItemCount(\"Disarmed Trap\") == 0 then print(\"|cffFF0000PreyNotifier: ERROR> No Disarmed Traps Available.|r\") end\n/use Disarmed Trap")


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
	GameTooltip:AddLine("Bind this to a key: Options > Keybindings > AddOns", 1, 0.82, 0)
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
ScrollFrame:SetPoint("BOTTOMRIGHT", PreyListTab, "BOTTOMRIGHT", -40, 50)

local ScrollChild = CreateFrame("Frame")
ScrollChild:SetSize(ScrollFrame:GetWidth(), 1) 
ScrollFrame:SetScrollChild(ScrollChild)

local listFrames = {}
local function UpdateTargetList()
    for _, row in ipairs(listFrames) do row:Hide() end
    if not PreyNotifierDB then return end
    
    local yOffset = 0 
    local rowIndex = 1
    
    for mobName, _ in pairs(PreyNotifierDB) do
        if not mobName:match("^_") then
            if not listFrames[rowIndex] then
                local row = CreateFrame("Frame", nil, ScrollChild)
                row:SetSize(290, 25) 
                
                local txt = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                txt:SetPoint("LEFT", 5, 0)
                txt:SetWidth(165) 
                txt:SetWordWrap(false) 
                txt:SetJustifyH("LEFT") 
                row.text = txt
                
                local delBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                delBtn:SetSize(25, 25)
                delBtn:SetPoint("RIGHT", 0, 0)
                delBtn:SetText("X")
                row.delBtn = delBtn

                local priBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                priBtn:SetSize(85, 25)
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
                PreyNotifierTargetBtn:Show()
                print("|cff00FF00PreyNotifier:|r Primary Target set to |cffFFFF00" .. mobName .. "|r.")
                UpdateTargetList() 
            end)
            
            currentRow.delBtn:SetScript("OnClick", function()
                PreyNotifierDB[mobName] = nil
                if PreyNotifierDB["_PrimaryTarget"] == mobName then
                    PreyNotifierDB["_PrimaryTarget"] = nil
                    if not InCombatLockdown() then
                        PreyNotifierTargetBtn:SetAttribute("macrotext1", "")
                        PreyNotifierTargetBtn:Hide()
                    else
                        print("|cffFF9900PreyNotifier:|r Primary Target deleted, but button cannot be hidden while in combat.")
                    end
                    -- NEW: Hide the progress bar
                    if PreyNotifierProgBar then PreyNotifierProgBar:Hide() end 
                end
                UpdateTargetList()
            end)
            
            currentRow:Show()
            yOffset = yOffset - 30
            rowIndex = rowIndex + 1
        end
    end
    
    ScrollChild:SetHeight(math.abs(yOffset))
end

local ClearPriBtn = CreateFrame("Button", nil, PreyListTab, "UIPanelButtonTemplate")
ClearPriBtn:SetSize(120, 25)
ClearPriBtn:SetPoint("TOPRIGHT", ScrollFrame, "BOTTOMRIGHT", 0, -10)
ClearPriBtn:SetText("Clear Primary")

ClearPriBtn:SetScript("OnClick", function()
    if InCombatLockdown() then
        print("|cffFF0000PreyNotifier:|r Cannot clear Primary Target while in combat!")
        return
    end
    
    if PreyNotifierDB["_PrimaryTarget"] then
        PreyNotifierDB["_PrimaryTarget"] = nil
        PreyNotifierTargetBtn:SetAttribute("macrotext1", "")
        PreyNotifierTargetBtn:Hide()
        -- NEW: Hide the progress bar
        if PreyNotifierProgBar then PreyNotifierProgBar:Hide() end 
        print("|cff00FF00PreyNotifier:|r Primary Target cleared. Button hidden.")
        UpdateTargetList() 
    end
end)

UIFrame:SetScript("OnShow", function()
    UpdateTargetList()
    if PreyNotifierDB and PreyNotifierDB["_Cooldown"] then
        CooldownSlider:SetValue(PreyNotifierDB["_Cooldown"])
        SliderValueText:SetText(PreyNotifierDB["_Cooldown"] .. "s")
    end
    if PreyNotifierDB and PreyNotifierDB["_ShowProgressBar"] ~= nil then
        ShowBarChk:SetChecked(PreyNotifierDB["_ShowProgressBar"])
    end
	if PreyNotifierDB and PreyNotifierDB["_HideBlizzUI"] ~= nil then
        HideBlizzChk:SetChecked(PreyNotifierDB["_HideBlizzUI"])
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
		print("  --- Bind a key to quick target primary prey. Options > Keybindings > AddOns ---")
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
iconBg:SetTexture("Interface\\AddOns\\PreyNotifier\\preynotifier_minibutton.png") 
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
-- DAGGER TRACKER UI SETUP (Standalone & Movable)
-- ------------------------------------------
-- Reusing the name "PreyNotifierProgBar" so your saved position still works!
local CustomTracker = CreateFrame("Frame", "PreyNotifierProgBar", UIParent)
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
Background:SetTexture("Interface\\AddOns\\PreyNotifier\\Art\\dagger_base.tga")

-- Piece 1 (33%)
local Stage1 = CustomTracker:CreateTexture(nil, "ARTWORK")
Stage1:SetAllPoints()
Stage1:SetTexture("Interface\\AddOns\\PreyNotifier\\Art\\dagger_level_one.tga")

-- Piece 2 (66%)
local Stage2 = CustomTracker:CreateTexture(nil, "ARTWORK")
Stage2:SetAllPoints()
Stage2:SetTexture("Interface\\AddOns\\PreyNotifier\\Art\\dagger_level_two.tga")

-- Piece 3 (100%)
local Stage3 = CustomTracker:CreateTexture(nil, "ARTWORK")
Stage3:SetAllPoints()
Stage3:SetTexture("Interface\\AddOns\\PreyNotifier\\Art\\dagger_full.tga")

-- Load the Glow Art
local GlowArt = CustomTracker:CreateTexture(nil, "BORDER")
GlowArt:SetAllPoints()
GlowArt:SetTexture("Interface\\AddOns\\PreyNotifier\\Art\\dagger_glow.tga")
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

-- Keep the text below the dagger
CustomTracker.text = CustomTracker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
CustomTracker.text:SetPoint("TOP", CustomTracker, "BOTTOM", 0, -5)
CustomTracker.text:SetText("Searching for Prey...")

CustomTracker:Hide()


-- ------------------------------------------
-- DYNAMIC WIDGET SCANNER
-- ------------------------------------------
function UpdateProgressBar() 
    -- ZONE KILL SWITCH: Sleep if we aren't in a hunting ground
    if not IsInHuntZone() then
        if CustomTracker then CustomTracker:Hide() end
        return
    end

    if PreyNotifierDB and PreyNotifierDB["_ShowProgressBar"] == false then
        CustomTracker:Hide()
        return
    end

    if PreyNotifierDB and not PreyNotifierDB["_PrimaryTarget"] then
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
                                elseif info.progressState == 2 then pct = 66; stageName = "Tracking the Prey"
                                elseif info.progressState == 3 then pct = 100; stageName = "Found the Prey"
                                else pct = 0; stageName = "Begin the Hunt" end
                            end
                            
                            -- GRAPHICAL DAGGER LOGIC
                            if pct >= 33 then Stage1:Show() else Stage1:Hide() end
                            if pct >= 66 then Stage2:Show() else Stage2:Hide() end
                            if pct >= 100 then Stage3:Show() else Stage3:Hide() end

							--[[ GRAPHICAL DAGGER LOGIC (Exclusive Layering)
                            Stage1:Hide()
                            Stage2:Hide()
                            Stage3:Hide()
                            
                            if pct >= 100 then
                                Stage3:Show()
                            elseif pct >= 66 then
                                Stage2:Show()
                            elseif pct >= 33 then
                                Stage1:Show()
                            end]]

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
                            else
                                CustomTracker.text:SetTextColor(1, 1, 1) -- White text normally
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
end




-- ------------------------------------------
-- EVENT REGISTRATIONS
-- ------------------------------------------
PreyAddon:RegisterEvent("ADDON_LOADED")
PreyAddon:RegisterEvent("NAME_PLATE_UNIT_ADDED")
PreyAddon:RegisterEvent("PLAYER_TARGET_CHANGED")
PreyAddon:RegisterEvent("QUEST_ACCEPTED")
PreyAddon:RegisterEvent("UPDATE_UI_WIDGET") 
PreyAddon:RegisterEvent("UPDATE_ALL_UI_WIDGETS") 
PreyAddon:RegisterEvent("QUEST_REMOVED")
PreyAddon:RegisterEvent("PLAYER_ENTERING_WORLD")
PreyAddon:RegisterEvent("PLAYER_REGEN_DISABLED")
PreyAddon:RegisterEvent("ZONE_CHANGED_NEW_AREA")

local function ScanQuestLogForPrey()
    if not PreyNotifierDB then return end
    
    local currentPrimary = PreyNotifierDB["_PrimaryTarget"]
    local foundCurrentPrimary = false
    local firstFoundPrey = nil
    
    local numEntries = C_QuestLog.GetNumQuestLogEntries()
    for i = 1, numEntries do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.questID then
            if info.title and info.title:match("^Prey:") then
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
            PreyNotifierTargetBtn:Hide()
        end
        if PreyNotifierProgBar then PreyNotifierProgBar:Hide() end
        print("|cffFF9900PreyNotifier:|r Offline completion detected. Cleared missing Primary Target.")
        if UIFrame and UIFrame:IsShown() then UpdateTargetList() end
    end

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
                PreyNotifierTargetBtn:Show()
                print("|cff00FF00PreyNotifier:|r Auto-detected hunt! Primary Target set to |cffFFFF00" .. targetToSet .. "|r.")
            else
                print("|cffFF9900PreyNotifier:|r Hunt picked up, but cannot auto-set Primary Target while in combat.")
            end
        else
            if not InCombatLockdown() then
                PreyNotifierTargetBtn:SetAttribute("macrotext1", "/cleartarget\n/target " .. targetToSet)
                PreyNotifierTargetBtn:Show()
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
        return
    end
	-- WAKE UP / SLEEP WHEN CHANGING ZONES
    if event == "ZONE_CHANGED_NEW_AREA" then
        UpdateProgressBar()
        return
    end
	-- AUTO-HIDE MENU IN COMBAT
    if event == "PLAYER_REGEN_DISABLED" then
        if UIFrame and UIFrame:IsShown() then
            UIFrame:Hide()
            print("|cffFF9900PreyNotifier:|r Entering combat! Hiding menu.")
        end
        return
    end
	-- ADDON LOADED LOGIC
    if event == "ADDON_LOADED" and arg1 == "PreyNotifier" then
        if type(PreyNotifierDB) ~= "table" then
            PreyNotifierDB = { ["_Cooldown"] = 45, ["_MinimapAngle"] = math.rad(225) }
        end
        
        -- Initialize checkbox state
        if PreyNotifierDB["_ShowProgressBar"] == nil then 
            PreyNotifierDB["_ShowProgressBar"] = true 
        end
        
        UpdatePosition(PreyNotifierDB["_MinimapAngle"] or math.rad(225))
        
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
                PreyNotifierTargetBtn:Show()
            end
            if PreyNotifierDB["_BtnPoint"] then
                PreyNotifierTargetBtn:ClearAllPoints()
                PreyNotifierTargetBtn:SetPoint(PreyNotifierDB["_BtnPoint"], UIParent, PreyNotifierDB["_BtnRel"], PreyNotifierDB["_BtnX"], PreyNotifierDB["_BtnY"])
            end
        end)
        return 
    end

    -- PROGRESS BAR UPDATE LOGIC
    if event == "UPDATE_UI_WIDGET" or event == "UPDATE_ALL_UI_WIDGETS" then
        UpdateProgressBar()
        return
    end
    
    -- AUTO-DETECT QUEST ACCEPTANCE
    if event == "QUEST_ACCEPTED" then
        local questId = arg2 and arg2 or arg1 
        local questName = C_QuestLog.GetTitleForQuestID(questId)
        
        if questName then
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
                        PreyNotifierTargetBtn:Show()
                        print("|cff00FF00PreyNotifier:|r Auto-detected hunt! Primary Target set to |cffFFFF00" .. mobName .. "|r.")
                    else
                        print("|cffFF9900PreyNotifier:|r Hunt picked up, but cannot auto-set Primary Target while in combat.")
                    end
                else
                    if not InCombatLockdown() then
                        PreyNotifierTargetBtn:SetAttribute("macrotext1", "/cleartarget\n/target " .. mobName)
                        PreyNotifierTargetBtn:Show()
                    end
                end
                
                if UIFrame and UIFrame:IsShown() then
                    UpdateTargetList()
                end
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
            
            for i = 1, numEntries do
                local info = C_QuestLog.GetInfo(i)
                if info and not info.isHeader and info.questID then
                    if info.title and info.title:match("^Prey:") then
                        local mobName = info.title:match("^Prey:%s+(.-)%s+%([^)]+%)$")
                        
                        if mobName == targetName then
                            found = true
                            break
                        end
                    end
                end
            end
            
            -- If the tracked prey is no longer in the quest log, clear the tracker!
            if not found then
                PreyNotifierDB["_PrimaryTarget"] = nil
                if not InCombatLockdown() then
                    PreyNotifierTargetBtn:SetAttribute("macrotext1", "")
                    PreyNotifierTargetBtn:Hide()
                end
                if PreyNotifierProgBar then
                    PreyNotifierProgBar:Hide()
                end
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
    
    local inInstance, instanceType = IsInInstance()
    if inInstance then return end
    
    local currentUnit = (event == "PLAYER_TARGET_CHANGED") and "target" or arg1
    if not currentUnit or not UnitExists(currentUnit) then return end
    
    local mobName = UnitName(currentUnit)
    if type(mobName) ~= "string" then return end    
    if not mobName then return end 
    
    if PreyNotifierDB and PreyNotifierDB[mobName] then
        local currentTime = GetTime()
        if (currentTime - lastAlertTime) >= (PreyNotifierDB["_Cooldown"] or 45) then
            lastAlertTime = currentTime 
            
            pcall(PlaySoundFile, 552035, "Dialog")
            RaidNotice_AddMessage(RaidWarningFrame, "PREY AMBUSH: " .. string.upper(mobName) .. "!", ChatTypeInfo["RAID_WARNING"])
            print("|cffFF0000PreyNotifier: WARNING: Ambush Detected!|r")
        end
    end
end)



-- ==========================================
-- LOGGING FIREHOSE SNIFFER (/pns)
-- ==========================================
local SnifferFrame = CreateFrame("Frame")
local isSniffing = false

-- The Spam Filter
local ignoredEvents = {
    ["COMBAT_LOG_EVENT_UNFILTERED"] = true,
    ["WORLD_CURSOR_TOOLTIP_UPDATE"] = true,
    ["UPDATE_MOUSEOVER_UNIT"] = true,
    ["UNIT_AURA"] = true,
    ["UNIT_POWER_UPDATE"] = true,
    ["UNIT_HEALTH"] = true,
    ["SPELL_UPDATE_COOLDOWN"] = true,
    ["ACTIONBAR_UPDATE_COOLDOWN"] = true,
    ["BAG_UPDATE"] = true,
    ["BAG_UPDATE_COOLDOWN"] = true,
    ["PLAYER_STARTED_MOVING"] = true,
    ["PLAYER_STOPPED_MOVING"] = true,
    ["CURSOR_CHANGED"] = true,
    ["MODIFIER_STATE_CHANGED"] = true,
    ["UPDATE_UI_WIDGET"] = true,
    ["UPDATE_ALL_UI_WIDGETS"] = true,
}

SnifferFrame:SetScript("OnEvent", function(self, event, ...)
    if not isSniffing then return end
    if ignoredEvents[event] then return end 
    
    local args = {...}
    local output = ""
    
    for i, arg in ipairs(args) do
        output = output .. " [Arg" .. i .. ": " .. tostring(arg) .. "]"
    end
    
    local logString = GetTime() .. " | " .. event .. output
    
    -- Print to chat so you know it's working
    print("|cffFF9900[Sniff]|r " .. event)
    
    -- BUT ALSO: Save it to our database!
    if PreyNotifierDB then
        table.insert(PreyNotifierDB["_DebugLog"], logString)
    end
end)

local function ToggleSniffer()
    isSniffing = not isSniffing
    if isSniffing then
        -- Wipe the old log clean every time we turn it on so the file doesn't get to be 500MB
        if PreyNotifierDB then
            PreyNotifierDB["_DebugLog"] = {} 
        end
        SnifferFrame:RegisterAllEvents() 
        print("|cff00FF00PreyNotifier:|r LOGGING FIREHOSE ENABLED. Trigger the text, then type /pns to stop.")
    else
        SnifferFrame:UnregisterAllEvents()
        print("|cffFF0000PreyNotifier:|r LOGGING FIREHOSE DISABLED. Type /reload to write the log file to your hard drive.")
    end
end

SLASH_PREYSNIFF1 = "/pns"
SlashCmdList["PREYSNIFF"] = ToggleSniffer

-- ==========================================
-- SURGICAL CRITERIA SNIFFER (/pnc)
-- ==========================================
local CriteriaSniffer = CreateFrame("Frame")
local isSniffingCriteria = false

CriteriaSniffer:SetScript("OnEvent", function(self, event, ...)
    -- Only print when our specific event fires
    if isSniffingCriteria and event == "CRITERIA_UPDATE" then
        print("|cff00FF00[PreyBullseye]|r CRITERIA_UPDATE detected!")
    end
end)

local function ToggleCriteriaSniffer()
    isSniffingCriteria = not isSniffingCriteria
    if isSniffingCriteria then
        CriteriaSniffer:RegisterEvent("CRITERIA_UPDATE")
        print("|cff00FFFFPreyNotifier:|r Surgical Sniffer ENABLED. Watching only for CRITERIA_UPDATE...")
    else
        CriteriaSniffer:UnregisterAllEvents()
        print("|cffFF0000PreyNotifier:|r Surgical Sniffer DISABLED.")
    end
end

-- New command: /pnc (PreyNotifier Criteria)
SLASH_PREYCRITERIA1 = "/pnc"
SlashCmdList["PREYCRITERIA"] = ToggleCriteriaSniffer

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

-- ==========================================
-- EXPERIMENTAL PROGRESS SNIFFER (/pnp)
-- ==========================================
local ProgressSniffer = CreateFrame("Frame")
local isSniffingProgress = false

ProgressSniffer:SetScript("OnEvent", function(self, event, ...)
    if not isSniffingProgress then return end
    
    local args = {...}
    local argStr = ""
    for i, v in ipairs(args) do
        argStr = argStr .. tostring(v) .. (i < #args and ", " or "")
    end
    
    print("|cff00FFFFPrey Update Detected.|r |cffFFFF00API Fired:|r " .. event .. " | |cff00FF00Value(s):|r " .. (argStr ~= "" and argStr or "None"))
    
    -- If the quest log updates, let's actively peek at the hidden objectives of our Prey quest
    if (event == "QUEST_LOG_UPDATE" or event == "QUEST_WATCH_UPDATE" or event == "UNIT_QUEST_LOG_CHANGED") and PreyNotifierDB and PreyNotifierDB["_PrimaryTarget"] then
        local numEntries = C_QuestLog.GetNumQuestLogEntries()
        for i = 1, numEntries do
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader and info.questID then
                if info.title and info.title:match("^Prey:%s+(.-)%s+%([^)]+%)$") then
                    local objectives = C_QuestLog.GetQuestObjectives(info.questID)
                    if objectives then
                        for objIndex, obj in ipairs(objectives) do
                            -- obj.numFulfilled and obj.numRequired often hold the raw point values
                            print("   -> |cffCCCCCCObjective " .. objIndex .. ":|r " .. tostring(obj.text) .. " | |cff00FF00Progress: " .. tostring(obj.numFulfilled) .. "/" .. tostring(obj.numRequired) .. "|r")
                        end
                    end
                end
            end
        end
    end
end)

SLASH_PREYPROGRESS1 = "/pnp"
SLASH_PREYPROGRESS2 = "/pnprogress"
SlashCmdList["PREYPROGRESS"] = function()
    isSniffingProgress = not isSniffingProgress
    if isSniffingProgress then
        ProgressSniffer:RegisterEvent("SCENARIO_UPDATE")
        ProgressSniffer:RegisterEvent("SCENARIO_CRITERIA_UPDATE")
        ProgressSniffer:RegisterEvent("QUEST_WATCH_UPDATE")
        ProgressSniffer:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
        ProgressSniffer:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
        ProgressSniffer:RegisterEvent("CHAT_MSG_CURRENCY")
        ProgressSniffer:RegisterEvent("QUEST_LOG_UPDATE")
        ProgressSniffer:RegisterEvent("UI_INFO_MESSAGE")
        print("|cff00FF00PreyNotifier:|r Progress Sniffer ENABLED. Type /pnp to disable.")
    else
        ProgressSniffer:UnregisterAllEvents()
        print("|cffFF0000PreyNotifier:|r Progress Sniffer DISABLED.")
    end
end