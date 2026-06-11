// module_asbi.nut
// ASBI difficulty pack for advanced players. Disabled by default — the lobby
// leader turns it on with !cc_enable ASBI and off with !cc_disable ASBI
// (the state survives map changes when saved with !cc_save).
//
// Replication of the official ASBI challenge: the convar set from
// resource/challenges/asbi.txt plus scripts/vscripts/challenge_asbi.nut,
// including the skill-dependent block. asw_skill is read at the moment of
// enabling — re-enable ASBI after changing the difficulty.
// One deliberate deviation: rd_auto_kick_low_level_player is NOT included.
//
// The registry `convars` field is intentionally EMPTY: registry convars are
// applied at gameplay start regardless of the enabled flag. This module
// applies its set itself (snapshotting the previous values) and restores it
// on disable / mission end. Per the engine contract, enable side effects are
// applied in OnGameplayStart when the flag is already set (silent auto-load);
// OnEnable/OnDisable cover runtime transitions.

local m = {
    name        = "ASBI",
    enabled     = false,     // opt-in: advanced players only
    convars     = {},        // intentionally empty — see the header
    description = "Official ASBI difficulty preset: harder spawns, real friendly fire, tougher aliens (no low-level autokick).",
    requires_registry = 2,   // uses the OnEnable/OnDisable lifecycle hooks

    // resource/challenges/asbi.txt + the unconditional part of challenge_asbi.nut
    // (without rd_auto_kick_low_level_player — deliberately excluded)
    _BASE = {
        ["asw_horde_override"]                         = "1",
        ["asw_wanderer_override"]                      = "1",
        ["rd_ready_mark_override"]                     = "1",
        ["asw_sentry_friendly_fire_scale"]             = "1",
        ["asw_marine_ff_absorption"]                   = "0",
        ["asw_adjust_difficulty_by_number_of_marines"] = "0",
        ["asw_batch_interval"]                         = "3",
        ["rd_stuck_bot_teleport"]                      = "0",
        ["asw_realistic_death_chatter"]                = "1",
        ["asw_marine_ff"]                              = "2",
        ["asw_marine_ff_dmg_base"]                     = "3",
        ["asw_custom_skill_points"]                    = "0",
        ["asw_marine_death_cam_slowdown"]              = "0",
        ["asw_marine_death_protection"]                = "0",
        ["asw_marine_collision"]                       = "1",
        ["asw_difficulty_alien_health_step"]           = "0.2",
        ["asw_difficulty_alien_damage_step"]           = "0.2",
        ["asw_marine_time_until_ignite"]               = "0",
        ["rd_marine_ignite_immediately"]               = "1",
        ["asw_marine_burn_time_easy"]                  = "60",
        ["asw_marine_burn_time_normal"]                = "60",
        ["asw_marine_burn_time_hard"]                  = "60",
        ["asw_marine_burn_time_insane"]                = "60",
    },

    // the skill-dependent part of challenge_asbi.nut (asw_skill 1..5)
    _BY_SKILL = {
        [1] = {   // easy
            ["asw_marine_speed_scale_easy"]   = "0.96",
            ["asw_alien_speed_scale_easy"]    = "0.7",
            ["asw_drone_acceleration"]        = "5",
            ["asw_horde_interval_min"]        = "10",
            ["asw_horde_interval_max"]        = "30",
            ["asw_director_peak_min_time"]    = "2",
            ["asw_director_peak_max_time"]    = "4",
            ["asw_director_relaxed_min_time"] = "15",
            ["asw_director_relaxed_max_time"] = "30",
        },
        [2] = {   // normal
            ["asw_marine_speed_scale_normal"] = "1.0",
            ["asw_alien_speed_scale_normal"]  = "1.0",
            ["asw_drone_acceleration"]        = "5",
            ["asw_horde_interval_min"]        = "15",
            ["asw_horde_interval_max"]        = "60",
            ["asw_director_peak_min_time"]    = "2",
            ["asw_director_peak_max_time"]    = "4",
            ["asw_director_relaxed_min_time"] = "15",
            ["asw_director_relaxed_max_time"] = "30",
        },
        [3] = {   // hard
            ["asw_marine_speed_scale_hard"]   = "1.024",
            ["asw_alien_speed_scale_hard"]    = "1.7",
            ["asw_drone_acceleration"]        = "8",
            ["asw_horde_interval_min"]        = "15",
            ["asw_horde_interval_max"]        = "120",
            ["asw_director_peak_min_time"]    = "2",
            ["asw_director_peak_max_time"]    = "4",
            ["asw_director_relaxed_min_time"] = "15",
            ["asw_director_relaxed_max_time"] = "30",
        },
        [4] = {   // insane
            ["asw_marine_speed_scale_insane"] = "1.048",
            ["asw_alien_speed_scale_insane"]  = "1.8",
            ["asw_drone_acceleration"]        = "9",
            ["asw_horde_interval_min"]        = "15",
            ["asw_horde_interval_max"]        = "80",
            ["asw_director_peak_min_time"]    = "2",
            ["asw_director_peak_max_time"]    = "4",
            ["asw_director_relaxed_min_time"] = "15",
            ["asw_director_relaxed_max_time"] = "30",
        },
        [5] = {   // brutal
            ["asw_marine_speed_scale_insane"] = "1.048",
            ["asw_alien_speed_scale_insane"]  = "1.9",
            ["asw_drone_acceleration"]        = "10",
            ["asw_horde_interval_min"]        = "15",
            ["asw_horde_interval_max"]        = "60",
            ["asw_director_peak_min_time"]    = "2",
            ["asw_director_peak_max_time"]    = "4",
            ["asw_director_relaxed_min_time"] = "10",
            ["asw_director_relaxed_max_time"] = "30",
        },
    },

    _saved = null,   // convar -> value before we touched it (for restore)

    // ---------- convar plumbing ----------

    function _snapshotAndSet(set) {
        foreach (cvar, val in set) {
            if (!(cvar in this._saved)) {
                local cur = Convars.GetStr(cvar);
                if (cur != null) this._saved[cvar] <- cur;
            }
            Convars.SetValueString(cvar, val);
        }
    },

    function _apply() {
        if (this._saved == null) this._saved = {};

        local skill = Convars.GetFloat("asw_skill");
        local skillSet = null;
        if (skill != null && (skill.tointeger() in this._BY_SKILL))
            skillSet = this._BY_SKILL[skill.tointeger()];

        this._snapshotAndSet(this._BASE);
        if (skillSet != null) this._snapshotAndSet(skillSet);

        printl("[CC] ASBI convars applied"
            + (skillSet != null ? " (skill " + skill.tointeger() + ")" : ""));
    },

    function _restore() {
        if (this._saved == null) return;
        foreach (cvar, val in this._saved)
            Convars.SetValueString(cvar, val);
        this._saved = null;
        printl("[CC] ASBI convars restored");
    },

    // ---------- hooks ----------

    function OnEnable()  { this._apply();   },
    function OnDisable() { this._restore(); },

    function OnGameplayStart() {
        this._saved = null;              // fresh map — the old snapshot is meaningless
        if (this.enabled) this._apply(); // flag may be pre-set by the silent auto-load
    },

    function Cleanup() {
        this._restore();   // mission over — leave the server with clean values
    },
};

::RegisterModule(m);
