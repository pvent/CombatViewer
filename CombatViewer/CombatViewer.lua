-- ============================================================================
-- CombatViewer - Single-Column Combat Log Addon
-- ============================================================================

-------------------------------------------------------------------------------
-- DEFAULT CONFIGURATION & SAVED VARIABLES
-------------------------------------------------------------------------------
local DEFAULT_SETTINGS = {
    FRAME_WIDTH            = 280,
    FRAME_HEIGHT           = 280,
    MAX_ROWS               = 40,
    FONT_SIZE              = 10,
    ROW_HEIGHT             = 20,
    ICON_SIZE              = 16,
    BG_ALPHA               = 0.95,
    MIN_DAMAGE_THRESHOLD   = 0,
    MIN_HEAL_THRESHOLD     = 0,
    MIN_RESOURCE_THRESHOLD = 0,
    DEFAULT_ICON           = "Interface\\Icons\\SAMWISE",
    -- Event Toggles
    SHOW_INCOMING_DMG      = true,
    SHOW_OUTGOING_DMG      = true,
    SHOW_INCOMING_HEAL     = true,
    SHOW_OUTGOING_HEAL     = true,
    SHOW_ENVIRONMENTAL     = true,
    SHOW_RESOURCE_GAINS    = true,
    SHOW_AURAS             = true,
    SHOW_MISSES            = true,
    SHOW_XP_FACTION        = true,
    SHOW_COMBAT_STATUS     = true,
    SHOW_DEATHS            = true,
}

CombatViewerDB = CombatViewerDB or {}

-------------------------------------------------------------------------------
-- POWER TYPE COLOR & NAME LOOKUP TABLE
-------------------------------------------------------------------------------
local POWER_INFO = {
    [0]  = { name = "Mana",        color = "0066ff", icon = "Interface\\Icons\\Spell_Holy_MagicalSentry" },
    [1]  = { name = "Rage",        color = "ff0000", icon = "Interface\\Icons\\Spell_Nature_BloodLust" },
    [2]  = { name = "Focus",       color = "ff8000", icon = "Interface\\Icons\\Ability_Hunter_MasterMarksman" },
    [3]  = { name = "Energy",      color = "ffff00", icon = "Interface\\Icons\\Spell_Shadow_ShadowWordDominate" },
    [4]  = { name = "Happiness",   color = "00ffcc", icon = "Interface\\Icons\\Ability_Physical_Taunt" },
    [6]  = { name = "Runic Power", color = "00dfff", icon = "Interface\\Icons\\ClassIcon_DeathKnight" },
    [8]  = { name = "Lunar Power", color = "3366ff", icon = "Interface\\Icons\\Spell_Nature_StarFall" },
    [11] = { name = "Maelstrom",   color = "00ffff", icon = "Interface\\Icons\\Spell_Shaman_MaelstromWeapon" },
    [13] = { name = "Insanity",    color = "9900ff", icon = "Interface\\Icons\\Spell_Shadow_Portal" },
    [17] = { name = "Fury",        color = "c74ccd", icon = "Interface\\Icons\\Ability_DemonHunter_SpecDemonHunter" },
    [18] = { name = "Pain",        color = "ff9900", icon = "Interface\\Icons\\Ability_DemonHunter_SpecVengeance" },
}

-------------------------------------------------------------------------------
-- LOCAL API & VARIABLES
-------------------------------------------------------------------------------
local addonName, ns = ...

local CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo
local UnitGUID = UnitGUID
local UnitName = UnitName
local GetSpellTexture = GetSpellTexture or C_Spell.GetSpellTexture
local IsShiftKeyDown = IsShiftKeyDown

local MAX_HISTORY = 250
local scrollOffset = 0
local history = {}
local rows = {}

local playerGUID, playerName
local npcMap = {}
local npcCounter = 0

-------------------------------------------------------------------------------
-- HELPER FUNCTIONS
-------------------------------------------------------------------------------
local function FormatIconString(texturePath)
    local tex = texturePath
    if not tex or tex == "" then
        tex = CombatViewerDB.DEFAULT_ICON or DEFAULT_SETTINGS.DEFAULT_ICON
    end
    local sz = CombatViewerDB.ICON_SIZE or DEFAULT_SETTINGS.ICON_SIZE
    return "|T" .. tex .. ":" .. sz .. ":" .. sz .. ":0:0:64:64:4:60:4:60|t "
end

local function GetIcon(spellId)
    if not spellId then return CombatViewerDB.DEFAULT_ICON or DEFAULT_SETTINGS.DEFAULT_ICON end
    return GetSpellTexture(spellId) or (CombatViewerDB.DEFAULT_ICON or DEFAULT_SETTINGS.DEFAULT_ICON)
end

local function GetNPCIdentifier(guid, name)
    if not guid or not name or guid == playerGUID then return name end

    if guid:sub(1, 8) == "Creature" or guid:sub(1, 7) == "Vehicle" then
        if not npcMap[guid] then
            npcCounter = npcCounter + 1
            npcMap[guid] = "#" .. npcCounter
        end
        return name .. " " .. npcMap[guid]
    end

    return name
end

-------------------------------------------------------------------------------
-- MAIN FRAME CREATION
-------------------------------------------------------------------------------
local Frame = CreateFrame("Frame", "CombatViewerFrame", UIParent, "BackdropTemplate")
Frame:SetSize(DEFAULT_SETTINGS.FRAME_WIDTH, DEFAULT_SETTINGS.FRAME_HEIGHT)
Frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
Frame:SetMovable(true)
Frame:SetResizable(true)
if Frame.SetResizeBounds then
    Frame:SetResizeBounds(180, 120, 600, 800)
else
    Frame:SetMinResize(180, 120)
    Frame:SetMaxResize(600, 800)
end

Frame:EnableMouse(true)
Frame:EnableMouseWheel(true)
Frame:RegisterForDrag("LeftButton")
Frame:SetScript("OnDragStart", Frame.StartMoving)
Frame:SetScript("OnDragStop", Frame.StopMovingOrSizing)

Frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
})

-- Header Divider Line
local headerLine = Frame:CreateTexture(nil, "ARTWORK")
headerLine:SetHeight(1)
headerLine:SetPoint("TOPLEFT", Frame, "TOPLEFT", 6, -24)
headerLine:SetPoint("TOPRIGHT", Frame, "TOPRIGHT", -6, -24)
headerLine:SetColorTexture(0.5, 0.5, 0.5, 0.5)

-- Header Title
local hTitle = Frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
hTitle:SetPoint("TOPLEFT", Frame, "TOPLEFT", 8, -6)
hTitle:SetPoint("TOPRIGHT", Frame, "TOPRIGHT", -24, -6)
hTitle:SetJustifyH("CENTER")
hTitle:SetText("CombatViewer")

-------------------------------------------------------------------------------
-- RESIZE HANDLE
-------------------------------------------------------------------------------
local resizeButton = CreateFrame("Button", nil, Frame)
resizeButton:SetSize(16, 16)
resizeButton:SetPoint("BOTTOMRIGHT", Frame, "BOTTOMRIGHT", 0, 0)
resizeButton:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
resizeButton:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
resizeButton:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

local function GetVisibleMaxRows()
    local frameHeight = Frame:GetHeight()
    local availableHeight = frameHeight - 32
    local rowHeight = CombatViewerDB.ROW_HEIGHT or DEFAULT_SETTINGS.ROW_HEIGHT
    local maxVisible = math.floor(availableHeight / rowHeight)
    return math.max(1, math.min(maxVisible, DEFAULT_SETTINGS.MAX_ROWS))
end

-------------------------------------------------------------------------------
-- ROW CREATION & LAYOUT UPDATES
-------------------------------------------------------------------------------
for i = 1, DEFAULT_SETTINGS.MAX_ROWS do
    local text = Frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetShadowColor(0, 0, 0, 1)
    text:SetShadowOffset(1, -1)
    rows[i] = text
end

local function UpdateRowLayout()
    local rowHeight = CombatViewerDB.ROW_HEIGHT or DEFAULT_SETTINGS.ROW_HEIGHT
    local fontSize = CombatViewerDB.FONT_SIZE or DEFAULT_SETTINGS.FONT_SIZE

    for i = 1, DEFAULT_SETTINGS.MAX_ROWS do
        local yOffset = -28 - ((i - 1) * rowHeight)
        rows[i]:ClearAllPoints()
        rows[i]:SetPoint("TOPLEFT", Frame, "TOPLEFT", 10, yOffset)
        rows[i]:SetPoint("TOPRIGHT", Frame, "TOPRIGHT", -10, yOffset)
        rows[i]:SetHeight(rowHeight)
        rows[i]:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE")
    end
end

local function UpdateDisplay()
    UpdateRowLayout()

    if scrollOffset > 0 then
        hTitle:SetText("|cffffcc00[CombatViewer - History]|r")
    else
        hTitle:SetText("CombatViewer")
    end

    local maxRows = GetVisibleMaxRows()
    for i = 1, DEFAULT_SETTINGS.MAX_ROWS do
        if i <= maxRows then
            local dataIndex = i + scrollOffset
            local data = history[dataIndex]
            if data then
                rows[i]:SetText(data.text)
                if data.col == "INCOMING" then
                    rows[i]:SetJustifyH("LEFT")
                elseif data.col == "OUTGOING" then
                    rows[i]:SetJustifyH("RIGHT")
                else
                    rows[i]:SetJustifyH("CENTER")
                end
                rows[i]:Show()
            else
                rows[i]:SetText("")
                rows[i]:Hide()
            end
        else
            rows[i]:SetText("")
            rows[i]:Hide()
        end
    end
end

resizeButton:SetScript("OnMouseDown", function(self, button)
    if button == "LeftButton" then
        Frame:StartSizing("BOTTOMRIGHT")
    end
end)

resizeButton:SetScript("OnMouseUp", function(self, button)
    if button == "LeftButton" then
        Frame:StopMovingOrSizing()
        CombatViewerDB.FRAME_WIDTH = Frame:GetWidth()
        CombatViewerDB.FRAME_HEIGHT = Frame:GetHeight()
        UpdateDisplay()
    end
end)

Frame:SetScript("OnSizeChanged", function(self, width, height)
    UpdateDisplay()
end)

local function PushEvent(col, text)
    table.insert(history, 1, {col = col, text = text})
    if #history > MAX_HISTORY then
        table.remove(history)
    end

    local maxRows = GetVisibleMaxRows()
    if scrollOffset > 0 then
        scrollOffset = math.min(scrollOffset + 1, #history - maxRows)
    end

    UpdateDisplay()
end

-------------------------------------------------------------------------------
-- SCROLL HANDLER
-------------------------------------------------------------------------------
Frame:SetScript("OnMouseWheel", function(self, delta)
    local maxRows = GetVisibleMaxRows()
    if #history <= maxRows then return end

    local maxOffset = #history - maxRows

    if delta > 0 then
        if IsShiftKeyDown() then
            scrollOffset = 0
        else
            scrollOffset = math.max(scrollOffset - 1, 0)
        end
    elseif delta < 0 then
        if IsShiftKeyDown() then
            scrollOffset = maxOffset
        else
            scrollOffset = math.min(scrollOffset + 1, maxOffset)
        end
    end
    UpdateDisplay()
end)

-------------------------------------------------------------------------------
-- CONFIGURATION / SETTINGS WINDOW
-------------------------------------------------------------------------------
local ConfigFrame = CreateFrame("Frame", "CombatViewerConfigFrame", UIParent, "BackdropTemplate")
ConfigFrame:SetSize(320, 500)
ConfigFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
ConfigFrame:SetMovable(true)
ConfigFrame:EnableMouse(true)
ConfigFrame:RegisterForDrag("LeftButton")
ConfigFrame:SetScript("OnDragStart", ConfigFrame.StartMoving)
ConfigFrame:SetScript("OnDragStop", ConfigFrame.StopMovingOrSizing)

ConfigFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 }
})
ConfigFrame:Hide()

tinsert(UISpecialFrames, "CombatViewerConfigFrame")

local cfgTitle = ConfigFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
cfgTitle:SetPoint("TOP", ConfigFrame, "TOP", 0, -16)
cfgTitle:SetText("CombatViewer Settings")

local closeBtn = CreateFrame("Button", nil, ConfigFrame, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", ConfigFrame, "TOPRIGHT", -5, -5)

local configToggleBtn = CreateFrame("Button", nil, Frame)
configToggleBtn:SetSize(16, 16)
configToggleBtn:SetPoint("TOPRIGHT", Frame, "TOPRIGHT", -6, -5)

local configBtnText = configToggleBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
configBtnText:SetPoint("CENTER", configToggleBtn, "CENTER", 0, 0)
configBtnText:SetText("|cffaaaaaa[C]|r")

configToggleBtn:SetScript("OnEnter", function(self)
    configBtnText:SetText("|cffffcc00[C]|r")
end)
configToggleBtn:SetScript("OnLeave", function(self)
    configBtnText:SetText("|cffaaaaaa[C]|r")
end)
configToggleBtn:SetScript("OnClick", function()
    if ConfigFrame:IsShown() then
        ConfigFrame:Hide()
    else
        ConfigFrame:Show()
    end
end)

local function CreateCheckbox(parent, labelText, dbKey, yOffset)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, yOffset)
    
    cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cb.text:SetPoint("LEFT", cb, "RIGHT", 5, 1)
    cb.text:SetText(labelText)

    cb:SetScript("OnShow", function(self)
        self:SetChecked(CombatViewerDB[dbKey])
    end)

    cb:SetScript("OnClick", function(self)
        CombatViewerDB[dbKey] = self:GetChecked()
    end)

    return cb
end

local function CreateInputBox(parent, labelText, dbKey, yOffset, onUpdateCallback)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, yOffset)
    label:SetText(labelText)

    local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    eb:SetSize(60, 20)
    eb:SetPoint("LEFT", label, "RIGHT", 15, 0)
    eb:SetNumeric(true)
    eb:SetAutoFocus(false)

    eb:SetScript("OnShow", function(self)
        self:SetText(tostring(CombatViewerDB[dbKey] or DEFAULT_SETTINGS[dbKey] or 0))
    end)

    local function ApplyValue(self)
        local val = tonumber(self:GetText()) or DEFAULT_SETTINGS[dbKey] or 0
        CombatViewerDB[dbKey] = val
        if onUpdateCallback then
            onUpdateCallback(val)
        end
    end

    eb:SetScript("OnEnterPressed", function(self)
        ApplyValue(self)
        self:ClearFocus()
    end)

    eb:SetScript("OnEditFocusLost", function(self)
        ApplyValue(self)
    end)

    return eb
end

-- Controls
CreateInputBox(ConfigFrame, "Font Size:", "FONT_SIZE", -40, function() UpdateDisplay() end)
CreateInputBox(ConfigFrame, "Row Height:", "ROW_HEIGHT", -65, function() UpdateDisplay() end)
CreateInputBox(ConfigFrame, "Icon Size:", "ICON_SIZE", -90, function() UpdateDisplay() end)

CreateInputBox(ConfigFrame, "Min Damage Threshold:", "MIN_DAMAGE_THRESHOLD", -120)
CreateInputBox(ConfigFrame, "Min Heal Threshold:", "MIN_HEAL_THRESHOLD", -145)
CreateInputBox(ConfigFrame, "Min Resource Threshold:", "MIN_RESOURCE_THRESHOLD", -170)

CreateCheckbox(ConfigFrame, "Show Incoming Damage", "SHOW_INCOMING_DMG", -200)
CreateCheckbox(ConfigFrame, "Show Outgoing Damage", "SHOW_OUTGOING_DMG", -225)
CreateCheckbox(ConfigFrame, "Show Incoming Healing", "SHOW_INCOMING_HEAL", -250)
CreateCheckbox(ConfigFrame, "Show Outgoing Healing", "SHOW_OUTGOING_HEAL", -275)
CreateCheckbox(ConfigFrame, "Show Environmental Damage", "SHOW_ENVIRONMENTAL", -300)
CreateCheckbox(ConfigFrame, "Show Resource Gains", "SHOW_RESOURCE_GAINS", -325)
CreateCheckbox(ConfigFrame, "Show Buffs & Debuffs", "SHOW_AURAS", -350)
CreateCheckbox(ConfigFrame, "Show Misses / Resists", "SHOW_MISSES", -375)
CreateCheckbox(ConfigFrame, "Show XP & Faction Gains", "SHOW_XP_FACTION", -400)
CreateCheckbox(ConfigFrame, "Show Combat Status (+/-)", "SHOW_COMBAT_STATUS", -425)
CreateCheckbox(ConfigFrame, "Show Unit Deaths", "SHOW_DEATHS", -450)

-------------------------------------------------------------------------------
-- EVENT PROCESSING
-------------------------------------------------------------------------------
Frame:RegisterEvent("ADDON_LOADED")
Frame:RegisterEvent("PLAYER_ENTERING_WORLD")
Frame:RegisterEvent("PLAYER_REGEN_DISABLED")
Frame:RegisterEvent("PLAYER_REGEN_ENABLED")
Frame:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
Frame:RegisterEvent("CHAT_MSG_COMBAT_FACTION_CHANGE")
Frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

Frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == addonName then
            for k, v in pairs(DEFAULT_SETTINGS) do
                if CombatViewerDB[k] == nil then
                    CombatViewerDB[k] = v
                end
            end
            Frame:SetSize(CombatViewerDB.FRAME_WIDTH or DEFAULT_SETTINGS.FRAME_WIDTH, CombatViewerDB.FRAME_HEIGHT or DEFAULT_SETTINGS.FRAME_HEIGHT)
            Frame:SetBackdropColor(0, 0, 0, CombatViewerDB.BG_ALPHA)
            UpdateDisplay()
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        playerGUID = UnitGUID("player")
        playerName = UnitName("player")
        wipe(npcMap)
        npcCounter = 0

    elseif event == "PLAYER_REGEN_DISABLED" then
        if CombatViewerDB.SHOW_COMBAT_STATUS then
            local iconStr = FormatIconString("Interface\\Icons\\ABILITY_DUALWIELD")
            PushEvent("MISC", iconStr .. "|cffff0000+++COMBAT+++|r")
        end

    elseif event == "PLAYER_REGEN_ENABLED" then
        if CombatViewerDB.SHOW_COMBAT_STATUS then
            local iconStr = FormatIconString("Interface\\Icons\\ABILITY_DUALWIELD")
            PushEvent("MISC", iconStr .. "|cff00ff00---COMBAT---|r")
        end
        wipe(npcMap)
        npcCounter = 0

    elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
        if not CombatViewerDB.SHOW_XP_FACTION then return end
        local msg = ...
        local amount = msg:match("(%d+) %f[%a]experience") or msg:match("(%d+) XP") or msg:match("(%d+)")
        if amount then
            local iconStr = FormatIconString("Interface\\Icons\\XP_ICON")
            PushEvent("MISC", iconStr .. "|cff7000ff+" .. amount .. " XP|r")
        end

    elseif event == "CHAT_MSG_COMBAT_FACTION_CHANGE" then
        if not CombatViewerDB.SHOW_XP_FACTION then return end
        local msg = ...
        local faction, amount = msg:match("Reputation with (%b{}) increased by (%d+)")
        if not faction then
            faction, amount = msg:match("Reputation with (.+) increased by (%d+)")
        end
        if not faction then
            amount, faction = msg:match("+(%d+) reputation with (.+)")
        end

        local iconStr = FormatIconString("Interface\\Icons\\INV_Scroll_06")
        if faction and amount then
            faction = faction:gsub("[{}%[%]]", "")
            PushEvent("MISC", iconStr .. "|cff66ccff+" .. amount .. " Rep (" .. faction .. ")|r")
        elseif amount then
            PushEvent("MISC", iconStr .. "|cff66ccff+" .. amount .. " Rep|r")
        end

    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local timestamp, subEvent, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags, arg12, arg13, arg14, arg15, arg16, arg17, arg18, arg19, arg20 = CombatLogGetCurrentEventInfo()

        if not subEvent then return end

        local isSourcePlayer = (sourceGUID and sourceGUID == playerGUID)
        local isDestPlayer = (destGUID and destGUID == playerGUID)

        -- Handle Unit Deaths
        if subEvent == "UNIT_DIED" or subEvent == "PARTY_KILL" then
            if not CombatViewerDB.SHOW_DEATHS then return end

            local iconStr = FormatIconString("Interface\\Icons\\ABILITY_DUALWIELD")

            if isDestPlayer then
                PushEvent("INCOMING", iconStr .. "|cffff0000 You Died!|r")
            elseif isSourcePlayer and destName then
                local targetStr = GetNPCIdentifier(destGUID, destName)
                PushEvent("OUTGOING", "|cffff0000 Slain: " .. targetStr .. "|r " .. iconStr)
            elseif destName and (isSourcePlayer or isDestPlayer or subEvent == "PARTY_KILL") then
                local targetStr = GetNPCIdentifier(destGUID, destName)
                PushEvent("INCOMING", iconStr .. "|cff888888 Died: " .. targetStr .. "|r")
            end
            return
        end

        -- Check if event involves the player as target or source
        if not isSourcePlayer and not isDestPlayer then return end

        -- Environmental Damage
        if subEvent == "ENVIRONMENTAL_DAMAGE" and isDestPlayer and CombatViewerDB.SHOW_ENVIRONMENTAL then
            local envType, amount = arg12, arg13
            amount = amount or 0

            if amount >= (CombatViewerDB.MIN_DAMAGE_THRESHOLD or 0) then
                local iconPath = "Interface\\Icons\\Spell_Magic_FeatherFall"
                if envType == "LAVA" or envType == "FIRE" then
                    iconPath = "Interface\\Icons\\Spell_Fire_Fire"
                elseif envType == "DROWNING" then
                    iconPath = "Interface\\Icons\\Spell_Shadow_DemonBreath"
                elseif envType == "SLIME" then
                    iconPath = "Interface\\Icons\\INV_Misc_Slime_01"
                end

                local iconStr = FormatIconString(iconPath)
                local envName = envType and (envType:sub(1,1):upper() .. envType:sub(2):lower()) or "Environment"
                PushEvent("INCOMING", iconStr .. "|cffff4444" .. amount .. " <- " .. envName .. "|r")
            end

        -- Resource Gains
        elseif (subEvent == "SPELL_ENERGIZE" or subEvent == "SPELL_PERIODIC_ENERGIZE") and isDestPlayer and CombatViewerDB.SHOW_RESOURCE_GAINS then
            local spellId, spellName, spellSchool, amount, powerType = arg12, arg13, arg14, arg15, arg16
            amount = amount or 0

            if amount >= (CombatViewerDB.MIN_RESOURCE_THRESHOLD or 0) then
                local pInfo = POWER_INFO[powerType] or { name = "Power", color = "00ffcc", icon = CombatViewerDB.DEFAULT_ICON }
                local iconPath = GetIcon(spellId) or pInfo.icon
                local iconStr = FormatIconString(iconPath)

                PushEvent("INCOMING", iconStr .. "|cff" .. pInfo.color .. "+" .. amount .. " " .. pInfo.name .. "|r")
            end

        -- Melee Auto Attacks
        elseif subEvent == "SWING_DAMAGE" then
            local amount, overload, school, resisted, blocked, absorbed, critical = arg12, arg13, arg14, arg15, arg16, arg17, arg18
            amount = amount or 0
            
            if amount >= (CombatViewerDB.MIN_DAMAGE_THRESHOLD or 0) then
                local iconStr = FormatIconString("Interface\\Icons\\INV_Sword_04")
                local critStr = critical and "*" or ""

                if isDestPlayer and not isSourcePlayer and CombatViewerDB.SHOW_INCOMING_DMG then
                    local attackerStr = sourceName and (" <- " .. GetNPCIdentifier(sourceGUID, sourceName)) or ""
                    PushEvent("INCOMING", iconStr .. "|cffff4444" .. critStr .. amount .. critStr .. attackerStr .. "|r")
                elseif isSourcePlayer and CombatViewerDB.SHOW_OUTGOING_DMG then
                    local targetStr = (destName and destName ~= playerName) and (GetNPCIdentifier(destGUID, destName) .. " -> ") or ""
                    PushEvent("OUTGOING", "|cff44ff44" .. targetStr .. critStr .. amount .. critStr .. "|r " .. iconStr)
                end
            end

        -- Direct Spell & Ranged Damage
        elseif subEvent == "SPELL_DAMAGE" or subEvent == "RANGE_DAMAGE" then
            local spellId, spellName, spellSchool = arg12, arg13, arg14
            local _, _, _, _, _, _, _, _, _, _, _, _, _, _, amount, overkill, school, resisted, blocked, absorbed, critical = CombatLogGetCurrentEventInfo()
            amount = amount or 0

            if amount >= (CombatViewerDB.MIN_DAMAGE_THRESHOLD or 0) then
                local iconStr = FormatIconString(GetIcon(spellId))
                local isCrit = (critical == 1 or critical == true)
                local critStr = isCrit and "*" or ""

                if isDestPlayer and not isSourcePlayer and CombatViewerDB.SHOW_INCOMING_DMG then
                    local dmgVal = critStr .. amount .. critStr
                    if absorbed and type(absorbed) == "number" and absorbed > 0 then
                        dmgVal = dmgVal .. " (" .. absorbed .. " A)"
                    end
                    local srcStr = (sourceName and sourceName ~= "") and (" <- " .. GetNPCIdentifier(sourceGUID, sourceName)) or (spellName and (" <- " .. spellName) or "")
                    PushEvent("INCOMING", iconStr .. "|cffffaa44 " .. dmgVal .. srcStr .. "|r")

                elseif isSourcePlayer and CombatViewerDB.SHOW_OUTGOING_DMG then
                    local targetStr = (destName and destName ~= playerName) and (GetNPCIdentifier(destGUID, destName) .. " -> ") or ""
                    PushEvent("OUTGOING", "|cffffcc00" .. targetStr .. critStr .. amount .. critStr .. "|r " .. iconStr)
                end
            end

        -- DoT Damage
        elseif subEvent == "SPELL_PERIODIC_DAMAGE" then
            local spellId, spellName, spellSchool, amount, overload, school, resisted, blocked, absorbed, critical = arg12, arg13, arg14, arg15, arg16, arg17, arg18, arg19, arg20
            amount = amount or 0

            if amount >= (CombatViewerDB.MIN_DAMAGE_THRESHOLD or 0) then
                local iconStr = FormatIconString(GetIcon(spellId))
                local critStr = critical and "*" or ""

                if isDestPlayer and not isSourcePlayer and CombatViewerDB.SHOW_INCOMING_DMG then
                    local srcStr = (sourceName and sourceName ~= "") and (" <- " .. GetNPCIdentifier(sourceGUID, sourceName)) or (spellName and (" <- " .. spellName) or "")
                    PushEvent("INCOMING", iconStr .. "|cffffaa44 " .. critStr .. amount .. critStr .. srcStr .. "|r")
                elseif isSourcePlayer and CombatViewerDB.SHOW_OUTGOING_DMG then
                    local targetStr = (destName and destName ~= playerName) and (GetNPCIdentifier(destGUID, destName) .. " -> ") or ""
                    PushEvent("OUTGOING", "|cffffcc00" .. targetStr .. critStr .. amount .. critStr .. "|r " .. iconStr)
                end
            end

        -- Direct Heals & HoTs
        elseif subEvent == "SPELL_HEAL" or subEvent == "SPELL_PERIODIC_HEAL" then
            local spellId, spellName, spellSchool = arg12, arg13, arg14
            local amount, overheal, absorbed, critical

            if type(arg15) == "number" then
                amount = arg15
                overheal = type(arg16) == "number" and arg16 or 0
                absorbed = type(arg17) == "number" and arg17 or 0
                critical = arg18
                if critical == nil and type(arg19) == "boolean" then critical = arg19 end
            end

            amount = amount or 0
            overheal = overheal or 0
            local totalHealVal = amount + overheal
            local minHeal = CombatViewerDB.MIN_HEAL_THRESHOLD or 0

            if (amount >= minHeal or overheal >= minHeal) and totalHealVal > 0 then
                local iconStr = FormatIconString(GetIcon(spellId))
                local isCrit = (critical == true or critical == 1)
                local critStr = isCrit and "*" or ""
                
                local healText = critStr .. amount .. critStr
                if overheal > 0 then
                    healText = healText .. " {" .. overheal .. "}"
                end

                if isDestPlayer and CombatViewerDB.SHOW_INCOMING_HEAL then
                    local healerStr = sourceName and (" <- " .. sourceName) or ""
                    PushEvent("INCOMING", iconStr .. "|cff00ffff " .. healText .. healerStr .. "|r")
                elseif isSourcePlayer and CombatViewerDB.SHOW_OUTGOING_HEAL then
                    local targetStr = destName and (destName .. " -> ") or ""
                    PushEvent("OUTGOING", "|cff00ffff " .. targetStr .. healText .. "|r " .. iconStr)
                end
            end

        -- Buffs & Debuffs
        elseif (subEvent == "SPELL_AURA_APPLIED" or subEvent == "SPELL_AURA_REMOVED" or subEvent == "SPELL_AURA_REFRESH") and CombatViewerDB.SHOW_AURAS then
            local spellId, spellName, spellSchool, auraType = arg12, arg13, arg14, arg15
            local iconStr = FormatIconString(GetIcon(spellId))

            if isDestPlayer then
                local prefix = (subEvent == "SPELL_AURA_REMOVED") and "-" or "+"
                
                if auraType == "BUFF" then
                    PushEvent("MISC", iconStr .. "|cffffd100" .. prefix .. (spellName or "Buff") .. "|r")
                elseif auraType == "DEBUFF" then
                    PushEvent("MISC", iconStr .. "|cffcc5555" .. prefix .. (spellName or "Debuff") .. "|r")
                end
            elseif isSourcePlayer and auraType == "DEBUFF" and subEvent ~= "SPELL_AURA_REMOVED" then
                local targetStr = destName and (GetNPCIdentifier(destGUID, destName) .. " -> ") or ""
                PushEvent("OUTGOING", "|cffff0055 " .. targetStr .. "|r " .. iconStr)
            end

        -- Misses / Resists
        elseif (subEvent == "SPELL_MISSED" or subEvent == "RANGE_MISSED" or subEvent == "SPELL_PERIODIC_MISSED") and CombatViewerDB.SHOW_MISSES then
            local spellId, spellName, spellSchool, missType = arg12, arg13, arg14, arg15
            local iconStr = FormatIconString(GetIcon(spellId))
            local label = missType and (missType:sub(1,1):upper() .. missType:sub(2):lower()) or "Resist"

            if isDestPlayer and not isSourcePlayer then
                local attackerStr = sourceName and (" <- " .. GetNPCIdentifier(sourceGUID, sourceName)) or ""
                PushEvent("INCOMING", iconStr .. "|cffff8888 " .. label .. attackerStr .. "|r")
            elseif isSourcePlayer then
                local targetStr = (destName and destName ~= playerName) and (GetNPCIdentifier(destGUID, destName) .. " -> ") or ""
                PushEvent("OUTGOING", "|cff8888ff " .. targetStr .. label .. "|r " .. iconStr)
            end
        end
    end
end)

-------------------------------------------------------------------------------
-- SAFE SLASH COMMANDS
-------------------------------------------------------------------------------
SLASH_CombatViewer1 = "/combatviewer"
SLASH_CombatViewer2 = "/cv"

local function HandleSlashCmd(msg)
    local cmd = (msg or ""):lower():match("^%s*(.-)%s*$")

    if cmd == "config" or cmd == "options" or cmd == "settings" then
        if ConfigFrame:IsShown() then
            ConfigFrame:Hide()
        else
            ConfigFrame:Show()
        end
    else
        if Frame:IsShown() then
            Frame:Hide()
        else
            Frame:Show()
        end
    end
end

SlashCmdList["CombatViewer"] = HandleSlashCmd