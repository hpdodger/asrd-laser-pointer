// shot_announcer_messages.nut
// Sub-file for module_shot_announcer.nut.
// Exports data via a global — the only way to pass values across IncludeScript boundaries.
// The entry point captures it to a local before defining the table, making it an upvalue.

::SA_messages <- [
    "%s opens fire!",
    "%s pulls the trigger!",
    "%s is back in action!",
    "%s shows no mercy!",
    "%s is laying it down!",
];
