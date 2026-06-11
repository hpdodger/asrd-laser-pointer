// module_toxic_atmo.nut
// Example 3: module with Update and configurable variables.
//
// Effect: every interval seconds deals damage HP to all marines.
// Parameters are tunable at runtime via !cc_set in chat (see module_chat_admin.nut).

local m = {
    name      = "ToxicAtmo",
    enabled   = true,
    convars = {
        ["asw_marine_death_protection"] = "1",  // conflict with InfiniteAmmo (wants "0") — for testing
        ["asw_marine_ff_absorption"]    = "0",  // same as InfiniteAmmo — no conflict
    },

    variables = {
        damage   = 5,   // HP removed per tick
        interval = 3.0, // seconds between ticks
    },

    _nextUpdate = 0.0,  // private — not a configurable variable

    function Update() {
        if (Time() < this._nextUpdate) return;
        this._nextUpdate = Time() + this.variables.interval;

        local marine = null;
        while ((marine = Entities.FindByClassname(marine, "asw_marine")) != null) {
            local hp = marine.GetHealth();
            if (hp > 1) marine.SetHealth(hp - this.variables.damage);
        }
    },

    function Cleanup() {
        this._nextUpdate = 0.0;
    },
};

::RegisterModule(m);
