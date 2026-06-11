// challenge_combiner.nut
// Dispatcher template for combining multiple modules into one challenge.
// Copy this file and replace the IncludeScript list with the modules you need.
//
// To add a module: one IncludeScript line + a new OnGameEvent_* if required.
// To remove a module: delete its IncludeScript line.

IncludeScript("combine_registry.nut");
IncludeScript("module_chat_admin.nut");       // lobby-leader chat commands; remove if not needed
IncludeScript("module_infinite_ammo.nut");
IncludeScript("module_shot_announcer.nut");
IncludeScript("module_toxic_atmo.nut");

function OnGameplayStart() {
    ::ApplyConvars();
    ::Dispatch("OnGameplayStart");
}

// List every event that at least one module may need.
// Dispatch/DispatchEvent check internally which modules have the hook.
function OnGameEvent_weapon_fire(params)        { ::DispatchEvent("OnGameEvent_weapon_fire", params); }
function OnGameEvent_player_say(params)         { ::DispatchEvent("OnGameEvent_player_say", params); }
function OnGameEvent_player_fullyjoined(params) { ::DispatchEvent("OnGameEvent_player_fullyjoined", params); }
function OnGameEvent_mission_success(params)    { ::Dispatch("Cleanup"); }
function OnGameEvent_mission_failed(params)     { ::Dispatch("Cleanup"); }

function Update() {
    ::Dispatch("Update");
    return 0.1;
}
