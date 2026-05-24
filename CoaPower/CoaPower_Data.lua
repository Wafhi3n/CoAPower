-- SunBuff_Data.lua
-- Class + spell configuration — edit this file to add classes or change spells.
-- Loaded before SunBuff.lua by the TOC.
--
-- Fields per entry:
--   id   : spell ID used for icon lookup via GetSpellInfo(id)
--           → set to 0 if unknown, falls back to name-based lookup
--   name : spell name matched against UnitBuff() — must be exact

COAPOWER_CLASS_DATA = {

    -- ── Ascension custom classes ─────────────────────────────────────────────
    SUNCLERIC = {
        { id = 0, name = "Devotion of Dawn"     },
        { id = 0, name = "Devotion of Grace"    },
        { id = 0, name = "Devotion of Radiance" },
    },

    -- ── Standard classes ─────────────────────────────────────────────────────
    DRUID = {
        { id = 1126,  name = "Mark of the Wild" },
        { id = 21849, name = "Gift of the Wild"  },
    },

    PRIEST = {
        { id = 1243,  name = "Power Word: Fortitude" },
        { id = 21562, name = "Prayer of Fortitude"   },
    },

    MAGE = {
        { id = 1459,  name = "Arcane Intellect"  },
        { id = 23028, name = "Arcane Brilliance"  },
    },

    PALADIN = {
        { id = 19740, name = "Blessing of Might"  },
        { id = 25291, name = "Greater Blessing of Might"  },
    },

    SHAMAN = {
        { id = 8076,  name = "Strength of Earth Totem" },
        { id = 8827,  name = "Flametongue Totem"       },
    },

    WARRIOR = {},
    HUNTER  = {},
    ROGUE   = {},
    WARLOCK = {},
    DEATHKNIGHT = {},
}
