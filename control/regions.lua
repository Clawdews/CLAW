-- Keep this allowlist small. Unknown places/layers must not be treated as interchangeable.
local Regions = {}
local names = {
    eastluminant = "EastLuminant", easternluminant = "EastLuminant", theeasternluminant = "EastLuminant",
    etreanluminant = "EtreanLuminant", theetreanluminant = "EtreanLuminant",
}
local places = { [6473861193] = "EastLuminant", [6032399813] = "EtreanLuminant" }
function Regions.normalize(value)
    if type(value) ~= "string" then return nil end
    return names[value:lower():gsub("[%s_%-]", "")]
end
function Regions.forPlace(placeId) return places[placeId] end
function Regions.choose(profile, placeId, catalog, now)
    local region = Regions.forPlace(placeId)
    if not region then return nil, "UNSUPPORTED_REGION: this place/layer is not mapped" end
    local allowed = profile.approvedSlots
    if type(allowed) ~= "table" then return nil, "NO_APPROVED_SLOT: approve a character in Discord" end
    local preferred = profile.preferredSlots and profile.preferredSlots[region]
    local matches = {}
    for _, entry in ipairs(catalog or {}) do
        local supportedEvidence = entry.confirmed == true or (entry.source == "menu-card" and entry.complete == true)
        if allowed[entry.slot] == true and (entry.region or Regions.normalize(entry.location)) == region and supportedEvidence
            and type(entry.observedAt) == "number" and entry.observedAt <= now and now - entry.observedAt <= 86400 then
            matches[entry.slot] = true
        end
    end
    if preferred and matches[preferred] then return preferred, region end
    local only
    for slot in pairs(matches) do
        if only then return nil, "CHOOSE_PREFERRED_SLOT: several approved characters match " .. region end
        only = slot
    end
    if only then return only, region end
    return nil, "NO_COMPATIBLE_SLOT: confirm an approved character in " .. region
end
return Regions
