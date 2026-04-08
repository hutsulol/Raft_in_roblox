local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local VOXEL_RESOLUTION = 4
local SAMPLE_HALF_SIZE = 2

local BLUR_SIZE_UNDERWATER = 22
local TINT_UNDERWATER = Color3.fromRGB(0, 110, 90)
local SATURATION_UNDERWATER = -0.3
local CONTRAST_UNDERWATER = 0.05

local blur = Lighting:FindFirstChild("UnderwaterBlur")
if not blur or not blur:IsA("BlurEffect") then
	if blur then blur:Destroy() end
	blur = Instance.new("BlurEffect")
	blur.Name = "UnderwaterBlur"
	blur.Size = 0
	blur.Parent = Lighting
end

local colorFx = Lighting:FindFirstChild("UnderwaterColorCorrection")
if not colorFx or not colorFx:IsA("ColorCorrectionEffect") then
	if colorFx then colorFx:Destroy() end
	colorFx = Instance.new("ColorCorrectionEffect")
	colorFx.Name = "UnderwaterColorCorrection"
	colorFx.Enabled = false
	colorFx.Parent = Lighting
end

local isUnderwater = false

local function applyUnderwaterEffects(enabled)
	if enabled then
		blur.Size = BLUR_SIZE_UNDERWATER
		colorFx.Enabled = true
		colorFx.TintColor = TINT_UNDERWATER
		colorFx.Saturation = SATURATION_UNDERWATER
		colorFx.Contrast = CONTRAST_UNDERWATER
	else
		blur.Size = 0
		colorFx.Enabled = false
	end
end

local function cameraInsideWater(cameraPos)
	local min = cameraPos - Vector3.new(SAMPLE_HALF_SIZE, SAMPLE_HALF_SIZE, SAMPLE_HALF_SIZE)
	local max = cameraPos + Vector3.new(SAMPLE_HALF_SIZE, SAMPLE_HALF_SIZE, SAMPLE_HALF_SIZE)
	local region = Region3.new(min, max):ExpandToGrid(VOXEL_RESOLUTION)

	local materials, occupancy = Workspace.Terrain:ReadVoxels(region, VOXEL_RESOLUTION)
	local sx, sy, sz = materials.Size.X, materials.Size.Y, materials.Size.Z
	local cx = math.clamp(math.floor((sx + 1) / 2), 1, sx)
	local cy = math.clamp(math.floor((sy + 1) / 2), 1, sy)
	local cz = math.clamp(math.floor((sz + 1) / 2), 1, sz)

	return materials[cx][cy][cz] == Enum.Material.Water and occupancy[cx][cy][cz] > 0.1
end

RunService.RenderStepped:Connect(function()
	local camera = Workspace.CurrentCamera
	if not camera then return end

	local nowUnderwater = cameraInsideWater(camera.CFrame.Position)
	if nowUnderwater ~= isUnderwater then
		isUnderwater = nowUnderwater
		applyUnderwaterEffects(isUnderwater)
	end
end)
