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
local function object(name, class, attributes, text, children)
    local o = { Name = name, ClassName = class or "Frame", Text = text, children = children or {}, attributes = attributes or {} }
    function o:IsA(c) return self.ClassName == c end
    function o:GetAttribute(k) return self.attributes[k] end
    function o:GetChildren() return self.children end
    return o
end
test("scanner reads explicit slot candidates without confirming or acting", function()
    local root = object("PlayerGui", "PlayerGui", nil, nil, {
        object("StartMenu", nil, nil, nil, { object("Character", "TextButton", { DataSlot = "L", Region = "Eastern Luminant" }, "Character One") }) })
    local result = Scan.collect(root)
    assert(#result.candidates == 1 and result.candidates[1].slot == "L" and result.candidates[1].confirmed == false)
    assert(result.rows[1].text == "Character One")
end)
test("scanner excludes chat, third-party CLAW UI and text inputs", function()
    local root = object("PlayerGui", nil, nil, nil, { object("ChatMenu", nil, nil, nil, { object("Message", "TextLabel", nil, "SECRET") }),
        object("CLAWMenu", "TextLabel", nil, "SECRET"), object("StartMenu", nil, nil, nil, {
            object("Search", "TextBox", nil, "SECRET"), object("Chat", "TextLabel", nil, "SECRET"), object("Slot", "TextLabel", nil, "Visible") }) })
    local result = Scan.collect(root); assert(#result.rows == 1 and result.rows[1].text == "Visible")
end)
test("unknown menu structure is reported without guessing slot letters", function()
    local result = Scan.collect(object("PlayerGui", nil, nil, nil, { object("MysteryRoot", "TextLabel", nil, "Slot L Eastern Luminant") }))
    assert(result.status == "NO_MENU_ROOT" and #result.candidates == 0)
end)

test("observed LoadingGui menu is scanned without assuming it is only a splash", function()
    local result = Scan.collect(object("PlayerGui", nil, nil, nil, {
        object("LoadingGui", "ScreenGui", nil, nil, {
            object("Character", "TextLabel", nil, "Rook Janus"),
            object("Location", "TextLabel", nil, "Eastern Luminant"),
            object("Friends", nil, nil, nil, { object("Name", "TextLabel", nil, "PRIVATE") }),
            object("PatchNotes", "TextLabel", nil, "UNRELATED"),
        }),
        object("TooltipGui", "TextLabel", nil, "UNRELATED"),
    }))
    assert(result.status == "CAPTURED_UNCONFIRMED" and #result.rows == 2)
    assert(result.rows[1].path == "LoadingGui/Character")
    assert(result.rows[2].text == "Eastern Luminant" and #result.candidates == 0)
end)

test("loading root alone never invents character candidates", function()
    local result = Scan.collect(object("PlayerGui", nil, nil, nil, { object("LoadingGui", "ScreenGui") }))
    assert(result.status == "CAPTURED_UNCONFIRMED" and #result.rows == 0 and #result.candidates == 0)
    local unrelated = Scan.collect(object("PlayerGui", nil, nil, nil, { object("LoadingSplash", "TextLabel", nil, "PRIVATE") }))
    assert(unrelated.status == "NO_MENU_ROOT")
end)
test("scanner bounds work and yields between batches", function()
    local children = {}; for i = 1, 2000 do children[i] = object("Label" .. i, "TextLabel", nil, "text") end
    local pauses = 0
    local result = Scan.collect(object("PlayerGui", nil, nil, nil, { object("StartMenu", nil, nil, nil, children) }), function() pauses += 1 end)
    assert(result.visited <= Scan.MAX_NODES and #result.rows <= Scan.MAX_ROWS and result.truncated and pauses > 0)
end)
print(tostring(passed) .. " slot/region tests passed")
