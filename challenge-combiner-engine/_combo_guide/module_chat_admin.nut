// module_chat_admin.nut
// Chat commands for managing modules at runtime. Prefix: !cc_ (Challenge Combiner).
//
// Single source of truth: the _CMDS table (bottom of the file) defines every
// command token, its arguments, its help line and its access level. The parser,
// the !cc_help output and the usage hints are all generated from it — no token
// and no slice length is ever retyped.
//
// Settings persistence: !cc_save writes every module's `variables` to
// save/vscripts/cc/<leader steam id>.txt on the SERVER machine. At gameplay
// start the file of the CURRENT lobby leader is re-applied automatically;
// every value goes through the module's OnVariableChanged validation.
// !cc_reset restores compile-time defaults and clears the saved file.
//
// Everything except !cc_help is lobby leader only.
// Messages that do not start with "!cc_" are ignored (other modules may use
// their own !commands).

local m = {
    name    = "ChatAdmin",
    enabled = true,
    convars = {},

    _PREFIX       = "[CC] ",
    _CMD_PREFIX   = "!cc_",
    _SETTINGS_DIR = "cc/",   // under save/vscripts/ (StringToFile prepends that)

    // Command tokens — referenced everywhere, never retyped.
    _CMD_HELP       = "!cc_help",
    _CMD_CHALLENGES = "!cc_challenges",
    _CMD_ENABLE     = "!cc_enable",
    _CMD_DISABLE    = "!cc_disable",
    _CMD_VARS       = "!cc_vars",
    _CMD_SET        = "!cc_set",
    _CMD_SAVE       = "!cc_save",
    _CMD_LOAD       = "!cc_load",
    _CMD_RESET      = "!cc_reset",

    _CMDS     = null,   // built after the table literal — see the bottom of the file
    _defaults = null,   // moduleName -> { var = defaultValue }, snapshot at gameplay start

    // ---------- messaging ----------

    function _msg(hPlayer, text) {
        ClientPrint(hPlayer, HudPrint.Talk, this._PREFIX + text);
    },

    function _msgRaw(hPlayer, text) {   // continuation lines without the prefix
        ClientPrint(hPlayer, HudPrint.Talk, text);
    },

    function _broadcast(text) {
        Say(null, this._PREFIX + text);
    },

    function _moduleNotFound(hPlayer, name) {
        this._msg(hPlayer, "Module not found: " + name);
    },

    // ---------- lookups ----------

    function _isLobbyLeader(hPlayer) {
        local res = Entities.FindByClassname(null, "asw_game_resource");
        if (!res) return false;
        return hPlayer == NetProps.GetPropEntity(res, "m_Leader");
    },

    function _findModule(name) {
        foreach (mod in ::g_Modules)
            if (mod.name.tolower() == name.tolower()) return mod;
        return null;
    },

    // ---------- parser ----------

    function OnGameEvent_player_say(params) {
        if (!("text" in params)) return;
        local raw  = params["text"];
        local text = raw.tolower();
        if (text.find(this._CMD_PREFIX) != 0) return;   // not our command

        local hPlayer = GetPlayerFromUserID(params["userid"]);
        if (!hPlayer || !hPlayer.IsValid()) return;

        foreach (c in this._CMDS) {
            local n = c.cmd.len();
            local exact   = (text == c.cmd);
            local withArg = (text.len() > n + 1 && text.slice(0, n + 1) == c.cmd + " ");
            if (!exact && !withArg) continue;

            if (c.leader && !this._isLobbyLeader(hPlayer)) {
                this._msg(hPlayer, "Only the lobby leader can manage modules. Type "
                    + this._CMD_HELP + " for the command list.");
                return;
            }
            this[c.fn](hPlayer, withArg ? raw.slice(n + 1) : "");
            return;
        }
        this._printHelp(hPlayer, "");   // unknown !cc_ command
    },

    // ---------- variable plumbing (shared by !cc_set and the settings loader) ----------

    // Coerce valStr by the variable's current type, run the module's optional
    // OnVariableChanged hook (null = accept, false = reject, else corrected
    // value; strict typeof checks so a corrected 0 does not read as false),
    // store on success. Returns null when stored, "notfound" or "rejected".
    function _applyVariable(mod, varName, valStr) {
        if (!("variables" in mod) || !(varName in mod.variables)) return "notfound";
        local current = mod.variables[varName];
        local newVal;
        if (typeof current == "integer" || typeof current == "float") {
            newVal = valStr.tofloat();
        } else {
            newVal = valStr;
        }
        if ("OnVariableChanged" in mod) {
            local r = mod.OnVariableChanged(varName, newVal);
            if (typeof r == "bool" && !r) return "rejected";
            if (r != null && typeof r != "bool") newVal = r;
        }
        mod.variables[varName] = newVal;
        return null;
    },

    // ---------- commands (uniform signature: hPlayer, szArgs) ----------

    function _printHelp(hPlayer, szArgs) {
        this._msg(hPlayer, "Challenge Combiner chat commands:");
        foreach (c in this._CMDS)
            this._msgRaw(hPlayer, "  " + c.cmd + c.args + " - " + c.help);
        this._msgRaw(hPlayer, "  All commands except " + this._CMD_HELP + " are lobby leader only.");
    },

    function _printList(hPlayer, szArgs) {
        this._msg(hPlayer, "Modules:");
        foreach (mod in ::g_Modules) {
            if (mod.name == this.name) continue;
            local status = mod.enabled ? "[ON]" : "[OFF]";
            local hint = ("variables" in mod) ? "  (" + this._CMD_VARS + " " + mod.name + ")" : "";
            this._msgRaw(hPlayer, "  " + status + " " + mod.name + hint);
        }
    },

    function _enable(hPlayer, szArgs)  { this._toggleModule(hPlayer, szArgs, true);  },
    function _disable(hPlayer, szArgs) { this._toggleModule(hPlayer, szArgs, false); },

    function _toggleModule(hPlayer, name, enable) {
        local mod = this._findModule(name);
        if (mod == null) { this._moduleNotFound(hPlayer, name); return; }
        mod.enabled = enable;
        // Lifecycle hooks: Dispatch skips disabled modules, so OnDisable is the
        // module's only chance to clean up visible side effects.
        local hook = enable ? "OnEnable" : "OnDisable";
        if (hook in mod) {
            try {
                mod[hook]();
            } catch (e) {
                printl(this._PREFIX + "ERROR in " + mod.name + "." + hook + ": " + e);
            }
        }
        this._broadcast(mod.name + (enable ? " enabled." : " disabled."));
    },

    function _printVars(hPlayer, szArgs) {
        local mod = this._findModule(szArgs);
        if (mod == null) { this._moduleNotFound(hPlayer, szArgs); return; }
        if (!("variables" in mod)) {
            this._msg(hPlayer, mod.name + " has no variables.");
            return;
        }
        this._msg(hPlayer, mod.name + " variables:");
        foreach (k, v in mod.variables)
            this._msgRaw(hPlayer, "  " + k + " = " + v);
        this._msgRaw(hPlayer, "  " + this._CMD_SET + " " + mod.name + " <var> <value>");
    },

    // szArgs: "<ModuleName> <varName> <value>"
    function _setVar(hPlayer, szArgs) {
        local parts = this._split(szArgs);
        if (parts.len() < 3) {
            this._msg(hPlayer, "Usage: " + this._CMD_SET + " <module> <var> <value>");
            return;
        }
        local mod = this._findModule(parts[0]);
        if (mod == null) { this._moduleNotFound(hPlayer, parts[0]); return; }

        local status = this._applyVariable(mod, parts[1], parts[2]);
        if (status == "notfound") {
            this._msg(hPlayer, "Variable not found: " + parts[1]);
            return;
        }
        if (status == "rejected") {
            this._msg(hPlayer, "Rejected: " + mod.name + "." + parts[1] + " = " + parts[2]);
            return;
        }
        this._broadcast(mod.name + "." + parts[1] + " = " + mod.variables[parts[1]]);
    },

    // ---------- settings persistence ----------

    function _save(hPlayer, szArgs) {
        local id = this._leaderId();
        if (id == null) { this._msg(hPlayer, "Cannot resolve the lobby leader's Steam ID."); return; }
        StringToFile(this._settingsFile(id), this._serialize());
        this._msg(hPlayer, "Settings saved on this server; they re-apply automatically while you lead.");
    },

    function _load(hPlayer, szArgs) {
        local id = this._leaderId();
        if (id == null) { this._msg(hPlayer, "Cannot resolve the lobby leader's Steam ID."); return; }
        local n = this._loadApply(id);
        if (n < 0) this._msg(hPlayer, "No saved settings found.");
        else this._broadcast("Loaded " + n + " saved setting(s).");
    },

    function _reset(hPlayer, szArgs) {
        if (this._defaults != null) {
            foreach (modName, vars in this._defaults) {
                local mod = this._findModule(modName);
                if (mod == null || !("variables" in mod)) continue;
                foreach (k, v in vars)
                    if (k in mod.variables) mod.variables[k] = v;
            }
        }
        local id = this._leaderId();
        if (id != null) StringToFile(this._settingsFile(id), "");   // clear the persisted file
        this._broadcast("Settings reset to defaults.");
    },

    function _settingsFile(id) {
        return this._SETTINGS_DIR + id + ".txt";
    },

    // File names must be filesystem-safe; Steam IDs contain ':' and brackets.
    function _sanitizeId(s) {
        local out = "";
        for (local i = 0; i < s.len(); i++) {
            local ch = s[i];
            if ((ch >= '0' && ch <= '9') || (ch >= 'A' && ch <= 'Z')
                || (ch >= 'a' && ch <= 'z') || ch == '_')
                out += ch.tochar();
            else
                out += "_";
        }
        return out;
    },

    function _leaderId() {
        local res = Entities.FindByClassname(null, "asw_game_resource");
        if (!res) return null;
        local hLeader = NetProps.GetPropEntity(res, "m_Leader");
        if (hLeader == null || !hLeader.IsValid()) return null;
        return this._sanitizeId(hLeader.GetNetworkIDString());
    },

    // One "ModuleName.varName=value" line per variable.
    function _serialize() {
        local s = "";
        foreach (mod in ::g_Modules) {
            if (!("variables" in mod)) continue;
            foreach (k, v in mod.variables)
                s += mod.name + "." + k + "=" + v + "\n";
        }
        return s;
    },

    function _splitLines(text) {
        local lines = [];
        local start = 0;
        for (local i = 0; i <= text.len(); i++) {
            if (i == text.len() || text[i] == 10) {   // '\n' or end of text
                local line = text.slice(start, i);
                if (line.len() > 0 && line[line.len() - 1] == 13)   // trailing '\r'
                    line = line.slice(0, line.len() - 1);
                if (line.len() > 0) lines.append(line);
                start = i + 1;
            }
        }
        return lines;
    },

    // Apply saved lines through the same path as !cc_set (validation included).
    // Returns the number of applied values, or -1 if there is no file.
    function _loadApply(id) {
        local text = FileToString(this._settingsFile(id));
        if (text == null) return -1;
        local applied = 0;
        foreach (line in this._splitLines(text)) {
            local dot = line.find(".");
            local eq  = line.find("=");
            if (dot == null || eq == null || dot == 0 || dot >= eq) continue;
            local mod = this._findModule(line.slice(0, dot));
            if (mod == null) continue;
            if (this._applyVariable(mod, line.slice(dot + 1, eq), line.slice(eq + 1)) == null)
                applied++;
        }
        return applied;
    },

    // ---------- utility ----------

    // Split a string on spaces; returns an array of words.
    function _split(str) {
        local parts = [];
        local i = 0;
        while (i < str.len()) {
            while (i < str.len() && str[i] == 32) i++;
            if (i >= str.len()) break;
            local word = "";
            while (i < str.len() && str[i] != 32) {
                word += str.slice(i, i + 1);
                i++;
            }
            if (word.len() > 0) parts.append(word);
        }
        return parts;
    },

    // ---------- lifecycle ----------

    function OnGameplayStart() {
        // Snapshot compile-time defaults (the VM is fresh every map), then
        // auto-apply the current leader's saved settings on top.
        if (this._defaults == null) {
            this._defaults = {};
            foreach (mod in ::g_Modules) {
                if (!("variables" in mod)) continue;
                local copy = {};
                foreach (k, v in mod.variables) copy[k] <- v;
                this._defaults[mod.name] <- copy;
            }
        }
        local id = this._leaderId();
        if (id == null) return;
        local n = this._loadApply(id);
        if (n > 0) this._broadcast("Applied " + n + " saved setting(s) for the lobby leader.");
    },

    function Cleanup() {},
};

// The command table is built here, outside the literal, so entries can
// reference the token slots above. fn = name of the handler slot; the parser
// derives all slice offsets from cmd.len().
m._CMDS = [
    { cmd = m._CMD_HELP,       args = "",                        help = "this list (everyone)",                       leader = false, fn = "_printHelp" },
    { cmd = m._CMD_CHALLENGES, args = "",                        help = "list modules with ON/OFF status",            leader = true,  fn = "_printList" },
    { cmd = m._CMD_ENABLE,     args = " <module>",               help = "enable a module",                            leader = true,  fn = "_enable"    },
    { cmd = m._CMD_DISABLE,    args = " <module>",               help = "disable a module",                           leader = true,  fn = "_disable"   },
    { cmd = m._CMD_VARS,       args = " <module>",               help = "show a module's variables",                  leader = true,  fn = "_printVars" },
    { cmd = m._CMD_SET,        args = " <module> <var> <value>", help = "change a module's variable",                 leader = true,  fn = "_setVar"    },
    { cmd = m._CMD_SAVE,       args = "",                        help = "save all variables (per leader, this server)", leader = true, fn = "_save"     },
    { cmd = m._CMD_LOAD,       args = "",                        help = "re-apply the saved variables",               leader = true,  fn = "_load"      },
    { cmd = m._CMD_RESET,      args = "",                        help = "restore defaults and clear the saved file",  leader = true,  fn = "_reset"     },
];

::RegisterModule(m);
