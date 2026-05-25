-- CoaPower_frFR.lua
-- French (frFR) locale overrides.

if GetLocale() ~= "frFR" then return end

local L = CoaPowerL

-- ── Config window ─────────────────────────────────────────────────────────────
L["CoaPower Config"]       = "Configuration CoaPower"
L["Multi-class buff tracker"] = "Gestionnaire de buffs multi-classe"
L["Spell"]                 = "Sort"
L["Class"]                 = "Classe"
L["Options"]               = "Options"
L["Lock frame position"]   = "Verrouiller la position"
L["Range-only (hide out-of-range classes)"] = "Port\195\169e uniquement (masquer hors port\195\169e)"
L["Verbose output"]        = "Messages d\195\169taill\195\169s"
-- L["(slot %d)"] stays the same
-- L["(off)"] stays the same

-- ── Not active message ────────────────────────────────────────────────────────
L["not active panel"] = "CoaPower n'est pas actif pour votre classe.\n"
    .. "Ajoutez votre classe dans |cffFFD700CoaPower_Data.lua|r pour l'activer."

-- ── Tooltips ──────────────────────────────────────────────────────────────────
L["Buff Config"]           = "Config des buffs"
L["TT open IO"]            = "Ouvre Interface \226\134\146 AddOns \226\134\146 CoaPower"
L["Next: %s"]              = "Suivant\194\160: %s"
L["Expires in: %dm %ds"]   = "Expire dans\194\160: %dm %ds"
L["Everyone buffed!"]      = "Tout le monde est buff\195\169\194\160!"
L["TT mousewheel"]         = "|cffaaaaaa(Molette pour changer le sort actif)|r"

-- ── Class row / UI ────────────────────────────────────────────────────────────
L["all on"]                = "|cff00ff00tous activ\195\169s|r"
L["all off"]               = "|cffff6666tous d\195\169sactiv\195\169s|r"

-- ── Combat lock ───────────────────────────────────────────────────────────────
L["no config in combat"]   = "impossible de changer la config en combat."

-- ── Slash command messages ────────────────────────────────────────────────────
L["not active for class"]  = "non actif pour la classe '%s'. Utilisez /cp addspell <nom>."
L["frame locked"]          = "position |cffff9900verrouill\195\169e|r"
L["frame unlocked"]        = "position |cff00ff00d\195\169verrouill\195\169e|r"
L["range hidden"]          = "classes hors port\195\169e |cff00ff00masqu\195\169es|r"
L["range greyed"]          = "classes hors port\195\169e |cffffff00gris\195\169es|r"
L["usage addspell"]        = "usage\194\160: /cp addspell <nom du sort>"
L["already tracked"]       = "'%s' d\195\169j\195\160 suivi."
L["now tracking"]          = "suivi de '%s'"
L["usage removespell"]     = "usage\194\160: /cp removespell <1|2|3>"
L["removed spell"]         = "'%s' supprim\195\169"
L["no spell at index"]     = "aucun sort personnalis\195\169 \195\160 l'indice %d"
L["no spells tracked"]     = "aucun sort suivi pour %s"
L["use addspell hint"]     = "  Utilisez /cp addspell <nom> pour configurer."
L["tracking for"]          = "suivi pour %s\194\160:"
L["reset done"]            = "toutes les assignations remises par d\195\169faut."
L["not active short"]      = "non actif."
L["verbose on"]            = "messages |cff00ff00activ\195\169s|r"
L["verbose off"]           = "messages |cffff6666d\195\169sactiv\195\169s|r"

-- ── Help text ─────────────────────────────────────────────────────────────────
L["help 01"] = "  /cp                    \226\128\148 afficher/masquer la fen\195\170tre"
L["help 02"] = "  /cp lock               \226\128\148 verrouiller / d\195\169verrouiller la position"
L["help 03"] = "  /cp range              \226\128\148 masquer ou griser les classes hors de port\195\169e"
L["help 04"] = "  /cp addspell <nom>     \226\128\148 ajouter un sort de buff"
L["help 05"] = "  /cp removespell <N>    \226\128\148 supprimer un sort par indice"
L["help 06"] = "  /cp spells             \226\128\148 lister les sorts suivis"
L["help 07"] = "  /cp reset              \226\128\148 r\195\169initialiser les assignations"
L["help 08"] = "  /cp config             \226\128\148 ouvrir / fermer la matrice de config"
L["help 09"] = "  /cp verbose            \226\128\148 activer/d\195\169sactiver les messages"
L["help 10"] = "  Molette sur la rang\195\169e de classe \226\128\148 changer le sort actif"

-- ── Spell names (spellbook returns French names on frFR client) ──────────────
-- Verify these names in-game with /script print(GetSpellInfo(N)) if unsure.
COAPOWER_CLASS_DATA.DRUID = {
    "Marque des fauves",
    "Don de la nature sauvage",
}
COAPOWER_CLASS_DATA.PRIEST = {
    "Mot de pouvoir\194\160: Vigueur",
    "Pri\195\168re de vigueur",
}
COAPOWER_CLASS_DATA.MAGE = {
    "Intellect des arcanes",
    "Brillance des arcanes",
}
COAPOWER_CLASS_DATA.PALADIN = {
    "B\195\169n\195\169diction de puissance",
    "Grande b\195\169n\195\169diction de puissance",
}
COAPOWER_CLASS_DATA.SHAMAN = {
    "Totem de force de la Terre",
    "Totem langue de feu",
}
-- SUNCLERIC / RANGER : noms de sorts Ascension, probablement toujours en anglais
-- COAPOWER_CLASS_DATA.SUNCLERIC = { "Devotion of Dawn", ... }  -- laisser tel quel
