// module_chat_admin.nut
// Chat commands for managing modules at runtime. Prefix: !cc_ (Challenge Combiner).
//
// Commands:
//   !cc_help                          — list available commands (everyone)
//   !cc_challenges                    — list all modules with their status
//   !cc_enable  <name>                — enable a module
//   !cc_disable <name>                — disable a module
//   !cc_vars    <name>                — show a module's variables
//   !cc_set     <name> <var> <value>  — change a module's variable
//
// Everything except !cc_help is lobby leader only.
// Messages that do not start with "!cc_" are ignored (other modules may use
// their own !commands).

local m = {
    name    = "ChatAdmin",
    enabled = true,
    convars = {},

    _isLobbyLeader = function(hPlayer) {
        local res = Entities.FindByClassname(null, "asw_game_resource");
        if (!res) return false;
        return hPlayer == NetProps.GetPropEntity(res, "m_Leader");
    },

    function OnGameEvent_player_say(params) {
        if (!("text" in params)) return;
        local raw  = params["text"];
        local text = raw.tolower();
        if (text.len() < 4 || text.slice(0, 4) != "!cc_") return;   // not our command

        local hPlayer = GetPlayerFromUserID(params["userid"]);
        if (!hPlayer || !hPlayer.IsValid()) return;

        if (text == "!cc_help") {
            this._printHelp(hPlayer);
            return;
        }

        if (!this._isLobbyLeader(hPlayer)) {
            ClientPrint(hPlayer, 3, "[CC] Only the lobby leader can manage modules. Type !cc_help for the command list.");
            return;
        }

        if (text == "!cc_challenges") {
            this._printList(hPlayer);
        } else if (text.len() > 11 && text.slice(0, 11) == "!cc_enable ") {
            this._toggle(hPlayer, raw.slice(11), true);
        } else if (text.len() > 12 && text.slice(0, 12) == "!cc_disable ") {
            this._toggle(hPlayer, raw.slice(12), false);
        } else if (text.len() > 9 && text.slice(0, 9) == "!cc_vars ") {
            this._printVars(hPlayer, raw.slice(9));
        } else if (text.len() > 8 && text.slice(0, 8) == "!cc_set ") {
            this._setVar(hPlayer, raw.slice(8));
        } else {
            this._printHelp(hPlayer);   // unknown !cc_ command
        }
    },

    function _printHelp(hPlayer) {
        ClientPrint(hPlayer, 3, "[CC] Challenge Combiner chat commands:");
        ClientPrint(hPlayer, 3, "  !cc_help - this list");
        ClientPrint(hPlayer, 3, "  !cc_challenges - list modules with ON/OFF status");
        ClientPrint(hPlayer, 3, "  !cc_enable <module> - enable a module");
        ClientPrint(hPlayer, 3, "  !cc_disable <module> - disable a module");
        ClientPrint(hPlayer, 3, "  !cc_vars <module> - show a module's variables");
        ClientPrint(hPlayer, 3, "  !cc_set <module> <var> <value> - change a variable");
        ClientPrint(hPlayer, 3, "  All commands except !cc_help are lobby leader only.");
    },

    function _printList(hPlayer) {
        ClientPrint(hPlayer, 3, "[CC] Modules:");
        foreach (mod in ::g_Modules) {
            if (mod.name == "ChatAdmin") continue;
            local status = mod.enabled ? "[ON]" : "[OFF]";
            local hint = ("variables" in mod) ? "  (!cc_vars " + mod.name + ")" : "";
            ClientPrint(hPlayer, 3, "  " + status + " " + mod.name + hint);
        }
    },

    function _toggle(hPlayer, name, enable) {
        foreach (mod in ::g_Modules) {
            if (mod.name.tolower() == name.tolower()) {
                mod.enabled = enable;
                Say(null, "[CC] " + mod.name + (enable ? " enabled." : " disabled."));
                return;
            }
        }
        ClientPrint(hPlayer, 3, "[CC] Module not found: " + name);
    },

    function _printVars(hPlayer, name) {
        foreach (mod in ::g_Modules) {
            if (mod.name.tolower() != name.tolower()) continue;
            if (!("variables" in mod)) {
                ClientPrint(hPlayer, 3, "[CC] " + mod.name + " has no variables.");
                return;
            }
            ClientPrint(hPlayer, 3, "[CC] " + mod.name + " variables:");
            foreach (k, v in mod.variables)
                ClientPrint(hPlayer, 3, "  " + k + " = " + v);
            ClientPrint(hPlayer, 3, "  !cc_set " + mod.name + " <var> <value>");
            return;
        }
        ClientPrint(hPlayer, 3, "[CC] Module not found: " + name);
    },

    // Format: "<ModuleName> <varName> <value>"
    function _setVar(hPlayer, args) {
        local parts = this._split(args);
        if (parts.len() < 3) {
            ClientPrint(hPlayer, 3, "[CC] Usage: !cc_set <module> <var> <value>");
            return;
        }
        local modName = parts[0];
        local varName = parts[1];
        local valStr  = parts[2];

        foreach (mod in ::g_Modules) {
            if (mod.name.tolower() != modName.tolower()) continue;
            if (!("variables" in mod) || !(varName in mod.variables)) {
                ClientPrint(hPlayer, 3, "[CC] Variable not found: " + varName);
                return;
            }
            // Preserve type: if the current value is numeric, convert to float.
            local current = mod.variables[varName];
            if (typeof current == "integer" || typeof current == "float") {
                mod.variables[varName] = valStr.tofloat();
            } else {
                mod.variables[varName] = valStr;
            }
            Say(null, "[CC] " + mod.name + "." + varName + " = " + mod.variables[varName]);
            return;
        }
        ClientPrint(hPlayer, 3, "[CC] Module not found: " + modName);
    },

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

    function Cleanup() {},
};

::RegisterModule(m);
