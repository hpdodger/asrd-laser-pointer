# Laser Pointer — a challenge for Alien Swarm: Reactive Drop

A Deep Rock Galactic style laser pointer: a player switches it on and **everyone**
in the lobby sees a beam going from their marine to their crosshair. The beam
stops on enemies and teammates, not just walls. Firing while the pointer is
active "marks" the target: a glow flash plays at the spot and a chat message
reports what was marked and how far away it is. Everything is rendered by the
engine — other players do not need any files.

Built on top of **challenge-combiner-engine** (vendored in
[`challenge-combiner-engine/`](challenge-combiner-engine/)) — a modular framework
for ASRD challenges where each challenge is a self-contained module that can run
standalone or be combined with other modules by a shared dispatcher. All laser
pointer logic is a single combo module, `module_laser_pointer.nut`, that plugs
unchanged into both the standalone dispatcher and the challenge combiner.

## Installation

1. Copy the contents of `src/` (the `resource/` and `scripts/` folders) into
   `<game>/reactivedrop/`
   (typically `C:\Program Files (x86)\Steam\steamapps\common\Alien Swarm Reactive Drop\reactivedrop`).
2. In the console before loading a map: `rd_challenge laser_pointer`
   (or pick the "Laser Pointer" challenge in the lobby settings).

## Controls

| Action | How |
|---|---|
| Toggle on/off | type `laser` (or `!laser`) in chat |
| Same, without chat spam | `scripted_user_func laser` in console; handy as `bind v "scripted_user_func laser"` |
| Hold mode (shines while the key is held) | `alias +lp "scripted_user_func laser_on"`<br>`alias -lp "scripted_user_func laser_off"`<br>`bind MOUSE4 "+lp"` |
| Mark a target | fire while the pointer is active (default; turn off with `mark_on_fire 0`) |
| Mark without firing | `bind MOUSE5 "scripted_user_func laser_mark"` |
| Full DRG gesture (hold = beam, release = mark, no shot) | `alias +lpm "scripted_user_func laser_on"`<br>`alias -lpm "scripted_user_func laser_mark; scripted_user_func laser_off"`<br>`bind MOUSE4 "+lpm"` |

`scripted_user_func` is a stock engine command (added to RD in December 2017):
the client forwards it to the server, and the challenge receives the
`UserConsoleCommand(player, value)` hook. Only the first word is passed through.

## Runtime tuning (via chat)

```
!cc_help                               — list commands (available to everyone)
!cc_challenges                         — list modules
!cc_vars LaserPointer                  — current parameters
!cc_set LaserPointer interval 0.1      — update rate
!cc_set LaserPointer mark_particles 1  — extra particle burst on mark
!cc_set LaserPointer mark_on_fire 0    — firing no longer marks (use laser_mark)
!cc_save                               — persist current settings (auto-applied while you lead)
```

All commands except `!cc_help` are lobby leader only. Engine replies are prefixed
with `[CC]` (Challenge Combiner), laser pointer messages with `[LP]`. Saved
settings survive map changes: they are stored per lobby leader on the server
(`!cc_reset` restores defaults).

| Parameter | Default | What it does |
|---|---|---|
| `interval` | `0.05` | update period, seconds |
| `src_height` | `45` | beam source height (45 ≈ weapon, 60 ≈ head) |
| `mark_radius` | `64` | fallback search radius for naming the marked target (used when the ray hit the world) |
| `mark_cooldown` | `1.0` | minimum time between marks, seconds |
| `mark_duration` | `1.2` | mark flash duration, seconds |
| `mark_particles` | `0` | `1` — also spawn particles at the mark (invisible on some maps) |
| `mark_on_fire` | `1` | `1` — firing while active marks the target; `0` — only `laser_mark` does |
| `idle_ttl` | `60` | seconds before an inactive player's laser entities are freed (0 = keep) |
| `beam_width` | `1.5` | env_beam width |
| `beam_alpha` | `220` | env_beam opacity |

Pointer colors are assigned automatically per player slot (8 colors, stable for
the duration of the mission).

## Multiplayer

Only the host (the player whose game runs the server) needs the challenge
installed. The beam, the mark flash and the chat messages are rendered and sent
by the engine itself, so everyone else sees everything without installing
anything.

## Repository layout

```
src/                                       the challenge itself (copy into the game folder)
  resource/challenges/laser_pointer.txt    challenge manifest (no convars)
  scripts/vscripts/
    challenge_laser_pointer.nut            standalone dispatcher (combo format)
    module_laser_pointer.nut               all logic (combo module)
    combine_registry.nut                   engine copy — do not edit
    module_chat_admin.nut                  engine copy (!cc_help / !cc_vars / !cc_set) — do not edit
challenge-combiner-engine/                 the framework this challenge is based on
  _combo_guide/                            module format guide + example modules
  asrd_challenge_combiner/                 reference combiner challenge (laser module already wired in)
```

### Using it in the Challenge Combiner

Adding the module to a combiner dispatcher takes one
`IncludeScript("module_laser_pointer.nut");` line plus a `UserConsoleCommand`
wrapper — see
`challenge-combiner-engine/asrd_challenge_combiner/scripts/vscripts/challenge_challenge_combiner.nut`,
where it is already done. `module_laser_pointer.nut` must sit next to the other
modules in `scripts/vscripts/`.

## How it works

- **Position markers** are `rd_hud_vscript` entities: they have
  `FL_EDICT_ALWAYS`, so they are always networked to every client. A modelless
  `info_target` is not reliably networked — an earlier prototype sank on exactly
  that. Both beam endpoints additionally carry an invisible model
  (`rendermode` none): an entity with a model is not a "static point" for
  `env_beam`, so the engine tracks its position instead of baking it.
- **The beam**: one persistent server-side `env_beam` per player (`life = 0`)
  bound to the two tracked markers. The beam is networked once like any entity;
  every client then follows the marker positions frame-by-frame over the
  reliable entity channel. No temp entities, nothing created or destroyed per
  tick — toggling just fires `TurnOn`/`TurnOff`.
- **Mark flash**: a persistent hidden `env_sprite` (`sprites/glow01.vmt`, glow
  render mode, slot color) per player; a mark moves it to the spot and fires
  `ShowSprite`/`HideSprite`. Engine-rendered, so everyone sees it.
- Every `interval` seconds the server takes the player's
  `GetCrosshairTracePos()` and runs `ScriptTraceLineTable` from the marine's
  upper body (default mask `MASK_VISIBLE_AND_NPCS`): the beam clips on walls,
  aliens and marines alike, and the hit entity is remembered — a mark names it
  in chat (`GetMarineName()` for marines, classname otherwise).
- After `idle_ttl` seconds of inactivity a player's laser entities are freed;
  the color slot is kept and everything is rebuilt transparently on the next
  toggle.

## Engine notes from development

Things the early prototypes got wrong — kept here because they are useful to
anyone scripting ASRD:

1. **Invisible HUD beam**: the server script set only `SetEntity(0)` while the
   client script waited for an endpoint in `GetEntity(1)` and silently bailed
   out of `Paint()`. Lesson: a server/client slot contract must be
   single-sourced. (The HUD render path was later removed entirely — the engine
   renders everything.)
2. **Entity churn**: recreating 2×`info_target` + `env_beam` twenty times per
   second per player is replaced by a single persistent `env_beam` whose
   endpoints the engine tracks by itself.
3. **Temp entities are lossy**: an intermediate version re-struck the beam every
   tick via `StrikeOnce`, which broadcasts unreliable temp-entity messages —
   remote players saw the beam flicker on any packet loss while the listen host
   saw it perfectly. Entity-tracked beams use the reliable channel instead.
4. **Map-dependent particles**: `jumpjet_glow`/`explosion_sparks` are not loaded
   on every map, so the mark visual is an engine-rendered `env_sprite` glow
   flash (works everywhere); particles remain as the `mark_particles` option.
5. **Template junk convars** (`rd_techreq`, `rd_hackall`, etc.) were removed from
   the manifest; the challenge changes no gameplay convars at all.
6. **Key binding**: instead of an unimplementable MOUSE3 detection plan, the
   stock `scripted_user_func` command provides a silent toggle and a hold mode
   via `+`/`-` aliases.

## Known limitations

- A few `late precache` console warnings (beam sprite, marker model, glow
  sprite) on challenge start / first activation are normal.
- The engine also forwards `menuselect N` into `UserConsoleCommand` — the
  handler only reacts to the exact tokens `laser` / `laser_on` / `laser_off` /
  `laser_mark`.
- The physical left mouse button cannot be repurposed for marking: intercepting
  the attack before the shot would require engine (C++) changes, which this
  challenge deliberately avoids. `laser_mark` on any other key is the closest
  VScript equivalent of the DRG pointer click.
