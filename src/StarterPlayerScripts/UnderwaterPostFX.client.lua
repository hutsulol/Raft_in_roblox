local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local CHECK_INTERVAL = 0.25
local VOXEL_RESOLUTION = 4
local SAMPLE_HALF_SIZE = 2

local UNDERWATER_BLUR_SIZE = 16
local UNDERWATER_TINT = Color3.fromRGB(0, 170, 255)
local UNDERWATER_SATURATION = -0.2
local UNDERWATER_CONTRAST = 0.1

local UNDERWATER_FOG_COLOR = Color3.fromRGB(25, 130, 180)
local UNDERWATER_FOG_END = 120

local TWEEN_IN = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_OUT = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local defaultFogColor = Lighting.FogColor
local defaultFogEnd = Lighting.FogEnd

local blur = Lighting:FindFirstChild("UnderwaterBlur")
if not blur or not blur:IsA("BlurEffect") then
	if blur then blur:Destroy() end
	blur = Instance.new("BlurEffect")
	blur.Name = "UnderwaterBlur"
	blur.Size = 0
	blur.Enabled = true
	blur.Parent = Lighting
end

local colorFx = Lighting:FindFirstChild("UnderwaterColorCorrection")
if not colorFx or not colorFx:IsA("ColorCorrectionEffect") then
	if colorFx then colorFx:Destroy() end
	colorFx = Instance.new("ColorCorrectionEffect")
	colorFx.Name = "UnderwaterColorCorrection"
	colorFx.TintColor = UNDERWATER_TINT
	colorFx.Saturation = UNDERWATER_SATURATION
	colorFx.Contrast = UNDERWATER_CONTRAST
	colorFx.Enabled = false
	colorFx.Parent = Lighting
end

local activeTweens = {}
local isUnderwater = false

local function playTween(obj, info, goal)
	local t = TweenService:Create(obj, info, goal)
	table.insert(activeTweens, t)
	t:Play()
	return t
end

local function stopTweens()
	for _, t in activeTweens do
		t:Cancel()
	end
	table.clear(activeTweens)
end

local function setUnderwaterState(nextState)
	if isUnderwater == nextState then return end
	isUnderwater = nextState
	stopTweens()

	if nextState then
		colorFx.Enabled = true
		playTween(blur, TWEEN_IN, {Size = UNDERWATER_BLUR_SIZE})
		playTween(colorFx, TWEEN_IN, {
			TintColor = UNDERWATER_TINT,
			Saturation = UNDERWATER_SATURATION,
			Contrast = UNDERWATER_CONTRAST,
		})
		playTween(Lighting, TWEEN_IN, {
			FogColor = UNDERWATER_FOG_COLOR,
			FogEnd = UNDERWATER_FOG_END,
		})
	else
		playTween(blur, TWEEN_OUT, {Size = 0})
		local fade = playTween(colorFx, TWEEN_OUT, {
			Saturation = 0,
			Contrast = 0,
			TintColor = Color3.new(1, 1, 1),
		})
		fade.Completed:Once(function()
			if not isUnderwater then
				colorFx.Enabled = false
			end
		end)
		playTween(Lighting, TWEEN_OUT, {
			FogColor = defaultFogColor,
			FogEnd = defaultFogEnd,
		})
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

task.spawn(function()
	while player.Parent do
		local cam = Workspace.CurrentCamera
		if cam then
			setUnderwaterState(cameraInsideWater(cam.CFrame.Position))
		else
			setUnderwaterState(false)
		end
		task.wait(CHECK_INTERVAL)
	end
end)

player.CharacterAdded:Connect(function()
	task.wait(0.1)
	if not Workspace.CurrentCamera then
		setUnderwaterState(false)
	end
end)
