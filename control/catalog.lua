-- Compact menu metadata only; never send raw UI labels, friends, or local report files.
local Catalog = { VERSION = 1, MAX_CARDS = 60 }
local fields = { characterName = 80, race = 40, oath = 60, origin = 60, location = 100,
    playtime = 32, lastPlayed = 32 }
local function text(value, limit)
    if type(value) ~= "string" then return nil end
    value = value:gsub("[%z\1-\31]", " ")
    if not utf8.len(value) then return nil end
    if #value > limit then
        local ok, offset = pcall(utf8.offset, value, 0, limit + 1)
        value = value:sub(1, ok and offset and offset - 1 or limit)
    end
    if value == "" then return nil end
    return value
end
function Catalog.fromScan(report, accountId, at)
    if type(report) ~= "table" or type(report.cards) ~= "table" then return nil end
    local packet = { type = "catalog", version = 1, accountId = accountId,
        placeId = 4111023553, complete = not report.truncated and #report.cards > 0,
        cards = {}, status = report.status, observedAt = at }
    for _, source in ipairs(report.cards) do
        if #packet.cards >= Catalog.MAX_CARDS then packet.complete = false; break end
        if type(source.slot) == "string" and source.slot:match("^[A-Z]+$") and #source.slot <= 3 then
            local card = { slot = source.slot, slotLabel = source.slotLabel, level = source.level,
                complete = source.complete == true and not source.truncated and source.slotLabel == source.slot,
                confirmed = false, source = "menu-card", observedAt = at }
            for field, limit in pairs(fields) do card[field] = text(source[field], limit) end
            card.complete = card.complete and card.characterName ~= nil and card.race ~= nil and card.location ~= nil
                and type(card.level) == "number" and card.level % 1 == 0 and card.level >= 0 and card.level <= 1000
            packet.cards[#packet.cards + 1] = card
            if not card.complete then packet.complete = false end
        else packet.complete = false end
    end
    return packet
end
function Catalog.signature(packet)
    local ordered = table.clone(packet.cards)
    table.sort(ordered, function(a, b) return a.slot < b.slot end)
    local parts = { tostring(packet.complete) }
    for _, card in ipairs(ordered) do
        for _, field in ipairs({ "slot", "slotLabel", "complete", "level", "characterName", "race", "oath", "origin", "location", "playtime", "lastPlayed" }) do
            local value = tostring(card[field]); parts[#parts + 1] = #value .. ":" .. value
        end
    end
    return table.concat(parts, "|")
end
return Catalog
