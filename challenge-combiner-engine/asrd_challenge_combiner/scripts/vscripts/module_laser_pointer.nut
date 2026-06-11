// module_laser_pointer.nut
// DRG-style laser pointer: a beam from your marine to your crosshair, visible
// to every player, plus a "mark" pulse + chat info when you fire while active.
//
// Activation:
//   chat:    laser  (or !laser)                 — toggle
//   console: scripted_user_func laser           — toggle without chat spam (bindable)
//            scripted_user_func laser_on / laser_off — for hold-style +/- aliases
//
// Render modes (variables.mode):
//   "beam" (default) — world-space env_beam tracking two marker entities;
//                      rendered by the engine, works even for clients that do
//                      NOT have the challenge files installed
//   "hud"            — screen-space line drawn by laser_pointer_hud.nut;
//                      requires the challenge files on EVERY client
//
// rd_hud_vscript slot contract (MUST match laser_pointer_hud.nut):
//   SetEntity(0) = source marker          SetInt(0) = active
//   SetEntity(1) = endpoint marker        SetInt(1) = color index 0..7
//   SetEntity(2) = mark pulse anchor      SetInt(2) = draw line (0 in beam mode)
//   SetEntity(3) = owner player           SetFloat(0) = mark Time(), SetFloat(1) = mark duration

local m = {
    name    = "LaserPointer",
    enabled = true,
    convars = {},

    variables = {
        mode           = "beam", // "beam" — engine-rendered, works for everyone; "hud" — needs files on every client
        interval       = 0.05,   // update period, seconds
        src_height     = 45,     // beam source z-offset above marine origin (45 = weapon, 60 = head)
        mark_radius    = 64,     // search radius for naming the marked target
        mark_cooldown  = 1.0,    // seconds between marks per player
        mark_duration  = 1.2,    // mark pulse/flash length, seconds
        mark_particles = 0,      // 1 = also spawn particle burst (invisible on some maps)
        beam_width     = 1.5,
        beam_alpha     = 220,
    },

    // Engine assets, always shipped with the game (see asw_ammo.cpp / asw_tesla_trap.cpp)
    _MARKER_MODEL = "models/swarm/ammo/ammoassaultrifle.mdl",
    _FLASH_SPRITE = "sprites/glow01.vmt",

    // keep in sync with SLOT_COLORS in laser_pointer_hud.nut
    _COLORS = ["255 50 50", "0 220 255", "50 255 50", "255 220 0",
               "255 140 0", "255 50 255", "220 220 220", "160 50 255"],

    _players    = {},               // hPlayer -> state table (see _NewState)
    _slotOwner  = array(8, null),   // slot -> hPlayer; keeps per-player colors stable
    _nextUpdate = 0.0,

    // ---------- per-player state ----------

    // rd_hud_vscript as a world marker: FL_EDICT_ALWAYS (networked to every
    // client; info_target without a model is not — that sank the old version).
    // Beam endpoints additionally get an invisible model: an entity WITH a model
    // is not a "static point" (beam_shared.cpp IsStaticPointEntity), so a
    // persistent env_beam tracks its position client-side every frame.
    function _Marker(targetname, bBeamEndpoint) {
        local e = Entities.CreateByClassname("rd_hud_vscript");
        if (targetname != null)
            e.__KeyValueFromString("targetname", targetname);
        if (bBeamEndpoint) {
            e.__KeyValueFromInt("rendermode", 10);   // kRenderNone — the model is never drawn
            e.__KeyValueFromInt("effects", 272);     // EF_NOSHADOW | EF_NORECEIVESHADOW
        }
        e.Spawn();
        e.Activate();
        if (bBeamEndpoint)
            e.SetModel(this._MARKER_MODEL);
        return e;
    },

    function _NewState(hPlayer, slot) {
        local u = UniqueString();
        local srcName = "lp_src_" + slot + u;
        local dstName = "lp_dst_" + slot + u;

        local src   = this._Marker(srcName, true);
        local dst   = this._Marker(dstName, true);
        local pulse = this._Marker(null, false);

        // Engine-rendered mark flash — visible even to clients without the files.
        // Named + no StartOn spawnflag = spawns hidden (Sprite.cpp).
        local flash = Entities.CreateByClassname("env_sprite");
        flash.__KeyValueFromString("targetname", "lp_flash_" + slot + u);
        flash.__KeyValueFromString("model", this._FLASH_SPRITE);
        flash.__KeyValueFromString("rendercolor", this._COLORS[slot]);
        flash.__KeyValueFromInt("renderamt", 255);
        flash.__KeyValueFromInt("rendermode", 9);    // world-space glow
        flash.__KeyValueFromFloat("scale", 0.4);
        flash.Spawn();
        flash.Activate();

        local hud = Entities.CreateByClassname("rd_hud_vscript");
        hud.__KeyValueFromString("client_vscript", "laser_pointer_hud.nut");
        hud.Spawn();
        hud.Activate();
        hud.SetEntity(0, src);
        hud.SetEntity(1, dst);
        hud.SetEntity(2, pulse);
        hud.SetEntity(3, hPlayer);
        hud.SetInt(0, 0);
        hud.SetInt(1, slot);
        hud.SetInt(2, 1);
        hud.SetFloat(0, 0.0);
        hud.SetFloat(1, 0.0);

        return {
            slot = slot, active = false,
            hud = hud, src = src, dst = dst, pulse = pulse, flash = flash,
            beam = null, beamOn = false,
            srcName = srcName, dstName = dstName,
            lastMark = -999.0, lastEnd = null,
        };
    },

    function _GetState(hPlayer) {
        if (hPlayer in this._players) {
            local st = this._players[hPlayer];
            if (st.hud.IsValid() && st.src.IsValid() && st.dst.IsValid()
                && st.pulse.IsValid() && st.flash.IsValid())
                return st;
            // stale handles (mission restarted) — rebuild, keep slot and active flag
            return this._RebuildState(hPlayer, st);
        }
        local slot = -1;
        for (local i = 0; i < this._slotOwner.len(); i++) {
            local owner = this._slotOwner[i];
            if (owner == null || !owner.IsValid()) { slot = i; break; }
        }
        if (slot < 0) return null;
        this._slotOwner[slot] = hPlayer;
        local st = this._NewState(hPlayer, slot);
        this._players[hPlayer] <- st;
        return st;
    },

    function _RebuildState(hPlayer, stOld) {
        this._DestroyState(stOld);
        local st = this._NewState(hPlayer, stOld.slot);
        st.active = stOld.active;
        this._slotOwner[stOld.slot] = hPlayer;
        this._players[hPlayer] <- st;
        return st;
    },

    function _DestroyState(st) {
        foreach (k in ["hud", "src", "dst", "pulse", "flash", "beam"]) {
            if (st[k] != null && st[k].IsValid()) st[k].Destroy();
            st[k] = null;
        }
        local owner = this._slotOwner[st.slot];
        if (owner == null || !owner.IsValid()) this._slotOwner[st.slot] = null;
    },

    // ---------- env_beam (world-space mode) ----------

    // Persistent server-side env_beam (life = 0). Both endpoints are entities
    // WITH models, so the beam is networked once and every client tracks the
    // marker positions frame-by-frame over the reliable entity channel — no
    // per-tick temp entities (those get dropped on lossy connections).
    // TurnOn/TurnOff only toggle EF_NODRAW; the endpoint binding is kept.
    function _EnsureBeam(st) {
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

    function _BeamOff(st) {
        if (st.beam != null && st.beam.IsValid() && st.beamOn)
            DoEntFire("!self", "TurnOff", "", 0, null, st.beam);
        st.beamOn = false;
    },

    // ---------- activation ----------

    function _SetActive(hPlayer, on, announce) {
        local st = this._GetState(hPlayer);
        if (st == null) { ClientPrint(hPlayer, 3, "[LP] No free laser slots."); return; }
        if (st.active == on) return;
        st.active = on;
        if (!on) {
            if (st.hud.IsValid()) st.hud.SetInt(0, 0);
            this._BeamOff(st);
        }
        if (announce)
            ClientPrint(null, 3, "[LP] " + hPlayer.GetPlayerName() + ": laser "
                + (on ? "ON" : "OFF") + " (" + this.variables.mode + ")");
    },

    function _Toggle(hPlayer, announce) {
        local st = this._GetState(hPlayer);
        if (st == null) { ClientPrint(hPlayer, 3, "[LP] No free laser slots."); return; }
        this._SetActive(hPlayer, !st.active, announce);
    },

    // ---------- hooks ----------

    function OnGameplayStart() {
        this.Cleanup();   // fresh round: drop stale handles, free all slots
        PrecacheModel(this._MARKER_MODEL);
        PrecacheModel(this._FLASH_SPRITE);
    },

    function OnGameEvent_player_say(params) {
        if (!("text" in params)) return;
        local t = params["text"].tolower();
        if (t != "laser" && t != "!laser") return;
        local hPlayer = GetPlayerFromUserID(params["userid"]);
        if (hPlayer == null || !hPlayer.IsValid()) return;
        this._Toggle(hPlayer, true);
    },

    // From the dispatcher: scripted_user_func <token> lands here (and so does
    // menuselect, which the engine forwards too) — match tokens exactly.
    // params = { player = hPlayer, value = szValue }
    function UserConsoleCommand(params) {
        local hPlayer = params.player;
        if (hPlayer == null || !hPlayer.IsValid()) return;
        local v = params.value.tolower();
        if      (v == "laser")     this._Toggle(hPlayer, true);
        else if (v == "laser_on")  this._SetActive(hPlayer, true, false);
        else if (v == "laser_off") this._SetActive(hPlayer, false, false);
    },

    function OnGameEvent_weapon_fire(params) {
        if (!("userid" in params)) return;
        local hPlayer = GetPlayerFromUserID(params["userid"]);
        if (hPlayer == null || !hPlayer.IsValid()) return;
        if (!(hPlayer in this._players)) return;
        local st = this._players[hPlayer];
        if (!st.active || !st.hud.IsValid() || !st.pulse.IsValid() || !st.flash.IsValid()) return;

        local hMarine = hPlayer.GetMarine();
        if (hMarine == null || !hMarine.IsValid()) return;
        if (("marine" in params) && params["marine"] != hMarine.entindex()) return;

        if (Time() - st.lastMark < this.variables.mark_cooldown) return;
        st.lastMark = Time();
        this._DoMark(hPlayer, hMarine, st);
    },

    // ---------- mark ----------

    function _DoMark(hPlayer, hMarine, st) {
        local pos = (st.lastEnd != null) ? st.lastEnd : hPlayer.GetCrosshairTracePos();

        // pulse: anchor entity + timestamp contract (client animates by Time())
        st.pulse.SetOrigin(pos);
        st.hud.SetFloat(1, this.variables.mark_duration.tofloat());
        st.hud.SetFloat(0, Time());

        // engine-rendered glow flash — visible to clients without the files too
        st.flash.SetOrigin(pos);
        DoEntFire("!self", "ShowSprite", "", 0, null, st.flash);
        DoEntFire("!self", "HideSprite", "", this.variables.mark_duration.tofloat(), null, st.flash);

        local what = this._DescribeTarget(pos);
        local d = pos - hMarine.GetOrigin();
        local dist = sqrt(d.x * d.x + d.y * d.y + d.z * d.z).tointeger();
        ClientPrint(null, 3, "[LP] " + hPlayer.GetPlayerName() + " marks " + what
            + " (" + dist + " units)");

        if (this.variables.mark_particles != 0) this._ParticleBurst(pos);
    },

    function _DescribeTarget(pos) {
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
        if (best.GetClassname() == "asw_marine") return best.GetMarineName();
        return best.GetClassname();
    },

    // Legacy world-space burst. Off by default: these particle systems are not
    // loaded on every map (the HUD pulse always works, this is a bonus).
    function _ParticleBurst(pos) {
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

        local beamMode = (this.variables.mode.tolower() == "beam");
        local toRemove = [];
        local toHeal = [];

        foreach (hPlayer, st in this._players) {
            if (!hPlayer.IsValid()) { toRemove.append(hPlayer); continue; }
            if (!st.active) continue;

            if (!st.hud.IsValid() || !st.src.IsValid() || !st.dst.IsValid() || !st.pulse.IsValid()) {
                toHeal.append(hPlayer);   // a restart killed our entities mid-round
                continue;
            }

            local hMarine = hPlayer.GetMarine();
            if (hMarine == null || !hMarine.IsValid()) {
                st.hud.SetInt(0, 0);      // hidden while dead; auto-resumes on respawn
                this._BeamOff(st);
                continue;
            }

            local srcPos = hMarine.GetOrigin() + Vector(0, 0, this.variables.src_height.tofloat());
            local dstPos = hPlayer.GetCrosshairTracePos();

            // Clip at the first wall. Trace from the visual source, not the feet,
            // otherwise the floor clips the beam.
            local frac = TraceLine(srcPos, dstPos, hMarine);
            if (frac < 1.0) dstPos = srcPos + (dstPos - srcPos) * frac;
            st.lastEnd = dstPos;

            st.src.SetOrigin(srcPos);
            st.dst.SetOrigin(dstPos);
            st.hud.SetInt(1, st.slot);
            st.hud.SetInt(2, beamMode ? 0 : 1);
            st.hud.SetInt(0, 1);

            if (beamMode) {
                local b = this._EnsureBeam(st);
                if (!st.beamOn) {
                    DoEntFire("!self", "TurnOn", "", 0, null, b);
                    st.beamOn = true;
                }
            } else {
                this._BeamOff(st);
            }
        }

        foreach (p in toHeal) this._RebuildState(p, this._players[p]);
        foreach (p in toRemove) {
            this._DestroyState(this._players[p]);
            this._players.rawdelete(p);
        }
    },

    function Cleanup() {
        foreach (hPlayer, st in this._players) this._DestroyState(st);
        this._players = {};
        this._slotOwner = array(8, null);
        this._nextUpdate = 0.0;
    },
};

::RegisterModule(m);
