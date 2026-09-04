-- Passive, bounded menu inspection. Never clicks, selects slots, invokes remotes or reads chat.
local Scan = { VERSION = "0.1.0", MAX_NODES = 1200, MAX_ROWS = 250, MAX_DEPTH = 14 }
local fields = { "DataSlot", "SlotId", "Slot", "Luminant", "Region", "Location" }
local function short(value, limit)
    if type(value) ~= "string" and type(value) ~= "number" then return nil end
    return tostring(value):gsub("[%z\1-\31]", " "):sub(1, limit or 160)
end
local function lower(value) return tostring(value):lower():gsub("[%s_%-]", "") end
local function excluded(name)
    name = lower(name)
    return name:find("chat", 1, true) or name:find("claw", 1, true)
        or name:find("backpack", 1, true) or name:find("choiceprompt", 1, true)
end
local function relevant(name)
    name = lower(name)
    return name:find("menu", 1, true) or name:find("slot", 1, true) or name:find("characterselect", 1, true)
end
function Scan.collect(playerGui, yieldStep)
    local result = { version = Scan.VERSION, roots = {}, rows = {}, visited = 0, truncated = false,
        status = "NO_MENU_ROOT", candidates = {} }
    if not playerGui then return result end
    local queue = {}
    for _, root in ipairs(playerGui:GetChildren()) do
        if #result.roots < 60 then result.roots[#result.roots + 1] = short(root.Name, 80) end
        if not excluded(root.Name) and relevant(root.Name) then
            queue[#queue + 1] = { object = root, path = short(root.Name, 80), depth = 0 }
        end
    end
    if #queue == 0 then return result end
    result.status = "CAPTURED_UNCONFIRMED"
    local head, textBytes = 1, 0
    while head <= #queue and result.visited < Scan.MAX_NODES do
        local item = queue[head]; head += 1
        local object = item.object; result.visited += 1
        if not excluded(object.Name) then
            local row = { path = item.path, class = object.ClassName, attributes = {} }
            for _, name in ipairs(fields) do
                local ok, value = pcall(object.GetAttribute, object, name)
                if ok then row.attributes[name] = short(value) end
            end
            if object:IsA("TextLabel") or object:IsA("TextButton") then row.text = short(object.Text) end
            -- TextBoxes may contain user-entered values; never collect them.
            if next(row.attributes) or row.text then
                local cost = #row.path + #(row.text or "") + 100
                for _, value in pairs(row.attributes) do cost += #value + 30 end
                if #result.rows < Scan.MAX_ROWS and textBytes + cost <= 60000 then
                    result.rows[#result.rows + 1] = row; textBytes += cost
                else result.truncated = true end
                local slot = row.attributes.DataSlot or row.attributes.SlotId or row.attributes.Slot
                if slot and #result.candidates < 30 then
                    result.candidates[#result.candidates + 1] = { slot = slot, path = row.path,
                        location = row.attributes.Luminant or row.attributes.Region or row.attributes.Location,
                        confirmed = false, source = "menu-attribute-candidate" }
                end
            end
            if item.depth < Scan.MAX_DEPTH then
                for _, child in ipairs(object:GetChildren()) do
                    if #queue >= Scan.MAX_NODES then result.truncated = true; break end
                    queue[#queue + 1] = { object = child, path = (item.path .. "/" .. short(child.Name, 80)):sub(1, 350), depth = item.depth + 1 }
                end
            else result.truncated = true end
        end
        if yieldStep and result.visited % 100 == 0 then yieldStep() end
    end
    if head <= #queue then result.truncated = true end
    return result
end
return Scan
