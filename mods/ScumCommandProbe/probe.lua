-- What the probe looks for. This version looks for ways to put items into a player's
-- inventory (starter kits) and to read or change a player's money (safe player bounties and
-- paid teleports). Delete this file to get the original admin/chat report.
return {
    title = "ScumCommandProbe report: items, inventory, money and teleports",
    keywords = {
        "item", "inventory", "spawn", "give", "equip", "container", "loot", "pickup",
        "slot", "hands", "stack", "attach",
        "currency", "balance", "money", "cash", "bank", "wallet", "fame", "teleport",
    },
    -- Only SCUM's own C++ classes; Blueprint functions are mostly UI and animation noise.
    nativeOnly = true,
    -- List every function of classes whose name contains these words.
    wholeClasses = { "inventory", "itemspawn", "itemstatics", "itemcontainer", "itemmanager", "currency", "bank", "economy" },
}
