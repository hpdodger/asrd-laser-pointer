// module_laser_pointer.nut
// DRG-style laser pointer: an engine-rendered beam from your marine to your
// crosshair, visible to every player — other clients need NO files. The beam
// stops on enemies and teammates, not just walls. Firing while the pointer is
// active "marks" the target: a glow flash at the spot plus a chat message with
// the target's name and distance.
//
// Activation:
//   chat:    laser  (or !laser)                 — toggle
//   console: scripted_user_func laser           — toggle without chat spam (bindable)
//            scripted_user_func laser_on / laser_off — for hold-style +/- aliases
//
// Rendering (all engine-side, no client scripts):
//   beam — persistent server-side env_beam between two tracked marker entities
//   mark — env_sprite glow flash

local m = {
    name    = "LaserPointer",
    enabled = true,
    convars = {},
    requires_registry = 2,   // uses HudPrint and the lifecycle/validation hooks

    variables = {
        interval       = 0.05,   // update period, seconds
        src_height     = 45,     // beam source z-offset above marine origin (45 = weapon, 60 = head)
        mark_radius    = 64,     // fallback search radius for naming the marked target
        mark_cooldown  = 1.0,    // seconds between marks per player
        mark_duration  = 1.2,    // mark flash length, seconds
        mark_particles = 0,      // 1 = also spawn particle burst (invisible on some maps)
        mark_on_fire   = 1,      // 1 = firing while active marks; 0 = only the laser_mark token marks
        idle_ttl       = 60,     // seconds before an inactive player's entities are freed (0 = keep)
        beam_width     = 1.5,
        beam_alpha     = 220,
    },

    // activation tokens (chat + scripted_user_func)
    _TOK_TOGGLE = "laser",
    _TOK_ON     = "laser_on",
    _TOK_OFF    = "laser_off",
    _TOK_MARK   = "laser_mark",   // mark without firing; in a -release alias put it BEFORE laser_off

    _PREFIX = "[LP] ",

    // Engine assets, always shipped with the game (see asw_ammo.cpp / asw_tesla_trap.cpp)
    _MARKER_MODEL = "models/swarm/ammo/ammoassaultrifle.mdl",
    _FLASH_SPRITE = "sprites/glow01.vmt",

    _COLORS = ["255 50 50", "0 220 255", "50 255 50", "255 220 0",
               "255 140 0", "255 50 255", "220 220 220", "160 50 255"],

    _players    = {},               // hPlayer -> state table (see _newState)
    _slotOwner  = array(8, null),   // slot -> hPlayer; keeps per-player colors stable
    _nextUpdate = 0.0,
    _trace      = {},               // reusable table for ScriptTraceLineTable (no per-tick allocs)
    _VEC_ZERO   = Vector(0, 0, 0),  // mins = maxs = zero => line trace

    // ---------- messaging ----------

    function _msg(hPlayer, text) {
        ClientPrint(hPlayer, HudPrint.Talk, this._PREFIX + text);
    },

    function _broadcast(text) {
        ClientPrint(null, HudPrint.Talk, this._PREFIX + text);
    },

    function _noSlots(hPlayer) {
        this._msg(hPlayer, "No free laser slots.");
    },

    // ---------- per-player state ----------

    // rd_hud_vscript as a beam endpoint marker: FL_EDICT_ALWAYS (networked to
    // every client; a modelless info_target is not — that sank an early
    // version), plus an invisible model: an entity WITH a model is not a
    // "static point" (beam_shared.cpp IsStaticPointEntity), so the persistent
    // env_beam tracks its position client-side every frame.
    function _marker(targetname) {
        local e = Entities.CreateByClassname("rd_hud_vscript");
        e.__KeyValueFromString("targetname", targetname);
        e.__KeyValueFromInt("rendermode", 10);   // kRenderNone — the model is never drawn
        e.__KeyValueFromInt("effects", 272);     // EF_NOSHADOW | EF_NORECEIVESHADOW
        e.Spawn();
        e.Activate();
        e.SetModel(this._MARKER_MODEL);
        return e;
    },

    function _newState(hPlayer, slot) {
        local u = UniqueString();
        local srcName = "lp_src_" + slot + u;
        local dstName = "lp_dst_" + slot + u;

        local src = this._marker(srcName);
        local dst = this._marker(dstName);

        // Engine-rendered mark flash. Named + no StartOn spawnflag = spawns
        // hidden (Sprite.cpp); ShowSprite/HideSprite toggle it.
        local flash = Entities.CreateByClassname("env_sprite");
        flash.__KeyValueFromString("targetname", "lp_flash_" + slot + u);
        flash.__KeyValueFromString("model", this._FLASH_SPRITE);
        flash.__KeyValueFromString("rendercolor", this._COLORS[slot]);
        flash.__KeyValueFromInt("renderamt", 255);
        flash.__KeyValueFromInt("rendermode", 9);    // world-space glow
        flash.__KeyValueFromFloat("scale", 0.4);
        flash.Spawn();
        flash.Activate();

        return {
            slot = slot, active = false,
            src = src, dst = dst, flash = flash,
            beam = null, beamOn = false,
            srcName = srcName, dstName = dstName,
            lastMark = -999.0, lastEnd = null, lastHit = null,
            lastActive = Time(),
        };
    },

    function _entsValid(st) {
        return st.src != null && st.src.IsValid()
            && st.dst != null && st.dst.IsValid()
            && st.flash != null && st.flash.IsValid();
    },

    function _getState(hPlayer) {
        if (hPlayer in this._players) {
            local st = this._players[hPlayer];
            if (this._entsValid(st))
                return st;
            // entities gone (mission restart or idle cleanup) — rebuild, keep
            // the slot (stable color) and the active flag
            return this._rebuildState(hPlayer, st);
        }
        local slot = -1;
        for (local i = 0; i < this._slotOwner.len(); i++) {
            local owner = this._slotOwner[i];
            if (owner == null || !owner.IsValid()) { slot = i; break; }
        }
        if (slot < 0) return null;
        this._slotOwner[slot] = hPlayer;
        local st = this._newState(hPlayer, slot);
        this._players[hPlayer] <- st;
        return st;
    },

    function _rebuildState(hPlayer, stOld) {
        this._destroyState(stOld);
        local st = this._newState(hPlayer, stOld.slot);
        st.active = stOld.active;
        this._slotOwner[stOld.slot] = hPlayer;
        this._players[hPlayer] <- st;
        return st;
    },

    function _destroyState(st) {
        foreach (k in ["src", "dst", "flash", "beam"]) {
            if (st[k] != null && st[k].IsValid()) st[k].Destroy();
            st[k] = null;
        }
        st.beamOn = false;
        local owner = this._slotOwner[st.slot];
        if (owner == null || !owner.IsValid()) this._slotOwner[st.slot] = null;
    },

    // ---------- env_beam ----------

    // Persistent server-side env_beam (life = 0). Both endpoints are entities
    // WITH models, so the beam is networked once and every client tracks the
    // marker positions frame-by-frame over the reliable entity channel — no
    // per-tick temp entities (those get dropped on lossy connections).
    // TurnOn/TurnOff only toggle EF_NODRAW; the endpoint binding is kept.
    function _ensureBeam(st) {
        if (st.beam != null && st.beam.IsValid()) return st.beam;
        local b = Entities.CreateByClassname("env_beam");
        b.__KeyValueFromString("targetname", "lp_beam_" + st.slot + UniqueString());
        b.__KeyValueFromString("LightningStart", st.srcName);
        b.__KeyValueFromString("LightningEnd", st.dstName);
        b.__KeyValueFromString("texture", "sprites/laserbeam.vmt");
        b.__KeyValueFromString("life", "0");                 // permanent, server-side
        b.__KeyValueFromFloat("BoltWidth", this.variables.beam_width.tofloat());
        b.__KeyValueFromString("rendercolor", this._COLORS[st.slot]);
        b.__KeyValueFromInt("renderamt", this.variables.beam_alpha.tointeger());
        b.__KeyValueFromFloat("NoiseAmplitude", 0.0);
        b.__KeyValueFromInt("TextureScroll", 0);
        b.__KeyValueFromString("spawnflags", "1");           // StartOn
        b.Spawn();
        b.Activate();    // binds the (modeled => tracked) endpoint entities here
        st.beam = b;
        st.beamOn = true;
        return b;
    },

    function _beamOff(st) {
        if (st.beam != null && st.beam.IsValid() && st.beamOn)
            DoEntFire("!self", "TurnOff", "", 0, null, st.beam);
        st.beamOn = false;
    },

    // ---------- activation ----------

    function _setActive(hPlayer, on, announce) {
        local st = this._getState(hPlayer);
        if (st == null) { this._noSlots(hPlayer); return; }
        if (st.active == on) return;
        st.active = on;
        if (on) st.lastActive = Time();
        else this._beamOff(st);
        if (announce)
            this._broadcast(hPlayer.GetPlayerName() + ": laser " + (on ? "ON" : "OFF"));
    },

    function _toggle(hPlayer, announce) {
        local st = this._getState(hPlayer);
        if (st == null) { this._noSlots(hPlayer); return; }
        this._setActive(hPlayer, !st.active, announce);
    },

    // ---------- hooks ----------

    function OnGameplayStart() {
        this.Cleanup();   // fresh round: drop stale handles, free all slots
        PrecacheModel(this._MARKER_MODEL);
        PrecacheModel(this._FLASH_SPRITE);
    },

    // chat_admin calls this on !cc_disable: hide everything we own. Active
    // flags are kept, so !cc_enable resumes the lasers on the next Update.
    function OnDisable() {
        foreach (hPlayer, st in this._players)
            this._beamOff(st);
    },

    // !cc_set validation: null = accept, false = reject, else corrected value.
    function OnVariableChanged(name, value) {
        if (name == "interval" && value < 0.02) return 0.02;
        if (name == "idle_ttl" && value < 0)    return 0;
    },

    function OnGameEvent_player_say(params) {
        if (!("text" in params)) return;
        local t = params["text"].tolower();
        if (t != this._TOK_TOGGLE && t != "!" + this._TOK_TOGGLE) return;
        local hPlayer = GetPlayerFromUserID(params["userid"]);
        if (hPlayer == null || !hPlayer.IsValid()) return;
        this._toggle(hPlayer, true);
    },

    // From the dispatcher: scripted_user_func <token> lands here (and so does
    // menuselect, which the engine forwards too) — match tokens exactly.
    // params = { player = hPlayer, value = szValue }
    function UserConsoleCommand(params) {
        local hPlayer = params.player;
        if (hPlayer == null || !hPlayer.IsValid()) return;
        local v = params.value.tolower();
        if      (v == this._TOK_TOGGLE) this._toggle(hPlayer, true);
        else if (v == this._TOK_ON)     this._setActive(hPlayer, true, false);
        else if (v == this._TOK_OFF)    this._setActive(hPlayer, false, false);
        else if (v == this._TOK_MARK)   this._tryMark(hPlayer);
    },

    function OnGameEvent_weapon_fire(params) {
        if (this.variables.mark_on_fire == 0) return;
        if (!("userid" in params)) return;
        local hPlayer = GetPlayerFromUserID(params["userid"]);
        if (hPlayer == null || !hPlayer.IsValid()) return;

        // only shots from the marine this player controls
        local hMarine = hPlayer.GetMarine();
        if (hMarine == null || !hMarine.IsValid()) return;
        if (("marine" in params) && params["marine"] != hMarine.entindex()) return;

        this._tryMark(hPlayer);
    },

    // ---------- mark ----------

    // Shared by the weapon_fire path and the laser_mark token: requires an
    // active pointer and a living marine, rate-limited by mark_cooldown.
    function _tryMark(hPlayer) {
        if (!(hPlayer in this._players)) return;
        local st = this._players[hPlayer];
        if (!st.active || st.flash == null || !st.flash.IsValid()) return;

        local hMarine = hPlayer.GetMarine();
        if (hMarine == null || !hMarine.IsValid()) return;

        if (Time() - st.lastMark < this.variables.mark_cooldown) return;
        st.lastMark = Time();
        this._doMark(hPlayer, hMarine, st);
    },

    function _doMark(hPlayer, hMarine, st) {
        local pos = (st.lastEnd != null) ? st.lastEnd : hPlayer.GetCrosshairTracePos();

        // engine-rendered glow flash — everyone sees it, no client files needed
        st.flash.SetOrigin(pos);
        DoEntFire("!self", "ShowSprite", "", 0, null, st.flash);
        DoEntFire("!self", "HideSprite", "", this.variables.mark_duration.tofloat(), null, st.flash);

        // the beam trace already told us what we are pointing at
        local what;
        if (st.lastHit != null && st.lastHit.IsValid()) what = this._describeEntity(st.lastHit);
        else what = this._describeTarget(pos);

        local d = pos - hMarine.GetOrigin();
        local dist = sqrt(d.x * d.x + d.y * d.y + d.z * d.z).tointeger();
        this._broadcast(hPlayer.GetPlayerName() + " marks " + what + " (" + dist + " units)");

        if (this.variables.mark_particles != 0) this._particleBurst(pos);
    },

    function _describeEntity(e) {
        if (e.GetClassname() == "asw_marine") return e.GetMarineName();
        return e.GetClassname();
    },

    // Fallback for when the ray hit the world: name the nearest notable entity
    // around the endpoint (corpses, items and other non-solid things the trace
    // cannot hit).
    function _describeTarget(pos) {
        local radius = this.variables.mark_radius.tofloat();
        local best = null;
        local bestDistSq = radius * radius;
        local e = null;
        while ((e = Entities.FindInSphere(e, pos, radius)) != null) {
            if (!e.IsValid()) continue;
            local cls = e.GetClassname();
            if (cls == "rd_hud_vscript" || cls == "env_beam" || cls == "player"
                || cls == "worldspawn"
                || cls.find("info_") == 0 || cls.find("trigger_") == 0
                || cls.find("func_") == 0 || cls.find("env_") == 0) continue;
            local dd = e.GetOrigin() - pos;
            local distSq = dd.x * dd.x + dd.y * dd.y + dd.z * dd.z;
            if (distSq < bestDistSq) { best = e; bestDistSq = distSq; }
        }
        if (best == null) return "a position";
        return this._describeEntity(best);
    },

    // Legacy world-space burst. Off by default: these particle systems are not
    // loaded on every map (the glow flash always works, this is a bonus).
    function _particleBurst(pos) {
        foreach (eff in ["jumpjet_glow", "explosion_sparks"]) {
            local p = Entities.CreateByClassname("info_particle_system");
            p.__KeyValueFromString("effect_name", eff);
            p.__KeyValueFromString("start_active", "1");
            p.SetOrigin(pos);
            p.Spawn();
            p.Activate();
            DoEntFire("!self", "Kill", "", 2.0, null, p);
        }
    },

    // ---------- update loop ----------

    function Update() {
        if (Time() < this._nextUpdate) return;
        this._nextUpdate = Time() + this.variables.interval;

        local toRemove = [];
        local toHeal = [];

        foreach (hPlayer, st in this._players) {
            if (!hPlayer.IsValid()) { toRemove.append(hPlayer); continue; }

            if (!st.active) {
                // free this player's edicts after idle_ttl seconds; the slot and
                // the entry stay, so the color survives reactivation
                if (st.src != null && this.variables.idle_ttl > 0
                    && Time() - st.lastActive > this.variables.idle_ttl)
                    this._destroyState(st);
                continue;
            }
            st.lastActive = Time();

            if (!this._entsValid(st)) {
                toHeal.append(hPlayer);   // a restart killed our entities mid-round
                continue;
            }

            local hMarine = hPlayer.GetMarine();
            if (hMarine == null || !hMarine.IsValid()) {
                this._beamOff(st);        // hidden while dead; auto-resumes on respawn
                continue;
            }

            local srcPos = hMarine.GetOrigin() + Vector(0, 0, this.variables.src_height.tofloat());
            local dstPos = hPlayer.GetCrosshairTracePos();

            // Clip against world AND characters (default mask is
            // MASK_VISIBLE_AND_NPCS): the beam stops on aliens and marines like
            // the DRG pointer, and the hit entity names the mark target.
            local t = this._trace;
            t.ignore <- hMarine;
            ScriptTraceLineTable(t, srcPos, dstPos, this._VEC_ZERO, this._VEC_ZERO);
            dstPos = t.pos;
            local hit = t.enthit;
            st.lastHit = (hit != null && hit.IsValid() && hit.GetClassname() != "worldspawn") ? hit : null;
            st.lastEnd = dstPos;

            st.src.SetOrigin(srcPos);
            st.dst.SetOrigin(dstPos);

            local b = this._ensureBeam(st);
            if (!st.beamOn) {
                DoEntFire("!self", "TurnOn", "", 0, null, b);
                st.beamOn = true;
            }
        }

        foreach (p in toHeal) this._rebuildState(p, this._players[p]);
        foreach (p in toRemove) {
            this._destroyState(this._players[p]);
            this._players.rawdelete(p);
        }
    },

    function Cleanup() {
        foreach (hPlayer, st in this._players) this._destroyState(st);
        this._players = {};
        this._slotOwner = array(8, null);
        this._nextUpdate = 0.0;
    },
};

::RegisterModule(m);
