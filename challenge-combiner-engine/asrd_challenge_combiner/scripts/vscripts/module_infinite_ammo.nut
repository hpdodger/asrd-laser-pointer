// module_infinite_ammo.nut
// Example 1: single-file module.
//
// Effect: after every shot the weapon clip is refilled to its maximum.
//
// Structure: one file, no sub-files, no HUD.
// The module self-registers via RegisterModule() on load.

local m = {
    name    = "InfiniteAmmo",
    enabled = true,

    convars = {
        ["asw_marine_death_protection"] = "0",  // conflict with ToxicAtmo (wants "1") — for testing
        ["asw_marine_ff_absorption"]    = "0",  // same as ToxicAtmo — no conflict
    },

    function OnGameplayStart() {},

    function OnGameEvent_weapon_fire(params) {
        local weapon = EntIndexToHScript(params["weapon"]);
        if (!weapon || !weapon.IsValid()) return;
        local maxClip = weapon.GetMaxClip1();
        if (maxClip > 0) weapon.SetClip1(maxClip);
    },

    function Cleanup() {},
};

::RegisterModule(m);
