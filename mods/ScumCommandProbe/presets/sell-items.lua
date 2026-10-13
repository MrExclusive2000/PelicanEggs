-- ExclsvProbe preset: how SCUM takes an item out of a player's inventory (dropping, consuming,
-- destroying, moving between containers), so items can be sold to the server safely.
-- Copy this file to probe-settings.lua next to the README.
return {
    title = "ExclsvProbe report: removing items from an inventory",
    keywords = {
        "inventory", "removeitem", "removefrom", "destroyitem", "dropitem", "discard", "consume",
        "iteminhand", "itemsinhand", "getitems", "containeditem", "owneditem", "attacheditem",
        "pickup", "holster", "despawn", "deleteitem", "transfer", "moveitem",
    },
    nativeOnly = true,
    -- Every function and value of the prisoner, the item base class and the inventory containers.
    -- "=" means the exact class name, so "=item" is SCUM's Item class and not every item.
    wholeClasses = { "=prisoner", "=item", "=conzcharacter", "itemcontainer", "inventorycomponent", "entityinventory" },
    lateScanMinutes = 0,
}
