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
//   ::CC_DeclareVariables(m, [[name, default, help], ...]) — single-source tunables
//   enum HudPrint               — ClientPrint destination codes (use HudPrint.Talk)

// Shared constants for every module. This file is included exactly once and
// first, so a single definition is visible to all modules compiled after it.
// ClientPrint destinations (Source HUD_PRINT* values):
enum HudPrint {
    Notify  = 1,   // top-left notify area
    Console = 2,   // console only
    Talk    = 3,   // chat
    Center  = 4    // center of the screen
}

// Copies of this file have no other version control: bump on incompatible
// changes so that combining a new module with an old registry warns loudly
// instead of breaking silently.
// v2: HudPrint enum, error isolation, lifecycle/validation hooks
// v3: CC_DeclareVariables (single-source tunables: default + help + order)
::CC_REGISTRY_VERSION <- 3;

::g_Modules         <- [];
::g_ConvarRegistry  <- {};
::g_ConvarConflicts <- [];

// Register a module. Convars from m.convars are added to the registry automatically.
// Each module_*.nut calls this once at the end of the file.
// A module may declare `requires_registry = N` to demand at least registry vN.
::RegisterModule <- function(m) {
    if (("requires_registry" in m) && m.requires_registry > ::CC_REGISTRY_VERSION) {
        local msg = "[CC] WARNING: module " + m.name + " requires registry v"
            + m.requires_registry + ", this is v" + ::CC_REGISTRY_VERSION
            + " - update combine_registry.nut";
        printl(msg);
        ClientPrint(null, HudPrint.Talk, msg);
    }
    ::g_Modules.append(m);
    foreach (cvar, val in m.convars)
        ::_ConvarAdd(m.name, cvar, val.tostring());
};

// Call a no-arg hook on every enabled module that defines it. A module that
// throws is reported and skipped — it must not silence the rest of the combo.
::Dispatch <- function(hookName) {
    foreach (m in ::g_Modules) {
        if (!m.enabled || !(hookName in m)) continue;
        try {
            m[hookName]();
        } catch (e) {
            printl("[CC] ERROR in " + m.name + "." + hookName + ": " + e);
        }
    }
};

// Same, for hooks that take a single params argument.
::DispatchEvent <- function(hookName, params) {
    foreach (m in ::g_Modules) {
        if (!m.enabled || !(hookName in m)) continue;
        try {
            m[hookName](params);
        } catch (e) {
            printl("[CC] ERROR in " + m.name + "." + hookName + ": " + e);
        }
    }
};

// Apply all registered convars. Print conflict warnings to chat and console.
// Call from the dispatcher's OnGameplayStart — before ::Dispatch("OnGameplayStart").
// Registry is cleared after applying so map restarts work correctly.
::ApplyConvars <- function() {
    foreach (msg in ::g_ConvarConflicts) {
        Say(null, msg);
        ClientPrint(null, HudPrint.Talk, msg);
    }
    foreach (cvar, entry in ::g_ConvarRegistry) {
        // The convar system parses the string itself — works for string convars
        // too (SetValue + tofloat() silently turned those into 0).
        Convars.SetValueString(cvar, entry.value);
    }
    ::g_ConvarRegistry  = {};
    ::g_ConvarConflicts = [];
};

// Declare a module's tunables from one list of [name, default, help] entries.
// Fills m.variables (plain name -> value, read by module code as before) plus
// m.variables_help and m.variables_order, which !cc_vars uses to print each
// variable with its description in the declared order. A plain
// `variables = {...}` literal still works — just without descriptions.
::CC_DeclareVariables <- function(m, decls) {
    m.variables       <- {};
    m.variables_help  <- {};
    m.variables_order <- [];
    foreach (d in decls) {
        m.variables[d[0]]      <- d[1];
        m.variables_help[d[0]] <- d[2];
        m.variables_order.append(d[0]);
    }
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
