local DetectorEvent = {}
DetectorEvent.__index = DetectorEvent

local function findEntity(instance)
	local cursor = instance
	while cursor and cursor ~= workspace do
		if cursor:IsA("Model") and cursor:FindFirstChildWhichIsA("Humanoid") then
			return cursor
		end
		cursor = cursor.Parent
	end
	return nil
end

function DetectorEvent.new(detector, id, instance, values)
	values = values or {}
	local entity = values.entity or (instance and findEntity(instance))
	local root = entity and entity:FindFirstChild("HumanoidRootPart")

	return setmetatable({
		detector = detector,
		id = tostring(id or ""),
		instance = instance,
		entity = entity,
		root = root,
		track = values.track,
		position = values.position or (root and root.Position),
		startedAt = values.startedAt or os.clock(),
		metadata = values.metadata or {},
	}, DetectorEvent)
end

return DetectorEvent
