// Laser Pointer — standalone challenge dispatcher (combo format).
// Loaded by the engine via: rd_challenge laser_pointer

IncludeScript("combine_registry.nut");
IncludeScript("module_chat_admin.nut");      // chat commands: !cc_help / !cc_vars / !cc_set
IncludeScript("module_laser_pointer.nut");

function OnGameplayStart() {
    ::ApplyConvars();
    ::Dispatch("OnGameplayStart");
}

function OnGameEvent_player_say(params)  { ::DispatchEvent("OnGameEvent_player_say", params); }
function OnGameEvent_weapon_fire(params) { ::DispatchEvent("OnGameEvent_weapon_fire", params); }
function OnGameEvent_mission_success(params) { ::Dispatch("Cleanup"); }
function OnGameEvent_mission_failed(params)  { ::Dispatch("Cleanup"); }

// Engine hook signature is (player, value); the registry dispatches a single
// params argument, so wrap both into a table.
function UserConsoleCommand(hPlayer, szValue) {
    ::DispatchEvent("UserConsoleCommand", { player = hPlayer, value = szValue });
}

// 20 Hz so the laser endpoint follows the cursor smoothly;
// modules self-throttle via their own variables.interval.
function Update() {
    ::Dispatch("Update");
    return 0.05;
}
