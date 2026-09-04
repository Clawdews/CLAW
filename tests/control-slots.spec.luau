local Regions = require("../control/regions")
local Scan = require("../control/menu-scan")
local passed = 0
local function test(name, fn) fn(); passed += 1; print("PASS " .. name) end
local now = 2000000000
local function entry(slot, region, confirmed, age)
    return { slot = slot, region = region, confirmed = confirmed, observedAt = now - (age or 0) }
end
test("region aliases are exact, not substring matches or guessed layers", function()
    assert(Regions.normalize("Eastern Luminant") == "EastLuminant")
    assert(Regions.normalize("EtreanLuminant") == "EtreanLuminant")
    assert(Regions.normalize("not Eastern Luminant") == nil)
    assert(Regions.forPlace(123) == nil and Regions.normalize("Layer 2") == nil)
end)
test("only confirmed approved compatible slots are selected", function()
    local profile = { approvedSlots = { L = true, A = true } }
    assert(Regions.choose(profile, 6473861193, { entry("L", "EastLuminant", true), entry("A", "EtreanLuminant", true) }, now) == "L")
    assert(Regions.choose(profile, 6473861193, { entry("L", "EastLuminant", false) }, now) == nil)
    assert(Regions.choose({ approvedSlots = {} }, 6473861193, { entry("L", "EastLuminant", true) }, now) == nil)
end)
test("several compatible slots require a preference", function()
    local p = { approvedSlots = { L = true, A = true } }
    local slots = { entry("L", "EastLuminant", true), entry("A", "EastLuminant", true) }
    assert(Regions.choose(p, 6473861193, slots, now) == nil)
    p.preferredSlots = { EastLuminant = "A" }; assert(Regions.choose(p, 6473861193, slots, now) == "A")
end)
test("stale and future observations never arm slot selection", function()
    local p = { approvedSlots = { L = true } }
    assert(Regions.choose(p, 6473861193, { entry("L", "EastLuminant", true, 86401) }, now) == nil)
    assert(Regions.choose(p, 6473861193, { entry("L", "EastLuminant", true, -1) }, now) == nil)
end)
local guiClasses = { Frame = true, ScrollingFrame = true, TextButton = true, TextLabel = true,
    TextBox = true, ViewportFrame = true, ImageLabel = true }
local function object(name, class, text, children)
    local o = { Name = name, ClassName = class or "Frame", Text = text, children = children or {} }
    function o:IsA(c) return self.ClassName == c or (c == "GuiObject" and guiClasses[self.ClassName] == true) end
    function o:GetChildren() return self.children end
    return o
end
local function label(name, text) return object(name, "TextLabel", text) end
local function menu(cards, extras)
    local list = object("SlotScroll", "ScrollingFrame", nil, cards)
    local node = list
    for _, name in ipairs({ "Slots", "MainFrame", "Columns", "Overlay", "LoadingGui" }) do
        node = object(name, "Frame", nil, { node })
        if name == "Overlay" then for _, extra in ipairs(extras or {}) do table.insert(node.children, extra) end end
    end
    return object("PlayerGui", "PlayerGui", nil, { node })
end
local function card(slot, extra)
    local details = { label("CharacterName", "Sample " .. slot), label("Level", "Lv. 1"),
        label("Race", "<font color=\"#aabbcc\">Khan</font>"), label("Oath", "Oathless"),
        label("Origin", "Authority Ensign"), label("Realm", "<i>Eastern Luminant</i>"),
        label("Playtime", "0h 26m"), label("LastPlayed", "0m ago") }
    for _, child in ipairs(extra or {}) do table.insert(details, child) end
    return object(slot, "TextButton", "", { object("SlotColumns", nil, nil, {
        object("Details", nil, nil, details), object("Buttons", nil, nil, { label("Slot", slot) }) }) })
end
test("targeted reader captures every named card field and leaves candidates unconfirmed", function()
    local result = Scan.collect(menu({ card("L") }))
    local c = result.cards[1]
    assert(result.status == "CARDS_CAPTURED_UNCONFIRMED" and result.completeCards == 1)
    assert(c.slot == "L" and c.slotLabel == "L" and c.characterName == "Sample L")
    assert(c.level == 1 and c.race == "Khan" and c.oath == "Oathless" and c.origin == "Authority Ensign")
    assert(c.location == "Eastern Luminant" and c.playtime == "0h 26m" and c.lastPlayed == "0m ago")
    assert(c.confirmed == false and c.complete and #c.missing == 0)
    assert(c.fieldSources.location == "SlotColumns/Details/Realm")
end)
test("large friends lists and avatar models never consume the card budget", function()
    local social = object("SocialScroll")
    function social:GetChildren() error("Never inspect friends") end
    local viewport = object("Portrait", "ViewportFrame")
    function viewport:GetChildren() error("Never inspect avatar descendants") end
    local cards = {}
    for i = 1, 13 do cards[i] = card(string.char(64 + i), { viewport }) end
    local result = Scan.collect(menu(cards, { social }))
    assert(#result.cards == 13 and result.completeCards == 13 and not result.truncated)
    assert(result.visited < 400 and result.cards[1].slot == "A" and result.cards[13].slot == "M")
end)
test("offscreen cards are read and new-slot buttons are ignored", function()
    local offscreen = card("AA"); offscreen.Visible = false
    local result = Scan.collect(menu({ card("Z"), offscreen, object("NewSlot", "TextButton", "New Slot") }))
    assert(#result.cards == 2 and result.cards[1].slot == "Z" and result.cards[2].slot == "AA")
end)
test("textboxes, scripts, deletion prompts and social text are never read", function()
    local textbox = object("Search", "TextBox", "SECRET")
    function textbox:GetChildren() error("Never inspect editable input") end
    local result = Scan.collect(menu({ card("A", { textbox, object("DeleteConfirm", "TextLabel", "SECRET"),
        object("LocalScript", "LocalScript", "SECRET"), object("SocialPanel", "TextLabel", "SECRET") }) }))
    assert(result.labelCount == 9 and result.completeCards == 1)
    for _, row in ipairs(result.cards[1].labels) do assert(row.text ~= "SECRET") end
end)
test("composite level and colored race are parsed without guessing oath or origin", function()
    local root = menu({ object("C", "TextButton", "", {
        label("CharacterName", "Sample C"), label("Race", 'Lv. 20 <font color="#abc">Vesperian</font> Visionshaper'),
        label("Origin", "Voidwalker"), label("Realm", "Etrean Luminant"),
    }) })
    local c = Scan.collect(root).cards[1]
    assert(c.level == 20 and c.race == "Vesperian" and c.origin == "Voidwalker")
    assert(c.oath == nil and c.summary == "Lv. 20 Vesperian Visionshaper")
    assert(c.labels[2].rawText:find("<font", 1, true))
end)
test("unknown labels remain available and placeholders are not fabricated into values", function()
    local c = Scan.collect(menu({ object("A", "TextButton", "", {
        label("CharacterName", "???"), label("NewDetailFormat", "Lv. 2 UnknownRace NewOrigin"), label("Realm", "Fragments of Else"),
    }) })).cards[1]
    assert(c.level == 2 and c.race == nil and c.characterName == nil and not c.complete)
    assert(c.location == "Fragments of Else" and #c.labels == 2 and c.confirmed == false)
end)
test("conflicting labels and slot mismatches cannot be complete cards", function()
    local c = Scan.collect(menu({ card("A", { label("Realm", "Etrean Luminant"), label("Slot", "B") }) })).cards[1]
    assert(not c.complete and c.location == nil and c.conflicts.location)
    assert(table.find(c.warnings, "conflicting-slotLabel"))
    local mismatch = Scan.collect(menu({ object("A", "TextButton", "", { label("Slot", "B") }) })).cards[1]
    assert(table.find(mismatch.warnings, "slot-label-mismatch"))
end)
test("duplicate slot entries stay ambiguous instead of silently overwriting", function()
    local result = Scan.collect(menu({ card("A"), card("A") }))
    assert(result.completeCards == 0 and #result.cards == 2)
    assert(table.find(result.cards[1].warnings, "duplicate-slot"))
end)
test("one oversized card cannot starve the next card", function()
    local nested = {}
    for i = 1, 1000 do nested[i] = object("Decoration" .. i) end
    local pauses = 0
    local result = Scan.collect(menu({ card("A", nested), card("B") }), function() pauses += 1 end)
    assert(result.status == "PARTIAL_CARDS" and result.cards[1].truncated)
    assert(result.cards[2].complete and result.cards[1].visited <= Scan.MAX_CARD_NODES and pauses > 0)
end)
test("per-card label and global text limits are enforced", function()
    local labels = {}; for i = 1, 100 do labels[i] = label("Unknown" .. i, string.rep("x", 600)) end
    local result = Scan.collect(menu({ card("A", labels) }))
    assert(result.truncated and #result.cards[1].labels == Scan.MAX_CARD_LABELS)
    local previous = Scan.MAX_TEXT_BYTES
    Scan.MAX_TEXT_BYTES = 500
    local limited = Scan.collect(menu({ card("A"), card("B") }))
    Scan.MAX_TEXT_BYTES = previous
    assert(limited.truncated and limited.textBytes <= 500)
end)
test("missing menu, empty list and duplicate containers never trigger a broad scan", function()
    assert(Scan.collect(nil).status == "NO_SLOT_LIST")
    assert(Scan.collect(object("PlayerGui", nil, nil, { object("MysteryMenu", "TextLabel", "PRIVATE") })).status == "NO_SLOT_LIST")
    local empty = Scan.collect(menu({ object("NewSlot", "TextButton", "Buy") }))
    assert(empty.status == "WAITING_FOR_CARDS" and empty.visited == 0)
    local root = menu({ card("A") }); table.insert(root.children, root.children[1])
    assert(Scan.collect(root).status == "NO_SLOT_LIST")
end)
test("card count is bounded and extra cards are reported as partial", function()
    local cards = {}
    for i = 1, 26 do
        cards[#cards + 1] = card(string.char(64 + i))
        cards[#cards + 1] = card("A" .. string.char(64 + i))
        cards[#cards + 1] = card("B" .. string.char(64 + i))
    end
    local result = Scan.collect(menu(cards))
    assert(#result.cards == Scan.MAX_CARDS and result.truncated)
end)
print(tostring(passed) .. " slot/region tests passed")
