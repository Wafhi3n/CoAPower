-- CoaPower_Data.lua
-- Class + spell configuration — edit this file to add classes or change spells.
-- Loaded before CoaPower.lua by the TOC.
--
-- Each entry is just the exact spell name as it appears in the spellbook.
-- CoaPower will automatically find the highest rank the player knows.

COAPOWER_CLASS_DATA = {

    -- ── Ascension custom classes ─────────────────────────────────────────────
    SUNCLERIC = {
        "Devotion of Dawn",
        "Devotion of Grace",
        "Devotion of Radiance",
    },
    RANGER = {
        "Woodsman's Adaptation",
    },
    -- ── Standard classes ─────────────────────────────────────────────────────
    DRUID = {
        "Mark of the Wild",
        "Gift of the Wild",
    },

    PRIEST = {
        "Power Word: Fortitude",
        "Prayer of Fortitude",
    },

    MAGE = {
        "Arcane Intellect",
        "Arcane Brilliance",
    },

    PALADIN = {
        "Blessing of Might",
        "Greater Blessing of Might",
    },

    SHAMAN = {
        "Strength of Earth Totem",
        "Flametongue Totem",
    },

    WARRIOR     = {},
    HUNTER      = {},
    ROGUE       = {},
    WARLOCK     = {},
    DEATHKNIGHT = {},
}
