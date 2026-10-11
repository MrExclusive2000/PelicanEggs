-- What the probe looks for. This version looks for ways to put items into a player's
-- inventory (for starter kits). Delete this file to get the original admin/chat report.
return {
    title = "ScumCommandProbe report: items and inventory",
    keywords = {
        "item", "inventory", "spawn", "give", "equip", "container", "loot", "pickup",
        "slot", "hands", "stack", "attach",
    },
    -- Only SCUM's own C++ classes; Blueprint functions are mostly UI and animation noise.
    nativeOnly = true,
    -- List every function of classes whose name contains these words.
    wholeClasses = { "inventory", "itemspawn", "itemstatics", "itemcontainer", "itemmanager" },
}
