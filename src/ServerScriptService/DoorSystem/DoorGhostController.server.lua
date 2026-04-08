local Workspace = game:GetService("Workspace")

local DOOR_BUILD_TYPE = "door_wood"
local HOOK_ATTR = "DoorGhostControllerHooked"
local STATE_ATTR = "DoorIsOpen"

local function getDoorHinge(doorModel)
	return doorModel:FindFirstChild("Hinge", true)
end

local function getDoorPrompt(doorModel)
	local base = doorModel:FindFirstChild("Base", true)
	if not base then return nil end
	return base:FindFirstChildWhichIsA("ProximityPrompt")
end

local function setDoorOpenState(doorModel, isOpen)
	local hinge = getDoorHinge(doorModel)
	if hinge and hinge:IsA("BasePart") then
		hinge.Transparency = isOpen and 1 or 0
		hinge.CanCollide = not isOpen
		hinge.CanQuery = not isOpen
		hinge.CanTouch = not isOpen
	end
	doorModel:SetAttribute(STATE_ATTR, isOpen)
end

local function disableLegacyDoorScript(doorModel)
	local legacy = doorModel:FindFirstChildWhichIsA("Script", true)
	if legacy then
		legacy.Disabled = true
	end
end

local function hookDoor(doorModel)
	if not doorModel:IsA("Model") then return end
	if doorModel:GetAttribute("BuildType") ~= DOOR_BUILD_TYPE then return end
	if doorModel:GetAttribute(HOOK_ATTR) then return end

	local prompt = getDoorPrompt(doorModel)
	if not prompt then return end

	disableLegacyDoorScript(doorModel)

	if doorModel:GetAttribute(STATE_ATTR) == nil then
		doorModel:SetAttribute(STATE_ATTR, false)
	end
	setDoorOpenState(doorModel, doorModel:GetAttribute(STATE_ATTR) == true)
	prompt.ActionText = (doorModel:GetAttribute(STATE_ATTR) and "Close") or "Open"

	prompt.Triggered:Connect(function()
		local nextState = not (doorModel:GetAttribute(STATE_ATTR) == true)
		setDoorOpenState(doorModel, nextState)
		prompt.ActionText = nextState and "Close" or "Open"
	end)

	doorModel:SetAttribute(HOOK_ATTR, true)
end

local function scanAndHookDoors(root)
	for _, desc in root:GetDescendants() do
		if desc:IsA("Model") and desc:GetAttribute("BuildType") == DOOR_BUILD_TYPE then
			hookDoor(desc)
		end
	end
end

local raft = Workspace:FindFirstChild("Raft")
if raft then
	scanAndHookDoors(raft)
	raft.DescendantAdded:Connect(function(desc)
		if desc:IsA("Model") and desc:GetAttribute("BuildType") == DOOR_BUILD_TYPE then
			hookDoor(desc)
		end
	end)
end

Workspace.ChildAdded:Connect(function(child)
	if child.Name == "Raft" then
		scanAndHookDoors(child)
		child.DescendantAdded:Connect(function(desc)
			if desc:IsA("Model") and desc:GetAttribute("BuildType") == DOOR_BUILD_TYPE then
				hookDoor(desc)
			end
		end)
	end
end)
