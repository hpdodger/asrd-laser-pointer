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
IncludeScript("laser_pointer/module_laser_pointer.nut");
IncludeScript("laser_pointer/module_asbi.nut");   // difficulty pack, off by default (!cc_enable ASBI)

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

// Engine hook signature is (player, value); the registry dispatches a single
// params argument, so wrap both into a table. Used by module_laser_pointer
// (scripted_user_func laser / laser_on / laser_off).
function UserConsoleCommand(hPlayer, szValue) {
    ::DispatchEvent("UserConsoleCommand", { player = hPlayer, value = szValue });
}

function Update() {
    ::Dispatch("Update");
    return 0.05;   // 20 Hz for the laser pointer; modules self-throttle via variables.interval
}
