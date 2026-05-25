-- CoaPower_enUS.lua
-- English (default) locale — all keys defined here as fallback.
-- Other locale files only need to override what they translate.

local L = {}
CoaPowerL = L

-- ── Config window ─────────────────────────────────────────────────────────────
L["CoaPower Config"]       = "CoaPower Config"
L["Multi-class buff tracker"] = "Multi-class buff tracker"
L["Spell"]                 = "Spell"
L["Class"]                 = "Class"
L["Options"]               = "Options"
L["Lock frame position"]   = "Lock frame position"
L["Range-only (hide out-of-range classes)"] = "Range-only (hide out-of-range classes)"
L["Verbose output"]        = "Verbose output"
L["(slot %d)"]             = "(slot %d)"
L["(off)"]                 = "|cff888888(off)|r"

-- ── Not active message ────────────────────────────────────────────────────────
L["not active panel"] = "CoaPower is not active for your class.\n"
    .. "Add your class to |cffFFD700CoaPower_Data.lua|r to enable it."

-- ── Tooltips ──────────────────────────────────────────────────────────────────
L["Buff Config"]           = "Buff Config"
L["TT open IO"]            = "Opens Interface \226\134\146 AddOns \226\134\146 CoaPower"
L["Next: %s"]              = "Next: %s"
L["Expires in: %dm %ds"]   = "Expires in: %dm %ds"
L["Everyone buffed!"]      = "Everyone buffed!"
L["TT mousewheel"]         = "|cffaaaaaa(Mousewheel to cycle active spell)|r"

-- ── Class row / UI ────────────────────────────────────────────────────────────
L["all on"]                = "|cff00ff00all on|r"
L["all off"]               = "|cffff6666all off|r"

-- ── Combat lock ───────────────────────────────────────────────────────────────
L["no config in combat"]   = "cannot change config during combat."

-- ── Slash command messages ────────────────────────────────────────────────────
L["not active for class"]  = "not active for class '%s'. Use /cp addspell <name>."
L["frame locked"]          = "frame |cffff9900locked|r"
L["frame unlocked"]        = "frame |cff00ff00unlocked|r"
L["range hidden"]          = "out-of-range rows |cff00ff00hidden|r"
L["range greyed"]          = "out-of-range rows |cffffff00greyed out|r"
L["usage addspell"]        = "usage: /cp addspell <spell name>"
L["already tracked"]       = "'%s' already tracked."
L["now tracking"]          = "tracking '%s'"
L["usage removespell"]     = "usage: /cp removespell <1|2|3>"
L["removed spell"]         = "removed '%s'"
L["no spell at index"]     = "no custom spell at index %d"
L["no spells tracked"]     = "no spells tracked for %s"
L["use addspell hint"]     = "  Use /cp addspell <name> to configure."
L["tracking for"]          = "tracking for %s:"
L["reset done"]            = "all class buff assignments reset to default."
L["not active short"]      = "not active."
L["verbose on"]            = "verbose |cff00ff00on|r"
L["verbose off"]           = "verbose |cffff6666off|r"

-- ── Help text ─────────────────────────────────────────────────────────────────
L["help 01"] = "  /cp                    \226\128\148 toggle window"
L["help 02"] = "  /cp lock               \226\128\148 lock / unlock frame position"
L["help 03"] = "  /cp range              \226\128\148 toggle hide vs grey out-of-range rows"
L["help 04"] = "  /cp addspell <name>    \226\128\148 track a new buff spell"
L["help 05"] = "  /cp removespell <N>    \226\128\148 remove custom spell by slot index"
L["help 06"] = "  /cp spells             \226\128\148 list currently tracked spells"
L["help 07"] = "  /cp reset              \226\128\148 reset all class buff assignments to default"
L["help 08"] = "  /cp config             \226\128\148 open / close buff config matrix"
L["help 09"] = "  /cp verbose            \226\128\148 toggle confirmation messages on/off"
L["help 10"] = "  Mousewheel on class row \226\128\148 cycle the active spell"
