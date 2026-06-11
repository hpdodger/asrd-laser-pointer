// combine_registry.nut
// Module registry and universal hook dispatch.
//
// Include only from the dispatcher file, once.
// Modules do not include this file themselves — they expect it to be already loaded.
//
// API:
//   ::RegisterModule(m)         — called from module_*.nut on load
//   ::Dispatch("HookName")      — call a no-arg hook on all enabled modules
//   ::DispatchEvent("HookName", p) — call an event hook on all enabled modules
//   ::ApplyConvars()            — apply convars, print conflict warnings

::g_Modules         <- [];
::g_ConvarRegistry  <- {};
::g_ConvarConflicts <- [];

// Register a module. Convars from m.convars are added to the registry automatically.
// Each module_*.nut calls this once at the end of the file.
::RegisterModule <- function(m) {
    ::g_Modules.append(m);
    foreach (cvar, val in m.convars)
        ::_ConvarAdd(m.name, cvar, val.tostring());
};

// Call a no-arg hook on every enabled module that defines it.
::Dispatch <- function(hookName) {
    foreach (m in ::g_Modules) {
        if (m.enabled && hookName in m) m[hookName]();
    }
};

// Call an event hook on every enabled module that defines it.
::DispatchEvent <- function(hookName, params) {
    foreach (m in ::g_Modules) {
        if (m.enabled && hookName in m) m[hookName](params);
    }
};

// Apply all registered convars. Print conflict warnings to chat and console.
// Call from the dispatcher's OnGameplayStart — before ::Dispatch("OnGameplayStart").
// Registry is cleared after applying so map restarts work correctly.
::ApplyConvars <- function() {
    foreach (msg in ::g_ConvarConflicts) {
        Say(null, msg);
        ClientPrint(null, 3, msg);
    }
    foreach (cvar, entry in ::g_ConvarRegistry) {
        Convars.SetValue(cvar, entry.value.tofloat());
    }
    ::g_ConvarRegistry  = {};
    ::g_ConvarConflicts = [];
};

// Internal: add one convar to the registry and check for conflicts.
::_ConvarAdd <- function(moduleName, cvar, valStr) {
    if (cvar in ::g_ConvarRegistry) {
        local e = ::g_ConvarRegistry[cvar];
        if (e.value != valStr)
            ::g_ConvarConflicts.append(
                "[CC] convar conflict: \"" + cvar + "\"" +
                " — " + e.module + " wants " + e.value +
                ", " + moduleName + " wants " + valStr +
                " (keeping " + e.value + ")"
            );
    } else {
        ::g_ConvarRegistry[cvar] <- { module = moduleName, value = valStr };
    }
};
