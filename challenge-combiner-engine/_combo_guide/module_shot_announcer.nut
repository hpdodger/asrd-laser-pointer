// module_shot_announcer.nut
// Example 2: multi-file module (entry point + sub-file).
//
// Effect: every shot prints a message to public chat with the marine's name.
//
// Sub-file pattern:
//   1. Sub-file exports data via a global (::SA_messages).
//   2. Entry point assigns that global to a table slot before calling RegisterModule.
//   3. Methods access the data via this._messages — upvalue capture is unreliable in VScript.

IncludeScript("shot_announcer_messages.nut");   // sets ::SA_messages

local m = {
    name      = "ShotAnnouncer",
    enabled   = true,
    convars   = {},
    _msgIndex = 0,
    _messages = null,   // assigned from ::SA_messages below, before RegisterModule

    function _pick(name) {
        local t = this._messages[this._msgIndex % this._messages.len()];
        this._msgIndex++;
        return format(t, name);
    },

    function OnGameplayStart() {
        this._msgIndex = 0;
    },

    function OnGameEvent_weapon_fire(params) {
        local marine = EntIndexToHScript(params["marine"]);
        if (!marine || !marine.IsValid()) return;
        Say(null, this._pick(marine.GetMarineName()));
    },

    function Cleanup() {
        this._msgIndex = 0;
    },
};

m._messages = ::SA_messages;
::RegisterModule(m);
