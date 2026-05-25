-- CoaPower.lua
-- Multi-class buff tracker â€” class rows, range check, chain cast, expiry timers
-- Ascension 3.3.5

-- â”€â”€ Constants â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
local NEEDS_REBUFF_THRESHOLD = 300   -- 5 min in seconds â†’ show in queue + timer
local SCAN_INTERVAL          = 1.5   -- seconds between full roster scans

-- Default tracked spells per caster class (auto-detected on PLAYER_LOGIN).
-- Add your class here or use /sb addspell <name> at runtime.
local CLASS_DEFAULTS = {
    SUNCLERIC = { "Devotion of Dawn",      "Devotion of Grace",     "Devotion of Radiance"  },
    DRUID     = { "Mark of the Wild",      "Gift of the Wild"      },
    PRIEST    = { "Power Word: Fortitude", "Prayer of Fortitude"   },
    MAGE      = { "Arcane Intellect",      "Arcane Brilliance"     },
}

-- â”€â”€ State â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
local isActive     = false
local casterClass  = nil              -- classToken of logged-in player
local spells       = {}               -- [i] = spellName  (up to MAX_SPELLS)
local spellIcons   = {}               -- [i] = icon texture path
local roster       = {}               -- flat ordered list of unitIDs
local classRows    = {}               -- ordered class tokens present in group
local classMembers = {}               -- [classToken] = { uid, uid, ... }
local buffStatus   = {}               -- [uid] = { name, unitID, [i]={present,expiry} }
local scanTimer    = 0
local db           = {}
local L            = nil              -- set in ADDON_LOADED from CoaPowerL

local function CoaPrint(...)
    if db.verbose ~= false then print(...) end
end

local DB_DEFAULTS = {
    point        = "CENTER",
    xOfs         = 0,
    yOfs         = 0,
    locked       = false,
    rangeOnly    = false,             -- true = hide out-of-range rows entirely
    verbose      = false,             -- false = suppress confirmation messages
    classConfig  = {},                -- [classToken] = { [1]=bool, [2]=bool, [3]=bool }
    spellsByClass= {},                -- [classToken] = {spellName,...} (user overrides)
    activeSpell  = {},                -- [classToken] = spell slot index (1..MAX_SPELLS)
}

-- â”€â”€ UI sizing â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
local MAX_SPELLS = 3
local ICON_SIZE  = 18
local ROW_H      = 22
local COL_W      = 24
local NAME_W     = 130
local HEADER_H   = 28
local PAD        = 4

local function GetFrameW()
    local cols = 0
    for i = 1, MAX_SPELLS do if spells[i] then cols = i end end
    return NAME_W + cols * COL_W + 14
end

-- UI handles
local mainFrame   = nil
local secureHost  = nil  -- UIParent child, SetAllPoints(mainFrame) â€” isolates secure buttons from mainFrame
local configFrame = nil
local ioPanel     = nil
local headerIcons = {}
local rowPool        = {}   -- [classToken] = row frame
local playerRowPool  = {}   -- [uid]        = player sub-row frame
local expandedClasses = {}  -- [classToken] = bool  (runtime, not saved)

local UpdateUI   -- forward declaration

-- â”€â”€ Buff info â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- Returns: present (bool), expiry (number|nil) â€” nil means permanent or absent
local function GetBuffInfo(unitID, spellName)
    local i = 1
    while true do
        local name, _, _, _, _, _, expirationTime = UnitBuff(unitID, i)
        if not name then return false, nil end
        if name == spellName then
            local expiry = (expirationTime and expirationTime > 0) and expirationTime or nil
            return true, expiry
        end
        i = i + 1
    end
end

-- â”€â”€ Range check â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- Returns true = in range (or AoE/no-range spell), false = out of range / invisible
local function GetRangeStatus(unitID, spellIdx)
    if not UnitIsVisible(unitID) then return false end
    local spell = spells[spellIdx]
    if not spell then return false end
    local r = IsSpellInRange(spell, unitID)
    return r == nil or r == 1   -- nil â†’ no range limit (AoE) â†’ always in range
end

-- â”€â”€ Spellbook scan â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
local function ScanSpellbook()
    wipe(spells)
    wipe(spellIcons)
    if not casterClass then return end

    -- Build target list: user overrides > data file > CLASS_DEFAULTS fallback
    -- Entries can be plain strings or {name="..."} tables.
    local targetNames = {}
    local userOverride = db.spellsByClass and db.spellsByClass[casterClass]
    if userOverride and #userOverride > 0 then
        for i, name in ipairs(userOverride) do targetNames[i] = name end
    else
        local classData = COAPOWER_CLASS_DATA and COAPOWER_CLASS_DATA[casterClass]
        local src = classData or CLASS_DEFAULTS[casterClass] or {}
        for i, entry in ipairs(src) do
            targetNames[i] = type(entry) == "string" and entry or entry.name
        end
    end

    -- Scan every spellbook slot; overwrite on each match so the
    -- last occurrence (= highest rank) wins.
    for tab = 1, GetNumSpellTabs() do
        local _, _, offset, count = GetSpellTabInfo(tab)
        for slot = offset + 1, offset + count do
            if GetSpellBookItemInfo(slot, BOOKTYPE_SPELL) ~= "FUTURESPELL" then
                local name = GetSpellBookItemName(slot, BOOKTYPE_SPELL)
                for i, target in ipairs(targetNames) do
                    if name == target and i <= MAX_SPELLS then
                        spells[i]     = name
                        local _, _, icon = GetSpellInfo(name)
                        spellIcons[i] = icon or "Interface\\Icons\\INV_Misc_QuestionMark"
                    end
                end
            end
        end
    end
end

-- â”€â”€ Roster management â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
local function RebuildRoster()
    wipe(roster)
    local numRaid  = GetNumRaidMembers()
    local numParty = GetNumPartyMembers()
    if numRaid > 0 then
        for i = 1, numRaid do roster[#roster + 1] = "raid" .. i end
    elseif numParty > 0 then
        for i = 1, numParty do roster[#roster + 1] = "party" .. i end
        roster[#roster + 1] = "player"
    else
        roster[1] = "player"
    end
end

local function RebuildClassRows()
    wipe(classRows)
    wipe(classMembers)
    for _, uid in ipairs(roster) do
        if UnitExists(uid) then
            local _, token = UnitClass(uid)
            if token then
                if not classMembers[token] then
                    classMembers[token] = {}
                    classRows[#classRows + 1] = token
                end
                classMembers[token][#classMembers[token] + 1] = uid
            end
        end
    end
end

-- â”€â”€ Buff scan â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
local function CheckUnit(unitID)
    if not UnitExists(unitID) then buffStatus[unitID] = nil; return end
    local name = UnitName(unitID)
    if not name or not UnitIsConnected(unitID) or UnitIsDeadOrGhost(unitID) then
        buffStatus[unitID] = nil
        return
    end
    local e    = buffStatus[unitID] or {}
    e.name     = name
    e.unitID   = unitID
    for i, spellName in ipairs(spells) do
        local present, expiry = GetBuffInfo(unitID, spellName)
        e[i] = { present = present, expiry = expiry }
    end
    buffStatus[unitID] = e
end

local function ScanAll()
    for _, uid in ipairs(roster) do CheckUnit(uid) end
end

-- â”€â”€ Needs-buff logic â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- Returns true if uid is missing spellIdx OR has less than threshold remaining
local function NeedsBuff(uid, spellIdx)
    local e = buffStatus[uid]
    if not e then return true end
    local info = e[spellIdx]
    if not info or not info.present then return true end
    if info.expiry and (info.expiry - GetTime()) < NEEDS_REBUFF_THRESHOLD then
        return true
    end
    return false
end

-- First member of classToken in range who needs spellIdx
local function GetNextInQueue(classToken, spellIdx)
    local members = classMembers[classToken]
    if not members or not spells[spellIdx] then return nil end
    for _, uid in ipairs(members) do
        if GetRangeStatus(uid, spellIdx) and NeedsBuff(uid, spellIdx) then
            return uid
        end
    end
    return nil
end

-- Count of members needing spellIdx (regardless of range)
local function CountNeeding(classToken, spellIdx)
    local members = classMembers[classToken]
    if not members then return 0 end
    local n = 0
    for _, uid in ipairs(members) do
        if NeedsBuff(uid, spellIdx) then n = n + 1 end
    end
    return n
end

-- True if at least one member is visible + in spell range for spellIdx
local function AnyInRange(classToken, spellIdx)
    local members = classMembers[classToken]
    if not members then return false end
    for _, uid in ipairs(members) do
        if GetRangeStatus(uid, spellIdx) then return true end
    end
    return false
end

-- â”€â”€ Class config helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- db.classConfig[classToken] = { [1]=bool, [2]=bool, [3]=bool }  (true = track this spell for this class)
local function GetClassCfg(classToken)
    local cfg = db.classConfig and db.classConfig[classToken]
    if type(cfg) ~= "table" then
        local r = {}
        for i = 1, MAX_SPELLS do r[i] = true end
        return r
    end
    local r = {}
    for i = 1, MAX_SPELLS do r[i] = (cfg[i] ~= false) end
    return r
end

-- Toggle all spell slots for a class (mousewheel shortcut; use /sb config for fine control)
local function CycleClassConfig(classToken, delta)
    if not db.classConfig then db.classConfig = {} end
    if type(db.classConfig[classToken]) ~= "table" then
        local cur = {}
        for ii = 1, MAX_SPELLS do cur[ii] = true end
        db.classConfig[classToken] = cur
    end
    local cfg = db.classConfig[classToken]
    local anyOn = false
    for i = 1, MAX_SPELLS do if cfg[i] ~= false then anyOn = true; break end end
    local newState = not anyOn
    for i = 1, MAX_SPELLS do cfg[i] = newState end
    local members   = classMembers[classToken]
    local className = classToken
    if members and members[1] then className = UnitClass(members[1]) or classToken end
    CoaPrint(string.format("|cffFFD700CoaPower|r: %s \226\134\146 %s",
        className, newState and L["all on"] or L["all off"]))
end

-- â”€â”€ Config window â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

-- Returns the active spell index for a class (collapsed single-button display)
local function GetActiveSpellIdx(classToken)
    local idx = db.activeSpell and db.activeSpell[classToken]
    if idx and spells[idx] then return idx end
    local cfg = GetClassCfg(classToken)
    for i = 1, MAX_SPELLS do
        if spells[i] and cfg[i] then return i end
    end
    return 1
end

-- Cycles to the next enabled spell (scroll wheel on class header)
local function CycleActiveSpell(classToken)
    if not db.activeSpell then db.activeSpell = {} end
    local cfg     = GetClassCfg(classToken)
    local current = GetActiveSpellIdx(classToken)
    for k = 1, MAX_SPELLS do
        local next = current % MAX_SPELLS + 1
        current    = next
        if spells[next] and cfg[next] then
            db.activeSpell[classToken] = next
            return
        end
    end
end

local CFG_CORNER_W = 148
local CFG_COL_W    = 72
local CFG_ROW_H    = 26
local CFG_HDR_H    = 28
local CFG_TITLE_H  = 26
local CFG_MAX_COLS = 12

local CreateConfigWindow  -- forward decl

local function RefreshConfigWindow()
    if not configFrame then CreateConfigWindow() end

    local cols = {}
    if #classRows > 0 then
        for _, t in ipairs(classRows) do cols[#cols + 1] = t end
    else
        for k in pairs(CLASS_DEFAULTS) do cols[#cols + 1] = k end
        table.sort(cols)
    end
    local nCols   = math.min(#cols, CFG_MAX_COLS)
    local nRows   = MAX_SPELLS
    local totalW  = CFG_CORNER_W + nCols * CFG_COL_W + 20
    local totalH  = CFG_TITLE_H + CFG_HDR_H + nRows * CFG_ROW_H + 20
    configFrame:SetSize(totalW, totalH)

    configFrame.hSep:SetWidth(totalW - 20)
    configFrame.hSep:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 10, -(CFG_TITLE_H))
    configFrame.vSep:SetHeight(CFG_HDR_H + nRows * CFG_ROW_H + 4)
    configFrame.vSep:SetPoint("TOPLEFT", configFrame, "TOPLEFT", CFG_CORNER_W, -(CFG_TITLE_H + 1))

    -- Column headers (class names)
    for c = 1, CFG_MAX_COLS do
        local lbl = configFrame.colHeaders[c]
        if c <= nCols then
            local classToken = cols[c]
            local className
            local members = classMembers[classToken]
            if members and members[1] then
                className = UnitClass(members[1]) or classToken
            else
                className = classToken:sub(1, 1) .. classToken:sub(2):lower()
            end
            lbl:SetText(className)
            local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
            if cc then lbl:SetTextColor(cc.r, cc.g, cc.b) else lbl:SetTextColor(1, 1, 1) end
            lbl:SetPoint("TOPLEFT", configFrame, "TOPLEFT",
                CFG_CORNER_W + (c - 1) * CFG_COL_W, -(CFG_TITLE_H + 2))
            lbl:Show()
        else
            lbl:Hide()
        end
    end

    -- Rows: spell icon + name + checkboxes
    for r = 1, nRows do
        local rowY = -(CFG_TITLE_H + CFG_HDR_H + (r - 1) * CFG_ROW_H)

        local ic = configFrame.rowIcons[r]
        ic:SetTexture(spellIcons[r] or "Interface\\Icons\\INV_Misc_QuestionMark")
        if spells[r] then ic:SetVertexColor(1, 1, 1) else ic:SetVertexColor(0.4, 0.4, 0.4) end
        ic:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 12, rowY - 4)
        ic:Show()

        local lb = configFrame.rowLabels[r]
        lb:SetText(spells[r] or string.format("|cff666666" .. L["(slot %d)"] .. "|r", r))
        lb:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 34, rowY - 2)
        lb:Show()

        for c = 1, CFG_MAX_COLS do
            local cb = configFrame.cells[r][c]
            if c <= nCols then
                local classToken = cols[c]
                cb._classToken = classToken
                local cfg = GetClassCfg(classToken)
                cb:SetChecked(cfg[r])
                cb:SetPoint("TOPLEFT", configFrame, "TOPLEFT",
                    CFG_CORNER_W + (c - 1) * CFG_COL_W + math.floor((CFG_COL_W - 22) / 2),
                    rowY - math.floor((CFG_ROW_H - 22) / 2))
                cb:Show()
            else
                cb._classToken = nil
                cb:Hide()
            end
        end
    end

    configFrame:Show()
    configFrame:Raise()
end

CreateConfigWindow = function()
    local f = CreateFrame("Frame", "CoaPowerConfigFrame", UIParent)
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile     = true, tileSize = 32, edgeSize = 32,
        insets   = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    f:SetBackdropColor(0, 0, 0, 0.92)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    f:SetClampedToScreen(true)
    f:SetPoint("CENTER")
    f:Hide()

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -8)
    title:SetText("|cffFFD700CoaPower|r " .. L["CoaPower Config"])

    -- Close button
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetSize(22, 22)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Horizontal separator (below title)
    local hSep = f:CreateTexture(nil, "ARTWORK")
    hSep:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    hSep:SetVertexColor(0.4, 0.4, 0.4, 1)
    hSep:SetHeight(1)
    f.hSep = hSep

    -- Vertical separator (between corner cell and class columns)
    local vSep = f:CreateTexture(nil, "ARTWORK")
    vSep:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    vSep:SetVertexColor(0.4, 0.4, 0.4, 1)
    vSep:SetWidth(1)
    f.vSep = vSep

    -- Corner diagonal labels
    local cornerSpell = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cornerSpell:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -(CFG_TITLE_H + 3))
    cornerSpell:SetTextColor(0.65, 0.65, 0.65)
    cornerSpell:SetText(L["Spell"])
    local cornerClass = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cornerClass:SetPoint("BOTTOMRIGHT", f, "TOPLEFT",
        CFG_CORNER_W - 6, -(CFG_TITLE_H + CFG_HDR_H - 5))
    cornerClass:SetTextColor(0.65, 0.65, 0.65)
    cornerClass:SetText(L["Class"])

    -- Pre-create column header labels
    f.colHeaders = {}
    for c = 1, CFG_MAX_COLS do
        local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetSize(CFG_COL_W - 4, CFG_HDR_H - 4)
        lbl:SetJustifyH("CENTER")
        lbl:SetJustifyV("MIDDLE")
        lbl:SetWordWrap(true)
        lbl:Hide()
        f.colHeaders[c] = lbl
    end

    -- Pre-create row icons, labels, checkboxes
    f.rowIcons  = {}
    f.rowLabels = {}
    f.cells     = {}
    for r = 1, MAX_SPELLS do
        local ic = f:CreateTexture(nil, "ARTWORK")
        ic:SetSize(18, 18)
        ic:Hide()
        f.rowIcons[r] = ic

        local lb = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lb:SetSize(CFG_CORNER_W - 36, CFG_ROW_H)
        lb:SetJustifyH("LEFT")
        lb:SetJustifyV("MIDDLE")
        lb:Hide()
        f.rowLabels[r] = lb

        f.cells[r] = {}
        for c = 1, CFG_MAX_COLS do
            local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
            cb:SetSize(22, 22)
            cb._r          = r
            cb._classToken = nil
            cb:SetScript("OnClick", function(self)
                local token = self._classToken
                if not token then return end
                if not db.classConfig then db.classConfig = {} end
                if type(db.classConfig[token]) ~= "table" then
                    local cur = {}
                    for ii = 1, MAX_SPELLS do cur[ii] = true end
                    db.classConfig[token] = cur
                end
                db.classConfig[token][self._r] = self:GetChecked() and true or false
                if isActive then UpdateUI() end
            end)
            cb:Hide()
            f.cells[r][c] = cb
        end
    end

    configFrame = f
end

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- Interface Options panel  (Escape â†’ Interface â†’ AddOns â†’ CoaPower)
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
local function RefreshIOPanel()
    if not ioPanel then return end
    if not isActive then
        ioPanel.notActive:Show()
        ioPanel.gridArea:Hide()
        for _, w in ipairs(ioPanel.optWidgets) do w:Hide() end
        return
    end
    ioPanel.notActive:Hide()
    ioPanel.gridArea:Show()
    for _, w in ipairs(ioPanel.optWidgets) do w:Show() end

    local cols = {}
    if #classRows > 0 then
        for _, t in ipairs(classRows) do cols[#cols + 1] = t end
    else
        local seen = {}
        for k in pairs(CLASS_DEFAULTS) do seen[k] = true end
        if COAPOWER_CLASS_DATA then
            for k, v in pairs(COAPOWER_CLASS_DATA) do
                if v and #v > 0 then seen[k] = true end
            end
        end
        for k in pairs(seen) do cols[#cols + 1] = k end
        table.sort(cols)
    end
    local nCols = math.min(#cols, CFG_MAX_COLS)

    for c = 1, CFG_MAX_COLS do
        local lbl = ioPanel.colHeaders[c]
        if c <= nCols then
            local t = cols[c]
            local m = classMembers[t]
            local name = (m and m[1] and UnitClass(m[1])) or (t:sub(1,1) .. t:sub(2):lower())
            lbl:SetText(name)
            local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[t]
            if cc then lbl:SetTextColor(cc.r, cc.g, cc.b) else lbl:SetTextColor(1,1,1) end
            lbl:Show()
        else
            lbl:Hide()
        end
    end

    for r = 1, MAX_SPELLS do
        local ic = ioPanel.rowIcons[r]
        ic:SetTexture(spellIcons[r] or "Interface\\Icons\\INV_Misc_QuestionMark")
        if spells[r] then ic:SetVertexColor(1,1,1) else ic:SetVertexColor(0.4,0.4,0.4) end
        ioPanel.rowLabels[r]:SetText(spells[r] or string.format("|cff666666" .. L["(slot %d)"] .. "|r", r))
        for c = 1, CFG_MAX_COLS do
            local cb = ioPanel.cells[r][c]
            if c <= nCols then
                local t = cols[c]
                cb._classToken = t
                cb:SetChecked(GetClassCfg(t)[r])
                cb:Show()
            else
                cb._classToken = nil
                cb:Hide()
            end
        end
    end

    ioPanel.lockCb:SetChecked(db.locked)
    ioPanel.rangeCb:SetChecked(db.rangeOnly)
    ioPanel.verboseCb:SetChecked(db.verbose ~= false)
end

local function CreateIOPanel()
    local p = CreateFrame("Frame", "CoaPowerInterfacePanel")
    p.name    = "CoaPower"
    p.refresh = RefreshIOPanel

    local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", p, "TOPLEFT", 16, -16)
    title:SetText("|cffFFD700CoaPower|r")
    local sub = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    sub:SetText(L["Multi-class buff tracker"])
    sub:SetTextColor(0.7, 0.7, 0.7)

    local notActive = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    notActive:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -20)
    notActive:SetTextColor(1, 0.5, 0.5)
    notActive:SetText(L["not active panel"])
    notActive:Hide()
    p.notActive = notActive

    -- Grid area (spell x class checkboxes)
    local ga = CreateFrame("Frame", nil, p)
    ga:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -16)
    ga:SetSize(CFG_CORNER_W + CFG_MAX_COLS * CFG_COL_W + 20,
               CFG_HDR_H + MAX_SPELLS * CFG_ROW_H + 4)
    ga:Hide()
    p.gridArea = ga

    local hSep = ga:CreateTexture(nil, "ARTWORK")
    hSep:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    hSep:SetVertexColor(0.4, 0.4, 0.4, 1)
    hSep:SetHeight(1)
    hSep:SetWidth(CFG_CORNER_W + CFG_MAX_COLS * CFG_COL_W)
    hSep:SetPoint("TOPLEFT", ga, "TOPLEFT", 0, -CFG_HDR_H)
    local vSep = ga:CreateTexture(nil, "ARTWORK")
    vSep:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    vSep:SetVertexColor(0.4, 0.4, 0.4, 1)
    vSep:SetWidth(1)
    vSep:SetHeight(CFG_HDR_H + MAX_SPELLS * CFG_ROW_H)
    vSep:SetPoint("TOPLEFT", ga, "TOPLEFT", CFG_CORNER_W, 0)

    local cs = ga:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cs:SetPoint("TOPLEFT", ga, "TOPLEFT", 4, -8)
    cs:SetTextColor(0.65, 0.65, 0.65)
    cs:SetText(L["Spell"])
    local cc2 = ga:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cc2:SetPoint("BOTTOMRIGHT", ga, "TOPLEFT", CFG_CORNER_W - 4, -(CFG_HDR_H - 5))
    cc2:SetTextColor(0.65, 0.65, 0.65)
    cc2:SetText(L["Class"])

    p.colHeaders = {}
    for c = 1, CFG_MAX_COLS do
        local lbl = ga:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetSize(CFG_COL_W - 4, CFG_HDR_H - 4)
        lbl:SetJustifyH("CENTER")
        lbl:SetJustifyV("MIDDLE")
        lbl:SetWordWrap(true)
        lbl:SetPoint("TOPLEFT", ga, "TOPLEFT", CFG_CORNER_W + (c - 1) * CFG_COL_W, -2)
        lbl:Hide()
        p.colHeaders[c] = lbl
    end

    p.rowIcons  = {}
    p.rowLabels = {}
    p.cells     = {}
    for r = 1, MAX_SPELLS do
        local rowY = -(CFG_HDR_H + (r - 1) * CFG_ROW_H)
        local ic = ga:CreateTexture(nil, "ARTWORK")
        ic:SetSize(18, 18)
        ic:SetPoint("TOPLEFT", ga, "TOPLEFT", 12, rowY - 4)
        p.rowIcons[r] = ic
        local lb = ga:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lb:SetSize(CFG_CORNER_W - 36, CFG_ROW_H)
        lb:SetJustifyH("LEFT")
        lb:SetJustifyV("MIDDLE")
        lb:SetPoint("TOPLEFT", ga, "TOPLEFT", 34, rowY - 2)
        p.rowLabels[r] = lb
        p.cells[r] = {}
        for c = 1, CFG_MAX_COLS do
            local cb = CreateFrame("CheckButton", nil, ga, "UICheckButtonTemplate")
            cb:SetSize(22, 22)
            cb:SetPoint("TOPLEFT", ga, "TOPLEFT",
                CFG_CORNER_W + (c - 1) * CFG_COL_W + math.floor((CFG_COL_W - 22) / 2),
                rowY - math.floor((CFG_ROW_H - 22) / 2))
            cb._r = r
            cb._classToken = nil
            cb:SetScript("OnClick", function(self)
                local token = self._classToken
                if not token then return end
                if not db.classConfig then db.classConfig = {} end
                if type(db.classConfig[token]) ~= "table" then
                    local cur = {}
                    for ii = 1, MAX_SPELLS do cur[ii] = true end
                    db.classConfig[token] = cur
                end
                db.classConfig[token][self._r] = self:GetChecked() and true or false
                if isActive then UpdateUI() end
            end)
            cb:Hide()
            p.cells[r][c] = cb
        end
    end

    -- Options section
    p.optWidgets = {}
    local optTitle = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    optTitle:SetPoint("TOPLEFT", ga, "BOTTOMLEFT", 0, -16)
    optTitle:SetText(L["Options"])
    optTitle:SetTextColor(1, 0.9, 0.5)
    p.optWidgets[#p.optWidgets + 1] = optTitle

    local function addOpt(labelText, dy)
        local cb = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
        cb:SetSize(22, 22)
        cb:SetPoint("TOPLEFT", optTitle, "BOTTOMLEFT", 0, dy)
        local lbl = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        lbl:SetText(labelText)
        p.optWidgets[#p.optWidgets + 1] = cb
        p.optWidgets[#p.optWidgets + 1] = lbl
        return cb
    end

    local lockCb    = addOpt(L["Lock frame position"], -4)
    local rangeCb   = addOpt(L["Range-only (hide out-of-range classes)"], -30)
    local verboseCb = addOpt(L["Verbose output"], -56)

    lockCb:SetScript("OnClick", function(self)
        db.locked = self:GetChecked() and true or false
    end)
    rangeCb:SetScript("OnClick", function(self)
        db.rangeOnly = self:GetChecked() and true or false
        if isActive then UpdateUI() end
    end)
    verboseCb:SetScript("OnClick", function(self)
        db.verbose = self:GetChecked() and true or false
    end)

    p.lockCb    = lockCb
    p.rangeCb   = rangeCb
    p.verboseCb = verboseCb

    InterfaceOptions_AddCategory(p)
    ioPanel = p
end

-- â”€â”€ Row factory â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
local function GetOrCreateClassRow(classToken)
    if rowPool[classToken] then return rowPool[classToken] end

    local row = CreateFrame("Frame", nil, mainFrame)
    row:SetHeight(ROW_H)
    row:EnableMouse(true)
    row:EnableMouseWheel(true)
    row._classToken = classToken

    -- Class name label (also shows count)
    local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("LEFT", row, "LEFT", 2, 0)
    lbl:SetWidth(NAME_W - 6)
    lbl:SetJustifyH("LEFT")
    row.lbl = lbl

    -- Transparent button over the label area — left-click to expand/collapse
    local expandBtn = CreateFrame("Button", nil, mainFrame)
    expandBtn:SetPoint("LEFT", row, "LEFT", 0, 0)
    expandBtn:SetSize(NAME_W, ROW_H)
    expandBtn:SetScript("OnClick", function()
        expandedClasses[classToken] = not expandedClasses[classToken]
        UpdateUI()
    end)
    row.expandBtn = expandBtn

    -- Buff buttons (MAX_SPELLS slots, shown/hidden per class config)
    row.btns = {}
    for i = 1, MAX_SPELLS do
        local btn = CreateFrame("Button", nil, secureHost, "SecureActionButtonTemplate")
        btn:SetSize(ICON_SIZE, ICON_SIZE)
        btn:SetFrameStrata("HIGH")
        btn:RegisterForClicks("LeftButtonUp")
        btn:SetAttribute("type",  "macro")
        btn:SetAttribute("macrotext", "")
        btn:Hide()

        local tex = btn:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        tex:SetTexture(spellIcons[i] or "Interface\\Icons\\INV_Misc_QuestionMark")
        btn.iconTex = tex

        -- Expiry timer overlay (bottom-right corner)
        local tmr = btn:CreateFontString(nil, "OVERLAY")
        tmr:SetFont("Fonts\\FRIZQT__.TTF", 7, "OUTLINE")
        tmr:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 1, 0)
        tmr:SetTextColor(1, 0.8, 0)
        tmr:Hide()
        btn.timerTxt = tmr

        -- Tooltip: show next target + expiry info
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local sn = spells[i]
            if sn then
                GameTooltip:AddLine(sn, 1, 1, 0)
                local nextUID = self._nextUID
                if nextUID then
                    GameTooltip:AddLine(string.format(L["Next: %s"], UnitName(nextUID) or nextUID), 0.8, 0.8, 1)
                    local e = buffStatus[nextUID]
                    if e and e[i] and e[i].expiry then
                        local rem = math.max(0, math.floor(e[i].expiry - GetTime()))
                        GameTooltip:AddLine(
                            string.format(L["Expires in: %dm %ds"], math.floor(rem / 60), rem % 60),
                            1, 0.8, 0)
                    end
                else
                    GameTooltip:AddLine(L["Everyone buffed!"], 0.5, 1, 0.5)
                end
            end
            GameTooltip:AddLine(L["TT mousewheel"])
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        row.btns[i] = btn
    end

    -- Mousewheel â†’ cycle this class's buff assignment
    row:SetScript("OnMouseWheel", function(self, delta)
        if InCombatLockdown() then
            print("|cffFFD700CoaPower|r: " .. L["no config in combat"])
            return
        end
        CycleActiveSpell(self._classToken)
        UpdateUI()
    end)

    rowPool[classToken] = row
    return row
end

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- Player sub-row factory  (one row per member when class is expanded)
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
local function GetOrCreatePlayerRow(uid)
    if playerRowPool[uid] then return playerRowPool[uid] end

    local row = CreateFrame("Frame", nil, mainFrame)
    row:SetHeight(ROW_H)
    row:EnableMouse(false)

    local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("LEFT", row, "LEFT", 14, 0)
    lbl:SetWidth(NAME_W - 16)
    lbl:SetJustifyH("LEFT")
    row.lbl = lbl

    row.btns = {}
    for i = 1, MAX_SPELLS do
        local btn = CreateFrame("Button", nil, secureHost, "SecureActionButtonTemplate")
        btn:SetSize(ICON_SIZE, ICON_SIZE)
        btn:SetFrameStrata("HIGH")
        btn:RegisterForClicks("LeftButtonUp")
        btn:SetAttribute("type", "macro")
        btn:SetAttribute("macrotext", "")
        btn:Hide()

        local tex = btn:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        btn.iconTex = tex

        local tmr = btn:CreateFontString(nil, "OVERLAY")
        tmr:SetFont("Fonts\\FRIZQT__.TTF", 7, "OUTLINE")
        tmr:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 1, 0)
        tmr:SetTextColor(1, 0.8, 0)
        tmr:Hide()
        btn.timerTxt = tmr

        local spellIdx = i
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local sn = spells[spellIdx]
            if sn then GameTooltip:AddLine(sn, 1, 1, 0) end
            local pname = UnitName(uid)
            if pname then GameTooltip:AddLine(pname, 0.8, 0.8, 1) end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        row.btns[i] = btn
    end

    playerRowPool[uid] = row
    return row
end

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- UI update  (collapsed class rows + expanded per-player sub-rows)
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
UpdateUI = function()
    if not mainFrame or not mainFrame:IsShown() or not isActive then return end

    local inCombat = InCombatLockdown()
    local now      = GetTime()
    local frameW   = GetFrameW()
    mainFrame:SetWidth(frameW)

    -- Refresh header spell icons
    for i = 1, MAX_SPELLS do
        if headerIcons[i] then
            headerIcons[i]:SetTexture(spellIcons[i] or "Interface\\Icons\\INV_Misc_QuestionMark")
            if spells[i] then
                headerIcons[i]:SetVertexColor(1, 1, 1)
            else
                headerIcons[i]:SetVertexColor(0.4, 0.4, 0.4)
            end
        end
    end

    RebuildClassRows()

    -- Determine visible classes
    local visible = {}
    for _, token in ipairs(classRows) do
        local cfg = GetClassCfg(token)
        local anyEnabled = false
        for i = 1, #spells do
            if cfg[i] then anyEnabled = true; break end
        end
        local inRange = not anyEnabled
        if anyEnabled then
            for i = 1, #spells do
                if cfg[i] and AnyInRange(token, i) then inRange = true; break end
            end
        end
        if not db.rangeOnly or inRange or not anyEnabled then
            visible[#visible + 1] = { token = token, inRange = inRange, anyEnabled = anyEnabled }
        end
    end

    -- Track what is rendered this pass (for cleanup)
    local shownTokens = {}
    local shownUIDs   = {}

    -- Layout with a running Y cursor (rows vary in count when expanded)
    local currentY = HEADER_H + PAD

    for _, entry in ipairs(visible) do
        local token = entry.token
        shownTokens[token] = true

        local row = GetOrCreateClassRow(token)
        row:SetWidth(frameW - 8)
        row:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 4, -currentY)
        row:Show()
        if row.expandBtn then row.expandBtn:SetSize(NAME_W, ROW_H) end

        -- Row alpha
        local anyEnabled = entry.anyEnabled
        if not anyEnabled then
            row:SetAlpha(0.35)
        elseif entry.inRange then
            row:SetAlpha(1.0)
        else
            row:SetAlpha(0.40)
        end

        -- Class label  (\226\150\188 = â–¼, \226\150\182 = â–¶)
        local members   = classMembers[token]
        local className = token
        if members and members[1] then className = UnitClass(members[1]) or token end
        local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
        if cc then row.lbl:SetTextColor(cc.r, cc.g, cc.b) else row.lbl:SetTextColor(1, 1, 1) end
        local cfg = GetClassCfg(token)
        local totalNeeding = 0
        for i = 1, #spells do
            if cfg[i] then totalNeeding = totalNeeding + CountNeeding(token, i) end
        end
        local mark = expandedClasses[token] and "\226\150\188 " or "\226\150\182 "
        if not anyEnabled then
            row.lbl:SetText(mark .. className .. " " .. L["(off)"])
        elseif totalNeeding > 0 then
            row.lbl:SetText(mark .. string.format("%s |cffffff00(%d)|r", className, totalNeeding))
        else
            row.lbl:SetText(mark .. className .. " |cff00ff00\226\156\147|r")
        end

        -- Collapsed view: show only the active spell button (scroll to cycle)
        local activeIdx = GetActiveSpellIdx(token)
        for i = 1, MAX_SPELLS do
            local btn = row.btns[i]
            if i ~= activeIdx or not spells[i] or not cfg[i] then
                btn:Hide()
                btn._nextUID = nil
            else
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", secureHost, "TOPLEFT",
                    4 + NAME_W + PAD, -(currentY + 2))
                btn:Show()
                btn.iconTex:SetTexture(spellIcons[i] or "Interface\\Icons\\INV_Misc_QuestionMark")
                local nextUID = GetNextInQueue(token, i)
                btn._nextUID  = nextUID
                if not inCombat then
                    local castTarget = nextUID or "player"
                    btn:SetAttribute("macrotext",
                        string.format("/cast [target=%s] %s", castTarget, spells[i]))
                end
                if nextUID then
                    btn.iconTex:SetVertexColor(1, 1, 1)
                    btn:SetAlpha(1.0)
                    local e = buffStatus[nextUID]
                    if e and e[i] and e[i].expiry then
                        local remaining = e[i].expiry - now
                        if remaining > 0 and remaining < NEEDS_REBUFF_THRESHOLD then
                            btn.timerTxt:SetText(math.ceil(remaining / 60) .. "m")
                            btn.timerTxt:Show()
                        else
                            btn.timerTxt:Hide()
                        end
                    else
                        btn.timerTxt:Hide()
                    end
                else
                    btn.iconTex:SetVertexColor(0.4, 1.0, 0.4)
                    btn:SetAlpha(0.55)
                    btn.timerTxt:Hide()
                end
            end
        end

        currentY = currentY + ROW_H

        -- Expanded view: one sub-row per player with all enabled spell buttons
        if expandedClasses[token] then
            local pmembers = classMembers[token] or {}
            for _, uid in ipairs(pmembers) do
                shownUIDs[uid] = true
                local prow = GetOrCreatePlayerRow(uid)
                prow:SetWidth(frameW - 8)
                prow:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 4, -currentY)
                prow:Show()

                local pname  = UnitName(uid) or uid
                local online = UnitIsConnected and UnitIsConnected(uid)
                prow.lbl:SetText(online ~= false
                    and ("  " .. pname)
                    or  ("  |cff888888" .. pname .. "|r"))
                prow.lbl:SetTextColor(1, 1, 1)

                for i = 1, MAX_SPELLS do
                    local pbtn = prow.btns[i]
                    if not spells[i] or not cfg[i] then
                        pbtn:Hide()
                    else
                        pbtn:ClearAllPoints()
                        pbtn:SetPoint("TOPLEFT", secureHost, "TOPLEFT",
                            4 + NAME_W + PAD + (i - 1) * COL_W,
                            -(currentY + 2))
                        pbtn:Show()
                        pbtn.iconTex:SetTexture(
                            spellIcons[i] or "Interface\\Icons\\INV_Misc_QuestionMark")
                        if not inCombat then
                            pbtn:SetAttribute("macrotext",
                                string.format("/cast [target=%s] %s", uid, spells[i]))
                        end
                        local needsBuff = NeedsBuff(uid, i)
                        local inRng     = GetRangeStatus(uid, i)
                        if needsBuff and inRng then
                            pbtn.iconTex:SetVertexColor(1, 1, 1)
                            pbtn:SetAlpha(1.0)
                            local e = buffStatus[uid]
                            if e and e[i] and e[i].expiry then
                                local remaining = e[i].expiry - now
                                if remaining > 0 and remaining < NEEDS_REBUFF_THRESHOLD then
                                    pbtn.timerTxt:SetText(math.ceil(remaining / 60) .. "m")
                                    pbtn.timerTxt:Show()
                                else
                                    pbtn.timerTxt:Hide()
                                end
                            else
                                pbtn.timerTxt:Hide()
                            end
                        elseif needsBuff then
                            pbtn.iconTex:SetVertexColor(1, 0.5, 0.5)
                            pbtn:SetAlpha(0.7)
                            pbtn.timerTxt:Hide()
                        else
                            pbtn.iconTex:SetVertexColor(0.4, 1.0, 0.4)
                            pbtn:SetAlpha(0.55)
                            pbtn.timerTxt:Hide()
                        end
                    end
                end

                currentY = currentY + ROW_H
            end
        end
    end

    mainFrame:SetHeight(math.max(currentY + PAD, HEADER_H + PAD * 2))

    -- Cleanup: hide class rows not visible this pass
    for token, row in pairs(rowPool) do
        if not shownTokens[token] then
            row:Hide()
            for j = 1, MAX_SPELLS do if row.btns[j] then row.btns[j]:Hide() end end
        end
    end

    -- Cleanup: hide player rows not visible this pass
    for uid, prow in pairs(playerRowPool) do
        if not shownUIDs[uid] then
            prow:Hide()
            for j = 1, MAX_SPELLS do if prow.btns[j] then prow.btns[j]:Hide() end end
        end
    end
end
local function CreateUI()
    local f = CreateFrame("Frame", "CoaPowerFrame", UIParent)
    mainFrame = f

    -- Secure host: child of UIParent (NOT mainFrame), follows mainFrame's layout.
    -- SecureActionButtonTemplate buttons are parented here so mainFrame stays
    -- outside the secure frame hierarchy and can be freely resized.
    local sh = CreateFrame("Frame", nil, UIParent)
    sh:SetAllPoints(f)
    secureHost = sh

    f:SetWidth(GetFrameW())
    f:SetHeight(HEADER_H + PAD)
    f:SetFrameStrata("MEDIUM")
    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile     = true, tileSize = 16, edgeSize = 12,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0, 0, 0, 0.85)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if not db.locked then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local _, _, _, x, y = self:GetPoint()
        db.xOfs, db.yOfs = x, y
    end)
    f:SetScript("OnHide", function()
        if configFrame then configFrame:Hide() end
        for _, r in pairs(rowPool) do
            for j = 1, MAX_SPELLS do
                if r.btns[j] then r.btns[j]:Hide() end
            end
        end
        for _, pr in pairs(playerRowPool) do
            for j = 1, MAX_SPELLS do
                if pr.btns[j] then pr.btns[j]:Hide() end
            end
        end
    end)
    f:SetClampedToScreen(true)
    f:SetPoint(db.point or "CENTER", UIParent, db.point or "CENTER",
               db.xOfs or 0, db.yOfs or 0)

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + 2, -5)
    title:SetText("|cffFFD700CoaPower|r")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetSize(18, 18)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", 2, 2)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Config gear button
    local cfgBtn = CreateFrame("Button", nil, f)
    cfgBtn:SetSize(18, 18)
    cfgBtn:SetPoint("RIGHT", closeBtn, "LEFT", -1, 0)
    cfgBtn:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
    cfgBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    cfgBtn:SetScript("OnClick", function()
        if ioPanel then
            InterfaceOptionsFrame_OpenToCategory(ioPanel)
            InterfaceOptionsFrame_OpenToCategory(ioPanel)
        end
    end)
    cfgBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Buff Config"], 1, 1, 0)
        GameTooltip:AddLine(L["TT open IO"], 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    cfgBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Spell column header icons
    for i = 1, MAX_SPELLS do
        local tex = f:CreateTexture(nil, "ARTWORK")
        tex:SetSize(ICON_SIZE, ICON_SIZE)
        tex:SetPoint("TOPLEFT", f, "TOPLEFT", NAME_W + PAD + (i - 1) * COL_W, -5)
        tex:SetTexture(spellIcons[i] or "Interface\\Icons\\INV_Misc_QuestionMark")
        if not spells[i] then tex:SetVertexColor(0.4, 0.4, 0.4) end
        headerIcons[i] = tex
    end

    -- Periodic scan + UI update
    f:SetScript("OnUpdate", function(self, elapsed)
        scanTimer = scanTimer + elapsed
        if scanTimer >= SCAN_INTERVAL then
            scanTimer = 0
            ScanAll()
            UpdateUI()
        end
    end)

    f:Hide()
end

-- â”€â”€ Event handling â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
local eventFrame = CreateFrame("Frame", "CoaPowerEventFrame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
eventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("LEARNED_SPELL_IN_TAB")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    -- â”€â”€ ADDON_LOADED â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    if event == "ADDON_LOADED" then
        local name = ...
        if name == "CoaPower" then
            CoaPowerDB = CoaPowerDB or {}
            for k, v in pairs(DB_DEFAULTS) do
                if CoaPowerDB[k] == nil then
                    CoaPowerDB[k] = (type(v) == "table") and {} or v
                end
            end
            db = CoaPowerDB
            L  = CoaPowerL
            CreateIOPanel()
            -- Migrate old integer classConfig format (0..3) to boolean array
            if db.classConfig then
                local OLD_MAP = {
                    [0] = { true,  true,  true  },
                    [1] = { true,  false, false },
                    [2] = { false, true,  false },
                    [3] = { false, false, false },
                }
                for token, val in pairs(db.classConfig) do
                    if type(val) == "number" then
                        db.classConfig[token] = OLD_MAP[val] or { true, true, true }
                    end
                end
            end
        end

    -- â”€â”€ PLAYER_LOGIN â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    elseif event == "PLAYER_LOGIN" then
        local _, token = UnitClass("player")
        casterClass = token
        -- Activate only if this class has known or user-configured spells
        local userList = db.spellsByClass and db.spellsByClass[token]
        local dataList = COAPOWER_CLASS_DATA and COAPOWER_CLASS_DATA[token]
        local hasSpells = (userList and #userList > 0)
            or CLASS_DEFAULTS[token]
            or (dataList and #dataList > 0)
        if not hasSpells then return end
        isActive = true
        ScanSpellbook()
        RebuildRoster()
        RebuildClassRows()
        ScanAll()
        CreateUI()
        mainFrame:Show()
        UpdateUI()

    -- â”€â”€ ROSTER CHANGES â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    elseif event == "RAID_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" then
        if not isActive then return end
        RebuildRoster()
        ScanAll()
        UpdateUI()

    -- â”€â”€ UNIT_AURA: recheck unit + auto-advance chain cast â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    elseif event == "UNIT_AURA" then
        if not isActive then return end
        local unitID = ...
        for _, uid in ipairs(roster) do
            if uid == unitID then
                CheckUnit(unitID)
                UpdateUI()   -- buttons automatically advance to next in queue
                return
            end
        end

    -- â”€â”€ NEW SPELL LEARNED â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    elseif event == "LEARNED_SPELL_IN_TAB" then
        if not isActive then return end
        ScanSpellbook()
        UpdateUI()

    -- â”€â”€ COMBAT ENDED: refresh secure attributes â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    elseif event == "PLAYER_REGEN_ENABLED" then
        if not isActive then return end
        ScanAll()
        UpdateUI()
    end
end)

-- â”€â”€ Slash commands â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
SLASH_COAPOWER1 = "/coapower"
SLASH_COAPOWER2 = "/cp"
SlashCmdList["COAPOWER"] = function(msg)
    local cmd, arg = msg:match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()

    if cmd == "" then
        if mainFrame then
            if mainFrame:IsShown() then mainFrame:Hide() else mainFrame:Show() end
        else
            print("|cffFFD700CoaPower|r: " .. string.format(L["not active for class"], casterClass or "unknown"))
        end

    elseif cmd == "lock" then
        db.locked = not db.locked
        CoaPrint("|cffFFD700CoaPower|r: " .. (db.locked and L["frame locked"] or L["frame unlocked"]))

    elseif cmd == "range" then
        db.rangeOnly = not db.rangeOnly
        CoaPrint("|cffFFD700CoaPower|r: " .. (db.rangeOnly and L["range hidden"] or L["range greyed"]))
        if isActive then UpdateUI() end

    elseif cmd == "addspell" then
        if arg == "" then
            print("|cffFFD700CoaPower|r: " .. L["usage addspell"])
            return
        end
        if not casterClass then return end
        if not db.spellsByClass then db.spellsByClass = {} end
        db.spellsByClass[casterClass] = db.spellsByClass[casterClass] or {}
        for _, s in ipairs(db.spellsByClass[casterClass]) do
            if s == arg then
                print("|cffFFD700CoaPower|r: " .. string.format(L["already tracked"], arg))
                return
            end
        end
        local list = db.spellsByClass[casterClass]
        list[#list + 1] = arg
        if not isActive then
            isActive = true
            ScanSpellbook()
            RebuildRoster()
            RebuildClassRows()
            ScanAll()
            if not mainFrame then CreateUI() end
            mainFrame:Show()
        else
            ScanSpellbook()
            ScanAll()
        end
        CoaPrint("|cffFFD700CoaPower|r: " .. string.format(L["now tracking"], arg))
        UpdateUI()

    elseif cmd == "removespell" then
        local idx = tonumber(arg)
        if not idx or not casterClass then
            print("|cffFFD700CoaPower|r: " .. L["usage removespell"])
            return
        end
        local list = db.spellsByClass and db.spellsByClass[casterClass]
        if list and list[idx] then
            local removed = list[idx]
            table.remove(list, idx)
            ScanSpellbook()
            CoaPrint("|cffFFD700CoaPower|r: " .. string.format(L["removed spell"], removed))
            if isActive then ScanAll(); UpdateUI() end
        else
            print("|cffFFD700CoaPower|r: " .. string.format(L["no spell at index"], idx))
        end

    elseif cmd == "spells" then
        if #spells == 0 then
            print("|cffFFD700CoaPower|r: " .. string.format(L["no spells tracked"], casterClass or "?"))
            print(L["use addspell hint"])
        else
            print("|cffFFD700CoaPower|r: " .. string.format(L["tracking for"], casterClass or "?"))
            for i, s in ipairs(spells) do
                print(string.format("  [%d] %s", i, s))
            end
        end

    elseif cmd == "reset" then
        if db.classConfig then
            db.classConfig = {}
            CoaPrint("|cffFFD700CoaPower|r: " .. L["reset done"])
            if isActive then UpdateUI() end
        end

    elseif cmd == "verbose" then
        db.verbose = not db.verbose
        print("|cffFFD700CoaPower|r: " .. (db.verbose and L["verbose on"] or L["verbose off"]))

    elseif cmd == "config" or cmd == "cfg" then
        if not isActive then print("|cffFFD700CoaPower|r: " .. L["not active short"]); return end
        if configFrame and configFrame:IsShown() then
            configFrame:Hide()
        else
            RefreshConfigWindow()
        end

    else
        print("|cffFFD700CoaPower|r commands:")
        print(L["help 01"])
        print(L["help 02"])
        print(L["help 03"])
        print(L["help 04"])
        print(L["help 05"])
        print(L["help 06"])
        print(L["help 07"])
        print(L["help 08"])
        print(L["help 09"])
        print(L["help 10"])
    end
end
