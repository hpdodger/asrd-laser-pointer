# Guide: Modularizing ASRD Challenges

## Problem

Each stock challenge has its own `Update()`, `OnGameplayStart()`, `OnGameEvent_*()` functions and global variables. Naively combining two files with `IncludeScript` breaks the first one — Squirrel overwrites all identically-named functions.

Secondary problem: each challenge may have a `convars` section in its `.txt` file. Combining challenges can create convar conflicts.

---

## Solution: file-triggered registration

Each module file ends with `::RegisterModule(m)` — one call that wires everything up.
The dispatcher only lists files; no manual hook wiring per module.

```
combine_registry.nut     module registry + Dispatch/DispatchEvent/ApplyConvars
module_*.nut             logic for one challenge; file ends with ::RegisterModule(m)
challenge_<name>.nut     dispatcher: IncludeScript + universal hooks
```

In TypeScript terms, each module implements this interface:

```typescript
interface IChallengeModule {
    name:      string;
    enabled:   boolean;
    convars:   { [cvar: string]: string };
    variables?: { [key: string]: string | number };  // tunable parameters
    requires_registry?: number;  // warn loudly when combined with an older combine_registry.nut

    OnGameplayStart?(): void;
    Update?(): void;
    Cleanup?(): void;
    OnEnable?(): void;       // called by chat_admin on !cc_enable
    OnDisable?(): void;      // called on !cc_disable — clean up visible side effects here
    OnVariableChanged?(name: string, value: any): null | false | any;
                             // !cc_set validation: null = accept, false = reject,
                             // anything else = corrected value that gets stored
    OnGameEvent_weapon_fire?(params: any): void;
    // ... any other OnGameEvent_*
}
```

Module state lives **inside the table** (`this._field`) — no globals for internal state. Tunable parameters go in `variables`; private state uses `_`-prefixed slots.

> **VScript limitation:** top-level `local` variables in a script file are NOT captured as upvalues by closures inside table literals. All data a method needs must be reachable via `this.*` or via a global.

---

## Comparison with the Challenge Creator Tool pattern

The Creator Tool generates a `challenge_allinone.nut` dispatcher + individual `.nut` files per module. The pattern works but does not scale well when combining many modules.

**Creator Tool module (`onehp.nut`):**
```squirrel
// State — top-level globals, must be uniquely prefixed
::OneHpCurrHPList   <- {}
::OneHpCurrMaxHPList <- {}
::HPRecorddone <- false

// Hooks — global functions, must be uniquely prefixed
::OneHPOnGameplayStart <- function() {
    if (g_StartOneHP) { ... }
}
```

**Creator Tool dispatcher (`challenge_allinone.nut`):**
```squirrel
// ~40 module flags
::g_StartOneHP <- false
::g_startASBI  <- false
// ...

function Update() {
    BackPackUpdate()        // manual call per module
    EscapeTheFogUpdate()
    ASB2Update()
    // ...
    return 0.1
}

function OnGameplayStart() {
    OneHPOnGameplayStart()  // manual call per module
    MemoryOnGameplayStart()
    // ...
}
```

| | Creator Tool | This guide |
|---|---|---|
| Module state | top-level globals (`::g_Foo <- ...`) | table slots (`this._field`) |
| Module hooks | prefixed globals (`::FooOnGameplayStart <- function()`) | table function slots |
| Dispatcher | calls each module explicitly in each hook | `::Dispatch("hookName")` iterates all |
| Adding a module | IncludeScript + flag + call in every hook | one `IncludeScript` line |
| Enable/disable at runtime | flag + custom menu system | `!cc_enable` / `!cc_disable` in chat |
| Convar conflict detection | not supported | automatic via `convars` field |
| Name collision risk | high — all globals must be manually prefixed | none — state is inside tables |

---

## Registry API (combine_registry.nut)

Globals injected into the root table when `combine_registry.nut` is included:

```typescript
declare let g_Modules: IChallengeModule[];

declare let CC_REGISTRY_VERSION: number;

declare function RegisterModule(m: IChallengeModule): void;
declare function Dispatch(hookName: string): void;
declare function DispatchEvent(hookName: string, params: Record<string, any>): void;
declare function ApplyConvars(): void;

declare enum HudPrint { Notify = 1, Console = 2, Talk = 3, Center = 4 }  // ClientPrint destinations
```

`Dispatch`/`DispatchEvent` isolate errors: a module that throws is reported to
the console (`[CC] ERROR in <module>.<hook>: ...`) and skipped for that event —
one broken module cannot silence the rest of the combo. `CC_REGISTRY_VERSION`
plus a module's `requires_registry` turn version drift between copied registry
files into a loud warning instead of silent breakage.

---

## Example structure

```
combine_registry.nut          infrastructure: registry, Dispatch*, ApplyConvars
module_infinite_ammo.nut      example 1: single-file module
module_shot_announcer.nut     example 2: multi-file module (entry point)
shot_announcer_messages.nut   └─ sub-file (local, not global)
module_toxic_atmo.nut         example 3: module with Update and self-throttling
module_chat_admin.nut         built-in module: lobby-leader chat commands
challenge_combiner.nut        dispatcher template: combines all examples
```

---

## Example 1: single-file module

```squirrel
// module_infinite_ammo.nut
local m = {
    name    = "InfiniteAmmo",
    enabled = true,
    convars = {},

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
```

---

## Example 2: multi-file module

The sub-file is included from the entry point — the dispatcher doesn't know it exists.

**Sub-file pattern** — three rules:
1. Sub-file exports data via a **global** (`::SA_messages <- [...]`) — `local` in the sub-file dies after the script returns
2. Entry point assigns that global to a **table slot** (`_messages = null`, then `m._messages = ::SA_messages` after the table literal)
3. Methods access the data via **`this._messages`** — upvalue capture from top-level script locals is unreliable in VScript

```squirrel
// shot_announcer_messages.nut
::SA_messages <- [
    "%s opens fire!",
    "%s pulls the trigger!",
    "%s is back in action!",
    "%s shows no mercy!",
    "%s is laying it down!",
];
```

```squirrel
// module_shot_announcer.nut
IncludeScript("shot_announcer_messages.nut");   // sets ::SA_messages

local m = {
    name      = "ShotAnnouncer",
    enabled   = true,
    convars   = {},
    _msgIndex = 0,
    _messages = null,   // assigned below, before RegisterModule

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
```

---

## Example 3: module with Update and variables

The dispatcher calls `Update()` on all modules every 0.1 s. If a module needs a different frequency it tracks time itself via `_nextUpdate`.

`variables` holds public tunable parameters. The module accesses them via `this.variables.*`. The lobby leader can change them at runtime with `!cc_set` in chat.

```squirrel
// module_toxic_atmo.nut
local m = {
    name      = "ToxicAtmo",
    enabled   = true,
    convars   = {},

    variables = {
        damage   = 5,   // HP removed per tick
        interval = 3.0, // seconds between ticks
    },

    _nextUpdate = 0.0,  // private state — not a variable

    function Update() {
        if (Time() < this._nextUpdate) return;
        this._nextUpdate = Time() + this.variables.interval;

        local marine = null;
        while ((marine = Entities.FindByClassname(marine, "asw_marine")) != null) {
            local hp = marine.GetHealth();
            if (hp > 1) marine.SetHealth(hp - this.variables.damage);
        }
    },

    function Cleanup() { this._nextUpdate = 0.0; },
};
::RegisterModule(m);
```

`::Dispatch("Update")` is **our** function from `combine_registry.nut`, not a built-in VScript method. The engine calls `function Update()` at the root of the challenge file; that calls `::Dispatch("Update")`, which iterates `g_Modules`.

---

## Dispatcher

Shape the ASRD engine expects from a challenge script's root scope:

```typescript
interface IChallenge {
    OnGameplayStart?(): void;
    Update?(): number;                                          // return = next call interval, seconds
    OnGameEvent_weapon_fire?(params: Record<string, any>): void;
    OnGameEvent_player_say?(params: Record<string, any>): void;
    OnGameEvent_player_fullyjoined?(params: Record<string, any>): void;
    OnGameEvent_mission_success?(params: Record<string, any>): void;
    OnGameEvent_mission_failed?(params: Record<string, any>): void;
    // add OnGameEvent_* for every event any module needs
}
```

```squirrel
// challenge_combiner.nut
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
```

**Adding a module = one `IncludeScript` line.**  
If the new module uses an event not yet in the dispatcher — add one `OnGameEvent_*`. That's a one-time cost.

---

## Standalone challenge from a single module

A module doesn't have to be used in a combo. For standalone use — same pattern, one module `IncludeScript`:

```squirrel
// challenge_toxic_atmo.nut
IncludeScript("combine_registry.nut");
IncludeScript("module_toxic_atmo.nut");

function OnGameplayStart() {
    ::ApplyConvars();
    ::Dispatch("OnGameplayStart");
}

function OnGameEvent_mission_success(params) { ::Dispatch("Cleanup"); }
function OnGameEvent_mission_failed(params)  { ::Dispatch("Cleanup"); }

function Update() { ::Dispatch("Update"); return 0.1; }
```

Only include the `OnGameEvent_*` hooks the module actually uses.

---

## Chat commands (module_chat_admin.nut)

Built-in module for managing other modules at runtime. All commands except `!cc_help` are available to the lobby leader only (detected via `asw_game_resource.m_Leader`). Messages that do not start with `!cc_` are ignored.

| Command | Action |
|---------|--------|
| `!cc_help` | List available commands (everyone) |
| `!cc_challenges` | List all modules with `[ON]`/`[OFF]` status |
| `!cc_enable <name>` | Enable a module |
| `!cc_disable <name>` | Disable a module |
| `!cc_vars <name>` | Show a module's `variables` |
| `!cc_set <name> <var> <value>` | Change a module's variable |
| `!cc_save` | Save all module variables (per leader, this server) |
| `!cc_load` | Re-apply the saved variables |
| `!cc_reset` | Restore defaults and clear the saved file |

Example:
```
!cc_vars ToxicAtmo
  damage = 5
  interval = 3.0

!cc_set ToxicAtmo damage 10
→ [CC] ToxicAtmo.damage = 10
```

Type is preserved: if the variable was a number, the value is converted to `float`.

Settings persist across maps: `!cc_save` writes every module's `variables` to
`save/vscripts/cc/<leader steam id>.txt` on the **server** machine; at gameplay
start the file of the *current* lobby leader is re-applied automatically, and
every value passes the module's `OnVariableChanged` validation. `!cc_reset`
restores compile-time defaults and clears the file. On a listen server the host
is usually the leader, so the settings effectively live with them; on a
dedicated server each leader gets their own file on that server.

Remove from the dispatcher if not needed — delete the `IncludeScript("module_chat_admin.nut")` line.

---

## Convars

Convars from the `convars` section of the `.txt` file must be duplicated in the module's `convars` field — otherwise the system can't detect conflicts when combining:

```squirrel
convars = {
    ["asw_marine_death_protection"] = "0",
    ["asw_marine_ff_absorption"]    = "0",
},
```

On conflict the system prints to chat and console:

```
[CC] convar conflict: "asw_marine_death_protection"
        — ModuleA wants 0, ModuleB wants 1 (keeping 0)
```

The module whose `IncludeScript` comes first in the dispatcher wins.

---

## Writing a new module

1. Create `module_<name>.nut` (plus sub-files if needed)
2. All state goes in table slots (`this._field`), not globals
3. Sub-files declare `local` variables captured as upvalues by closures
4. Call `::RegisterModule(m)` at the end of the file
5. In the dispatcher: add `IncludeScript("module_<name>.nut")` + any new `OnGameEvent_*`

## Converting an existing challenge to a module

1. Create `module_<name>.nut`
2. Move logic into the table: `function Update()` → `Update` slot in the table
3. Move global state into table slots: `g_hud` → `this._hud`
4. Fill `convars` from the `.txt` file
5. Turn the original `challenge_<name>.nut` into a standalone wrapper (see above)

---

## Naming convention

| What | Format | Example |
|------|--------|---------|
| Module file | `module_<name>.nut` | `module_toxic_atmo.nut` |
| Sub-file | `<name>_<subname>.nut` | `shot_announcer_messages.nut` |
| Tunable parameters | `variables.field` | `variables.damage`, `variables.interval` |
| Private state | `_field` | `_msgIndex`, `_nextUpdate` |
| Private helper functions | `_methodName` | `_printHelp`, `_ensureBeam` |
| Module-local constants | `_UPPER_SNAKE` slots | `_PREFIX`, `_CMD_SET`, `_MODE_BEAM` |
| Engine/registry contract names | as required (PascalCase) | `OnGameplayStart`, `Update`, `Cleanup`, `RegisterModule` |
| Dispatcher | `challenge_<name>.nut` | `challenge_combiner.nut` |

Repeated tokens, mode strings and print destinations never appear as raw
literals at call sites: tokens live in `_UPPER_SNAKE` slots (or a command table
that also carries help text and access rules), print destinations come from the
shared `HudPrint` enum in `combine_registry.nut`. One-off message strings stay
inline — extract on the second use.
