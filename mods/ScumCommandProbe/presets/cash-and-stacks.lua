-- ExclsvProbe preset: what SCUM exposes for cash items and stack amounts, to pay players in
-- banknotes without an admin online. Copy this file to probe-settings.lua next to the README.
return {
    title = "ExclsvProbe report: cash and item stacks",
    keywords = {
        "amount", "stack", "quantity", "discrete", "cash", "banknote", "money", "currency",
        "spawnitem", "itemspawn", "placeitem", "merge", "split",
    },
    -- Every function and value of the classes that hold stack sizes and of the cash item.
    wholeClasses = { "discreteamount", "stackable", "cash", "itementity", "itemcomponent" },
    lateScanMinutes = 0,
}
