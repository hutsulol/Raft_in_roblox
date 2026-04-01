-- Handles Bed crafting via the CraftItem event
-- Separate from CraftingSystem because that file may not sync
local rs = game:GetService("ReplicatedStorage")

local WORKBENCH_RANGE = 15

local craftEvent = rs:WaitForChild("CraftItem")

local function findWorkBench()
	for _, v in workspace:GetDescendants() do
		if v:IsA("Model") and v.Name == "WorkBench" then
			return v
		end
	end
	return nil
end

local function getWorkBenchPos()
	local wb = findWorkBench()
	if not wb then return nil end
	if wb.PrimaryPart then
		return wb.PrimaryPart.Position
	end
	local part = wb:FindFirstChildWhichIsA("BasePart", true)
	if part then return part.Position end
	return wb:GetPivot().Position
end

craftEvent.OnServerEvent:Connect(function(player, action, data)
	if action ~= "craft" or data ~= "Bed" then return end

	local char = player.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then return end

	local wbPos = getWorkBenchPos()
	if not wbPos then return end

	local dist = (char.HumanoidRootPart.Position - wbPos).Magnitude
	if dist > WORKBENCH_RANGE then return end

	local inv = _G.GetInventory and _G.GetInventory(player) or {}
	if (inv.Log or 0) < 2 then return end

	inv.Log = inv.Log - 2

	local backpack = player:FindFirstChild("Backpack")
	if not backpack then return end

	local tool = Instance.new("Tool")
	tool.Name = "Bed"
	tool.CanBeDropped = false
	tool.TextureId = "rbxassetid://110032041583533"

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1, 1, 1)
	handle.Transparency = 1
	handle.Parent = tool

	tool.Parent = backpack

	if _G.SendInventory then
		_G.SendInventory(player)
	end

	craftEvent:FireClient(player, "success", "Bed")
end)
