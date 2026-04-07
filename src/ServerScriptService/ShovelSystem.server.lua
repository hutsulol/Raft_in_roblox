-- ShovelSystem.server.lua
-- Tags Sand/Clay parts on islands and handles digging with the Shovel tool.
-- Unlike rocks, the part is NOT shrunk while being dug.

local rs = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local DIG_HITS_REQUIRED = 5
local DIG_RANGE = 15

local digDirtEvent = Instance.new("RemoteEvent")
digDirtEvent.Name = "DigDirt"
digDirtEvent.Parent = rs

local function tagPart(part)
	if not part:IsA("BasePart") then return end
	if part.Name ~= "Sand" and part.Name ~= "Clay" then return end
	if part:GetAttribute("Diggable") then return end

	part:SetAttribute("Diggable", true)
	part:SetAttribute("DigType", part.Name)
	part:SetAttribute("DigHealth", DIG_HITS_REQUIRED)
end

local function tagDiggablesInModel(model)
	for _, part in model:GetDescendants() do
		tagPart(part)
	end
end

local function isIsland(child)
	return child:IsA("Model") and (child.Name == "Island_1" or child.Name == "Island_2")
end

workspace.ChildAdded:Connect(function(child)
	if isIsland(child) then
		task.wait(0.1)
		tagDiggablesInModel(child)
	end
end)

for _, child in workspace:GetChildren() do
	if isIsland(child) then
		tagDiggablesInModel(child)
	end
end

digDirtEvent.OnServerEvent:Connect(function(player, part)
	if not part or not part:IsA("BasePart") then return end
	if not part:GetAttribute("Diggable") then return end

	local char = player.Character
	if not char then return end
	local tool = char:FindFirstChildWhichIsA("Tool")
	if not tool or tool.Name ~= "Shovel" then return end

	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	if (hrp.Position - part.Position).Magnitude > DIG_RANGE then return end

	local health = part:GetAttribute("DigHealth") or DIG_HITS_REQUIRED
	health = health - 1
	part:SetAttribute("DigHealth", health)

	if health <= 0 then
		local digType = part:GetAttribute("DigType") or "Sand"
		local inv = _G.GetInventory and _G.GetInventory(player) or {}
		inv[digType] = (inv[digType] or 0) + 1

		if _G.SendInventory then
			_G.SendInventory(player)
		end

		digDirtEvent:FireClient(player, "destroyed", 1, digType)
		part:Destroy()
	else
		digDirtEvent:FireClient(player, "hit", health)
	end
end)

-- ─── Ensure Sand/Clay exist in player inventories ───
local function ensureFields(player)
	task.wait(2)
	local inv = _G.GetInventory and _G.GetInventory(player)
	if inv then
		if inv.Sand == nil then inv.Sand = 0 end
		if inv.Clay == nil then inv.Clay = 0 end
	end
end

Players.PlayerAdded:Connect(function(p) task.spawn(ensureFields, p) end)
for _, p in Players:GetPlayers() do task.spawn(ensureFields, p) end
