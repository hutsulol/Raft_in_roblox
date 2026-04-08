local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local terrain = Workspace.Terrain

local VOXEL_RES = 4
local MAX_DEPTH = 5
local SURFACE_RAY_UP = 20

local TINT_COLOR = Color3.fromRGB(0, 140, 160)

local blur = Lighting:FindFirstChild("UnderwaterBlur")
if not blur or not blur:IsA("BlurEffect") then
	if blur then blur:Destroy() end
	blur = Instance.new("BlurEffect")
	blur.Name = "UnderwaterBlur"
	blur.Size = 0
	blur.Parent = Lighting
end

local colorCorrection = Lighting:FindFirstChild("UnderwaterColorCorrection")
if not colorCorrection or not colorCorrection:IsA("ColorCorrectionEffect") then
	if colorCorrection then colorCorrection:Destroy() end
	colorCorrection = Instance.new("ColorCorrectionEffect")
	colorCorrection.Name = "UnderwaterColorCorrection"
	colorCorrection.Enabled = false
	colorCorrection.Parent = Lighting
end
colorCorrection.TintColor = TINT_COLOR

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = false

local function resetEffects()
	blur.Size = 0
	colorCorrection.Enabled = false
end

local function isPointInWater(position)
	local min = position - Vector3.new(2, 2, 2)
	local max = position + Vector3.new(2, 2, 2)
	local region = Region3.new(min, max):ExpandToGrid(VOXEL_RES)

	local materials, occupancies = terrain:ReadVoxels(region, VOXEL_RES)
	local sx, sy, sz = materials.Size.X, materials.Size.Y, materials.Size.Z
	local cx = math.clamp(math.floor((sx + 1) / 2), 1, sx)
	local cy = math.clamp(math.floor((sy + 1) / 2), 1, sy)
	local cz = math.clamp(math.floor((sz + 1) / 2), 1, sz)

	return materials[cx][cy][cz] == Enum.Material.Water and occupancies[cx][cy][cz] > 0.1
end

local function getDepthUnderSurface(cameraPos)
	rayParams.FilterDescendantsInstances = {Workspace.CurrentCamera}
	local result = Workspace:Raycast(cameraPos, Vector3.new(0, SURFACE_RAY_UP, 0), rayParams)

	if result and result.Material == Enum.Material.Water then
		return result.Position.Y - cameraPos.Y
	end

	-- Если луч не нашел поверхность в пределах SURFACE_RAY_UP, считаем что глубоко под водой.
	return SURFACE_RAY_UP
end

RunService.RenderStepped:Connect(function()
	local camera = Workspace.CurrentCamera
	if not camera then
		resetEffects()
		return
	end

	local camPos = camera.CFrame.Position
	if not isPointInWater(camPos) then
		resetEffects()
		return
	end

	local depth = getDepthUnderSurface(camPos)
	local alpha = math.clamp(depth / MAX_DEPTH, 0, 1)

	blur.Size = alpha * 50
	colorCorrection.Enabled = alpha > 0
	colorCorrection.TintColor = TINT_COLOR
end)

Players.LocalPlayer.CharacterAdded:Connect(function()
	resetEffects()
end)
